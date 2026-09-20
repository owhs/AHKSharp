<#
  lint_docs.ps1 — catches documentation drift.

    powershell -File tests\lint_docs.ps1

  Checks README.md and docs\*.md for:
    1. relative markdown links that point at files that do not exist
    2. repository paths written in `backticks` (lib\, src\, ext\, examples\, tests\, docs\, workbench\) that do not exist
    3. CS.<Member> uses in code blocks / inline code that are not real members of the CS class
    4. _CS... / helper names mentioned in the docs that are not defined in lib\ahk#.ahk
    5. bridge (.cs) file names mentioned that do not exist under src\
  Exit code = number of problems.
#>
$root = Split-Path -Parent $PSScriptRoot
$docs = @(Get-Item (Join-Path $root "README.md")) + @(Get-ChildItem (Join-Path $root "docs") -Filter "*.md")
$lib = [IO.File]::ReadAllText((Join-Path $root "lib\ahk#.ahk"))

# real members of the CS class (static methods / properties) — read from the source, not hard-coded
$csBlock = [regex]::Match($lib, '(?ms)^class CS \{.*?^\}\s*$').Value
$members = [regex]::Matches($csBlock, '(?m)^\s{4}static\s+(\w+)') | ForEach-Object { $_.Groups[1].Value }
$members += @("Fast", "NuGet", "Config", "Promise")           # returned by CS.__Get
$members = $members | Where-Object { $_ -notmatch '^_' -and $_ -notin @("__Get", "Call") } | Sort-Object -Unique
$dotnetRoots = @("System", "Microsoft", "Windows", "Accessibility", "PresentationCore", "PresentationFramework", "WindowsBase", "UIAutomationClient", "MyNamespace", "Newtonsoft", "MyLib", "Acme", "Foo", "Company", "Name", "Namespace", "Type", "X", "TypeName", "Ns")

$problems = @()
foreach ($d in $docs) {
    $text = [IO.File]::ReadAllText($d.FullName)
    $rel = $d.FullName.Substring($root.Length + 1)

    # 1. markdown links
    foreach ($m in [regex]::Matches($text, '\]\((?!https?:|#|mailto:)([^)\s]+)\)')) {
        $target = [uri]::UnescapeDataString($m.Groups[1].Value.Split('#')[0])
        if ($target -eq "") { continue }
        $full = Join-Path $d.DirectoryName $target
        if (-not (Test-Path $full)) { $problems += "$rel : broken link -> $target" }
    }

    # 2. repository paths in backticks
    foreach ($m in [regex]::Matches($text, '`((?:lib|src|ext|examples|tests|docs|workbench)[\\/][^`\s]*)`')) {
        $p = $m.Groups[1].Value.TrimEnd('\', '/', '.', ',')
        if ($p -match '[*<>{}]|\.\.\.') { continue }
        if (-not (Test-Path (Join-Path $root $p))) { $problems += "$rel : path does not exist -> $p" }
    }

    # 3. CS.<Member>
    foreach ($m in [regex]::Matches($text, '(?<![\w.])CS\.([A-Za-z_]\w*)')) {
        $name = $m.Groups[1].Value
        if ($name -in $members -or $name -in $dotnetRoots) { continue }
        if ($name -cmatch '^[A-Z]' -and $name.Length -le 12 -and $text -match "CS\.$name\.") { continue }   # a .NET namespace root in an example
        $problems += "$rel : CS.$name is not a member of CS"
    }

    # 4. underscore-prefixed AHK# internals mentioned in the docs
    foreach ($m in [regex]::Matches($text, '(?<![\w])(_CS\w+)')) {
        $name = $m.Groups[1].Value
        if ($lib -notmatch "(?m)^(class )?$name\b|\b$name\s*\(|static $name\b") { $problems += "$rel : $name is not defined in lib\ahk#.ahk" }
    }

    # 5. .cs files mentioned
    foreach ($m in [regex]::Matches($text, '(?<![\w\\/.])([A-Z][A-Za-z]+\.cs)\b')) {
        $n = $m.Groups[1].Value
        if (-not (Get-ChildItem (Join-Path $root "src") -Recurse -Filter $n -ErrorAction SilentlyContinue) -and
            -not (Get-ChildItem (Join-Path $root "workbench") -Recurse -Filter $n -ErrorAction SilentlyContinue) -and
            -not (Get-ChildItem (Join-Path $root "examples") -Recurse -Filter $n -ErrorAction SilentlyContinue)) {
            $problems += "$rel : $n is not in the repository"
        }
    }
}

$problems = $problems | Sort-Object -Unique
if ($problems.Count) { $problems | ForEach-Object { Write-Host $_ -ForegroundColor Red } }
Write-Host ("docs lint: {0} problem(s) across {1} files" -f $problems.Count, $docs.Count) -ForegroundColor $(if ($problems.Count) { "Red" } else { "Green" })
exit $problems.Count
