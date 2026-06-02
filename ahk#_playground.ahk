;; ═══════════════════════════════════════════════════════════════════════════════
;; AHK# Developer Studio & Workbench v1.0
;; ═══════════════════════════════════════════════════════════════════════════════
;; A powerful visual companion for scripting, testing, and exploring AHK#.
;;
;; Features:
;;   Tab 1 — Interactive Scratchpad (C# Expression / C# Class / AHK Script)
;;   Tab 2 — .NET Type Explorer with reflection-based member inspector
;;   Tab 3 — NuGet Package Manager (search, install, view installed)
;;   Tab 4 — CSModule Precompiler Studio (compile & export DLLs)
;;   Tab 5 — Cache Manager (view, identify, and clear compiled DLL cache)
;;   Tab 6 — CLR Live Diagnostics (memory, GC, loaded assemblies)
;;
;; Usage:  AutoHotkey.exe helpers\ahk#_workbench.ahk
;; ═══════════════════════════════════════════════════════════════════════════════

#Requires AutoHotkey v2.0
#SingleInstance Force

; ── Includes ──────────────────────────────────────────────────────────────────
#Include lib\ahk#.ahk
#Include ext\ahk#.http.ahk
#Include ext\ahk#.ui.ahk

; ═══════════════════════════════════════════════════════════════════════════════
; EMBEDDED C# HELPER MODULE
; ═══════════════════════════════════════════════════════════════════════════════

class WBHelper extends _CSModule {
    static References := "System.Windows.Forms.dll;System.Drawing.dll;"
        . (A_WinDir "\Microsoft.NET\" (A_PtrSize == 8 ? "Framework64" : "Framework") "\v4.0.30319\WPF\UIAutomationClient.dll;")
        . (A_WinDir "\Microsoft.NET\" (A_PtrSize == 8 ? "Framework64" : "Framework") "\v4.0.30319\WPF\UIAutomationTypes.dll;")
        . (A_WinDir "\Microsoft.NET\" (A_PtrSize == 8 ? "Framework64" : "Framework") "\v4.0.30319\WPF\WindowsBase.dll")
    static CSharp := FileRead(A_ScriptDir "\workbench\ahk#_workbench.cs", "UTF-8")
}

; ═══════════════════════════════════════════════════════════════════════════════
; GLOBAL STATE & SNIPPETS
; ═══════════════════════════════════════════════════════════════════════════════

global g_currentTypeSearch := ""

AddButton(guiObj, options, text) {
    textColor := "0xd0d0e0"
    if InStr(text, "Clear ALL Cache") || InStr(text, "Uninstall Selected")
        textColor := "0xf87171"

    btn := guiObj.Add("Text", options " Center +0x200 +Border Background0x1f1f30 c" textColor, text)
    btn.DefineProp("defaultColor", { Value: textColor })
    btn.DefineProp("isCustomButton", { Value: true })
    return btn
}

#Include workbench\ahk#_workbench_snippets.ahk
#Include workbench\ahk#_workbench_gui.ahk
#Include workbench\ahk#_workbench_uia_explorer.ahk
#Include workbench\ahk#_workbench_uia_generator.ahk