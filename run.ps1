$workdir = Split-Path $MyInvocation.MyCommand.Path -Parent
Set-Location $workdir
$pythonExe = Join-Path $workdir ".venv\Scripts\python.exe"
$browserDir = Join-Path $workdir ".playwright-browsers"
$env:PLAYWRIGHT_BROWSERS_PATH = $browserDir

Write-Host "========================================"  -ForegroundColor Cyan
Write-Host "  TaoBao Link Parser" -ForegroundColor Cyan
Write-Host "========================================"  -ForegroundColor Cyan
Write-Host ""

$runtimeOk = Test-Path $pythonExe
$browserOk = Test-Path $browserDir
$envOk = Test-Path "data\.taobao.env"
$cookieOk = Test-Path "data\.taobao_cookies.json"

if (-not $runtimeOk) {
    Write-Host "  ERROR: The local Python environment is not configured." -ForegroundColor Red
    Write-Host "  Run setup.bat first." -ForegroundColor Yellow
    Read-Host "Press Enter to close"
    exit 1
}

if (-not $browserOk) {
    Write-Host "  ERROR: The project Chromium browser is not installed." -ForegroundColor Red
    Write-Host "  Run setup.bat first." -ForegroundColor Yellow
    Read-Host "Press Enter to close"
    exit 1
}

if (-not $envOk) {
    Write-Host "  ERROR: Not configured." -ForegroundColor Red
    Write-Host "  Opening setup.bat..." -ForegroundColor Yellow
    Start-Process (Join-Path $workdir "setup.bat")
    Read-Host "Press Enter to close"
    exit
}

if (-not $cookieOk) {
    Write-Host "  Not logged in." -ForegroundColor Red
    Write-Host "  Run setup.bat first." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Open setup.bat now? (y/n)" -ForegroundColor White
    $answer = Read-Host
    if ($answer -eq "y") { Start-Process (Join-Path $workdir "setup.bat") }
    Read-Host "Press Enter to close"
    exit
}

Write-Host "  Status: Logged in." -ForegroundColor Green
Write-Host ""

while ($true) {
    $url = Read-Host "Paste Taobao link (q to quit)"
    if ($url -eq "q") { break }
    if ($url -eq "") { continue }
    if ($url -notmatch "http") {
        Write-Host "  ERROR: Not a valid link." -ForegroundColor Red
        Write-Host ""
        continue
    }
    Write-Host "Parsing..." -ForegroundColor Yellow
    & $pythonExe "taobao_parser.py" $url 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ERROR: Parser exited with code $LASTEXITCODE." -ForegroundColor Red
    }
    Write-Host "----------------------------------------"
    Write-Host ""
}

Write-Host "Done." -ForegroundColor Green
Read-Host "Press Enter to close"
