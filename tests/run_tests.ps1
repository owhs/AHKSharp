<#
  run_tests.ps1 — run every tests\test_*.ahk and report.

    powershell -File tests\run_tests.ps1                    # all suites
    powershell -File tests\run_tests.ps1 -Filter binder     # only test_binder.ahk
    $env:AHKSHARP_NET = "1"; powershell -File tests\run_tests.ps1   # also the network tests (Http, NuGet)

  Each suite runs in its own AutoHotkey process through tests\run-ahk.ps1, which turns any error
  dialog / MsgBox into text and kills the process, so a broken test can never hang a run.
  Exit code = number of failing tests (or suites that crashed).
#>
param(
    [string]$Filter = "",
    [int]$TimeoutSec = 180
)

$here = $PSScriptRoot
$runner = Join-Path $here "run-ahk.ps1"
$suites = Get-ChildItem $here -Filter "test_*.ahk" | Where-Object { $_.Name -like "*$Filter*" } | Sort-Object Name
$failed = 0; $passed = 0; $skipped = 0; $crashed = @()

foreach ($s in $suites) {
    Write-Host ("== " + $s.Name) -ForegroundColor Cyan
    # test_net*.ahk needs the network at load time (module classes compile when defined): only with AHKSHARP_NET=1
    if ($s.Name -like "test_net*" -and $env:AHKSHARP_NET -ne "1") {
        Write-Host "  skipped (set AHKSHARP_NET=1)" -ForegroundColor DarkGray; $skipped++; continue
    }
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $runner -Script $s.FullName -TimeoutSec $TimeoutSec 2>&1 | Out-String
    $lines = $out -split "`r?`n"
    $exit = ([regex]::Match($out, "EXIT: (\d+)")).Groups[1].Value
    $summary = $lines | Where-Object { $_ -match "^# pass=(\d+) fail=(\d+) skip=(\d+)" } | Select-Object -Last 1
    foreach ($l in $lines) {
        if ($l -match "^not ok") { Write-Host ("  " + $l) -ForegroundColor Red }
        elseif ($l -match "# SKIP") { Write-Host ("  " + $l) -ForegroundColor DarkGray }
    }
    if ($summary -match "pass=(\d+) fail=(\d+) skip=(\d+)") {
        $passed += [int]$Matches[1]; $failed += [int]$Matches[2]; $skipped += [int]$Matches[3]
        Write-Host ("  " + $summary.TrimStart('# ')) -ForegroundColor $(if ([int]$Matches[2] -gt 0) { "Red" } else { "Green" })
    } else {
        $crashed += $s.Name
        Write-Host "  SUITE DID NOT FINISH (exit $exit)" -ForegroundColor Red
        $out.Split("`n") | Select-Object -First 25 | ForEach-Object { Write-Host ("    " + $_) -ForegroundColor DarkYellow }
    }
}

Write-Host ""
Write-Host ("TOTAL  pass=$passed  fail=$failed  skip=$skipped  crashed=" + $crashed.Count) -ForegroundColor $(if ($failed + $crashed.Count -gt 0) { "Red" } else { "Green" })
exit ($failed + $crashed.Count)
