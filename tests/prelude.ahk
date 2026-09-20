; Injected by tests\run-ahk.ps1 via /include: turns every unhandled error (including load-time class
; initialisers such as _CSModule compile errors) into text on stderr + exit code 9, never a dialog.
#Requires AutoHotkey v2.0
OnError(_RunAhkOnError, -1)
_RunAhkOnError(e, mode) {
    msg := "UNHANDLED " Type(e) ": " e.Message
    if (e.HasProp("Extra") && e.Extra != "")
        msg .= "`n  Specifically: " e.Extra
    if (e.HasProp("File"))
        msg .= "`n  at " e.File " line " e.Line
    try msg .= "`n" e.Stack
    FileAppend(msg "`n", "**")
    ExitApp(9)
}
