;; AHK# — CS.Eval: One-Liner Expressions
;; Evaluate C# expressions inline without defining a CSModule class.
;; Result is compiled and cached — second call with same expression is instant.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

; ── Math ──────────────────────────────────────────────────────────────────────
pi := CS.Eval("Math.PI")
sqrtVal := CS.Eval("Math.Sqrt(144)")
combined := CS.Eval("Math.Pow(2, 10) + Math.E")

msg := "π = " pi
    . "`n√144 = " sqrtVal
    . "`n2¹⁰ + e = " combined
MsgBox(msg, "AHK# — CS.Eval: Math")

; ── String Operations ─────────────────────────────────────────────────────────
upper := CS.Eval('"hello world".ToUpper()')
reversed := CS.Eval('new string("AHK Sharp".ToCharArray().Reverse().ToArray())')
b64 := CS.Eval('Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes("Hello AHK#"))')

msg2 := "Upper: " upper
    . "`nReversed: " reversed
    . "`nBase64: " b64
MsgBox(msg2, "AHK# — CS.Eval: Strings")

; ── System Info ───────────────────────────────────────────────────────────────
guid := CS.Eval("Guid.NewGuid().ToString()")
ticks := CS.Eval("DateTime.Now.Ticks")
cores := CS.Eval("Environment.ProcessorCount")

msg3 := "GUID: " guid
    . "`nTicks: " ticks
    . "`nCPU cores: " cores
MsgBox(msg3, "AHK# — CS.Eval: System")

; ── LINQ ──────────────────────────────────────────────────────────────────────
sum := CS.Eval("Enumerable.Range(1, 100).Sum()")
evens := CS.Eval("Enumerable.Range(1, 20).Where(x => x % 2 == 0).Count()")

msg4 := "Sum(1..100) = " sum
    . "`nEven count(1..20) = " evens
MsgBox(msg4, "AHK# — CS.Eval: LINQ")

; ── File System ───────────────────────────────────────────────────────────────
tempPath := CS.Eval("Path.GetTempPath()")
drives := CS.Eval('string.Join(", ", Directory.GetLogicalDrives())')

msg5 := "Temp path: " tempPath
    . "`nDrives: " drives
MsgBox(msg5, "AHK# — CS.Eval: File System")

MsgBox("CS.Eval demo complete!`n`nAll expressions are cached — re-run is instant.", "AHK# — Done", 0x40)
ExitApp()
