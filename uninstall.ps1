# Uninstall local runtime files for TaoBao Procurement Automation.
$workdir = Split-Path $MyInvocation.MyCommand.Path -Parent
Set-Location $workdir
$purchaseListName = (-join [char[]](0x91C7, 0x8D2D, 0x6E05, 0x5355)) + ".xlsx"

function Remove-ProjectPath {
    param([string]$TargetPath)

    $root = [IO.Path]::GetFullPath($workdir).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    $fullPath = [IO.Path]::GetFullPath($TargetPath)
    $rootPrefix = $root + [IO.Path]::DirectorySeparatorChar

    if (-not $fullPath.StartsWith(
        $rootPrefix,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "Refusing to remove a path outside the project: $fullPath"
    }

    if (-not (Test-Path -LiteralPath $fullPath)) {
        Write-Host "  Not found, skipped: $fullPath" -ForegroundColor DarkGray
        return $false
    }

    try {
        Remove-Item -LiteralPath $fullPath -Recurse -Force -ErrorAction Stop
        Write-Host "  Removed: $fullPath" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "  Failed: $fullPath" -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  TaoBao Tool Uninstall" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This removes local runtime files only." -ForegroundColor White
Write-Host "Project source files will be kept." -ForegroundColor White
Write-Host ""
Write-Host "[1] Safe uninstall (recommended)" -ForegroundColor Yellow
Write-Host "    Remove .venv, project Chromium, credentials, and cookies." -ForegroundColor DarkGray
Write-Host "    Keep purchase list: $purchaseListName" -ForegroundColor DarkGray
Write-Host ""
Write-Host "[2] Full cleanup" -ForegroundColor Yellow
Write-Host "    Also remove purchase list: $purchaseListName" -ForegroundColor DarkGray
Write-Host ""
Write-Host "[Q] Cancel" -ForegroundColor White
Write-Host ""

$choice = Read-Host "Choose an option (default: 1)"
if ([string]::IsNullOrWhiteSpace($choice)) {
    $choice = "1"
}
if ($choice -match '^[Qq]$') {
    Write-Host "Cancelled." -ForegroundColor Yellow
    Read-Host "Press Enter to close"
    exit 0
}
if ($choice -notin @("1", "2")) {
    Write-Host "Invalid option. Nothing was removed." -ForegroundColor Red
    Read-Host "Press Enter to close"
    exit 1
}

Write-Host ""
Write-Host "WARNING: Account data and login cookies will be deleted." -ForegroundColor Red
if ($choice -eq "2") {
    Write-Host "WARNING: The Excel purchase list will also be deleted." -ForegroundColor Red
}
$confirmation = Read-Host "Type UNINSTALL to continue"
if ($confirmation -cne "UNINSTALL") {
    Write-Host "Cancelled. Nothing was removed." -ForegroundColor Yellow
    Read-Host "Press Enter to close"
    exit 0
}

Write-Host ""
Write-Host "Removing local files..." -ForegroundColor Yellow
$targets = @(
    (Join-Path $workdir ".venv"),
    (Join-Path $workdir ".playwright-browsers"),
    (Join-Path $workdir "data")
)
if ($choice -eq "2") {
    $targets += (Join-Path $workdir $purchaseListName)
}

$removedCount = 0
foreach ($target in $targets) {
    if (Remove-ProjectPath $target) {
        $removedCount++
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Uninstall finished." -ForegroundColor Green
Write-Host "  Removed targets: $removedCount" -ForegroundColor Green
Write-Host "  Source files were kept." -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "A Chromium cache installed by older versions in" -ForegroundColor DarkGray
Write-Host "%LOCALAPPDATA%\ms-playwright was not removed because it may be shared." -ForegroundColor DarkGray
Write-Host "Run setup.bat to install this project again." -ForegroundColor White
Read-Host "Press Enter to close"
