function Update-WorkItemWithEstimation {
    param(
        [string]$Org,
        [string]$ProjectEncoded,
        [int]$WorkItemId,
        [hashtable]$PatchHeaders,
        [int]$StoryPointsValue,
        [string]$CommentText,
        [string[]]$AcceptanceCriteria,
        [string]$ExistingTags,
        [bool]$NeedsClarification,
        [bool]$NeedsBreakdown
    )
    # Prepare the PATCH data for story points and comment
    $updateData = @(
        @{ op = "add"; path = "/fields/Microsoft.VSTS.Scheduling.StoryPoints"; value = $StoryPointsValue }
        @{ op = "add"; path = "/fields/System.History"; value = $CommentText }
    )
    # Add acceptance criteria if provided
    if ($AcceptanceCriteria -and $AcceptanceCriteria.Count -gt 0) {
        $acceptanceCriteriaText = "<div>"
        for ($i = 0; $i -lt $AcceptanceCriteria.Count; $i++) {
            $acceptanceCriteriaText += "<div>$($i + 1). $($AcceptanceCriteria[$i])</div>"
            if ($i -lt $AcceptanceCriteria.Count - 1) {
                $acceptanceCriteriaText += "<div><br/></div>"
            }
        }
        $acceptanceCriteriaText += "</div>"
        $updateData += @{ op = "add"; path = "/fields/Microsoft.VSTS.Common.AcceptanceCriteria"; value = $acceptanceCriteriaText }
        Write-Log "   Adding $($AcceptanceCriteria.Count) acceptance criteria to work item field"
    }
    # Prepare tags: add needs-clarification and needs-breakdown if required
    $tagList = if ($ExistingTags) { $ExistingTags -split '; ' } else { @() }
    if ($NeedsClarification -and $tagList -notcontains "needs-clarification") {
        $tagList += "needs-clarification"
    }
    if ($NeedsBreakdown -and $tagList -notcontains "needs-breakdown") {
        $tagList += "needs-breakdown"
    }
    if ($tagList.Count -gt 0) {
        $newTags = $tagList -join '; '
        $updateData += @{ op = "add"; path = "/fields/System.Tags"; value = $newTags }
    }
    # Build the update URL for the PATCH request
    $updateUrl = "$Org/$ProjectEncoded/_apis/wit/workitems/$WorkItemId" + "?api-version=6.0"
    # Convert the update data to JSON
    $updateJson = $updateData | ConvertTo-Json -Depth 4
    # Send the PATCH request to update the work item
    $updateResult = Invoke-RestMethod -Uri $updateUrl -Method PATCH -Headers $PatchHeaders -Body $updateJson
    return $updateResult
}
