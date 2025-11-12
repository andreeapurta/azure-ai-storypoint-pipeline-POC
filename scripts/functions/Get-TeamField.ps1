function Get-TeamField {
    param(
        # The WorkItem object that contains various fields
        [object]$WorkItem
    )

    # Define a list of possible team field names to look for in the WorkItem
    $teamFieldNames = @('Custom.Team', 'TEAM', 'Team', 'team')

    # Search for the first matching team field name that exists in the WorkItem fields
    $foundTeamField = $teamFieldNames | Where-Object { 
        $WorkItem.fields.PSObject.Properties.Name -contains $_ 
    }

    # If a matching team field is found, return its value; otherwise, return an empty string
    if ($foundTeamField) {
        return $WorkItem.fields.$foundTeamField
    } else {
        return ''
    }
}