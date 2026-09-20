<#
  tests\run-ahk.ps1 — run an AutoHotkey v2 script headlessly and REPORT any dialog it shows.

  Why: AHK error dialogs / MsgBoxes block the process and pop up on the user's screen. This wrapper
  polls the child's top-level windows, reads every dialog's text (title, static/edit/button text),
  kills the process, and prints what it found — so nobody has to read a dialog aloud.

  Usage (PowerShell tool, NOT Git Bash — Bash rewrites the /ErrorStdOut flag into a path):
    powershell -File tests\run-ahk.ps1 -Script path\to\script.ahk -TimeoutSec 60   (AHK_EXE overrides the interpreter path)

  Output sections: EXIT / STDOUT / STDERR / DIALOGS. Exit code 3 = a dialog appeared (process killed),
  4 = timeout (process killed), otherwise the script's own exit code.
  Scripts should report via FileAppend(text "`n", "**")  (** = stderr, * = stdout).
#>
param(
    [Parameter(Mandatory)][string]$Script,
    [int]$TimeoutSec = 60,
    [string[]]$ScriptArgs = @(),
    [switch]$KeepGuiWindows,     # don't treat non-dialog windows as a problem (default already ignores them)
    [switch]$Validate,           # load + syntax-check only (AHK /validate): never runs the script
    [switch]$AutoDismiss         # click OK/Yes/Continue on plain MsgBoxes and log their text; still stop on error dialogs
)

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class WinProbe {
    delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc p, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr h, EnumProc p, IntPtr l);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, StringBuilder l);
    [DllImport("user32.dll")] static extern int GetWindowTextLength(IntPtr h);
    const int WM_GETTEXT = 0x000D;

    static string Text(IntPtr h) {
        int n = GetWindowTextLength(h);
        if (n <= 0) return "";
        StringBuilder sb = new StringBuilder(n + 2);
        SendMessage(h, WM_GETTEXT, (IntPtr)(n + 1), sb);   // works across processes for static/edit/button controls
        return sb.ToString();
    }

    static string Class(IntPtr h) {
        StringBuilder sb = new StringBuilder(256);
        GetClassName(h, sb, 256);
        return sb.ToString();
    }

    const int BM_CLICK = 0x00F5;

    /// <summary>Clicks the first OK/Yes/Continue button of the process' visible dialogs. Returns the dialog text it dismissed, or null.</summary>
    public static string DismissOk(int pid) {
        string dismissed = null;
        EnumWindows(delegate (IntPtr h, IntPtr l) {
            uint wp; GetWindowThreadProcessId(h, out wp);
            if (wp != (uint)pid || !IsWindowVisible(h) || Class(h) != "#32770") return true;
            StringBuilder sb = new StringBuilder();
            sb.Append("[").Append(Text(h)).Append("]");
            IntPtr okBtn = IntPtr.Zero;
            EnumChildWindows(h, delegate (IntPtr c, IntPtr l2) {
                string t = Text(c);
                if (Class(c) == "Button") {
                    string b = t.Replace("&", "");
                    if (okBtn == IntPtr.Zero && (b == "OK" || b == "Yes" || b == "Continue")) okBtn = c;
                } else if (t.Length > 0) sb.Append(" ").Append(t.Replace("\r\n", "\n").Replace("\n", " / "));
                return true;
            }, IntPtr.Zero);
            if (okBtn != IntPtr.Zero) { SendMessage(okBtn, BM_CLICK, IntPtr.Zero, null); dismissed = sb.ToString(); return false; }
            return true;
        }, IntPtr.Zero);
        return dismissed;
    }

    /// <summary>Visible dialog-class (#32770) top-level windows of a process, with all child text.</summary>
    public static string[] Dialogs(int pid) {
        List<string> found = new List<string>();
        EnumWindows(delegate (IntPtr h, IntPtr l) {
            uint wp; GetWindowThreadProcessId(h, out wp);
            if (wp != (uint)pid || !IsWindowVisible(h)) return true;
            if (Class(h) != "#32770") return true;
            StringBuilder sb = new StringBuilder();
            sb.Append("[").Append(Text(h)).Append("]");
            EnumChildWindows(h, delegate (IntPtr c, IntPtr l2) {
                string t = Text(c);
                if (t.Length > 0) sb.Append("\n    ").Append(Class(c)).Append(": ").Append(t.Replace("\r\n", "\n").Replace("\n", "\n      "));
                return true;
            }, IntPtr.Zero);
            found.Add(sb.ToString());
            return true;
        }, IntPtr.Zero);
        return found.ToArray();
    }
}
'@

$ahk = $env:AHK_EXE
if (-not $ahk) {
    $ahk = @("$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe", "$env:ProgramFiles\AutoHotkey\AutoHotkey64.exe", "${env:ProgramFiles(x86)}\AutoHotkey\v2\AutoHotkey32.exe") |
        Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $ahk) { Write-Error "AutoHotkey v2 not found. Set the AHK_EXE environment variable."; exit 2 }
$Script = (Resolve-Path -LiteralPath $Script).Path
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("runahk_" + [Guid]::NewGuid().ToString("N"))
$outF = "$tmp.out"; $errF = "$tmp.err"

$prelude = Join-Path $PSScriptRoot "prelude.ahk"
$flags = @("/ErrorStdOut=UTF-8")
if ($Validate) { $flags += "/validate" }
$argList = $flags + @("/include", "`"$prelude`"", "`"$Script`"") + $ScriptArgs
$p = Start-Process -FilePath $ahk -ArgumentList $argList -RedirectStandardOutput $outF -RedirectStandardError $errF -PassThru -WindowStyle Hidden

$sw = [Diagnostics.Stopwatch]::StartNew()
$dialogs = @(); $code = $null; $dismissedLog = @()
while ($true) {
    if ($p.HasExited) { $code = $p.ExitCode; break }
    if ($AutoDismiss) {
        $msg = [WinProbe]::DismissOk($p.Id)
        while ($msg) { $dismissedLog += $msg; Start-Sleep -Milliseconds 80; $msg = [WinProbe]::DismissOk($p.Id) }
    }
    $d = [WinProbe]::Dialogs($p.Id)
    if ($d.Count -gt 0) {
        Start-Sleep -Milliseconds 250                      # let the dialog finish creating its controls
        $dialogs = [WinProbe]::Dialogs($p.Id); $code = 3
        break
    }
    if ($sw.Elapsed.TotalSeconds -gt $TimeoutSec) { $code = 4; break }
    Start-Sleep -Milliseconds 120
}
if (-not $p.HasExited) { try { $p.Kill() } catch {} ; $null = $p.WaitForExit(3000) }

"EXIT: $code" + $(if ($code -eq 3) { "  (a dialog appeared; process killed)" } elseif ($code -eq 4) { "  (timeout after ${TimeoutSec}s; process killed)" } else { "" })
"--- STDOUT"; if (Test-Path $outF) { Get-Content -LiteralPath $outF -Encoding UTF8 }
"--- STDERR"; if (Test-Path $errF) { Get-Content -LiteralPath $errF -Encoding UTF8 }
if ($dismissedLog.Count -gt 0) { "--- MSGBOXES DISMISSED (" + $dismissedLog.Count + ")"; $dismissedLog }
if ($dialogs.Count -gt 0) { "--- DIALOGS"; $dialogs }
Remove-Item -LiteralPath $outF, $errF -ErrorAction SilentlyContinue
exit $code
