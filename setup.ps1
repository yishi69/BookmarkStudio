param(
    [string]$Configuration = "Debug"
)

# Ensure console uses UTF-8 so Chinese characters are not garbled in VS/PowerShell
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::InputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
    if (Get-Command chcp -ErrorAction SilentlyContinue) { chcp 65001 > $null }
} catch {
    # best-effort, ignore failures
}

function Fail($msg) {
    Write-Host "ERROR: $msg" -ForegroundColor Red
    exit 1
}

Write-Host "Checking tools: dotnet, msbuild, vswhere..." -ForegroundColor Cyan

# dotnet
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    Fail "dotnet not found. Install .NET SDK or use Developer PowerShell."
}

# msbuild
$msbuild = Get-Command msbuild.exe -ErrorAction SilentlyContinue
if ($msbuild) {
    Write-Host "msbuild: $($msbuild.Path)"
} else {
    Write-Host "msbuild not found; will attempt dotnet build as fallback."
}

# vswhere (用于检查 Visual Studio)
$vswherePath = "$env:ProgramFiles(x86)\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswherePath)) {
    Write-Host 'vswhere not found; cannot detect Visual Studio components. Ensure Visual Studio is installed with the "Visual Studio extension development" workload.' -ForegroundColor Yellow
} else {
    & $vswherePath -products * -latest -property installationPath | ForEach-Object {
        Write-Host "Detected Visual Studio: $_"
    }
}

Write-Host "Restoring NuGet / restoring dependencies..." -ForegroundColor Cyan
Push-Location $PSScriptRoot
try {
    dotnet restore BookmarkStudio.slnx
} catch {
    Fail "dotnet restore 失败: $_"
}

Write-Host "Building (Configuration: $Configuration)..." -ForegroundColor Cyan
if ($msbuild) {
    $exit = & $msbuild.Path "BookmarkStudio.slnx" /p:Configuration=$Configuration
    if ($LASTEXITCODE -ne 0) { Fail "msbuild 构建失败 (exit $LASTEXITCODE)." }
} else {
    $res = dotnet build "src\BookmarkStudio.csproj" -c $Configuration
    if ($LASTEXITCODE -ne 0) { Fail "dotnet build 失败 (exit $LASTEXITCODE)." }
}

Write-Host "Running unit tests..." -ForegroundColor Cyan
if (Test-Path "test\BookmarkStudio.Test\BookmarkStudio.Test.csproj") {
    dotnet test "test\BookmarkStudio.Test\BookmarkStudio.Test.csproj" -c $Configuration
    if ($LASTEXITCODE -ne 0) { Fail "Unit tests failed (exit $LASTEXITCODE)." }
} else {
    Write-Host "No test project found, skipping tests." -ForegroundColor Yellow
}

$WriteHost = Write-Host
Write-Host "Searching for generated VSIX files..." -ForegroundColor Cyan
$vsix = Get-ChildItem -Path . -Filter *.vsix -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if ($vsix) {
    Write-Host "Found VSIX: $($vsix.FullName)" -ForegroundColor Green
} else {
    Write-Host "No .vsix found in repository; it may be under build output (Debug/Release)." -ForegroundColor Yellow
    $found = Get-ChildItem -Path src -Filter *.vsix -Recurse -ErrorAction SilentlyContinue
    if ($found) { $found | ForEach-Object { Write-Host $_.FullName } }
}

Write-Host "" 
Write-Host 'Done. If Visual Studio extension components are missing, run Visual Studio Installer and install the "Visual Studio extension development" workload, then retry.' -ForegroundColor Green
Pop-Location
