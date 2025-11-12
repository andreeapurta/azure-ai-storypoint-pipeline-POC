function Get-WorkItemDetails {
    param(
        # The base URL of the Azure DevOps organization (e.g., https://dev.azure.com/YourOrg)
        [string]$Org,

        # The URL-encoded project name (used in REST API calls)
        [string]$ProjectEncoded,

        # A list of numeric Work Item IDs to fetch from Azure DevOps
        [int[]]$WorkItemIds,

        # HTTP headers for authentication and content type (should include a valid PAT in Authorization)
        [hashtable]$Headers,

        # Personal Access Token (optional if already included in $Headers)
        [string]$AccessToken
    )

    # Initialize an empty array to collect the work item details retrieved from the API
    $details = @()

    # Iterate through each provided work item ID
    foreach ($workItemId in $WorkItemIds) {
        # Skip invalid or empty work item IDs (e.g., null, empty string, or placeholder '-')
        if (-not $workItemId -or $workItemId -eq '' -or $workItemId -eq '-') {
            Write-Log "[ERROR] Skipping invalid or empty workItemId: '$workItemId'" "ERROR"
            continue
        }
        # Construct the REST API endpoint for the given work item ID
        $workItemUrl = "$Org/$ProjectEncoded/_apis/wit/workitems/$workItemId" + "?api-version=6.0"
        try {
            # Make a REST API GET call to fetch the work item details
            $workItem = Invoke-RestMethod -Uri $workItemUrl -Method GET -Headers $Headers

            # Add the retrieved work item object to the results array
            $details += $workItem
        } catch {
            # Clean the error message by removing non-printable characters and quotes for log safety
            $errMsg = $_.Exception.Message -replace '[^\x20-\x7E]', '' -replace '"', "'"

            # Log the failure and continue processing the next work item
            Write-Log "[ERROR] Failed to fetch work item $workItemId from $workItemUrl - Error: $errMsg" "ERROR"
            continue
        }
    }

    # Return all successfully retrieved work item objects
    return $details
}
