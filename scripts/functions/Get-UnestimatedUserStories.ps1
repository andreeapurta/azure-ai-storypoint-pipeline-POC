function Get-UnestimatedUserStories {
    param(
        # The base URL of the Azure DevOps organization (e.g., https://dev.azure.com/YourOrg)
        [string]$Org,

        # The URL-encoded project name (used for constructing API requests)
        [string]$ProjectEncoded,

        # The path of the current iteration (e.g., "ProjectName\Sprint 25") 
        # or "@CurrentIteration" macro for automatic detection
        [string]$CurrentIterationPath,

        # HTTP headers used for authentication and content type (includes PAT in Authorization header)
        [hashtable]$Headers
    )

    # Determine the correct WIQL iteration filter based on whether the user passed
    # a specific iteration path or wants to use the @CurrentIteration macro.
    $iterationCondition = if ($CurrentIterationPath -eq "@CurrentIteration") {
        "[System.IterationPath] = @CurrentIteration"
    } else {
        "[System.IterationPath] = '$CurrentIterationPath'"
    }

    # Define a WIQL (Work Item Query Language) query that selects all *User Story* work items
    # in the specified iteration that are missing Story Points (i.e., unestimated)
    # and are not in a completed or closed state.
    $wiqlQuery = @"
SELECT [System.Id], [System.IterationPath], [System.Title]
FROM WorkItems 
WHERE [System.WorkItemType] = 'User Story'
AND NOT [Microsoft.VSTS.Scheduling.StoryPoints] > 0
AND [System.State] NOT IN ('Closed', 'Removed', 'Done', 'Resolved', 'Completed')
AND $iterationCondition
ORDER BY [System.CreatedDate] DESC
"@

    # Convert the WIQL query into JSON format for the Azure DevOps REST API POST request
    $wiqlData = @{ query = $wiqlQuery } | ConvertTo-Json

    # Construct the WIQL endpoint URL for the given organization and project
    $wiqlUrl = "$Org/$ProjectEncoded/_apis/wit/wiql?api-version=6.0"

    # Log useful debugging and trace information to help verify the request context
    Write-Log "Executing WIQL query for CURRENT SPRINT ($CurrentIterationPath) User Stories."
    Write-Log "WIQL: $wiqlQuery"

    # Execute the WIQL query using the Azure DevOps REST API
    $queryResult = Invoke-RestMethod -Uri $wiqlUrl -Method POST -Headers $Headers -Body $wiqlData

    # Return the result object, which includes IDs and metadata of matching work items
    return $queryResult
}
