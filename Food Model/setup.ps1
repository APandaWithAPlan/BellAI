# setup.ps1 - one-time setup of the BellAi Food Model on a Windows PC with an NVIDIA GPU.
#
# Run from the Food Model folder in PowerShell:
#     powershell -ExecutionPolicy Bypass -File setup.ps1
#
# It: checks the GPU and Python, creates .venv, installs PyTorch (CUDA) and the
# requirements, saves your USDA key, creates an API key for the server, and can
# pre-download the model (~16 GB) so the first server start is quick.
# Safe to run again - it skips steps that are already done.

# "Continue" because Windows PowerShell treats normal pip/python warnings on stderr as errors
$ErrorActionPreference = "Continue"
Set-Location $PSScriptRoot

function Step($text) { Write-Host "`n== $text" -ForegroundColor Cyan }
function Fail($text) { Write-Host "`nERROR: $text" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------- GPU
Step "Checking for an NVIDIA GPU"
if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
    nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
    Write-Host "The 7B model needs about 20 GB of GPU memory; with less, use the 3B model (see README)."
} else {
    Write-Warning "nvidia-smi not found. Install the NVIDIA driver first, or the model will run on CPU (very slow)."
}

# ---------------------------------------------------------------- Python
Step "Checking Python"
$pyExe = $null; $pyArgs = @()
foreach ($candidate in "py -3.12", "py -3.11", "py -3.10", "python") {
    $parts = $candidate.Split(" ")
    $exe = $parts[0]; $extra = @($parts | Select-Object -Skip 1)
    if (Get-Command $exe -ErrorAction SilentlyContinue) {
        & $exe @extra -c "import sys; sys.exit(0 if (3,10) <= sys.version_info[:2] <= (3,12) else 1)" 2>$null
        if ($LASTEXITCODE -eq 0) { $pyExe = $exe; $pyArgs = $extra; break }
    }
}
if (-not $pyExe) {
    Fail "Need Python 3.10, 3.11 or 3.12. Install it from python.org (tick 'Add python.exe to PATH') and run this again."
}
& $pyExe @pyArgs --version

# ---------------------------------------------------------------- venv + packages
$venvPy = Join-Path $PSScriptRoot ".venv\Scripts\python.exe"
if (-not (Test-Path $venvPy)) {
    Step "Creating .venv"
    & $pyExe @pyArgs -m venv .venv
    if (-not (Test-Path $venvPy)) { Fail "Couldn't create .venv." }
}

Step "Installing PyTorch with CUDA (large download the first time)"
& $venvPy -m pip install --upgrade pip --quiet
& $venvPy -c "import torch, sys; sys.exit(0 if torch.cuda.is_available() else 1)" 2>$null
if ($LASTEXITCODE -ne 0) {
    & $venvPy -m pip install torch torchvision --index-url https://download.pytorch.org/whl/cu124
    if ($LASTEXITCODE -ne 0) { Fail "PyTorch install failed - see the messages above." }
} else {
    Write-Host "PyTorch with CUDA is already installed."
}

Step "Installing requirements"
& $venvPy -m pip install -r requirements.txt --quiet
if ($LASTEXITCODE -ne 0) { Fail "pip install failed - see the messages above." }

Step "Checking that PyTorch can see the GPU"
& $venvPy -c "import torch; print('CUDA available:', torch.cuda.is_available()); print(torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'No GPU visible to PyTorch')"

# ---------------------------------------------------------------- keys
function Get-SavedVar($name) {
    $v = [Environment]::GetEnvironmentVariable($name, "Process")
    if (-not $v) { $v = [Environment]::GetEnvironmentVariable($name, "User") }
    return $v
}

Step "USDA API key (FDC_API_KEY)"
if (Get-SavedVar "FDC_API_KEY") {
    Write-Host "Already set."
} else {
    $fdc = Read-Host "Paste your USDA key (free at https://fdc.nal.usda.gov/api-key-signup), or press Enter to skip"
    if ($fdc) {
        [Environment]::SetEnvironmentVariable("FDC_API_KEY", $fdc.Trim(), "User")
        $env:FDC_API_KEY = $fdc.Trim()
        Write-Host "Saved."
    } else {
        Write-Warning "Skipped - lookups will use DEMO_KEY, which allows only a few requests per hour."
    }
}

Step "Server API key (FOOD_API_KEY)"
if (Get-SavedVar "FOOD_API_KEY") {
    Write-Host "Already set. To see it: [Environment]::GetEnvironmentVariable('FOOD_API_KEY','User')"
} else {
    $bytes = New-Object byte[] 24
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $key = [Convert]::ToBase64String($bytes).Replace("+", "-").Replace("/", "_").TrimEnd("=")
    [Environment]::SetEnvironmentVariable("FOOD_API_KEY", $key, "User")
    $env:FOOD_API_KEY = $key
    Write-Host "Created a key for the server. Give it to whoever runs the website (privately):"
    Write-Host "    $key" -ForegroundColor Yellow
}

# ---------------------------------------------------------------- model download
Step "Model download"
$answer = Read-Host "Download Qwen2.5-VL-7B now (~16 GB)? Otherwise it downloads on the first server start. [y/N]"
if ($answer -match "^[yY]") {
    & $venvPy -c "from huggingface_hub import snapshot_download; snapshot_download('Qwen/Qwen2.5-VL-7B-Instruct')"
}

Step "Done"
Write-Host "Start the server with:   powershell -ExecutionPolicy Bypass -File start_server.ps1"
Write-Host "Then open http://127.0.0.1:8000 and upload a food photo."
