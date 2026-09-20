;; ═══════════════════════════════════════════════════════════════════════════════
;; AHK# Developer Studio & Workbench v1.0
;; ═══════════════════════════════════════════════════════════════════════════════
;; A visual companion for scripting, testing, and exploring AHK#.
;;
;; Tabs:
;;    1  Examples      — browse the scripts in examples\ and launch them
;;    2  Scratchpad    — run C# Expression / C# Class / AHK Script code
;;                       (Ctrl+Enter or F5 runs, run history, saved snippets,
;;                        C# version selector, Export as CSModule .ahk)
;;    3  Type Explorer — reflection-based .NET member inspector + snippet generator
;;    4  NuGet         — search, install and uninstall NuGet packages
;;    5  Precompiler   — compile CSModule source and export DLLs
;;    6  Cache         — inspect, delete and clean the compiled DLL cache
;;    7  CLR Monitor   — managed heap, GC counters, loaded assemblies
;;    8  Marshalling   — see how AHK values map to .NET objects
;;    9  Overloads     — predict which C# overload an AHK call resolves to
;;   10  Wrapper Gen   — generate AHK wrappers + IntelliSense (.d.ahk) for any assembly
;;
;; Usage:  AutoHotkey64.exe ahk#_playground.ahk
;;
;; Settings, run history and saved snippets live in %AppData%\AHKSharp\workbench.ini
;; ═══════════════════════════════════════════════════════════════════════════════

#Requires AutoHotkey v2.0
#SingleInstance Force

; ── Includes ──────────────────────────────────────────────────────────────────
#Include lib\ahk#.ahk
#Include ext\ahk#.http.ahk
#Include ext\ahk#.ui.ahk

; ═══════════════════════════════════════════════════════════════════════════════
; STARTUP SPLASH  (compiling WBHelper below takes a moment — show that we are alive)
; Class initialisers run in order of appearance, so this runs before WBHelper compiles.
; ═══════════════════════════════════════════════════════════════════════════════

class WBSplash {
    static win := ""

    static __New() {
        try {
            sg := Gui("-Caption +AlwaysOnTop +ToolWindow +Border", "AHK# Developer Studio")
            sg.BackColor := "0x0f0f1a"
            sg.MarginX := 28
            sg.MarginY := 20
            sg.SetFont("s13 c0x00d4ff Bold", "Segoe UI")
            sg.Add("Text", "w320 Center", "AHK# Developer Studio")
            sg.SetFont("s9 c0xa0a0c0 Norm", "Segoe UI")
            sg.Add("Text", "w320 Center", "Compiling helper module...")
            sg.Show("NoActivate")
            ; Paint synchronously: nothing pumps messages while the helper compiles
            DllCall("RedrawWindow", "ptr", sg.Hwnd, "ptr", 0, "ptr", 0, "uint", 0x185)
            WBSplash.win := sg
        }
    }

    static Close() {
        try WBSplash.win.Destroy()
        WBSplash.win := ""
    }
}

; ═══════════════════════════════════════════════════════════════════════════════
; EMBEDDED C# HELPER MODULE
; ═══════════════════════════════════════════════════════════════════════════════

class WBHelper extends _CSModule {
    static References := (A_WinDir "\Microsoft.NET\" (A_PtrSize == 8 ? "Framework64" : "Framework") "\v4.0.30319\WPF\UIAutomationClient.dll;")
        . (A_WinDir "\Microsoft.NET\" (A_PtrSize == 8 ? "Framework64" : "Framework") "\v4.0.30319\WPF\UIAutomationTypes.dll;")
        . (A_WinDir "\Microsoft.NET\" (A_PtrSize == 8 ? "Framework64" : "Framework") "\v4.0.30319\WPF\WindowsBase.dll")
    static CSharp := FileRead(A_ScriptDir "\workbench\ahk#_workbench.cs", "UTF-8")
}

; ═══════════════════════════════════════════════════════════════════════════════
; NAMED CONSTANTS  (tab and scratchpad-mode indexes — never use bare numbers)
; ═══════════════════════════════════════════════════════════════════════════════

global TAB_EXAMPLES := 1
global TAB_SCRATCH := 2
global TAB_TYPES := 3
global TAB_NUGET := 4
global TAB_PRECOMP := 5
global TAB_CACHE := 6
global TAB_CLR := 7
global TAB_MARSH := 8
global TAB_OVERLOADS := 9
global TAB_WRAPPER := 10

global MODE_EXPR := 1
global MODE_CLASS := 2
global MODE_AHK := 3

; ═══════════════════════════════════════════════════════════════════════════════
; SHARED HELPERS
; ═══════════════════════════════════════════════════════════════════════════════

global g_currentTypeSearch := ""

AddButton(guiObj, options, text) {
    textColor := "0xd0d0e0"
    if InStr(text, "Clear ALL Cache") || InStr(text, "Uninstall Selected") || InStr(text, "■ Stop")
        textColor := "0xf87171"

    btn := guiObj.Add("Text", options " Center +0x200 +Border Background0x1f1f30 c" textColor, text)
    btn.DefineProp("defaultColor", { Value: textColor })
    btn.DefineProp("isCustomButton", { Value: true })
    return btn
}

; ── Dark mode (one implementation shared by the studio and the UIA explorer) ──
global hUxtheme := 0
global pAllowDarkModeForWindow := 0
global lvSubclassCallback := 0      ; set by the studio: paints ListView header text light

WB_InitDarkMode() {
    global hUxtheme, pAllowDarkModeForWindow
    hUxtheme := DllCall("LoadLibrary", "str", "uxtheme.dll", "ptr")
    pAllowDarkModeForWindow := 0
    try {
        if hUxtheme {
            ; Ordinal 135: SetPreferredAppMode (2 = ForceDark)
            pSetPreferredAppMode := DllCall("GetProcAddress", "ptr", hUxtheme, "ptr", 135, "ptr")
            if pSetPreferredAppMode
                DllCall(pSetPreferredAppMode, "int", 2)

            ; Ordinal 136: FlushMenuThemes
            pFlushMenuThemes := DllCall("GetProcAddress", "ptr", hUxtheme, "ptr", 136, "ptr")
            if pFlushMenuThemes
                DllCall(pFlushMenuThemes)

            ; Ordinal 133: AllowDarkModeForWindow
            pAllowDarkModeForWindow := DllCall("GetProcAddress", "ptr", hUxtheme, "ptr", 133, "ptr")
        }
    } catch {
    }
}

; Dark title bar + dark scrollbars/menus for a top-level window
WB_DarkWindow(guiObj) {
    global pAllowDarkModeForWindow
    if pAllowDarkModeForWindow
        try DllCall(pAllowDarkModeForWindow, "ptr", guiObj.Hwnd, "int", 1)
    try {
        if (VerCompare(A_OSVersion, "10.0.17763") >= 0) {
            attr := (VerCompare(A_OSVersion, "10.0.18985") >= 0) ? 20 : 19
            DllCall("dwmapi\DwmSetWindowAttribute", "ptr", guiObj.Hwnd, "int", attr, "int*", true, "int", 4)
        }
    } catch {
    }
}

; Dark theme for one control (dropdowns, list views + their headers, edits, trees, ...)
WB_DarkControl(ctrl) {
    global pAllowDarkModeForWindow, lvSubclassCallback
    hwnd := ctrl.Hwnd
    ctrlType := Type(ctrl)

    if (pAllowDarkModeForWindow)
        try DllCall(pAllowDarkModeForWindow, "ptr", hwnd, "int", 1)

    if (ctrlType == "Gui.DDL" || ctrlType == "Gui.ComboBox") {
        try DllCall("uxtheme\SetWindowTheme", "ptr", hwnd, "wstr", "DarkMode_CFD", "ptr", 0)
    } else if (ctrlType == "Gui.ListView") {
        try DllCall("uxtheme\SetWindowTheme", "ptr", hwnd, "wstr", "Explorer", "ptr", 0)
        if (lvSubclassCallback)
            try DllCall("Comctl32\SetWindowSubclass", "Ptr", hwnd, "Ptr", lvSubclassCallback, "Ptr", hwnd, "Ptr", 0)
        try {
            headerHwnd := SendMessage(0x101F, 0, 0, hwnd) ; LVM_GETHEADER
            if headerHwnd
                DllCall("uxtheme\SetWindowTheme", "ptr", headerHwnd, "wstr", "DarkMode_ItemsView", "ptr", 0)
        }
    } else {
        try DllCall("uxtheme\SetWindowTheme", "ptr", hwnd, "wstr", "DarkMode_Explorer", "ptr", 0)
    }
}

; Dark theme for every ordinary control of a Gui (custom buttons/tabs paint themselves)
WB_DarkenAll(guiObj, skipCtrl := "") {
    for hwnd, ctrl in guiObj {
        if (ctrl.HasProp("isCustomTab") || ctrl.HasProp("isCustomButton") || ctrl.HasProp("isExampleCard") || ctrl.HasProp("isExampleCardChild"))
            continue
        if (skipCtrl && ctrl == skipCtrl)
            continue
        WB_DarkControl(ctrl)
    }
}

; Force a synchronous repaint of a window — used before blocking work so "Running..." is really visible
WB_Repaint(hwnd := 0) {
    if (!hwnd)
        hwnd := g.Hwnd
    DllCall("RedrawWindow", "ptr", hwnd, "ptr", 0, "ptr", 0, "uint", 0x185)
}

; Stable short hash (CRC-32 of the UTF-16 text) — used to derive deterministic class names
WB_Hash(str) {
    try {
        crc := DllCall("ntdll\RtlComputeCrc32", "uint", 0, "ptr", StrPtr(str), "uint", StrLen(str) * 2, "uint")
        return Format("{:08X}", crc)
    }
    h := 2166136261
    Loop Parse, str
        h := ((h ^ Ord(A_LoopField)) * 16777619) & 0xFFFFFFFF
    return Format("{:08X}", h)
}

#Include workbench\ahk#_workbench_snippets.ahk
#Include workbench\ahk#_workbench_gui.ahk
#Include workbench\ahk#_workbench_uia_explorer.ahk
#Include workbench\ahk#_workbench_uia_generator.ahk
