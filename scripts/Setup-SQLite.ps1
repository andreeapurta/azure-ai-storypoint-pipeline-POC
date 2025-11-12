# Setup SQLite for PowerShell using PSSQLite module
Write-Host "Setting up SQLite for AI Memory..." -ForegroundColor Cyan

# Check if PSSQLite is installed
if (Get-Module -ListAvailable -Name PSSQLite) {
    Write-Host "✅ PSSQLite module already installed" -ForegroundColor Green
} else {
    Write-Host "Installing PSSQLite module..." -ForegroundColor Yellow
    try {
        Install-Module -Name PSSQLite -Force -Scope CurrentUser -AllowClobber
        Write-Host "✅ PSSQLite installed successfully!" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Failed to install PSSQLite: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        Write-Host "Manual installation:" -ForegroundColor Yellow
        Write-Host "  Run as Administrator: Install-Module -Name PSSQLite -Force"
        exit 1
    }
}

Import-Module PSSQLite
Write-Host "✅ PSSQLite module loaded" -ForegroundColor Green
Write-Host ""
Write-Host "Next step: Run Initialize-EstimationDB.ps1" -ForegroundColor Cyan
