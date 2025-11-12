
# Collect historical estimation data from closed Azure DevOps User Stories

param(
    [Parameter(Mandatory = $true)]
    [string]$Organization,

    [Parameter(Mandatory = $true)]
    [string]$Project,

    [Parameter(Mandatory = $true)]
    [string]$AccessToken,

    [Parameter(Mandatory = $false)]
    [string]$DbPath = "estimation-memory.db",

    [Parameter(Mandatory = $false)]
    [int]$DaysBack = 180,  # Look back 6 months by default

    [Parameter(Mandatory = $false)]
    [string]$LogFile = "historical-collection.log"
)

# Dot-source Write-Log for consistent logging
. "$PSScriptRoot\functions\Write-Log.ps1"

# Import PSSQLite module
Import-Module PSSQLite -ErrorAction Stop

Write-Log "=== AI LEARNING: Collecting Historical Data ==="
Write-Log "Collecting closed User Stories from last $DaysBack days..."

# Database path - in the repository root (parent of scripts folder)
$repoRoot = Split-Path -Parent $PSScriptRoot
$dbFullPath = Join-Path $repoRoot $DbPath

# Check if database exists
if (-not (Test-Path $dbFullPath)) {
    Write-Log "❌ Database not found. Run Initialize-EstimationDB.ps1 first!" "ERROR"
    exit 1
}

# Azure DevOps headers
$encodedPAT = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$AccessToken"))
$headers = @{
    'Authorization' = "Basic $encodedPAT"
    'Content-Type'  = 'application/json'
}

$org = $Organization.TrimEnd('/')
$projectEncoded = [System.Uri]::EscapeDataString($Project)

# Calculate date range
$startDate = (Get-Date).AddDays(-$DaysBack).ToString("yyyy-MM-dd")

Write-Log "Searching for closed User Stories from $startDate onwards..."

# Test authentication first
$testUrl = "$org/_apis/projects?api-version=6.0"
try {
    $projects = Invoke-RestMethod -Uri $testUrl -Headers $headers
    Write-Log "Authentication successful!"
}
catch {
    Write-Log "Authentication failed: $($_.Exception.Message)" "ERROR"
    exit 1
}

# WIQL query for closed User Stories with story points
$wiqlQuery = @"
SELECT [System.Id], [System.Title], [System.Description], [System.WorkItemType],
    [Microsoft.VSTS.Scheduling.StoryPoints], [System.State], [System.CreatedDate],
    [System.ChangedDate], [System.IterationPath], [System.Tags]
FROM WorkItems
WHERE [System.WorkItemType] = 'User Story'
AND [System.State] IN ('Closed', 'Done', 'Completed', 'Resolved')
AND [Microsoft.VSTS.Scheduling.StoryPoints] > 0
ORDER BY [System.ChangedDate] DESC
"@

Write-Log "Looking for User Stories that are Closed/Done/Completed with Story Points > 0"

$wiqlData = @{ query = $wiqlQuery } | ConvertTo-Json
$wiqlUrl = "$org/$projectEncoded/_apis/wit/wiql?api-version=6.0"

try {
    $queryResult = Invoke-RestMethod -Uri $wiqlUrl -Method POST -Headers $headers -Body $wiqlData -ContentType "application/json"
}
catch {
    Write-Log "Error querying Azure DevOps: $($_.Exception.Message)" "ERROR"
    Write-Log "Response: $($_.ErrorDetails.Message)" "ERROR"
    exit 1
}

$totalItems = $queryResult.workItems.Count
Write-Log "Found $totalItems closed User Stories with story points"

# Debug: Show which work items were found
if ($totalItems -gt 0) {
    Write-Log "Work Item IDs found: $($queryResult.workItems.id -join ', ')"
}

if ($totalItems -eq 0) {
    Write-Log "No historical data to collect. Try increasing -DaysBack parameter."
    exit 0
}

$savedCount = 0
$skippedCount = 0

# Batch fetch work items (max 200 at a time)
$batchSize = 200
$workItemIds = $queryResult.workItems | ForEach-Object { $_.id }

for ($i = 0; $i -lt $workItemIds.Count; $i += $batchSize) {
    $batchIds = $workItemIds[$i..[Math]::Min($i + $batchSize - 1, $workItemIds.Count - 1)]
    $idsString = $batchIds -join ','

    $batchUrl = "$org/$projectEncoded/_apis/wit/workitems?ids=$idsString&api-version=6.0"
    $batchResult = Invoke-RestMethod -Uri $batchUrl -Method GET -Headers $headers

    foreach ($item in $batchResult.value) {
        try {
            $workItemId = $item.id
            $title = if ($item.fields.'System.Title') { $item.fields.'System.Title' } else { '' }
            $description = if ($item.fields.'System.Description') { $item.fields.'System.Description' } else { '' }
            $storyPoints = if ($item.fields.'Microsoft.VSTS.Scheduling.StoryPoints') { $item.fields.'Microsoft.VSTS.Scheduling.StoryPoints' } else { 0 }
            $changedDate = if ($item.fields.'System.ChangedDate') { $item.fields.'System.ChangedDate' } else { $null }
            $createdDate = if ($item.fields.'System.CreatedDate') { $item.fields.'System.CreatedDate' } else { $null }
            $iterationPath = if ($item.fields.'System.IterationPath') { $item.fields.'System.IterationPath' } else { '' }
            $tags = if ($item.fields.'System.Tags') { $item.fields.'System.Tags' } else { '' }
            $team = if ($item.fields.'Custom.Team') { $item.fields.'Custom.Team' } else { '' }

            Write-Log "Processing #$workItemId - '$title' (SP: $storyPoints, State: $($item.fields.'System.State'))"

            # Skip if no story points
            if ($storyPoints -le 0) {
                Write-Log "  Skipped: No story points"
                $skippedCount++
                continue
            }

            # Try to extract AI's original estimate from comments (take the LAST/most recent one)
            $aiOriginalEstimate = $null
            $hasAIComment = $false
                        # Try to extract AI's original estimate from comments (take the LAST/most recent one)
            $aiOriginalEstimate = $null
            $hasAIComment = $false
            try {
                $commentsUrl = "$org/$projectEncoded/_apis/wit/workitems/$workItemId/comments?api-version=6.0-preview.3"
                $comments = Invoke-RestMethod -Uri $commentsUrl -Method GET -Headers $headers -ErrorAction SilentlyContinue
                
                if ($comments.comments) {
                    # Reverse the order to process most recent comments first
                    $reversedComments = $comments.comments | Sort-Object -Property id -Descending
                    
                    foreach ($comment in $reversedComments) {
                        # "AI Estimation [TEAM]: X story points"
                        if ($comment.text -match 'AI Estimation.*?:\s*(\d+(?:\.\d+)?)\s*story\s*points?') {
                            $aiOriginalEstimate = [double]$matches[1]
                            $hasAIComment = $true
                            Write-Host "  Found AI estimate (old format): $aiOriginalEstimate SP" -ForegroundColor Cyan
                            
                            # Extract team from comment if not already set
                            if ([string]::IsNullOrEmpty($team) -and $comment.text -match 'AI Estimation \[([^\]]+)\]') {
                                $team = $matches[1]
                                Write-Host "  Extracted team from comment: $team" -ForegroundColor DarkCyan
                            }
                            break
                        }
                    }
                }
            }
            catch {
                # Comments API might not be available, continue without AI estimate
                Write-Log "  No AI estimate found in comments"
            }

            # Note: We save ALL closed stories, even without AI comments (for initial context)
            if ($hasAIComment) {
                Write-Log "  Has AI estimate: $aiOriginalEstimate SP"
            }
            else {
                Write-Log "  No AI estimate - saving as historical context only"
            }

            # Build insert query using PSSQLite
            $insertQuery = @"
INSERT OR REPLACE INTO estimations
(work_item_id, work_item_type, title, description, team, ai_estimated_sp, estimated_sp,
 ai_confidence, ai_reasoning, ai_model, estimation_date, completed_date,
 iteration_path, tags)
VALUES
($workItemId, 'User Story', @title, @description, @team, @ai_estimated_sp, $storyPoints,
 'Historical', 'Imported from closed User Story', 'Historical Data', @estimation_date, @completed_date,
 @iteration_path, @tags)
"@

            $params = @{
                title           = $title
                description     = $description
                team            = $team
                ai_estimated_sp = if ($aiOriginalEstimate) { $aiOriginalEstimate } else { [System.DBNull]::Value }
                estimation_date = if ($createdDate) { [DateTime]::Parse($createdDate).ToString("yyyy-MM-dd HH:mm:ss") } else { (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") }
                completed_date  = if ($changedDate) { [DateTime]::Parse($changedDate).ToString("yyyy-MM-dd HH:mm:ss") } else { (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") }
                iteration_path  = $iterationPath
                tags            = $tags
            }

            # Execute insert using PSSQLite
            Invoke-SqliteQuery -DataSource $dbFullPath -Query $insertQuery -SqlParameters $params | Out-Null
            $savedCount++
            Write-Log "  ✅ Saved #$workItemId"

            if ($savedCount % 10 -eq 0) {
                Write-Log "  Progress: Saved $savedCount / $totalItems..."
            }
        }
        catch {
            Write-Log "  ❌ Error saving work item #$workItemId : $($_.Exception.Message)" "ERROR"
            $skippedCount++
        }
    }
}

Write-Log "=== SUMMARY ==="
Write-Log "✅ Saved: $savedCount User Stories"
if ($skippedCount -gt 0) {
    Write-Log "⚠️  Skipped: $skippedCount items"
}

