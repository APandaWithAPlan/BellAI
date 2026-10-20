# start_server.ps1 - start the BellAi Food API.
#
#   powershell -ExecutionPolicy Bypass -File start_server.ps1          only this PC can connect
#   powershell -ExecutionPolicy Bypass -File start_server.ps1 -Lan     other devices on the same network can too
#   powershell -ExecutionPolicy Bypass -File start_server.ps1 -Small   use the 3B model (less GPU memory)
#
# Run setup.ps1 once before this.

param([switch]$Lan, [switch]$Small, [int]$Port = 8000)

$ErrorActionPreference = "Continue"
Set-Location $PSScriptRoot

$venvPy = Join-Path $PSScriptRoot ".venv\Scripts\python.exe"
if (-not (Test-Path $venvPy)) { Write-Host "No .venv found - run setup.ps1 first." -ForegroundColor Red; exit 1 }

# Pick up keys saved by setup.ps1 even if this window was opened before they were saved
foreach ($name in "FDC_API_KEY", "FOOD_API_KEY", "ALLOWED_ORIGINS") {
    if (-not [Environment]::GetEnvironmentVariable($name, "Process")) {
        $v = [Environment]::GetEnvironmentVariable($name, "User")
        if ($v) { Set-Item -Path "Env:$name" -Value $v }
    }
}

$env:PORT = "$Port"
if ($Small) { $env:FOOD_MODEL = "Qwen/Qwen2.5-VL-3B-Instruct" }

if ($Lan) {
    $env:HOST = "0.0.0.0"
    Write-Host "Other devices on this network can use:" -ForegroundColor Cyan
    Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" } |
        ForEach-Object { Write-Host "    http://$($_.IPAddress):$Port" }
    Write-Host "If Windows asks about the firewall, allow Python on Private networks."
} else {
    $env:HOST = "127.0.0.1"
}

Write-Host "Test page: http://127.0.0.1:$Port   (Ctrl+C to stop)" -ForegroundColor Cyan
& $venvPy server.py
