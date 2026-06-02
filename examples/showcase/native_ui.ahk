;; AHK# Example 08 — Native .NET UI Controls
;; Embed WinForms DataGridView, RichTextBox, and Panel inside an AHK Gui.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk
#Include ..\..\ext\ahk#.ui.ahk

; ══════════════════════════════════════════════════════════════════════════════
; 1. Create AHK GUI Shell
; ══════════════════════════════════════════════════════════════════════════════

myGui := Gui("+Resize", "AHK# — Native UI Controls")
myGui.BackColor := "0x1a1a2e"
myGui.SetFont("s10 c0xe2e2e2", "Segoe UI")

myGui.AddText("x15 y10 w560 h25 c0x00d4ff", "═══ AHK# Native UI Demo ═══")

; ══════════════════════════════════════════════════════════════════════════════
; 2. DataGridView — Full .NET Grid inside AHK
; ══════════════════════════════════════════════════════════════════════════════

myGui.AddText("x15 y40 w200 h20 c0xaaaaaa", "▸ .NET DataGridView:")

myGui.Show("w590 h550")

grid := NativeUI.DataGridView(myGui, 15, 65, 560, 180)
grid.AddColumn("Name", "Project Name")
grid.AddColumn("Language", "Language")
grid.AddColumn("Stars", "★ Stars")
grid.AddColumn("Status", "Status")

; Populate with data
grid.AddRow("AHK#", "AHK2 / C#", "1,500", "Active")
grid.AddRow("AutoHotkey v2", "C++", "8,900", "Active")
grid.AddRow("Visual Studio Code", "TypeScript", "165,000", "Active")
grid.AddRow("Neovim", "Lua / C", "82,000", "Active")
grid.AddRow("Rust Lang", "Rust", "96,000", "Active")
grid.AddRow("Go Lang", "Go", "123,000", "Active")

; ══════════════════════════════════════════════════════════════════════════════
; 3. RichTextBox — Formatted Text Editor
; ══════════════════════════════════════════════════════════════════════════════

myGui.AddText("x15 y255 w200 h20 c0xaaaaaa", "▸ .NET RichTextBox:")

rtb := NativeUI.RichTextBox(myGui, 15, 280, 560, 120)
rtb.Text := "Welcome to AHK# Native UI!`r`n`r`n"
    . "This RichTextBox is a real .NET WinForms control embedded`r`n"
    . "inside an AutoHotkey v2 GUI. You can type here, select text,`r`n"
    . "and interact with it just like any native .NET control."

; ══════════════════════════════════════════════════════════════════════════════
; 4. Control Buttons
; ══════════════════════════════════════════════════════════════════════════════

btnAdd := myGui.AddButton("x15 y415 w130 h30", "Add Row")
btnAdd.OnEvent("Click", AddRow)

btnClear := myGui.AddButton("x155 y415 w130 h30", "Clear Grid")
btnClear.OnEvent("Click", ClearGrid)

btnGetCell := myGui.AddButton("x295 y415 w130 h30", "Get Cell (0,0)")
btnGetCell.OnEvent("Click", GetCell)

btnGetText := myGui.AddButton("x435 y415 w140 h30", "Get RTB Text")
btnGetText.OnEvent("Click", GetRTBText)

; ══════════════════════════════════════════════════════════════════════════════
; 5. Status Panel
; ══════════════════════════════════════════════════════════════════════════════

myGui.AddText("x15 y460 w200 h20 c0xaaaaaa", "▸ Status Panel:")
panel := NativeUI.Panel(myGui, 15, 485, 560, 50)

; ── Event Handlers ──────────────────────────────────────────────────────────

AddRow(*) {
    static rowNum := 7
    grid.AddRow("New Project " rowNum, "AHK2", "0", "Draft")
    rowNum++
}

ClearGrid(*) {
    grid.Clear()
    ; Re-add headers
    grid.AddRow("AHK#", "AHK2 / C#", "1,500", "Active")
}

GetCell(*) {
    try {
        val := grid.GetCell(0, 0)
        MsgBox("Cell(0,0) = " val, "Grid Cell")
    } catch as e {
        MsgBox("Error: " e.Message, "Grid Cell")
    }
}

GetRTBText(*) {
    txt := rtb.Text
    MsgBox("RTB Text (" StrLen(txt) " chars):`n`n" SubStr(txt, 1, 200), "RichTextBox Content")
}

myGui.OnEvent("Close", (*) => ExitApp())
