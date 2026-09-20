;; AHK# — find your way around .NET: CS.Types, CS.Members, "did you mean", and editor autocomplete

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

out := ""

; What is in a namespace? What can a type do?
out .= "Types in System.IO (first 6):`n"
for i, line in StrSplit(CS.Types("System.IO"), "`n") {
    if (i > 6)
        break
    out .= "  " line "`n"
}
out .= "`nMath.Abs overloads:`n  " StrReplace(CS.Members(CS.System.Math, "abs"), "`n", "`n  ") "`n"

; Typos say what you probably meant
try CS.System.Math.Abss(1)
catch as e
    out .= "`n" e.Message "`n"
try CS.System.Tex.StringBuilder()
catch as e
    out .= "`n" e.Message "`n"

MsgBox(out, "CS.Types / CS.Members")

; Editor autocomplete: write lib\ahk#.d.ahk once, then open a script in VS Code with the
; AutoHotkey v2 language server (thqby.vscode-autohotkey2-lsp): `CS.System.Text.StringBuilder().` completes.
if (MsgBox("Write editor declarations for System.Text, System.IO and System.Math into lib\ahk#.d.ahk?", "CS.Declare", "YesNo") = "Yes") {
    path := CS.Declare("System.Text", "System.IO", "System.Math")
    MsgBox("Wrote " path "`n`nReopen a script that includes ahk#.ahk in VS Code and type  CS.System.Math.", "CS.Declare")
}
