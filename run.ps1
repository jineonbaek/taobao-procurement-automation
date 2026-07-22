$workdir = Split-Path $MyInvocation.MyCommand.Path -Parent
Set-Location $workdir

Write-Host "========================================"  -ForegroundColor Cyan
Write-Host "  TaoBao Link Parser" -ForegroundColor Cyan
Write-Host "========================================"  -ForegroundColor Cyan
Write-Host ""

$envOk = Test-Path "data\.taobao.env"
$cookieOk = Test-Path "data\.taobao_cookies.json"

if (-not $envOk) {
    Write-Host "  ERROR: Not configured." -ForegroundColor Red
    Write-Host "  Opening setup.bat..." -ForegroundColor Yellow
    Start-Process "setup.bat"
    Read-Host "Press Enter to close"
    exit
}

if (-not $cookieOk) {
    Write-Host "  Not logged in." -ForegroundColor Red
    Write-Host "  Run setup.bat first." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Open setup.bat now? (y/n)" -ForegroundColor White
    $answer = Read-Host
    if ($answer -eq "y") { Start-Process "setup.bat" }
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
    python taobao_parser.py $url 2>&1
    Write-Host "----------------------------------------"
    Write-Host ""
}

Write-Host "Done." -ForegroundColor Green
Read-Host "Press Enter to close"
