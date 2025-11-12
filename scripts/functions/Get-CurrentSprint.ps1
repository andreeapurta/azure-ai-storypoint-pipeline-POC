function Get-CurrentSprint {
    param(
        # The name of the Azure DevOps organization (e.g., https://dev.azure.com/YourOrg)
        [string]$Organization,

        # The Azure DevOps project name
        [string]$Project,

        # The personal access token used for authentication (optional if passed via headers)
        [string]$AccessToken,

        # Optional: Manually specified sprint name or iteration path
        [string]$Sprint,

        # HTTP request headers (should include authorization, typically with the access token)
        [hashtable]$Headers
    )
    
    # Remove any trailing slashes from the organization URL for consistency
    $org = $Organization.TrimEnd('/')

    # URL-encode the project name to ensure it’s safe for REST API requests
    $projectEncoded = [System.Uri]::EscapeDataString($Project)

    # If a sprint name was manually specified, use it directly
    if ($Sprint) {
        # Construct the full iteration path using the project name and sprint
        $currentIterationPath = "$Project\$Sprint"
        Write-Log "Using manually specified sprint: $currentIterationPath"
        return $currentIterationPath
    } else {
        # Otherwise, automatically detect the current sprint from Azure DevOps
        Write-Log "Auto-detecting current sprint/iteration..."

        try {
            # Construct the Azure DevOps REST API endpoint for current iterations
            $iterationsUrl = "$org/$projectEncoded/_apis/work/teamsettings/iterations?`$timeframe=current&api-version=6.0"

            # Call the REST API to retrieve the current iteration details
            $currentIteration = Invoke-RestMethod -Uri $iterationsUrl -Method GET -Headers $Headers

            # If the API response contains a valid current iteration, return its path
            if ($currentIteration.value -and $currentIteration.value.Count -gt 0) {
                $currentIterationPath = $currentIteration.value[0].path
                Write-Log "Current sprint detected: $currentIterationPath"
                return $currentIterationPath
            } else {
                # If no current iteration is found, fall back to using the @CurrentIteration macro
                Write-Log "No current iteration found, using @CurrentIteration macro" "WARNING"
                return "@CurrentIteration"
            }
        } catch {
            # Handle any errors from the REST call gracefully
            Write-Log "Failed to detect current iteration: $($_.Exception.Message)" "WARNING"
            Write-Log "Falling back to @CurrentIteration macro"
            return "@CurrentIteration"
        }
    }
}
