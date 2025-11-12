# Collect historical estimation data from closed Azure DevOps User Stories
param(
    [Parameter(Mandatory=$true)]
    [string]$Organization,
    
    [Parameter(Mandatory=$true)]
    [string]$Project,
    
    [Parameter(Mandatory=$true)]
    [string]$AccessToken,
    
    [Parameter(Mandatory=$false)]
    [string]$DbPath = "estimation-memory.db",
    
    [Parameter(Mandatory=$false)]
    [int]$DaysBack = 180  # Look back 6 months by default
)

# ...existing code...
# Replace any hardcoded org/project/token with placeholders
# Example:
# $org = $Organization.TrimEnd('/')
# $projectEncoded = [System.Uri]::EscapeDataString($Project)
# ...existing code...
