# Setup - TaoBao Procurement Automation
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Setup - First Time Configuration" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$cookieOk = Test-Path "data\.taobao_cookies.json"

# Step 1: Python deps + find pip command
Write-Host "[1/3] Checking Python dependencies..." -ForegroundColor Yellow

# Find working pip command (not always in PATH on Windows)
$pipCmd = $null
foreach ($try in @("python -m pip", "py -m pip", "pip3", "pip")) {
    $null = Invoke-Expression "$try --version 2>&1"; $err = $LASTEXITCODE
    if ($err -eq 0) { $pipCmd = $try; break }
}
if (-not $pipCmd) {
    Write-Host "      ERROR: Python/pip not found. Install Python 3.10+ from https://python.org" -ForegroundColor Red
    Write-Host "      Make sure to check 'Add Python to PATH' during installation." -ForegroundColor Yellow
    Read-Host "Press Enter to close"; exit 1
}
# Extract python command from pip command
$pythonCmd = $pipCmd -replace '\s+-m\s+pip$', ''
Write-Host "      Using: python=$pythonCmd, pip=$pipCmd" -ForegroundColor DarkGray

$hasPW = $false; $hasOP = $false
Invoke-Expression "$pipCmd show playwright 2>&1" | Out-Null; if ($LASTEXITCODE -eq 0) { $hasPW = $true }
Invoke-Expression "$pipCmd show openpyxl 2>&1" | Out-Null; if ($LASTEXITCODE -eq 0) { $hasOP = $true }

if ($hasPW -and $hasOP) {
    Write-Host "      Already installed, skipping." -ForegroundColor Green
} else {
    Write-Host "      Installing..." -ForegroundColor Yellow
    Invoke-Expression "$pipCmd install playwright openpyxl"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "      ERROR: pip install failed." -ForegroundColor Red
        Read-Host "Press Enter to close"; exit 1
    }
    Write-Host "      Done." -ForegroundColor Green
}
Write-Host ""

# Step 2: Chromium browser
Write-Host "[2/3] Checking Chromium browser..." -ForegroundColor Yellow
$msPlaywright = "$env:LOCALAPPDATA\ms-playwright"
$chromiumFound = $false
if (Test-Path $msPlaywright) {
    $d = Get-ChildItem "$msPlaywright\chromium-*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($d) {
        Write-Host "      Already installed, skipping." -ForegroundColor Green
        Write-Host "      Path: $($d.FullName)" -ForegroundColor DarkGray
        $chromiumFound = $true
    }
}
if (-not $chromiumFound) {
    Write-Host "      Installing (may take a few minutes)..." -ForegroundColor Yellow
    Invoke-Expression "$pythonCmd -m playwright install chromium"
    if (Test-Path $msPlaywright) {
        $d = Get-ChildItem "$msPlaywright\chromium-*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($d) { Write-Host "      Done. Path: $($d.FullName)" -ForegroundColor Green }
    } else {
        Write-Host "      WARNING: Chromium may not have installed correctly." -ForegroundColor Yellow
    }
}
Write-Host ""

# Step 3: Taobao login
Write-Host "[3/3] Taobao login" -ForegroundColor Yellow

if ($cookieOk) {
    Write-Host "      Already logged in, skipping." -ForegroundColor Green
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  All set. Run run.bat to start." -ForegroundColor Green
    Write-Host "========================================`n" -ForegroundColor Cyan
    Read-Host "Press Enter to close"; exit
}

Write-Host "      Enter your Taobao credentials.`n" -ForegroundColor DarkGray
do {
    $phone = Read-Host "      Phone number (11 digits)"
    if ($phone -notmatch '^\d{11}$') { Write-Host "      Must be exactly 11 digits." -ForegroundColor Red; $phone = "" }
} while ($phone -eq "")
$pwd = Read-Host "      Password" -AsSecureString
$pwdText = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pwd))

Set-Location (Split-Path $MyInvocation.MyCommand.Path -Parent)
New-Item -ItemType Directory -Path "data" -Force | Out-Null
Set-Content -Path "data\.taobao.env" -Encoding utf8 -Value "# Taobao credentials - LOCAL ONLY`nTAOBAO_USERNAME=$phone`nTAOBAO_PASSWORD=$pwdText"

Write-Host "`n      Logging in (~20 seconds)..." -ForegroundColor Yellow

# Write login script to temp file to avoid inline escaping issues
@'
import asyncio, json, sys
from pathlib import Path
from playwright.async_api import async_playwright

async def main():
    env = {}
    for line in Path("data/.taobao.env").read_text(encoding="utf-8").splitlines():
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip()
    u = env.get("TAOBAO_USERNAME", "")
    p = env.get("TAOBAO_PASSWORD", "")
    if not u:
        sys.exit(1)

    async with async_playwright() as pw:
        browser = await pw.chromium.launch(headless=True, args=["--disable-blink-features=AutomationControlled"])
        ctx = await browser.new_context(viewport={"width": 1366, "height": 768}, locale="zh-CN")
        page = await ctx.new_page()

        await page.goto("https://login.taobao.com/", wait_until="domcontentloaded", timeout=30000)
        await page.wait_for_timeout(3000)

        if "login" not in page.url.lower():
            cookies = await ctx.cookies()
            Path("data/.taobao_cookies.json").write_text(json.dumps(cookies), encoding="utf-8")
            print("OK")
            await browser.close()
            return

        for sel in ['text=\u5bc6\u7801\u767b\u5f55', 'a:has-text("\u5bc6\u7801\u767b\u5f55")']:
            tab = await page.query_selector(sel)
            if tab:
                await tab.click()
                await page.wait_for_timeout(2000)
                break

        try:
            cb = await page.query_selector("#fm-agreement-checkbox")
            if cb and not await cb.is_checked():
                await cb.check()
                await page.wait_for_timeout(500)
        except:
            pass

        for sel in ["#fm-login-id", 'input[placeholder*="\u624b\u673a"]']:
            el = await page.query_selector(sel)
            if el:
                await el.fill(u)
                await page.wait_for_timeout(500)
                break

        for sel in ["#fm-login-password", 'input[type="password"]']:
            el = await page.query_selector(sel)
            if el:
                await el.fill(p)
                await page.wait_for_timeout(500)
                break

        for sel in ["#fm-login-submit", 'button[type="submit"]', ".fm-button"]:
            btn = await page.query_selector(sel)
            if btn:
                await btn.click()
                break
        else:
            await page.keyboard.press("Enter")

        try:
            await page.wait_for_url(lambda u: "login" not in u.lower(), timeout=20000)
        except:
            pass

        await page.wait_for_timeout(5000)

        if "login" not in page.url.lower():
            cookies = await ctx.cookies()
            Path("data/.taobao_cookies.json").write_text(json.dumps(cookies), encoding="utf-8")
            print("OK")
        else:
            print("FAIL: SMS may be needed")

        await browser.close()

asyncio.run(main())
'@ | Set-Content -Path "data\_login_test.py" -Encoding utf8

Invoke-Expression "$pythonCmd data\_login_test.py"
Remove-Item data\_login_test.py -Force -ErrorAction SilentlyContinue

if (Test-Path "data\.taobao_cookies.json") {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  Login successful!" -ForegroundColor Green
    Write-Host "========================================`n" -ForegroundColor Cyan
    Write-Host "  Next: double-click run.bat" -ForegroundColor White
} else {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  WARNING: Login may need SMS." -ForegroundColor Red
    Write-Host "========================================`n" -ForegroundColor Cyan
}
Read-Host "Press Enter to close"
