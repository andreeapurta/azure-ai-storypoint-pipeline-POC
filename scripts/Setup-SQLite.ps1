
# Dot-source shared Write-Log function
. "$PSScriptRoot\functions\Write-Log.ps1"

Write-Log "Setting up SQLite for AI Memory..."

# Check if PSSQLite is installed

if (Get-Module -ListAvailable -Name PSSQLite) {
    Write-Log "✅ PSSQLite module already installed"
} else {
    Write-Log "Installing PSSQLite module..."
    try {
        Install-Module -Name PSSQLite -Force -Scope CurrentUser -AllowClobber
        Write-Log "✅ PSSQLite installed successfully!"
    }
    catch {
        Write-Log "❌ Failed to install PSSQLite: $($_.Exception.Message)" "ERROR"
        Write-Log "Manual installation:" "WARN"
        Write-Log "  Run as Administrator: Install-Module -Name PSSQLite -Force" "WARN"
        exit 1
    }
}

Import-Module PSSQLite
Write-Log "✅ PSSQLite module loaded"
Write-Log "Next step: Run Initialize-EstimationDB.ps1"
