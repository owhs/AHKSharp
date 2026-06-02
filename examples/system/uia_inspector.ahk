;; AHK# Example 06 — UI Automation Inspector
;; Demonstrates the UIA extension for crawling, querying, and interacting
;; with any application's UI tree at native speed.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk
#Include ..\..\ext\ahk#.uia.ahk

; ══════════════════════════════════════════════════════════════════════════════
; 1. Element Under Cursor — Press F1
; ══════════════════════════════════════════════════════════════════════════════

global tipShowing := false

F1:: {
    global tipShowing
    MouseGetPos(&mx, &my)

    el := UIA2.FromPoint(mx, my)
    if !IsObject(el) {
        ToolTip("No element found at cursor")
        SetTimer(() => ToolTip(""), -2000)
        return
    }

    info := "═══ UIA Element ═══"
        . "`n▸ Name:       " el.Name
        . "`n▸ Type:       " el.ControlType
        . "`n▸ ClassName:  " el.ClassName
        . "`n▸ AutoId:     " el.AutomationId
        . "`n▸ Bounds:     " el.BoundingX "," el.BoundingY
        . " (" el.BoundingW "×" el.BoundingH ")"
        . "`n▸ Enabled:    " el.IsEnabled
        . "`n▸ Value:      " el.Value
        . "`n▸ PID:        " el.ProcessId

    ToolTip(info, mx + 20, my + 20)
    tipShowing := true
    SetTimer(() => (ToolTip(""), tipShowing := false), -4000)
}

; ══════════════════════════════════════════════════════════════════════════════
; 2. Focused Element — Press F2
; ══════════════════════════════════════════════════════════════════════════════

F2:: {
    el := UIA2.Focused()
    if !IsObject(el) {
        MsgBox("No focused element detected", "UIA")
        return
    }

    MsgBox("Focused Element:"
        . "`n  Name:     " el.Name
        . "`n  Type:     " el.ControlType
        . "`n  Class:    " el.ClassName
        . "`n  AutoId:   " el.AutomationId
        , "AHK# — Focused Element")
}

; ══════════════════════════════════════════════════════════════════════════════
; 3. Crawl Active Window — Press F3
; ══════════════════════════════════════════════════════════════════════════════

F3:: {
    hwnd := WinGetID("A")
    title := WinGetTitle("A")

    ToolTip("Crawling UI tree for: " title "...")

    ; Crawl with max depth of 5 to keep it fast
    elements := UIA2.CrawlTree(hwnd, 5)

    ToolTip("")

    if !IsObject(elements) {
        MsgBox("No elements found", "UIA Crawler")
        return
    }

    ; Count element types
    types := Map()
    count := 0
    try {
        Loop {
            try {
                el := elements[A_Index - 1]
                ct := el.ControlType
                if !types.Has(ct)
                    types[ct] := 0
                types[ct] := types[ct] + 1
                count++
            } catch
                break
        }
    }

    msg := "═══ UI Tree: " title " ═══"
        . "`nTotal elements: " count
        . "`n`n─── Element Types ───"

    for typeName, n in types
        msg .= "`n  " typeName ": " n

    ; Show first 10 elements
    msg .= "`n`n─── First 10 Elements ───"
    Loop Min(10, count) {
        try {
            el := elements[A_Index - 1]
            indent := ""
            Loop el.Depth
                indent .= "  "
            msg .= "`n" indent "[" el.ControlType "] " el.Name
        }
    }

    MsgBox(msg, "AHK# — UIA Tree Crawl")
}

; ══════════════════════════════════════════════════════════════════════════════
; 4. Find Buttons in Active Window — Press F4
; ══════════════════════════════════════════════════════════════════════════════

F4:: {
    hwnd := WinGetID("A")
    title := WinGetTitle("A")

    ToolTip("Finding buttons in: " title "...")
    buttons := UIA2.Find(hwnd, "ControlType=Button", 10)
    ToolTip("")

    if !IsObject(buttons) {
        MsgBox("No buttons found", "UIA Find")
        return
    }

    msg := "═══ Buttons in: " title " ═══`n"
    count := 0
    try {
        Loop {
            try {
                btn := buttons[A_Index - 1]
                count++
                msg .= "`n▸ " btn.Name
                if (btn.AutomationId != "")
                    msg .= " (id=" btn.AutomationId ")"
                msg .= " [" btn.BoundingX "," btn.BoundingY "]"
            } catch
                break
        }
    }

    MsgBox(count " buttons found:`n" msg, "AHK# — UIA Button Finder")
}

; ══════════════════════════════════════════════════════════════════════════════

MsgBox("AHK# UIA Inspector Ready!`n`n"
    . "F1 — Element under cursor`n"
    . "F2 — Focused element`n"
    . "F3 — Crawl active window tree`n"
    . "F4 — Find all buttons`n"
    . "Esc — Exit"
    , "AHK# — UIA Demo", 0x40)

Esc::ExitApp()
