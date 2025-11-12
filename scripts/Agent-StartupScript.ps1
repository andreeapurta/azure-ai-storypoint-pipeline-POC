Write-Host "Starting Azure DevOps Agent + Local Ollama AI" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "AI Provider: Ollama (Local & Private)" -ForegroundColor Yellow
Write-Host "Starting Ollama service..." -ForegroundColor Yellow
try {
    $ollamaProcess = Get-Process ollama -ErrorAction SilentlyContinue
    if ($ollamaProcess) {
        Write-Host "   Already running (PID: $($ollamaProcess.Id))" -ForegroundColor Green
    } else {
        Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden
        Start-Sleep -Seconds 3
        Write-Host "   Ollama started" -ForegroundColor Green
    }
}
catch {
    Write-Host "   Error starting Ollama: $($_.Exception.Message)" -ForegroundColor Yellow
}
Write-Host ""
Write-Host "Starting Azure DevOps Agent..." -ForegroundColor Yellow
$agentPath = "AGENT_PATH_PLACEHOLDER"
if (Test-Path $agentPath) {
    Set-Location $agentPath
    Write-Host "   Agent directory: $agentPath" -ForegroundColor Cyan
    .\run.cmd
} else {
    Write-Host "   Agent directory not found: $agentPath" -ForegroundColor Red
    Read-Host "Press Enter to exit..."
}
Write-Host ""
Write-Host "Agent stopped." -ForegroundColor Yellow
try {
    Stop-Process -Name ollama -Force -ErrorAction SilentlyContinue
    Write-Host "   Ollama stopped" -ForegroundColor Green
}
catch {}
