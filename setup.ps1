# Setup - TaoBao Procurement Automation (Windows)
$workdir = Split-Path $MyInvocation.MyCommand.Path -Parent
Set-Location $workdir

function Stop-Setup {
    param([string]$Message)
    Write-Host "      ERROR: $Message" -ForegroundColor Red
    Read-Host "Press Enter to close"
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Setup - First Time Configuration" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Find Python 3.10+ and create one project-local environment.
Write-Host "[1/3] Preparing Python environment..." -ForegroundColor Yellow

$pythonCandidates = @(
    [pscustomobject]@{ Command = "py"; Arguments = @("-3") },
    [pscustomobject]@{ Command = "python"; Arguments = @() }
)
$launcher = $null

foreach ($candidate in $pythonCandidates) {
    $command = $candidate.Command
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        continue
    }
    $arguments = $candidate.Arguments
    $version = & $command @arguments -c "import sys; print('.'.join(map(str, sys.version_info[:3]))); raise SystemExit(0 if sys.version_info >= (3, 10) else 1)" 2>$null
    if ($LASTEXITCODE -eq 0) {
        $launcher = $candidate
        Write-Host "      Found Python $version ($command $($arguments -join ' '))" -ForegroundColor Green
        break
    }
}

if (-not $launcher) {
    Stop-Setup "Python 3.10+ was not found. Install it from https://python.org and enable 'Add Python to PATH'."
}

$venvDir = Join-Path $workdir ".venv"
$pythonExe = Join-Path $venvDir "Scripts\python.exe"

if (-not (Test-Path $pythonExe)) {
    Write-Host "      Creating local environment..." -ForegroundColor Yellow
    $launcherCommand = $launcher.Command
    $launcherArguments = $launcher.Arguments
    & $launcherCommand @launcherArguments -m venv $venvDir
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $pythonExe)) {
        Stop-Setup "Could not create the local Python environment."
    }
}

& $pythonExe -c "import playwright, openpyxl" 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "      Installing Python packages..." -ForegroundColor Yellow
    & $pythonExe -m pip install --disable-pip-version-check -r (Join-Path $workdir "requirements.txt")
    if ($LASTEXITCODE -ne 0) {
        Stop-Setup "Python package installation failed. Check the internet connection or proxy."
    }
} else {
    Write-Host "      Python packages already installed." -ForegroundColor Green
}
Write-Host ""

# Step 2: Let Playwright install/check the exact Chromium version it needs.
Write-Host "[2/3] Checking Chromium browser..." -ForegroundColor Yellow
& $pythonExe -m playwright install chromium
if ($LASTEXITCODE -ne 0) {
    Stop-Setup "Chromium installation failed. Check the internet connection, firewall, or proxy."
}

$browserCheck = @'
from playwright.sync_api import sync_playwright
with sync_playwright() as pw:
    browser = pw.chromium.launch(headless=True)
    browser.close()
'@
$browserCheck | & $pythonExe -
if ($LASTEXITCODE -ne 0) {
    Stop-Setup "Chromium was downloaded but could not start."
}
Write-Host "      Chromium is ready." -ForegroundColor Green
Write-Host ""

# Step 3: Configure Taobao login.
Write-Host "[3/3] Taobao login" -ForegroundColor Yellow
$dataDir = Join-Path $workdir "data"
$envFile = Join-Path $dataDir ".taobao.env"
$cookieFile = Join-Path $dataDir ".taobao_cookies.json"

if ((Test-Path $envFile) -and (Test-Path $cookieFile)) {
    Write-Host "      Existing login data found, skipping login." -ForegroundColor Green
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  All set. Double-click run.bat to start." -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    Read-Host "Press Enter to close"
    exit 0
}

Write-Host "      Enter your Taobao credentials." -ForegroundColor DarkGray
do {
    $phone = Read-Host "      Phone number (11 digits)"
    if ($phone -notmatch '^\d{11}$') {
        Write-Host "      Must be exactly 11 digits." -ForegroundColor Red
        $phone = ""
    }
} while ($phone -eq "")

$securePassword = Read-Host "      Password" -AsSecureString
$passwordPtr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
try {
    $passwordText = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPtr)
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPtr)
}

New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
Set-Content -Path $envFile -Encoding utf8 -Value "# Taobao credentials - LOCAL ONLY`nTAOBAO_USERNAME=$phone`nTAOBAO_PASSWORD=$passwordText"
$passwordText = $null

Write-Host ""
Write-Host "      A Chromium window will open." -ForegroundColor Yellow
Write-Host "      Complete SMS, slider, or identity verification in that window if requested." -ForegroundColor Yellow

$loginScript = Join-Path $dataDir "_login_setup.py"
@'
import asyncio
import json
import sys
import time
from pathlib import Path

from playwright.async_api import async_playwright

AUTH_MARKERS = (
    "login.taobao.com",
    "passport.taobao.com",
    "login_jump",
    "normal_validate",
)
LOGIN_COOKIE_NAMES = {"cookie2", "cookie17", "tracknick", "lgc"}


def is_auth_page(url):
    lowered = (url or "").lower()
    return any(marker in lowered for marker in AUTH_MARKERS)


def load_env():
    values = {}
    for line in Path("data/.taobao.env").read_text(encoding="utf-8").splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip()
    return values


async def main():
    env = load_env()
    username = env.get("TAOBAO_USERNAME", "")
    password = env.get("TAOBAO_PASSWORD", "")
    if not username or not password:
        print("FAIL: credentials are missing")
        return 2

    async with async_playwright() as pw:
        browser = await pw.chromium.launch(
            headless=False,
            args=["--disable-blink-features=AutomationControlled"],
        )
        context = await browser.new_context(
            viewport={"width": 1366, "height": 768},
            locale="zh-CN",
        )
        page = await context.new_page()
        await page.add_init_script(
            "Object.defineProperty(navigator, 'webdriver', {get: () => undefined})"
        )

        try:
            await page.goto(
                "https://login.taobao.com/",
                wait_until="domcontentloaded",
                timeout=30000,
            )
        except Exception:
            pass
        await page.wait_for_timeout(3000)

        for selector in [
            'text=\u5bc6\u7801\u767b\u5f55',
            'a:has-text("\u5bc6\u7801\u767b\u5f55")',
        ]:
            try:
                tab = await page.query_selector(selector)
                if tab:
                    await tab.click()
                    await page.wait_for_timeout(1500)
                    break
            except Exception:
                pass

        try:
            checkbox = await page.query_selector("#fm-agreement-checkbox")
            if checkbox and not await checkbox.is_checked():
                await checkbox.check()
        except Exception:
            pass

        for selector in ["#fm-login-id", 'input[placeholder*="\u624b\u673a"]']:
            field = await page.query_selector(selector)
            if field:
                await field.fill(username)
                break

        for selector in ["#fm-login-password", 'input[type="password"]']:
            field = await page.query_selector(selector)
            if field:
                await field.fill(password)
                break

        for selector in ["#fm-login-submit", 'button[type="submit"]', ".fm-button"]:
            button = await page.query_selector(selector)
            if button:
                await button.click()
                break

        print("Complete any verification in the Chromium window. Waiting up to 5 minutes...")
        deadline = time.monotonic() + 300
        while time.monotonic() < deadline:
            if page.is_closed():
                break
            cookies = await context.cookies()
            cookie_names = {cookie.get("name") for cookie in cookies}
            if not is_auth_page(page.url) and LOGIN_COOKIE_NAMES.intersection(cookie_names):
                Path("data/.taobao_cookies.json").write_text(
                    json.dumps(cookies, ensure_ascii=False, indent=2),
                    encoding="utf-8",
                )
                print("OK")
                await browser.close()
                return 0
            await page.wait_for_timeout(1000)

        print("FAIL: login or verification was not completed")
        await browser.close()
        return 2


raise SystemExit(asyncio.run(main()))
'@ | Set-Content -Path $loginScript -Encoding utf8

& $pythonExe $loginScript
$loginExitCode = $LASTEXITCODE
Remove-Item -LiteralPath $loginScript -Force -ErrorAction SilentlyContinue

if ($loginExitCode -eq 0 -and (Test-Path $cookieFile)) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Login successful!" -ForegroundColor Green
    Write-Host "  Double-click run.bat to start." -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
} else {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Login was not completed." -ForegroundColor Red
    Write-Host "  Run setup.bat again and finish verification." -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Cyan
}

Read-Host "Press Enter to close"
