# AHK# Bridge v2.0 — Full Build Script
# Compiles ALL C# source files into a single ahk#.bridge.dll
# Uses content-hashing for aggressive caching — only recompiles when source changes.
#
# Why .NET Framework v4.0.30319?
#   This is the widest natively-compatible CLR on Windows:
#   - Windows 7 SP1+, 8, 8.1 — .NET 4.0 via Windows Update
#   - Windows 10/11          — .NET 4.8 pre-installed
#   Result: ZERO dependency installs on any supported Windows version.

param(
    [switch]$Force,
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$libDir = Join-Path $root "lib"
$outDll = Join-Path $libDir "ahk#.bridge.dll"
$srcDir = Join-Path $root "src"

# Ensure lib directory exists
if (!(Test-Path $libDir)) { New-Item -ItemType Directory -Path $libDir -Force | Out-Null }

# ── Gather all C# source files ────────────────────────────────────────────
$sourceFiles = Get-ChildItem $srcDir -Recurse -Filter "*.cs" | Sort-Object FullName
$srcPaths = $sourceFiles | ForEach-Object { $_.FullName }

if ($Verbose) {
    Write-Host "[AHK#] Source files:" -ForegroundColor DarkGray
    $sourceFiles | ForEach-Object { Write-Host "  $($_.FullName)" -ForegroundColor DarkGray }
}

# ── Content Hash Check ─────────────────────────────────────────────────────
$hasher = [System.Security.Cryptography.SHA256]::Create()
$combinedBytes = [System.Text.Encoding]::UTF8.GetBytes(($sourceFiles | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n")
$hashBytes = $hasher.ComputeHash($combinedBytes)
$srcHash = [BitConverter]::ToString($hashBytes).Replace("-", "").Substring(0, 16)
$hashFile = Join-Path $libDir ".bridge_hash"

if (!$Force -and (Test-Path $outDll) -and (Test-Path $hashFile)) {
    $cachedHash = Get-Content $hashFile -Raw
    if ($cachedHash.Trim() -eq $srcHash) {
        if ($Verbose) { Write-Host "[AHK#] Bridge DLL is up-to-date (hash: $srcHash)" -ForegroundColor Green }
        exit 0
    }
}

Write-Host "[AHK#] Compiling $($sourceFiles.Count) source files..." -ForegroundColor Cyan

# ── Locate csc.exe ─────────────────────────────────────────────────────────
# Uses the built-in .NET Framework 4.x compiler (C# 4.0 syntax)
# This ensures zero dependencies — csc.exe ships with every Windows install
$cscPath = Join-Path $env:windir "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (!(Test-Path $cscPath)) {
    $cscPath = Join-Path $env:windir "Microsoft.NET\Framework\v4.0.30319\csc.exe"
}
if (!(Test-Path $cscPath)) {
    Write-Error "[AHK#] FATAL: csc.exe not found. .NET Framework 4.x is required."
    exit 1
}

# ── Reference Assemblies ───────────────────────────────────────────────────
# Core .NET assemblies for the bridge functionality
$fxDir = Split-Path $cscPath
$wpfDir = Join-Path $fxDir "WPF"

$refs = @(
    "System.dll", "System.Core.dll", "Microsoft.CSharp.dll",
    "System.Data.dll", "System.Drawing.dll", "System.Windows.Forms.dll",
    "System.Xml.dll", "System.Xml.Linq.dll",
    "System.IO.Compression.dll", "System.IO.Compression.FileSystem.dll",  # NuGet ZIP extraction
    "System.Net.dll",                                                       # HTTP downloads
    "UIAutomationClient.dll", "UIAutomationTypes.dll", "WindowsBase.dll"
)

$refArgs = ($refs | ForEach-Object { "/reference:`"$_`"" }) -join " "
$srcArgs = ($srcPaths | ForEach-Object { "`"$_`"" }) -join " "

# ── Compile ────────────────────────────────────────────────────────────────
$compileCmd = "& `"$cscPath`" /nologo /target:library /optimize+ /unsafe /out:`"$outDll`" /lib:`"$fxDir`" /lib:`"$wpfDir`" $refArgs $srcArgs 2>&1"

if ($Verbose) { Write-Host "[AHK#] $compileCmd" -ForegroundColor DarkGray }

$output = Invoke-Expression $compileCmd

if ($LASTEXITCODE -ne 0) {
    Write-Host "[AHK#] Compilation FAILED:" -ForegroundColor Red
    $output | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
}

# ── Success ────────────────────────────────────────────────────────────────
$srcHash | Out-File $hashFile -Encoding UTF8 -NoNewline
$dllSize = (Get-Item $outDll).Length / 1KB
Write-Host "[AHK#] Bridge compiled successfully: $([math]::Round($dllSize, 1)) KB ($($sourceFiles.Count) source files)" -ForegroundColor Green
Write-Host "[AHK#] Output: $outDll" -ForegroundColor DarkGray

exit 0
