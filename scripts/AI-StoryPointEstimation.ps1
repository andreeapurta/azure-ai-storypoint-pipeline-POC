<#
    This script automates story point estimation for Azure DevOps User Stories using AI (Groq Cloud or local Ollama).
    It fetches unestimated User Stories in the current sprint, analyzes their content, and applies a hybrid approach:
        - Extracts keywords and synonyms for similarity search in a local SQLite database of historical stories
        - Uses AI (Groq or Ollama) to estimate story points, generate acceptance criteria, and flag quality issues
        - Updates User Stories in Azure DevOps with estimated points, acceptance criteria, and tags (needs-clarification, needs-breakdown)
        - Logs all actions and results to a log file for traceability
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Organization,
    
    [Parameter(Mandatory=$true)]
    [string]$Project,
    
    [Parameter(Mandatory=$true)]
    [string]$AccessToken,
    
    [Parameter(Mandatory=$false)]
    [string]$LogFile = "requirement-estimation.log",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet('Groq', 'Ollama')]
    [string]$AIProvider = 'Ollama',
    
    [Parameter(Mandatory=$false)]
    [string]$OllamaEndpoint = 'http://localhost:11434',
    
    [Parameter(Mandatory=$false)]
    [string]$OllamaModel = 'llama3.2:3b',
    
    [Parameter(Mandatory=$false)]
    [string]$GroqApiKey = '',
    
    [Parameter(Mandatory=$false)]
    [string]$GroqModel = 'llama-3.1-8b-instant',
    
    [Parameter(Mandatory=$false)]
    [string]$Sprint = 'Sprint 2'  # Optional: specify sprint manually (e.g., "Sprint 2")
)

# Import new modularized functions
. "$PSScriptRoot\functions\Write-Log.ps1"
. "$PSScriptRoot\functions\Get-SimilarHistoricalStories.ps1"
. "$PSScriptRoot\functions\Get-FreeAIEstimate.ps1"
. "$PSScriptRoot\functions\Get-CurrentSprint.ps1"
. "$PSScriptRoot\functions\Get-UnestimatedUserStories.ps1"
. "$PSScriptRoot\functions\Get-WorkItemDetails.ps1"
. "$PSScriptRoot\functions\Update-WorkItemWithEstimation.ps1"
. "$PSScriptRoot\functions\Get-TeamField.ps1"

try {
    Write-Log "=== FREE AI STORY POINT ESTIMATION - CURRENT SPRINT USER STORIES ==="
    Write-Log "Starting AI story point estimation for project: $Project"
    Write-Log "Scope: User Stories in current sprint without story points"
    Write-Log "AI Provider: $AIProvider"
    if ($AIProvider -eq 'Ollama') {
        Write-Log "Ollama Endpoint: $OllamaEndpoint, Ollama Model: $OllamaModel"
        Write-Log "Mode: LOCAL"
    } else {
        Write-Log "Mode: CLOUD (Groq - fast & reliable)"
    }
    
    # Headers for GET/POST operations (WIQL queries)
    $headers = @{
        'Authorization' = "Bearer $AccessToken"
        'Content-Type' = 'application/json'
    }
    
    $org = $Organization.TrimEnd('/')
    $projectEncoded = [System.Uri]::EscapeDataString($Project)
    
    # Get current sprint/iteration path
    $currentIterationPath = Get-CurrentSprint -Organization $Organization -Project $Project -AccessToken $AccessToken -Sprint $Sprint -Headers $headers
    
    # Find unestimated User Stories in CURRENT SPRINT ONLY
    $queryResult = Get-UnestimatedUserStories -Org $org -ProjectEncoded $projectEncoded -CurrentIterationPath $currentIterationPath -Headers $headers
    Write-Log "Query returned $($queryResult.workItems.Count) unestimated User Stories in current sprint"
    
    if (-not $queryResult.workItems -or $queryResult.workItems.Count -eq 0) {
        Write-Log "[OK] No User Stories in current sprint need estimation - all have story points!"
        
        # Let's check what User Stories ARE in the current sprint
        $checkIterationCondition = if ($currentIterationPath -eq "@CurrentIteration") {
            "[System.IterationPath] = @CurrentIteration"
        } else {
            "[System.IterationPath] = '$currentIterationPath'"
        }
        
        $checkQuery = @"
SELECT [System.Id], [System.WorkItemType], [System.Title], [System.IterationPath], [Microsoft.VSTS.Scheduling.StoryPoints]
FROM WorkItems 
WHERE [System.WorkItemType] = 'User Story'
AND $checkIterationCondition
AND [System.State] NOT IN ('Closed', 'Removed', 'Done', 'Resolved')
"@
        $checkData = @{ query = $checkQuery } | ConvertTo-Json
        $checkResult = Invoke-RestMethod -Uri $wiqlUrl -Method POST -Headers $headers -Body $checkData
        
        if ($checkResult.workItems -and $checkResult.workItems.Count -gt 0) {
            Write-Log "[INFO] Current sprint has $($checkResult.workItems.Count) active User Stories total"
            
            # Get details to see which have story points
            $checkIds = $checkResult.workItems | ForEach-Object { $_.id }
            $batchUrl = "$org/$projectEncoded/_apis/wit/workitems?ids=$($checkIds -join ',')&fields=System.Id,System.WorkItemType,System.Title,System.IterationPath,Microsoft.VSTS.Scheduling.StoryPoints&api-version=6.0"
            $details = Invoke-RestMethod -Uri $batchUrl -Method GET -Headers @{'Authorization' = "Bearer $AccessToken"}
            
            foreach ($item in $details.value) {
                $sp = $item.fields.'Microsoft.VSTS.Scheduling.StoryPoints'
                $title = $item.fields.'System.Title'
                $spStatus = if ($sp) { "SP: $sp" } else { "No SP" }
                Write-Log "[INFO]   #$($item.id) - User Story - $spStatus - $title"
            }
            
            Write-Log "[INFO] Current Sprint Path: $currentIterationPath"
        } else {
            Write-Log "[WARN] Current sprint appears to have no User Stories"
        }
        
        return
    }
    
    Write-Log "[TARGET] Found $($queryResult.workItems.Count) current sprint User Stories for FREE AI estimation"
    
    # Get work item details individually (more reliable than batch API)
    $workItemIds = $queryResult.workItems | ForEach-Object { $_.id }
    Write-Log "[DEBUG] workItemIds array: $($workItemIds | Out-String)"
    Write-Log "Fetching work item details for IDs: $($workItemIds -join ', ')"
    $results = @()
    $processedCount = 0
    $workItems = Get-WorkItemDetails -Org $org -ProjectEncoded $projectEncoded -WorkItemIds $workItemIds -Headers $headers -AccessToken $AccessToken
    foreach ($workItem in $workItems) {
        try {
            $workItemId = $workItem.id
            $title = if ($workItem.fields.'System.Title') { $workItem.fields.'System.Title' } else { '' }
            $descriptionRaw = if ($workItem.fields.'System.Description') { $workItem.fields.'System.Description' } else { '' }
            $description = $descriptionRaw -replace '<[^>]+>', ' '
            $workItemType = if ($workItem.fields.'System.WorkItemType') { $workItem.fields.'System.WorkItemType' } else { 'Unknown' }
            $team = Get-TeamField -WorkItem $workItem
            Write-Log "PIPELINE DEBUG: Processing [$team] $title"
            $estimation = $null
            try {
                $estimation = Get-FreeAIEstimate -Title $title -Description $description -WorkItemType $workItemType -Team $team -Provider $AIProvider
                Write-Log "PIPELINE DEBUG: AI estimation completed successfully"
            } catch {
                Write-Log "PIPELINE ERROR: AI estimation threw exception: $($_.Exception.Message)" "ERROR"
                Write-Log "PIPELINE ERROR: Failed on work item #$workItemId - '$title'" "ERROR"
                Write-Log "PIPELINE ERROR: Skipping this work item and continuing with next..." "ERROR"
                continue
            }
            if ($null -eq $estimation) {
                Write-Log "   AI estimation failed" "ERROR"
                continue
            }
            Write-Log "   Estimated: $($estimation.StoryPoints) story points ($($estimation.AIModel))"
            $pts = [int]($estimation.StoryPoints | Select-Object -First 1)
            $conf = [string]($estimation.Confidence | Select-Object -First 1)
            $model = [string]($estimation.AIModel | Select-Object -First 1)
            $reason = [string]($estimation.Reasoning | Select-Object -First 1)
            $acceptanceCriteria = $estimation.AcceptanceCriteria
            $descriptionLength = $description.Trim().Length
            $needsClarification = ($descriptionLength -eq 0 -or $descriptionLength -lt 30)
            $needsBreakdown = if ($null -ne $estimation.NeedsBreakdown) { $estimation.NeedsBreakdown } else { ($pts -eq 8) }
            Write-Log "   Description length: $descriptionLength characters"
            Write-Log "   Quality flags: needsClarification=$needsClarification, needsBreakdown=$needsBreakdown"
            $complexityInfo = ""
            if ($reason -match "Complexity: (\d+)") { $complexityInfo = " Complexity $($matches[1])" }
            $teamInfo = if ($team) { " [$team]" } else { "" }
            $commentText = "AI Estimation" + $teamInfo + ": $pts story points$complexityInfo`nConfidence: $conf"
            $storyPointsValue = [int]($estimation.StoryPoints | Select-Object -First 1)
            $existingTags = if ($workItem.fields.'System.Tags') { $workItem.fields.'System.Tags' } else { "" }
            $patchHeaders = @{
                'Authorization' = "Bearer $AccessToken"
                'Content-Type' = 'application/json-patch+json'
            }
            $updateResult = Update-WorkItemWithEstimation -Org $org -ProjectEncoded $projectEncoded -WorkItemId $workItemId -PatchHeaders $patchHeaders -StoryPointsValue $storyPointsValue -CommentText $commentText -AcceptanceCriteria $acceptanceCriteria -ExistingTags $existingTags -NeedsClarification $needsClarification -NeedsBreakdown $needsBreakdown
            $updatedSP = $updateResult.fields.'Microsoft.VSTS.Scheduling.StoryPoints'
            if ($updatedSP) {
                Write-Log "   ✅ Updated #$workItemId with $updatedSP story points"
                $processedCount++
            } else {
                Write-Log "   ⚠️  Update succeeded but story points not confirmed" "WARNING"
            }
        } catch {
            $errorMsg = $_.Exception.Message -replace '[^\x20-\x7E]', '' -replace '"', "'"
            Write-Log "Failed work item $($workItem.id) - Error: $errorMsg" "ERROR"
        }
    }
    
    Write-Log "=== SUMMARY ==="
    Write-Log "SUCCESS: AI estimation complete for current sprint User Stories!"
    Write-Log "Processed: $processedCount User Stories"
    Write-Log "Sprint: $currentIterationPath"
}
catch {
    Write-Log "FATAL ERROR: $($_.Exception.Message)" "ERROR"
    throw
}
