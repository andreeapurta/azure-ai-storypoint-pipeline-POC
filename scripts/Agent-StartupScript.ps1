    # Dot-source shared Write-Log function
    . "$PSScriptRoot\functions\Write-Log.ps1"

Write-Log "Starting Azure DevOps Agent + Local Ollama AI"
Write-Log "Starting Ollama service..."
try {
    $ollamaProcess = Get-Process ollama -ErrorAction SilentlyContinue
    if ($ollamaProcess) {
    Write-Log "   Already running (PID: $($ollamaProcess.Id))"
    } else {
        Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden
        Start-Sleep -Seconds 3
    Write-Log "   Ollama started"
    }
}
catch {
    Write-Log "   Error starting Ollama: $($_.Exception.Message)" "WARN"
}
Write-Log ""
Write-Log "Starting Azure DevOps Agent..."
$agentPath = "C:\Users\purte\OneDrive\Desktop\agent test\vsts-agent-win-x64-4.261.0"
if (Test-Path $agentPath) {
    Set-Location $agentPath
    Write-Log "   Agent directory: $agentPath"
    .\run.cmd
} else {
    Write-Log "   Agent directory not found: $agentPath" "ERROR"
}
Write-Log "Agent stopped."
try {
    Stop-Process -Name ollama -Force -ErrorAction SilentlyContinue
    Write-Log "   Ollama stopped"
}
catch {}
