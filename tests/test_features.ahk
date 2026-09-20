#Include harness.ahk

; Runs an AHK script in a child process; returns [exitCode, stdout, stderr]
RunChild(script) {
    out := A_Temp "\ahksharp_child_" A_TickCount ".out"
    err := A_Temp "\ahksharp_child_" A_TickCount ".err"
    ; /include prelude.ahk turns every unhandled error into stderr text + exit code 9 — a child never opens a dialog
    code := RunWait(A_ComSpec ' /c ""' A_AhkPath '" /ErrorStdOut=UTF-8 /include "' A_ScriptDir '\prelude.ahk" "' script '" > "' out '" 2> "' err '""', , "Hide")
    o := FileExist(out) ? FileRead(out, "UTF-8") : ""
    e := FileExist(err) ? FileRead(err, "UTF-8") : ""
    try FileDelete(out)
    try FileDelete(err)
    return [code, o, e]
}

libDir := A_ScriptDir "\..\lib"

; ── tracing ───────────────────────────────────────────────────────────────────
Test("CS.Config.Trace logs each call with timing", () => (
    __state["trace"] := "", CS.Config.Trace := (line) => __state["trace"] := line,
    CS.System.Math.Abs(-3), CS.Config.Trace := "",
    Has(__state["trace"], "System.Math.Abs(-3) => 3"), Has(__state["trace"], "us]")))
Test("Trace also reports failures", () => (
    __state["trace"] := "", CS.Config.Trace := (line) => __state["trace"] := line,
    Throws(() => CS.System.Int32.Parse("x")), CS.Config.Trace := "",
    Has(__state["trace"], "ERROR")))

; ── CS.Wrap generates a usable AHK class ──────────────────────────────────────
Test("CS.Wrap writes a class with real parameter names and overload comments", () => (
    src := CS.Wrap("System.Math", "", "MathW"), Has(src, "class MathW"), Has(src, "static Abs("), Has(src, "; Double Round(")))
Test("the wrapper file validates and forwards calls", () => _wrapTest())

_wrapTest() {
    stamp := A_TickCount
    wrapper := A_Temp "\ahksharp_wrap_" stamp ".ahk"
    script := A_Temp "\ahksharp_wrapuse_" stamp ".ahk"
    CS.Wrap("System.Math", wrapper, "MathW")
    FileAppend("#Requires AutoHotkey v2.0`n#Include " libDir "\ahk#.ahk`n#Include " wrapper "`n"
        . 'FileAppend(MathW.Round(2.567, 2) "|" MathW.Abs(-2.5) "|" MathW.Max(3.7, 2) "|" MathW.PI, "*")', script, "UTF-8")
    r := RunChild(script)
    try FileDelete(wrapper)
    try FileDelete(script)
    Eq(r[1], 0, "exit code (stderr: " SubStr(r[3], 1, 200) ")")
    parts := StrSplit(r[2], "|")
    Near(parts[1], 2.57)
    Near(parts[2], 2.5)
    Near(parts[3], 3.7)
    Near(parts[4], 3.14159265, 0.00001)
}

; ── the bridge DLL is pinned by SHA-256 ───────────────────────────────────────
Test("a modified bridge DLL is refused", () => _tamperTest())
Test("the intact DLL loads", () => _intactTest())

_stage() {
    dir := A_Temp "\ahksharp_pin_" A_TickCount
    DirCreate(dir)
    FileCopy(libDir "\ahk#.ahk", dir "\ahk#.ahk")
    FileCopy(libDir "\ahk#.bridge.dll", dir "\ahk#.bridge.dll")
    FileAppend("#Requires AutoHotkey v2.0`n#Include ahk#.ahk`nFileAppend(CS.System.Math.Abs(-7), `"*`")", dir "\t.ahk", "UTF-8")
    return dir
}

_tamperTest() {
    dir := _stage()
    f := FileOpen(dir "\ahk#.bridge.dll", "rw")
    f.Pos := f.Length - 5
    b := f.ReadUChar()
    f.Pos := f.Length - 5
    f.WriteUChar(b ^ 0xFF)
    f.Close()
    r := RunChild(dir "\t.ahk")
    try DirDelete(dir, true)
    IsTrue(r[1] != 0, "exit code should be non-zero")
    Has(r[3], "does not match the hash pinned")
}

_intactTest() {
    dir := _stage()
    r := RunChild(dir "\t.ahk")
    try DirDelete(dir, true)
    Eq(r[1], 0, "exit code (stderr: " SubStr(r[3], 1, 200) ")")
    Eq(r[2], "7")
}

; ── CS.Declare writes the editor declaration file ─────────────────────────────
Test("CS.Declare writes ahk#.d.ahk next to the library and later calls add to it", () => _declareTest())

_declareTest() {
    dir := A_Temp "\ahksharp_decl_" A_TickCount
    DirCreate(dir)
    FileCopy(libDir "\ahk#.ahk", dir "\ahk#.ahk")
    FileCopy(libDir "\ahk#.bridge.dll", dir "\ahk#.bridge.dll")
    FileAppend("#Requires AutoHotkey v2.0`n#Include ahk#.ahk`nCS.Declare(`"System.Text.StringBuilder`")`nCS.Declare(CS.System.Math, `"System.IO.File`")`nFileAppend(`"done`", `"*`")", dir "\t.ahk", "UTF-8")
    r := RunChild(dir "\t.ahk")
    text := ""
    try text := FileRead(dir "\ahk#.d.ahk", "UTF-8")
    try DirDelete(dir, true)
    Eq(r[2], "done", "child output (stderr: " SubStr(r[3], 1, 200) ")")
    Has(text, ";@specs System.Text.StringBuilder;System.Math;System.IO.File")
    Has(text, "class StringBuilder extends CS._Object")
    Has(text, "static Abs(value)")
    Has(text, "static ReadAllText(path, encoding := `"`")")
    IsTrue(!InStr(text, "ToString() =>", true) || InStr(text, "class StringBuilder"), "sane output")
}

Test("a modified DLL named by CS.Config.BridgeDll is refused too", () => _tamperCustomTest())
Test("an intact DLL named by CS.Config.BridgeDll loads", () => _intactCustomTest())

_stageCustom(tamper) {
    dir := A_Temp "\ahksharp_pin2_" A_TickCount
    DirCreate(dir "\lib")
    FileCopy(libDir "\ahk#.ahk", dir "\lib\ahk#.ahk")
    FileCopy(libDir "\ahk#.bridge.dll", dir "\custom.dll")
    if tamper {
        f := FileOpen(dir "\custom.dll", "rw")
        f.Pos := f.Length - 5
        b := f.ReadUChar()
        f.Pos := f.Length - 5
        f.WriteUChar(b ^ 0xFF)
        f.Close()
    }
    FileAppend("#Requires AutoHotkey v2.0`n#Include lib\ahk#.ahk`nCS.Config.BridgeDll := A_ScriptDir `"\custom.dll`"`nFileAppend(CS.System.Math.Abs(-7), `"*`")", dir "\t.ahk", "UTF-8")
    return dir
}

_tamperCustomTest() {
    dir := _stageCustom(true)
    r := RunChild(dir "\t.ahk")
    try DirDelete(dir, true)
    IsTrue(r[1] != 0, "exit code should be non-zero")
    Has(r[3], "does not match the hash pinned")
}

_intactCustomTest() {
    dir := _stageCustom(false)
    r := RunChild(dir "\t.ahk")
    try DirDelete(dir, true)
    Eq(r[1], 0, "exit code (stderr: " SubStr(r[3], 1, 200) ")")
    Eq(r[2], "7")
}

; ── config ────────────────────────────────────────────────────────────────────
Test("CS.Config.CallbackTimeoutMs round-trips", () => (CS.Config.CallbackTimeoutMs := 1234, Eq(CS.Config.CallbackTimeoutMs, 1234), CS.Config.CallbackTimeoutMs := 5000))

RunTests()
