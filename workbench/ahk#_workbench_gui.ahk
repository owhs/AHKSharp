; ═══════════════════════════════════════════════════════════════════════════════
; MAIN GUI CONSTRUCTION
; ═══════════════════════════════════════════════════════════════════════════════

global hUxtheme := DllCall("LoadLibrary", "str", "uxtheme.dll", "ptr")
global pAllowDarkModeForWindow := 0
try {
    if hUxtheme {
        ; Ordinal 135: SetPreferredAppMode
        pSetPreferredAppMode := DllCall("GetProcAddress", "ptr", hUxtheme, "ptr", 135, "ptr")
        if pSetPreferredAppMode
            DllCall(pSetPreferredAppMode, "int", 2) ; 2 = ForceDark

        ; Ordinal 136: FlushMenuThemes
        pFlushMenuThemes := DllCall("GetProcAddress", "ptr", hUxtheme, "ptr", 136, "ptr")
        if pFlushMenuThemes
            DllCall(pFlushMenuThemes)

        ; Ordinal 133: AllowDarkModeForWindow
        pAllowDarkModeForWindow := DllCall("GetProcAddress", "ptr", hUxtheme, "ptr", 133, "ptr")
    }
} catch {
}

g := Gui("-Resize", "AHK# Developer Studio")
if pAllowDarkModeForWindow
    try DllCall(pAllowDarkModeForWindow, "ptr", g.hwnd, "int", 1) ; AllowDarkModeForWindow (enables dark scrollbars for child controls)
g.BackColor := "0x0f0f1a"
g.MarginX := 8
g.MarginY := 8

try {
    if (VerCompare(A_OSVersion, "10.0.17763") >= 0) {
        attr := 19
        if (VerCompare(A_OSVersion, "10.0.18985") >= 0)
            attr := 20
        DllCall("dwmapi\DwmSetWindowAttribute", "ptr", g.hwnd, "int", attr, "int*", true, "int", 4)
    }
} catch {
}

; ── Title Bar ─────────────────────────────────────────────────────────────────
;g.SetFont("s14 c0x00d4ff Bold", "Segoe UI")
;g.Add("Text", "x15 y8 w400 h28 BackgroundTrans", "AHK# Developer Studio")
g.SetFont("s9 c0x6a6a8a", "Segoe UI")

; ── Tab Control (Logical Hidden Manager) ──────────────────────────────────────
tabs := g.Add("Tab2", "x0 y0 w0 h0 -Wrap -TabStop",
    ["Examples", "Scratchpad", "Type Explorer", "NuGet", "Precompiler", "Cache", "CLR Monitor", "Marshalling", "Overloads", "Wrapper Gen"])

tabs.UseTab()

; ── Premium Unified Background Card Panel ─────────────────────────────────────
g.Add("Text", "x10 y38 w1120 h680 Background0x12121f +Border")

; ── Premium Tab Button Custom Navigation ──────────────────────────────────────
customTabs := []
tabNames := ["Examples", "Scratchpad", "Type Explorer", "NuGet", "Precompiler", "Cache", "CLR Monitor", "Marshalling", "Overloads", "Wrapper Gen"]
global activeTabIndex := 1

; Draw a beautiful background bar for the tabs
g.Add("Text", "x10 y5 w1120 h28 Background0x1a1a2e +Border")

for i, name in tabNames {
    xPos := 12 + (i - 1) * 111
    tBtn := g.Add("Text", "x" xPos " y4 w108 h27 Center +0x200 BackgroundTrans c" (i == 1 ? "0x00d4ff" : "0x8a8ab0"), name)
    tBtn.DefineProp("isCustomTab", { Value: true })
    tBtn.DefineProp("tabIndex", { Value: i })
    tBtn.OnEvent("Click", OnTabClick)
    customTabs.Push(tBtn)
}

; Dynamic Accent line under the active tab
accentLine := g.Add("Text", "x12 y30 w108 h3 Background0x00d4ff")

OnTabClick(ctrl, *) {
    global activeTabIndex
    if (ctrl.tabIndex == activeTabIndex)
        return

    ; Deactivate old tab
    oldTab := customTabs[activeTabIndex]
    oldTab.Opt("c0x8a8ab0")
    oldTab.Redraw()

    ; Activate new tab
    activeTabIndex := ctrl.tabIndex
    ctrl.Opt("c0x00d4ff")
    ctrl.Redraw()

    ; Move accent line to new tab
    newX := 12 + (activeTabIndex - 1) * 111
    accentLine.Move(newX, , 108)

    ; Switch the logical tab control
    tabs.Choose(activeTabIndex)

    ; Call tab change events if any
    if (activeTabIndex == 6)
        OnCacheRefresh()
    else if (activeTabIndex == 7)
        OnRefreshCLR()
    else if (activeTabIndex == 4)
        OnRefreshInstalled()
}

; ═══════════════════════════════════════════════════════════════════════════════
; TAB 2 — INTERACTIVE SCRATCHPAD
; ═══════════════════════════════════════════════════════════════════════════════
tabs.UseTab(2)

g.SetFont("s9 c0x00d4ff", "Segoe UI")
g.Add("Text", "x20 y50 w55 h22 BackgroundTrans", "Mode:")
g.SetFont("s9 c0xd0d0e0", "Segoe UI")
ddlMode := g.Add("DropDownList", "x75 y48 w150 Background0x1a1a2e", ["C# Expression", "C# Class", "AHK Script"])
ddlMode.Choose(1)

g.SetFont("s9 c0x00d4ff", "Segoe UI")
g.Add("Text", "x240 y50 w60 h22 BackgroundTrans", "Snippet:")
g.SetFont("s9 c0xd0d0e0", "Segoe UI")
ddlSnippet := g.Add("DropDownList", "x305 y48 w250 Background0x1a1a2e", snippetNames)

btnLoadSnippet := AddButton(g, "x565 y47 w100 h24", "Load Snippet")
btnLoadSnippet.OnEvent("Click", OnLoadSnippet)

; Code Editor
g.SetFont("s9 c0x00d4ff", "Segoe UI")
g.Add("Text", "x20 y78 w200 h18 BackgroundTrans", "◆  Code Input")
g.SetFont("s10 c0xd4d4e8", "Cascadia Code")
edCode := g.Add("Edit", "x20 y98 w1090 h290 Multi WantTab VScroll HScroll Background0x12121f +Border -E0x200", "")

; Button Row
g.SetFont("s10 c0xd0d0e0", "Segoe UI")
btnRun := AddButton(g, "x20 y396 w120 h30", "▸ Run")
btnRun.OnEvent("Click", OnRunCode)

btnClearOutput := AddButton(g, "x150 y396 w120 h30", "Clear Output")
btnClearOutput.OnEvent("Click", (*) => edOutput.Value := "")

btnUiaExplorer := AddButton(g, "x280 y396 w140 h30", "▸ UIA Explorer")
btnUiaExplorer.OnEvent("Click", LaunchUiaExplorer)

btnSendToPrecomp := AddButton(g, "x430 y396 w170 h30", "Send to Precompiler")
btnSendToPrecomp.OnEvent("Click", OnSendToPrecompiler)

g.SetFont("s9 c0x6a6a8a", "Segoe UI")
lblRunStatus := g.Add("Text", "x610 y402 w230 h20 BackgroundTrans", "Ready")

g.SetFont("s8 c0x4a5568", "Segoe UI")
g.Add("Text", "x20 y428 w700 h16 BackgroundTrans", "💡 Tip: In C# Class mode, add  // NuGet: PackageName Version  to auto-install and reference NuGet packages.")

; Output Area
g.SetFont("s9 c0xa78bfa", "Segoe UI")
g.Add("Text", "x20 y448 w200 h18 BackgroundTrans", "◆  Output")
g.SetFont("s10 c0x4ade80", "Cascadia Code")
edOutput := g.Add("Edit", "x20 y468 w1090 h240 Multi ReadOnly VScroll HScroll Background0x0d0d18 +Border -E0x200", "")

; ═══════════════════════════════════════════════════════════════════════════════
; TAB 3 — .NET TYPE EXPLORER
; ═══════════════════════════════════════════════════════════════════════════════
tabs.UseTab(3)

g.SetFont("s10 c0xd0d0e0", "Segoe UI")
btnBackType := AddButton(g, "x20 y48 w30 h24", "<")
btnBackType.OnEvent("Click", OnBtnBackType)

g.SetFont("s9 c0x00d4ff", "Segoe UI")
g.Add("Text", "x60 y51 w80 h20 BackgroundTrans", "Type Name:")
g.SetFont("s10 c0xd4d4e8", "Cascadia Code")

commonTypes := ["System.IO.File", "System.Math", "System.String", "System.DateTime", "System.Convert", "System.Environment", "System.Text.StringBuilder", "System.Net.WebClient", "System.Net.Http.HttpClient", "System.Collections.Generic.List``1", "System.Collections.Generic.Dictionary``2", "System.Threading.Thread", "System.Threading.Tasks.Task", "System.Diagnostics.Process", "System.Reflection.Assembly", "System.Text.RegularExpressions.Regex", "System.Xml.XmlDocument", "System.Xml.Linq.XDocument"]
edTypeName := g.Add("ComboBox", "vTypeName x140 y48 w470 Background0x12121f c0xd4d4e8 -E0x200", commonTypes)
btnFilters := AddButton(g, "x620 y48 w80 h24", "Filters ▾")
btnFilters.OnEvent("Click", OnFiltersClick)
edTypeName.Text := "System.IO.File"

g.SetFont("s10 c0xd0d0e0", "Segoe UI")
btnExplore := AddButton(g, "x710 y48 w100 h24", "Explore")
btnExplore.OnEvent("Click", OnExploreType)

chkInherited := g.Add("Checkbox", "x825 y50 w180 h20 c0xd0d0e0", "Include Inherited")

g.SetFont("s9 c0x00d4ff", "Segoe UI")
g.Add("Text", "x20 y86 w200 h18 BackgroundTrans", "◆  Members")
g.SetFont("s9 c0xd0d0e0", "Segoe UI")
lvTypes := g.Add("ListView", "x20 y106 w1090 h430 Background0x12121f c0xd0d0e0 -E0x200",
    ["Type", "Name", "Signature", "Scope"])
lvTypes.ModifyCol(1, 90)
lvTypes.ModifyCol(2, 220)
lvTypes.ModifyCol(3, 580)
lvTypes.ModifyCol(4, 80)
lvTypes.OnEvent("DoubleClick", OnTypesDoubleClick)

; Snippet Generator
g.SetFont("s9 c0xa78bfa", "Segoe UI")
g.Add("Text", "x20 y546 w200 h18 BackgroundTrans", "◆  Generated AHK# Snippet")
btnGenSnippet := AddButton(g, "x220 y543 w130 h22", "Generate Snippet")
btnGenSnippet.OnEvent("Click", OnGenSnippet)

btnCopySnippet := AddButton(g, "x360 y543 w90 h22", "Copy")
btnCopySnippet.OnEvent("Click", (*) => (A_Clipboard := edSnippet.Value, SetStatus("Snippet copied to clipboard!")))

btnSendToWrap := AddButton(g, "x460 y543 w150 h22", "Send to Wrapper Gen")
btnSendToWrap.OnEvent("Click", OnSendToWrapper)

g.SetFont("s10 c0x4ade80", "Cascadia Code")
edSnippet := g.Add("Edit", "x20 y568 w1090 h100 Multi ReadOnly Background0x0d0d18 -E0x200", "; Select a member and click Generate Snippet")

; Quick-search common types
g.SetFont("s8 c0x6a6a8a", "Segoe UI")
g.Add("Text", "x20 y682 BackgroundTrans", "Quick:")
For i, qtype in ["System.Math", "System.IO.File", "System.IO.Path", "System.String", "System.DateTime", "System.Convert", "System.Environment", "System.Text.StringBuilder", "System.Net.WebClient"] {
    if (i > 1) {
        g.SetFont("c0x6a6a8a")
        g.Add("Text", "x+8 y682 BackgroundTrans", "|")
    }
    g.SetFont("c0x00d4ff")
    lbl := g.Add("Text", "x+8 y682 BackgroundTrans", qtype)
    lbl.OnEvent("Click", ((typeStr, *) => (edTypeName.Text := typeStr, OnExploreType())).Bind(qtype))
}

; ═══════════════════════════════════════════════════════════════════════════════
; TAB 4 — NUGET PACKAGE MANAGER
; ═══════════════════════════════════════════════════════════════════════════════
tabs.UseTab(4)

g.SetFont("s9 c0x00d4ff", "Segoe UI")
g.Add("Text", "x20 y50 w60 h22 BackgroundTrans", "Search:")
edNuGetSearch := g.Add("Edit", "vNuGetSearch x85 y48 w550 h24 Background0x12121f +Border -E0x200", "Newtonsoft.Json")

g.SetFont("s10 c0xd0d0e0", "Segoe UI")
btnNuGetSearch := AddButton(g, "x645 y47 w110 h26", "Search NuGet")
btnNuGetSearch.OnEvent("Click", OnNuGetSearch)

g.SetFont("s9 c0x6a6a8a", "Segoe UI")
lblNuGetStatus := g.Add("Text", "x770 y52 w300 h20 BackgroundTrans", "")

g.SetFont("s9 c0x00d4ff", "Segoe UI")
g.Add("Text", "x20 y78 w200 h18 BackgroundTrans", "◆  Search Results")
g.SetFont("s9 c0xd0d0e0", "Segoe UI")
lvNuGetResults := g.Add("ListView", "x20 y98 w1090 h220 Background0x12121f c0xd0d0e0 -E0x200",
    ["Package", "Version", "Downloads", "Description"])
lvNuGetResults.ModifyCol(1, 220)
lvNuGetResults.ModifyCol(2, 100)
lvNuGetResults.ModifyCol(3, 100)
lvNuGetResults.ModifyCol(4, 550)

g.SetFont("s10 c0xd0d0e0", "Segoe UI")
btnNuGetInstall := AddButton(g, "x20 y324 w160 h28", "Install Selected")
btnNuGetInstall.OnEvent("Click", OnNuGetInstall)

g.SetFont("s9 c0xfbbf24", "Segoe UI")
lblInstallStatus := g.Add("Text", "x195 y329 w400 h20 BackgroundTrans", "")

; Installed packages
g.SetFont("s9 c0x00d4ff", "Segoe UI")
g.Add("Text", "x20 y364 w200 h18 BackgroundTrans", "◆  Installed Packages")

btnRefreshPkgs := AddButton(g, "x230 y361 w100 h22", "Refresh")
btnRefreshPkgs.OnEvent("Click", OnRefreshInstalled)

btnNuGetSendToWrap := AddButton(g, "x340 y361 w150 h22", "Send to Wrapper Gen")
btnNuGetSendToWrap.OnEvent("Click", OnNuGetSendToWrapper)

btnNuGetRemove := AddButton(g, "x500 y361 w140 h22", "Uninstall Selected")
btnNuGetRemove.OnEvent("Click", OnNuGetRemove)

g.SetFont("s9 c0xd0d0e0", "Segoe UI")
lvInstalled := g.Add("ListView", "x20 y387 w1090 h315 Background0x12121f c0xd0d0e0 -E0x200",
    ["Package", "Version", "Contents", "Size"])
lvInstalled.ModifyCol(1, 280)
lvInstalled.ModifyCol(2, 130)
lvInstalled.ModifyCol(3, 130)
lvInstalled.ModifyCol(4, 130)
lvInstalled.OnEvent("ContextMenu", OnNuGetInstalledContextMenu)

; ═══════════════════════════════════════════════════════════════════════════════
; TAB 5 — CSMODULE PRECOMPILER STUDIO
; ═══════════════════════════════════════════════════════════════════════════════
tabs.UseTab(5)

g.SetFont("s9 c0x00d4ff", "Segoe UI")
g.Add("Text", "x20 y50 w100 h22 BackgroundTrans", "Class Name:")
g.SetFont("s10 c0xd4d4e8", "Cascadia Code")
edClassName := g.Add("Edit", "x125 y48 w200 h24 Background0x12121f +Border -E0x200", "MyModule")

g.SetFont("s9 c0x00d4ff", "Segoe UI")
g.Add("Text", "x345 y50 w90 h22 BackgroundTrans", "C# Version:")
g.SetFont("s9 c0xd0d0e0", "Segoe UI")
ddlCSVer := g.Add("DropDownList", "x440 y48 w100 Background0x1a1a2e", ["4.0 (default)", "5.0", "6.0", "7.0", "7.3"])
ddlCSVer.Choose(1)

; Code Editor
g.SetFont("s9 c0x00d4ff", "Segoe UI")
g.Add("Text", "x20 y78 w200 h18 BackgroundTrans", "◆  C# Source Code")
g.SetFont("s10 c0xd4d4e8", "Cascadia Code")
edPrecompCode := g.Add("Edit", "x20 y98 w1090 h330 Multi WantTab VScroll HScroll Background0x12121f +Border -E0x200",
    'public static string Run() {`r`n    return "Hello from precompiled module!";`r`n}')

; References
g.SetFont("s9 c0x00d4ff", "Segoe UI")
g.Add("Text", "x20 y436 w90 h22 BackgroundTrans", "References:")
g.SetFont("s10 c0xd4d4e8", "Cascadia Code")
edPrecompRefs := g.Add("Edit", "x115 y434 w700 h24 Background0x12121f +Border -E0x200", "")

; Buttons
g.SetFont("s10 c0xd0d0e0", "Segoe UI")
btnCompile := AddButton(g, "x20 y466 w140 h30", "Compile")
btnCompile.OnEvent("Click", OnPrecompile)

btnExportDLL := AddButton(g, "x170 y466 w140 h30", "Export DLL...")
btnExportDLL.OnEvent("Click", OnExportDLL)

btnSendSnippetToScratch := AddButton(g, "x320 y466 w200 h30", "Send Snippet to Scratchpad")
btnSendSnippetToScratch.OnEvent("Click", OnSendPrecompSnippetToScratch)

; Status
g.SetFont("s9 c0xa78bfa", "Segoe UI")
g.Add("Text", "x20 y504 w200 h18 BackgroundTrans", "◆  Compilation Output")
g.SetFont("s10 c0x4ade80", "Cascadia Code")
edPrecompOut := g.Add("Edit", "x20 y524 w1090 h180 Multi ReadOnly VScroll Background0x0d0d18 +Border -E0x200", "")

global g_precompAsmId := ""

; ═══════════════════════════════════════════════════════════════════════════════
; TAB 6 — CACHE MANAGER
; ═══════════════════════════════════════════════════════════════════════════════
tabs.UseTab(6)

; Stats
g.SetFont("s10 c0xfbbf24 Bold", "Segoe UI")
lblCacheStats := g.Add("Text", "x20 y48 w800 h22 BackgroundTrans", "Loading cache statistics...")

g.SetFont("s8 c0x6a6a8a", "Segoe UI")
lblCachePath := g.Add("Text", "x20 y70 w800 h18 BackgroundTrans", "")

; Cache ListView
g.SetFont("s9 c0x00d4ff", "Segoe UI")
g.Add("Text", "x20 y92 w200 h18 BackgroundTrans", "◆  Compiled Module Cache")
g.SetFont("s9 c0xd0d0e0", "Segoe UI")
lvCache := g.Add("ListView", "x20 y112 w1090 h540 Background0x12121f c0xd0d0e0 -E0x200",
    ["Hash ID", "Size", "Compiled", "Exported Classes / Origin"])
lvCache.ModifyCol(1, 160)
lvCache.ModifyCol(2, 80)
lvCache.ModifyCol(3, 140)
lvCache.ModifyCol(4, 580)

; Buttons
g.SetFont("s10 c0xd0d0e0", "Segoe UI")
btnCacheRefresh := AddButton(g, "x20 y662 w120 h30", "Refresh")
btnCacheRefresh.OnEvent("Click", OnCacheRefresh)

btnCacheDelete := AddButton(g, "x150 y662 w160 h30", "Delete Selected")
btnCacheDelete.OnEvent("Click", OnCacheDelete)

g.SetFont("s10 c0xf87171", "Segoe UI")
btnCacheClearAll := AddButton(g, "x320 y662 w160 h30", "Clear ALL Cache")
btnCacheClearAll.OnEvent("Click", OnCacheClearAll)

g.SetFont("s9 c0x6a6a8a", "Segoe UI")
g.Add("Text", "x500 y667 w500 h22 BackgroundTrans",
    "Note: Clearing cache forces re-compilation next time modules are loaded.")

; ═══════════════════════════════════════════════════════════════════════════════
; TAB 7 — CLR LIVE DIAGNOSTICS
; ═══════════════════════════════════════════════════════════════════════════════
tabs.UseTab(7)

g.SetFont("s11 c0x00d4ff Bold", "Segoe UI")
g.Add("Text", "x20 y50 w300 h24 BackgroundTrans", "◆  Managed Heap")

g.SetFont("s22 c0x4ade80 Bold", "Cascadia Code")
lblHeapSize := g.Add("Text", "x20 y78 w300 h36 BackgroundTrans", "...")

g.SetFont("s9 c0xa78bfa", "Segoe UI")
g.Add("Text", "x350 y56 w80 BackgroundTrans", "Gen 0:")
g.Add("Text", "x350 y78 w80 BackgroundTrans", "Gen 1:")
g.Add("Text", "x350 y100 w80 BackgroundTrans", "Gen 2:")

g.SetFont("s9 c0xd0d0e0", "Segoe UI")
lblGen0 := g.Add("Text", "x410 y56 w80 BackgroundTrans", "0")
lblGen1 := g.Add("Text", "x410 y78 w80 BackgroundTrans", "0")
lblGen2 := g.Add("Text", "x410 y100 w80 BackgroundTrans", "0")

g.SetFont("s9 c0xa78bfa", "Segoe UI")
g.Add("Text", "x520 y56 w100 BackgroundTrans", "Assemblies:")
g.SetFont("s9 c0xd0d0e0", "Segoe UI")
lblAsmCount := g.Add("Text", "x620 y56 w60 BackgroundTrans", "0")

g.SetFont("s9 c0xa78bfa", "Segoe UI")
g.Add("Text", "x520 y78 w100 BackgroundTrans", "Raw Bytes:")
g.SetFont("s9 c0xd0d0e0", "Segoe UI")
lblRawBytes := g.Add("Text", "x620 y78 w200 BackgroundTrans", "0")

; Buttons
g.SetFont("s10 c0xd0d0e0", "Segoe UI")
btnForceGC := AddButton(g, "x20 y126 w130 h28", "Force GC")
btnForceGC.OnEvent("Click", OnForceGC)

btnRefreshCLR := AddButton(g, "x160 y126 w100 h28", "Refresh")
btnRefreshCLR.OnEvent("Click", OnRefreshCLR)

chkAutoRefresh := g.Add("Checkbox", "x280 y130 w150 h20 c0xd0d0e0", "Auto-refresh (2s)")
chkAutoRefresh.OnEvent("Click", OnToggleAutoRefresh)

btnClrSendToWrap := AddButton(g, "x450 y126 w210 h28", "Send Selected to Wrapper Gen")
btnClrSendToWrap.OnEvent("Click", OnClrSendToWrapper)

; Assemblies
g.SetFont("s9 c0x00d4ff", "Segoe UI")
g.Add("Text", "x20 y163 w200 h18 BackgroundTrans", "◆  Loaded .NET Assemblies")

g.SetFont("s9 c0xd0d0e0", "Segoe UI")
lvAssemblies := g.Add("ListView", "x20 y183 w1090 h520 Background0x12121f c0xd0d0e0 -E0x200",
    ["Assembly Name", "Version", "Size", "Classes / Exported Types", "Location"])
lvAssemblies.ModifyCol(1, 200)
lvAssemblies.ModifyCol(2, 80)
lvAssemblies.ModifyCol(3, 80)
lvAssemblies.ModifyCol(4, 380)
lvAssemblies.ModifyCol(5, 330)

; ═══════════════════════════════════════════════════════════════════════════════
; TAB 8 — MARSHALLING INSPECTOR
; ═══════════════════════════════════════════════════════════════════════════════
tabs.UseTab(8)

g.SetFont("s9 c0x00d4ff", "Segoe UI")
g.Add("Text", "x20 y51 w80 h20 BackgroundTrans", "Example:")
g.SetFont("s10 c0xd4d4e8", "Cascadia Code")
marshExamples := ['"Hello World"', '12345', '3.14159', '[1, 2, "three"]', 'Map("Key1", "Val1", "Key2", 42)', 'Map("Key1", "Val1", "Key2", {a: "lol"})', '{a: 1, b: "two", c: [3, 4]}', 'Buffer(16)']
cbMarshExample := g.Add("ComboBox", "vMarshExample x90 y48 w400 Background0x12121f c0xd4d4e8 -E0x200", marshExamples)
cbMarshExample.Text := '[1, 2, "three"]'

g.SetFont("s10 c0xd0d0e0", "Segoe UI")
btnInspectMarsh := AddButton(g, "x510 y48 w100 h24", "Inspect")
btnInspectMarsh.OnEvent("Click", OnInspectMarsh)

g.SetFont("s9 c0x00d4ff", "Segoe UI")
g.Add("Text", "x20 y86 w400 h18 BackgroundTrans", "◆  AHK Expression")
g.SetFont("s9 c0xa78bfa", "Segoe UI")
g.Add("Text", "x560 y86 w400 h18 BackgroundTrans", "◆  .NET Resolution (Interactive TreeView)")

g.SetFont("s10 c0xd4d4e8", "Cascadia Code")
global edMarshAhk := g.Add("Edit", "x20 y106 w520 h600 Multi WantTab VScroll HScroll Background0x12121f +Border -E0x200", '[1, 2, "three"]')

g.SetFont("s10 c0x4ade80", "Cascadia Code")
global tvMarsh := g.Add("TreeView", "x560 y106 w550 h600 Background0x12121f c0x4ade80 +Border -E0x200")

cbMarshExample.OnEvent("Change", (*) => edMarshAhk.Value := cbMarshExample.Text)

; ═══════════════════════════════════════════════════════════════════════════════
; TAB 9 — OVERLOAD PREDICTOR
; ═══════════════════════════════════════════════════════════════════════════════
tabs.UseTab(9)

g.SetFont("s9 c0x00d4ff", "Segoe UI")
g.Add("Text", "x20 y50 w80 h22 BackgroundTrans", "Type Name:")
g.SetFont("s10 c0xd4d4e8", "Cascadia Code")
edPredType := g.Add("Edit", "x100 y48 w320 Background0x12121f c0xd4d4e8 +Border -E0x200", "System.Convert")

g.SetFont("s9 c0x00d4ff", "Segoe UI")
g.Add("Text", "x450 y50 w90 h22 BackgroundTrans", "Method Name:")
g.SetFont("s10 c0xd4d4e8", "Cascadia Code")
edPredMethod := g.Add("Edit", "x550 y48 w320 Background0x12121f c0xd4d4e8 +Border -E0x200", "ToInt32")

g.SetFont("s10 c0xd0d0e0", "Segoe UI")
btnPredict := AddButton(g, "x900 y47 w210 h26", "Predict")
btnPredict.OnEvent("Click", OnPredictOverload)

g.SetFont("s9 c0x00d4ff", "Segoe UI")
g.Add("Text", "x20 y78 w400 h18 BackgroundTrans", '◆  AHK Arguments Array (JSON array format: ["123", 16] )')
g.SetFont("s10 c0xd4d4e8", "Cascadia Code")
global edPredArgs := g.Add("Edit", "x20 y98 w1090 h80 Multi WantTab Background0x12121f +Border -E0x200", '["123", 16]')

g.SetFont("s9 c0xa78bfa", "Segoe UI")
g.Add("Text", "x20 y186 w400 h18 BackgroundTrans", "◆  Selected C# Overload")
g.SetFont("s10 c0x4ade80", "Cascadia Code")
global edPredResult := g.Add("Edit", "x20 y206 w1090 h500 Multi ReadOnly Background0x0d0d18 +Border -E0x200", "")

; ═══════════════════════════════════════════════════════════════════════════════
; TAB 10 — VISUAL WRAPPER AUTO-GENERATOR
; ═══════════════════════════════════════════════════════════════════════════════
tabs.UseTab(10)

g.SetFont("s9 c0x00d4ff", "Segoe UI")
g.Add("Text", "x20 y50 w90 h22 BackgroundTrans", "Assembly Path:")
g.SetFont("s10 c0xd4d4e8", "Cascadia Code")
edWrapAsm := g.Add("Edit", "x115 y48 w400 h24 Background0x12121f c0xd4d4e8 +Border -E0x200", "System.Drawing")

g.SetFont("s10 c0xd0d0e0", "Segoe UI")
btnWrapBrowse := AddButton(g, "x525 y47 w90 h26", "Browse...")
btnWrapBrowse.OnEvent("Click", OnWrapBrowse)

btnWrapLoad := AddButton(g, "x630 y47 w100 h26", "Load Types")
btnWrapLoad.OnEvent("Click", OnWrapLoad)

g.SetFont("s9 c0x00d4ff", "Segoe UI")
g.Add("Text", "x20 y78 w200 h18 BackgroundTrans", "◆  Available Classes")
g.SetFont("s9 c0xd0d0e0", "Segoe UI")
lvWrapTypes := g.Add("ListView", "x20 y98 w400 h555 Background0x12121f c0xd0d0e0 Checked -E0x200", ["Class Name", "Methods"])
lvWrapTypes.ModifyCol(1, 300)
lvWrapTypes.ModifyCol(2, 70)

g.SetFont("s10 c0xd0d0e0", "Segoe UI")
btnWrapGen := AddButton(g, "x440 y356 w100 h40", "Generate ➔")
btnWrapGen.OnEvent("Click", OnWrapGen)

g.SetFont("s9 c0xa78bfa", "Segoe UI")
g.Add("Text", "x560 y78 w200 h18 BackgroundTrans", "◆  Runtime Wrapper (.ahk)")

g.SetFont("s9 c0x22d3ee", "Segoe UI")
g.Add("Text", "x840 y78 w200 h18 BackgroundTrans", "◆  IntelliSense Def (.d.ahk)")

g.SetFont("s9 c0x4ade80", "Cascadia Code")
global edWrapOut := g.Add("Edit", "x560 y98 w270 h555 Multi ReadOnly VScroll HScroll Background0x0d0d18 +Border -E0x200", "")

g.SetFont("s9 c0x22d3ee", "Cascadia Code")
global edWrapDef := g.Add("Edit", "x840 y98 w270 h555 Multi ReadOnly VScroll HScroll Background0x0d0d18 +Border -E0x200", "")

btnWrapTest := AddButton(g, "x560 y662 w130 h30", "Test Wrapper")
btnWrapTest.OnEvent("Click", OnWrapTest)

btnWrapSave := AddButton(g, "x700 y662 w130 h30", "Save Wrapper")
btnWrapSave.OnEvent("Click", OnWrapSave)

btnDefSave := AddButton(g, "x840 y662 w270 h30", "Save IntelliSense")
btnDefSave.OnEvent("Click", OnDefSave)

; ═══════════════════════════════════════════════════════════════════════════════
; TAB 1 — EXAMPLES CATALOGUE
; ═══════════════════════════════════════════════════════════════════════════════
tabs.UseTab(1)

g.SetFont("s9 c0x00d4ff", "Segoe UI")
g.Add("Text", "x20 y50 w350 h22 BackgroundTrans", "◆  Examples Catalogue")

global g_examplesList := []
global activeExampleIndex := 1

InitialLoadExamples() {
    global g_examplesList
    g_examplesList := []

    examplesDir := A_ScriptDir "\examples"

    Loop Files, examplesDir "\*.ahk", "R" {
        filePath := A_LoopFileFullPath

        ; Read file content using UTF-8 to preserve unicode / utf characters correctly
        content := FileRead(filePath, "UTF-8")

        ; Parse category (parent directory name)
        SplitPath(filePath, &fileName, &dirPath)
        SplitPath(dirPath, &category)

        ; Skip lib_bench category completely
        if (category == "lib_bench" || InStr(filePath, "\lib_bench\"))
            continue

        ; Default title and description from filename
        title := StrReplace(fileName, ".ahk", "")
        desc := "Runs the script " fileName " from the " category " category."

        ; Parse headers from the first few lines of the file
        Loop Parse, content, "`n", "`r" {
            if (A_Index == 1 && SubStr(A_LoopField, 1, 2) == ";;") {
                title := Trim(SubStr(A_LoopField, 3))
            } else if (A_Index == 2 && SubStr(A_LoopField, 1, 2) == ";;") {
                desc := Trim(SubStr(A_LoopField, 3))
                break
            } else if (A_Index > 2) {
                break
            }
        }

        ; Clean title to remove prefixes like "AHK# Example XX — " or "AHK# Example XX - "
        number := 999 ; Default if no match
        if (RegExMatch(title, "i)^AHK#\s+Example\s+(\d+)\s*(?:—|–|-|~)\s*(.*)$", &m)) {
            number := Integer(m[1])
            title := m[2]
        } else if (RegExMatch(title, "i)^AHK#\s+Example\s+(\d+)\s+(.*)$", &m)) {
            number := Integer(m[1])
            title := m[2]
        }

        g_examplesList.Push({
            title: title,
            category: FormatCategory(category),
            desc: desc,
            mode: "AHK Script",
            code: content,
            path: filePath,
            number: number
        })
    }

    ; Sort examples logically by category weight, then by example number, and finally by title
    SortExamples()
}

FormatCategory(cat) {
    if (cat == "basics")
        return "Basics"
    if (cat == "benchmarks")
        return "Benchmarks"
    if (cat == "features")
        return "Features"
    if (cat == "network")
        return "Network & Web"
    if (cat == "showcase")
        return "Showcases"
    if (cat == "system")
        return "System Diagnostics"
    if (cat == "tools")
        return "Developer Tools"
    return cat
}

GetCategoryWeight(cat) {
    if (cat == "Basics")
        return 1
    if (cat == "Features")
        return 2
    if (cat == "Network & Web")
        return 3
    if (cat == "System Diagnostics")
        return 4
    if (cat == "Showcases")
        return 5
    if (cat == "Benchmarks")
        return 6
    if (cat == "Developer Tools")
        return 7

    return 8
}

SortExamples() {
    global g_examplesList
    n := g_examplesList.Length
    Loop n {
        i := A_Index
        j := i
        while (j > 1) {
            prev := g_examplesList[j - 1]
            curr := g_examplesList[j]

            prevWeight := GetCategoryWeight(prev.category)
            currWeight := GetCategoryWeight(curr.category)

            shouldSwap := false
            if (prevWeight > currWeight) {
                shouldSwap := true
            } else if (prevWeight == currWeight) {
                if (prev.number > curr.number) {
                    shouldSwap := true
                } else if (prev.number == curr.number) {
                    if (StrCompare(prev.title, curr.title) > 0) {
                        shouldSwap := true
                    }
                }
            }

            if (shouldSwap) {
                g_examplesList[j] := prev
                g_examplesList[j - 1] := curr
                j--
            } else {
                break
            }
        }
    }
}

; Call the dynamic initial load at startup
InitialLoadExamples()

; Dynamic scrollable list of examples on the left
g.SetFont("s9 c0xd0d0e0", "Segoe UI")
global lvExamples := g.Add("ListView", "x20 y78 w360 h480 Background0x12121f c0xd0d0e0 -E0x200", ["Name", "Category"])
lvExamples.ModifyCol(1, 230)
lvExamples.ModifyCol(2, 110)
lvExamples.OnEvent("ItemSelect", OnExampleSelect)

; Create a dummy ImageList to increase ListView row height for a premium spacious feel
hIL := DllCall("comctl32\ImageList_Create", "int", 1, "int", 38, "uint", 0x20, "int", 1, "int", 1, "ptr")
DllCall("user32\SendMessage", "ptr", lvExamples.Hwnd, "uint", 0x1003, "ptr", 1, "ptr", hIL, "ptr") ; LVM_SETIMAGELIST

; Populate ListView
lvExamples.Opt("-Redraw")
for ex in g_examplesList {
    lvExamples.Add("", ex.title, ex.category)
}
lvExamples.Opt("+Redraw")

g.SetFont("s8 c0x6a6a8a", "Segoe UI")
g.Add("Text", "x20 y570 w360 h80 BackgroundTrans", "💡 Click any example in the scrollable catalogue on the left to see details and raw source code preview.`n`nClick 'Run' to execute in a standalone process.")

; Right Column Preview Controls
g.SetFont("s11 c0x00d4ff Bold", "Segoe UI")
global lblExTitle := g.Add("Text", "x400 y50 w450 h24 BackgroundTrans", "")

g.SetFont("s9 c0xa78bfa Bold", "Segoe UI")
global lblExMode := g.Add("Text", "x860 y50 w240 h22 Center +Border +0x200 Background0x1e1e38 c0xa78bfa", "")

g.SetFont("s9 c0xd0d0e0", "Segoe UI")
global edExDesc := g.Add("Edit", "x400 y86 w700 h80 Multi ReadOnly Background0x12121f -E0x200 c0xd0d0e0", "")

g.SetFont("s9 c0xa78bfa", "Segoe UI")
g.Add("Text", "x400 y176 w200 h18 BackgroundTrans", "◆  Example Code Preview")

g.SetFont("s9 c0x4ade80", "Cascadia Code")
global edExCode := g.Add("Edit", "x400 y196 w700 h420 Multi ReadOnly VScroll Background0x0d0d18 +Border -E0x200 c0x4ade80", "")

global btnExRun := AddButton(g, "x400 y628 w700 h36", "▸ Run")
btnExRun.OnEvent("Click", OnExRunClick)

; ═══════════════════════════════════════════════════════════════════════════════
; STATUS BAR & SHOW
; ═══════════════════════════════════════════════════════════════════════════════
tabs.UseTab()  ; Controls below are on all tabs

g.SetFont("s8 c0x4a4a6a", "Segoe UI")
lblStatus := g.Add("Text", "x15 y725 w1100 h18 BackgroundTrans",
    "AHK# Developer Studio ready  —  Bridge: " AHK_SHARP_VERSION "  —  CLR: " AHK_SHARP_CLR)

; Subclass procedure to dynamically paint ListView column headers with light grey text
global lvSubclassCallback := CallbackCreate(LV_SubclassProc, "F", 6)
LV_SubclassProc(hWnd, uMsg, wParam, lParam, uIdSubclass, dwRefData) {
    static WM_NOTIFY := 0x004E
    static NM_CUSTOMDRAW := -12
    static CDDS_PREPAINT := 0x1
    static CDDS_ITEMPREPAINT := 0x10001
    static CDRF_NOTIFYITEMDRAW := 0x20
    static CDRF_DODEFAULT := 0x0

    try {
        if (uMsg == WM_NOTIFY && lParam) {
            hdr_code := NumGet(lParam, 2 * A_PtrSize, "Int")
            if (hdr_code == NM_CUSTOMDRAW) {
                hwndFrom := NumGet(lParam, 0, "Ptr")

                ; Extremely fast, allocation-free check if the notification is from the SysHeader32 child control
                if (hwndFrom && hwndFrom == DllCall("user32\SendMessage", "ptr", hWnd, "uint", 0x101F, "ptr", 0, "ptr", 0, "ptr")) {
                    dwDrawStage := NumGet(lParam, 3 * A_PtrSize, "UInt")
                    if (dwDrawStage == CDDS_PREPAINT) {
                        return CDRF_NOTIFYITEMDRAW
                    }
                    if (dwDrawStage == CDDS_ITEMPREPAINT) {
                        hdc := NumGet(lParam, 4 * A_PtrSize, "Ptr")
                        DllCall("gdi32\SetTextColor", "ptr", hdc, "uint", 0xD0D0E0) ; Light grey BGR
                        DllCall("gdi32\SetBkMode", "ptr", hdc, "int", 1) ; Transparent
                        return CDRF_DODEFAULT
                    }
                }
            }
        }
    } catch {
        ; Prevent deadlocks from unhandled exceptions inside subclass procedure
    }
    return DllCall("Comctl32\DefSubclassProc", "Ptr", hWnd, "UInt", uMsg, "Ptr", wParam, "Ptr", lParam, "Ptr")
}

; Force dark mode for all controls (headers, scrollbars, dropdowns)
for hwnd, ctrl in g {
    ctrlType := Type(ctrl)

    ; Skip custom tabs, custom buttons, examples controls, and the hidden logical tab control
    if (ctrl.HasProp("isCustomTab") || ctrl.HasProp("isCustomButton") || ctrl.HasProp("isExampleCard") || ctrl.HasProp("isExampleCardChild") || ctrl == tabs)
        continue

    if (pAllowDarkModeForWindow)
        try DllCall(pAllowDarkModeForWindow, "ptr", hwnd, "int", 1)

    if (ctrlType == "Gui.DDL" || ctrlType == "Gui.ComboBox") {
        try DllCall("uxtheme\SetWindowTheme", "ptr", hwnd, "wstr", "DarkMode_CFD", "ptr", 0)
    } else if (ctrlType == "Gui.ListView") {
        try DllCall("uxtheme\SetWindowTheme", "ptr", hwnd, "wstr", "Explorer", "ptr", 0)
        try DllCall("Comctl32\SetWindowSubclass", "Ptr", hwnd, "Ptr", lvSubclassCallback, "Ptr", hwnd, "Ptr", 0)
    } else if (ctrlType == "Gui.Edit" || ctrlType == "Gui.TreeView") {
        try DllCall("uxtheme\SetWindowTheme", "ptr", hwnd, "wstr", "DarkMode_Explorer", "ptr", 0)
    } else {
        try DllCall("uxtheme\SetWindowTheme", "ptr", hwnd, "wstr", "DarkMode_Explorer", "ptr", 0)
    }

    if (ctrlType == "Gui.ListView") {
        try {
            headerHwnd := SendMessage(0x101F, 0, 0, hwnd) ; LVM_GETHEADER
            if headerHwnd {
                DllCall("uxtheme\SetWindowTheme", "ptr", headerHwnd, "wstr", "DarkMode_ItemsView", "ptr", 0)
            }
        }
    }
}

; Hook to color ComboBox/DropDownList popup menus dark
OnMessage(0x0134, WM_CTLCOLORLISTBOX)
WM_CTLCOLORLISTBOX(wParam, lParam, msg, hwnd) {
    DllCall("SetTextColor", "ptr", wParam, "uint", 0xE0D0D0) ; Light text
    DllCall("SetBkColor", "ptr", wParam, "uint", 0x2E1A1A)   ; Dark background
    static brush := DllCall("CreateSolidBrush", "uint", 0x2E1A1A, "ptr")
    return brush
}

g.Show("w1140 h748")
g.OnEvent("Close", (*) => ExitApp())

; ── Initial Data Load ─────────────────────────────────────────────────────────
SetTimer(InitialLoad, -200)

InitialLoad() {
    ; Load cache stats
    OnCacheRefresh()
    ; Load CLR diagnostics
    OnRefreshCLR()
    ; Load installed packages
    OnRefreshInstalled()
    ; Pre-load the first example in the previewer
    UpdateExamplePreview(1)
    try lvExamples.Modify(1, "Select Focus")
    SetStatus("AHK# Developer Studio loaded successfully")
}

; ═══════════════════════════════════════════════════════════════════════════════
; EVENT HANDLERS — EXAMPLES CATALOGUE
; ═══════════════════════════════════════════════════════════════════════════════

OnExampleSelect(ctrl, row, selected) {
    if (!selected)
        return
    UpdateExamplePreview(row)
}

UpdateExamplePreview(idx) {
    if (idx < 1 || idx > g_examplesList.Length)
        return
    ex := g_examplesList[idx]

    lblExTitle.Value := ex.title
    lblExMode.Value := ex.mode
    edExDesc.Value := ex.desc
    edExCode.Value := ex.code
}

OnExRunClick(*) {
    row := lvExamples.GetNext(0, "Focused")
    if (row == 0)
        row := 1
    if (row < 1 || row > g_examplesList.Length)
        return
    ex := g_examplesList[row]

    SetStatus("Running standalone example '" ex.title "'...")
    try {
        Run('"' A_AhkPath '" "' ex.path '"')
        SetStatus("Successfully launched '" ex.title "'")
    } catch as e {
        SetStatus("Failed to run example: " e.Message)
    }
}

LV_HitTest(hwnd) {
    pt := Buffer(8, 0)
    DllCall("user32\GetCursorPos", "ptr", pt)
    DllCall("user32\ScreenToClient", "ptr", hwnd, "ptr", pt)
    x := NumGet(pt, 0, "int")
    y := NumGet(pt, 4, "int")

    lvhti := Buffer(24, 0)
    NumPut("int", x, lvhti, 0)
    NumPut("int", y, lvhti, 4)

    row := DllCall("user32\SendMessage", "ptr", hwnd, "uint", 0x1039, "ptr", 0, "ptr", lvhti, "ptr") ; LVM_SUBITEMHITTEST
    return row + 1
}

; ═══════════════════════════════════════════════════════════════════════════════
; EVENT HANDLERS — SCRATCHPAD
; ═══════════════════════════════════════════════════════════════════════════════

OnLoadSnippet(*) {
    name := ddlSnippet.Text
    if !snippetCode.Has(name) {
        SetStatus("Select a valid snippet (not a separator)")
        return
    }
    info := snippetCode[name]
    edCode.Value := info.code

    ; Auto-select the correct mode
    if (info.mode == "C# Expression")
        ddlMode.Choose(1)
    else if (info.mode == "C# Class")
        ddlMode.Choose(2)
    else
        ddlMode.Choose(3)

    SetStatus("Loaded snippet: " name)
}

OnSendToPrecompiler(*) {
    global edCode, edPrecompCode, customTabs
    code := edCode.Value
    if (code == "") {
        SetStatus("Please enter some C# class code in the scratchpad first!")
        return
    }

    edPrecompCode.Value := code
    OnTabClick(customTabs[5])  ; Switch to Precompiler Tab (index 5)
    SetStatus("Transferred C# code to Precompiler")
}

OnRunCode(*) {
    code := edCode.Value
    if (code == "") {
        AppendOutput("⚠ No code to run.")
        return
    }

    mode := ddlMode.Text
    lblRunStatus.Value := "Running..."
    startTick := A_TickCount

    if (mode == "C# Expression") {
        try {
            result := CS.Eval(code)
            elapsed := A_TickCount - startTick
            AppendOutput("═══ C# Expression ═══  [" elapsed "ms]")
            AppendOutput("→ " (IsObject(result) ? String(result) : result))
            lblRunStatus.Value := "Completed in " elapsed "ms"
        } catch as e {
            elapsed := A_TickCount - startTick
            AppendOutput("═══ C# Expression ERROR ═══  [" elapsed "ms]")
            AppendOutput("✗ " e.Message)
            lblRunStatus.Value := "Error — see output"
        }
    }
    else if (mode == "C# Class") {
        try {
            className := "__WB_" A_TickCount
            refs := ""
            if RegExMatch(code, "im)//\s*NuGet:\s*([a-zA-Z0-9\.]+)(?:\s+([\d\.]+))?", &match) {
                AppendOutput("📦 Resolving NuGet package: " match[1])
                refs := CS.NuGet.Require(match[1], match[2] ? match[2] : "")
            }
            if RegExMatch(code, "im)//\s*Reference[s]?:\s*(.+)", &refMatch) {
                customRefs := Trim(refMatch[1])
                frameworkDir := A_WinDir "\Microsoft.NET\" (A_PtrSize == 8 ? "Framework64" : "Framework") "\v4.0.30319"
                resolvedRefs := ""
                for ref in StrSplit(customRefs, ";") {
                    ref := Trim(ref)
                    if (ref == "UIAutomationClient.dll" || ref == "UIAutomationTypes.dll" || ref == "WindowsBase.dll" || ref == "PresentationCore.dll" || ref == "PresentationFramework.dll") {
                        resolvedRefs .= (resolvedRefs == "" ? "" : ";") frameworkDir "\WPF\" ref
                    } else {
                        resolvedRefs .= (resolvedRefs == "" ? "" : ";") ref
                    }
                }
                refs := (refs == "") ? resolvedRefs : refs ";" resolvedRefs
                AppendOutput("📎 Referencing assemblies: " resolvedRefs)
            }
            ; Extract using directives to place them outside the class wrapper
            usings := "using System; using System.Linq; using System.Collections.Generic;"
            cleanCode := ""
            Loop Parse, code, "`n", "`r" {
                line := Trim(A_LoopField)
                if (SubStr(line, 1, 6) == "using " && SubStr(line, -1) == ";") {
                    usings .= " " line
                } else {
                    cleanCode .= A_LoopField "`n"
                }
            }
            fullCode := usings "`npublic class " className "`n{`n" cleanCode "`n}"
            bridge := _AhkSharpEngine.Boot()
            asmId := bridge.CompileModule(fullCode, refs)
            result := bridge.InvokeModule(asmId, className, "Run", "")
            elapsed := A_TickCount - startTick
            AppendOutput("═══ C# Class ═══  [" elapsed "ms]  (class: " className ")")
            AppendOutput("→ " (IsObject(result) ? String(result) : result))
            lblRunStatus.Value := "Compiled and executed in " elapsed "ms"
        } catch as e {
            elapsed := A_TickCount - startTick
            AppendOutput("═══ C# Class ERROR ═══  [" elapsed "ms]")
            AppendOutput("✗ " e.Message)
            lblRunStatus.Value := "Compilation/execution error"
        }
    }
    else if (mode == "AHK Script") {
        try {
            ; Save to temp file and run with AHK
            tmpFile := A_Temp "\ahk_wb_" A_TickCount ".ahk"
            libDir := A_ScriptDir "\lib"
            extDir := A_ScriptDir "\ext"
            header := "#Requires AutoHotkey v2.0`n#SingleInstance Force`n"
            header .= '#Include "' libDir '\ahk#.ahk"`n'
            header .= '#Include "' extDir '\ahk#.http.ahk"`n'
            ; Wrap user code in try/catch for robust error handling
            header .= "`ntry {`n"
            footer := "`n} catch as __wb_err {`n"
                . "    __wb_msg := '❌ ' . Type(__wb_err) . '``n``n' . __wb_err.Message`n"
                . "    if (__wb_err.Extra != '')`n"
                . "        __wb_msg .= '``n``n▸ Value/Target: ' . __wb_err.Extra`n"
                . "    if (__wb_err.What != '')`n"
                . "        __wb_msg .= '``n▸ Function: ' . __wb_err.What`n"
                . "    __wb_msg .= '``n▸ Line: ' . __wb_err.Line`n"
                . "    if (__wb_err.Stack != '')`n"
                . "        __wb_msg .= '``n``n── Call Stack ──``n' . __wb_err.Stack`n"
                . "    MsgBox(__wb_msg, 'Workbench Script Error', 'Icon!')`n}`n"
            FileAppend(header . code . footer, tmpFile, "UTF-8")
            Run('"' A_AhkPath '" "' tmpFile '"')
            elapsed := A_TickCount - startTick
            AppendOutput("═══ AHK Script Launched ═══  [" elapsed "ms]")
            AppendOutput("→ Script launched in new process")
            AppendOutput("  File: " tmpFile)
            lblRunStatus.Value := "Script launched"
            ; Clean up after delay
            SetTimer(() => (FileExist(tmpFile) ? FileDelete(tmpFile) : ""), -5000)
        } catch as e {
            AppendOutput("═══ AHK Script ERROR ═══")
            AppendOutput("✗ " e.Message)
            lblRunStatus.Value := "Launch error"
        }
    }
}

AppendOutput(text) {
    ts := FormatTime(, "HH:mm:ss")
    existing := edOutput.Value
    if (existing != "")
        edOutput.Value := existing "`r`n[" ts "] " text
    else
        edOutput.Value := "[" ts "] " text
    ; Scroll to bottom
    SendMessage(0x00B6, 0, -1, edOutput)  ; EM_LINESCROLL
}

OnExploreType(*) {
    typeName := Trim(edTypeName.Text)
    if (typeName == "") {
        SetStatus("Enter a .NET type name to explore")
        return
    }

    global g_skipHistoryPush
    global g_typeHistory
    if (!IsSet(g_typeHistory))
        g_typeHistory := []

    if (IsSet(g_currentTypeSearch) && g_currentTypeSearch != "" && g_currentTypeSearch != typeName) {
        if (!IsSet(g_skipHistoryPush) || !g_skipHistoryPush) {
            g_typeHistory.Push(g_currentTypeSearch)
        }
    }
    g_skipHistoryPush := false
    global g_currentTypeSearch := typeName

    SetStatus("Exploring " typeName "...")
    lvTypes.Delete()
    inherited := chkInherited.Value

    try {
        result := WBHelper.ExploreType(typeName, inherited)
        if (SubStr(result, 1, 6) == "ERROR:") {
            SetStatus(result)
            return
        }

        lvTypes.Opt("-Redraw")
        for line in StrSplit(result, "`n", "`r") {
            if (line == "")
                continue
            parts := StrSplit(line, "|")

            if (parts[1] == "Assembly") {
                global g_CurrentExploredAssembly := parts[2]
                continue
            }

            if (parts.Length >= 4) {
                kind := parts[1]
                if (IsSet(g_FilterStates) && g_FilterStates.Has(kind) && !g_FilterStates[kind])
                    continue
                lvTypes.Add("", parts[1], parts[2], parts[3], parts[4])
            }
        }
        lvTypes.Opt("+Redraw")
        SetStatus("Found " lvTypes.GetCount() " members in " typeName)
    } catch as e {
        SetStatus("Error: " e.Message)
    }
}

OnBtnBackType(*) {
    global g_typeHistory
    if (IsSet(g_typeHistory) && g_typeHistory.Length > 0) {
        edTypeName.Text := g_typeHistory.Pop()
        global g_skipHistoryPush := true
        OnExploreType()
    } else {
        SetStatus("No history to go back to")
    }
}

OnTypesDoubleClick(ctrl, info) {
    if (!info)
        return
    memberType := ctrl.GetText(info, 1)
    if (memberType == "Class" || memberType == "Interface" || memberType == "Struct" || memberType == "Enum" || memberType == "Delegate") {
        fullName := ctrl.GetText(info, 3)
        edTypeName.Text := fullName
        OnExploreType()
    }
}

OnGenSnippet(*) {
    row := lvTypes.GetNext(0, "Focused")
    if (!row) {
        edSnippet.Value := "; Select a member from the list first"
        return
    }
    memberType := lvTypes.GetText(row, 1)
    memberName := lvTypes.GetText(row, 2)
    typeName := g_currentTypeSearch

    if (memberType == "Class" || memberType == "Interface" || memberType == "Struct" || memberType == "Enum" || memberType == "Delegate") {
        fullName := lvTypes.GetText(row, 3)
        if (memberType == "Enum") {
            edSnippet.Value := "value := CS." StrReplace(fullName, "+", ".") "."
        } else {
            edSnippet.Value := "obj := CS." StrReplace(fullName, "+", ".") "()"
        }
        SetStatus("Snippet generated for Type: " fullName)
        return
    }

    try {
        snippet := WBHelper.GenerateSnippet(typeName, memberName, memberType)
        edSnippet.Value := snippet
        SetStatus("Snippet generated for " memberType ": " memberName)
    } catch as e {
        edSnippet.Value := "; Error generating snippet: " e.Message
    }
}

OnSendToWrapper(*) {
    if !IsSet(g_CurrentExploredAssembly) || g_CurrentExploredAssembly == "" {
        SetStatus("Please explore a valid type first!")
        return
    }

    ; Visually switch to Wrapper Gen Tab (Tab 10)
    OnTabClick(customTabs[10])

    ; Load the assembly types
    edWrapAsm.Value := g_CurrentExploredAssembly
    OnWrapLoad()

    ; Auto-check the class the user was looking at
    foundRow := 0
    Loop lvWrapTypes.GetCount() {
        if (lvWrapTypes.GetText(A_Index, 1) == edTypeName.Text) {
            lvWrapTypes.Modify(A_Index, "Check Select Focus")
            foundRow := A_Index
            break
        }
    }

    if (foundRow > 0) {
        ; Auto generate wrappers!
        OnWrapGen()
        SetStatus("Sent " edTypeName.Text " to Wrapper Generator and auto-generated wrappers.")
    } else {
        SetStatus("Sent assembly " g_CurrentExploredAssembly " to Wrapper Generator.")
    }
}

OnNuGetSearch(*) {
    query := Trim(edNuGetSearch.Value)
    if (query == "") {
        SetStatus("Enter a package name to search")
        return
    }

    lblNuGetStatus.Value := "Searching..."
    lvNuGetResults.Delete()
    SetStatus("Searching NuGet for: " query)

    ; Use async to avoid blocking UI
    WBHelper.Async.SearchNuGet(query).Then(OnNuGetResults)
}

OnNuGetResults(result) {
    if (SubStr(result, 1, 6) == "ERROR:") {
        lblNuGetStatus.Value := "Error!"
        SetStatus("NuGet error: " SubStr(result, 7))
        return
    }

    lvNuGetResults.Opt("-Redraw")
    lvNuGetResults.Delete()
    count := 0
    for line in StrSplit(result, "`n", "`r") {
        if (line == "")
            continue
        parts := StrSplit(line, "|")
        if (parts.Length >= 4) {
            ; Format download count
            dl := parts[3]
            try {
                dlNum := Integer(dl)
                if (dlNum > 1000000)
                    dl := Round(dlNum / 1000000, 1) "M"
                else if (dlNum > 1000)
                    dl := Round(dlNum / 1000, 1) "K"
            }
            lvNuGetResults.Add("", parts[1], parts[2], dl, parts[4])
            count++
        }
    }
    lvNuGetResults.Opt("+Redraw")
    lblNuGetStatus.Value := count " packages found"
    SetStatus("NuGet search complete — " count " results")
}

OnNuGetInstall(*) {
    row := lvNuGetResults.GetNext(0, "Focused")
    if (!row) {
        lblInstallStatus.Value := "Select a package first"
        return
    }
    pkgName := lvNuGetResults.GetText(row, 1)
    pkgVer := lvNuGetResults.GetText(row, 2)

    lblInstallStatus.Value := "Installing " pkgName " " pkgVer "..."
    SetStatus("Installing " pkgName " " pkgVer "...")

    try {
        CS.NuGet.Install(pkgName, pkgVer)
        lblInstallStatus.Value := "✓ Installed " pkgName " " pkgVer
        SetStatus("Successfully installed " pkgName " " pkgVer)
        OnRefreshInstalled()
    } catch as e {
        lblInstallStatus.Value := "✗ Error: " SubStr(e.Message, 1, 80)
        SetStatus("Install error: " e.Message)
    }
}

OnRefreshInstalled(*) {
    lvInstalled.Delete()
    try {
        result := WBHelper.ListInstalledPkgs()
        if (result == "")
            return

        lvInstalled.Opt("-Redraw")
        for line in StrSplit(result, "`n", "`r") {
            if (line == "")
                continue
            parts := StrSplit(line, "|")
            if (parts.Length >= 4)
                lvInstalled.Add("", parts[1], parts[2], parts[3], parts[4])
        }
        lvInstalled.Opt("+Redraw")
    }
}

OnNuGetSendToWrapper(*) {
    row := lvInstalled.GetNext(0, "Focused")
    if (row == 0) {
        SetStatus("Please select an installed package first!")
        return
    }

    pkgName := lvInstalled.GetText(row, 1)
    pkgVer := lvInstalled.GetText(row, 2)

    try {
        dllsStr := WBHelper.GetPackageDlls(pkgName, pkgVer)
        if (dllsStr == "") {
            SetStatus("No assembly DLLs found inside package " pkgName)
            return
        }

        parts := StrSplit(dllsStr, ";")
        firstDll := parts[1]

        ; Set Wrapper Gen DLL path
        edWrapAsm.Value := firstDll

        ; Visually switch to Wrapper Gen Tab (Tab 10)
        OnTabClick(customTabs[10])

        ; Load types
        OnWrapLoad()

        SetStatus("Loaded package DLL into Wrapper Generator: " pkgName " -> " firstDll)
    } catch as e {
        SetStatus("Error sending package: " e.Message)
    }
}

OnNuGetRemove(*) {
    row := lvInstalled.GetNext(0, "Focused")
    if (row == 0) {
        SetStatus("Please select an installed package first!")
        return
    }

    pkgName := lvInstalled.GetText(row, 1)
    pkgVer := lvInstalled.GetText(row, 2)

    if (MsgBox("Are you sure you want to uninstall " pkgName " (version " pkgVer ")?", "Confirm Uninstall", "YesNo Icon! Default2") != "Yes") {
        return
    }

    try {
        result := CS.NuGet.Uninstall(pkgName, pkgVer)
        if (result) {
            SetStatus("Successfully uninstalled " pkgName " (" pkgVer ")")
            OnRefreshInstalled()
        } else {
            SetStatus("Failed to uninstall " pkgName)
        }
    } catch as e {
        SetStatus("Error uninstalling package: " e.Message)
    }
}

OnNuGetInstalledContextMenu(ctrl, itemIndex, isRightClick, x, y) {
    if (!itemIndex)
        return
        
    pkgName := lvInstalled.GetText(itemIndex, 1)
    pkgVer := lvInstalled.GetText(itemIndex, 2)
    
    InstalledPkgMenu := Menu()
    InstalledPkgMenu.Add("Uninstall " pkgName " (" pkgVer ")", (*) => UninstallPackageDirect(pkgName, pkgVer))
    InstalledPkgMenu.Add("Send to Wrapper Gen", (*) => (lvInstalled.Modify(itemIndex, "Select Focus"), OnNuGetSendToWrapper()))
    InstalledPkgMenu.Show()
}

UninstallPackageDirect(pkgName, pkgVer) {
    if (MsgBox("Are you sure you want to uninstall " pkgName " (version " pkgVer ")?", "Confirm Uninstall", "YesNo Icon! Default2") != "Yes") {
        return
    }

    try {
        result := CS.NuGet.Uninstall(pkgName, pkgVer)
        if (result) {
            SetStatus("Successfully uninstalled " pkgName " (" pkgVer ")")
            OnRefreshInstalled()
        } else {
            SetStatus("Failed to uninstall " pkgName)
        }
    } catch as e {
        SetStatus("Error uninstalling package: " e.Message)
    }
}

OnSendPrecompSnippetToScratch(*) {
    global edPrecompOut, edCode, ddlMode, customTabs
    text := edPrecompOut.Value
    if (text == "") {
        SetStatus("Please compile C# code first!")
        return
    }

    snippet := ""
    if RegExMatch(text, "s)bridge := _AhkSharpEngine\.Boot\(\).*?MsgBox\(String\(result\)\)", &match) {
        snippet := match[0]
        snippet := RegExReplace(snippet, "m)^[ \t]+", "") ; Strip leading spaces
    } else {
        ; Fallback: look for bridge := _AhkSharpEngine.Boot() to the end
        startIdx := InStr(text, "bridge := _AhkSharpEngine.Boot()")
        if (startIdx) {
            snippet := SubStr(text, startIdx)
        } else {
            startIdx := InStr(text, "  bridge := _AhkSharpEngine.Boot()")
            if (startIdx) {
                snippet := SubStr(text, startIdx)
                snippet := RegExReplace(snippet, "m)^  ", "")
            }
        }
    }

    if (snippet == "") {
        SetStatus("No compiled test snippet available in output.")
        return
    }

    edCode.Value := snippet
    ddlMode.Choose(3)  ; AHK Script mode
    OnTabClick(customTabs[2])  ; Switch to Scratchpad Tab (index 2)
    SetStatus("Sent compiled test script to Scratchpad!")
}

OnPrecompile(*) {
    global g_precompAsmId
    code := edPrecompCode.Value
    className := edClassName.Value
    refs := edPrecompRefs.Value
    csVer := ddlCSVer.Text

    if (code == "" || className == "") {
        edPrecompOut.Value := "⚠ Enter a class name and C# code first."
        return
    }

    edPrecompOut.Value := "Compiling..."
    startTick := A_TickCount

    ; Build full source
    fullCode := "using System; using System.Linq; using System.Collections.Generic;"
        . " public class " className " { " code " }"

    try {
        bridge := _AhkSharpEngine.Boot()
        if (csVer != "4.0 (default)")
            g_precompAsmId := bridge.CompileModuleVersioned(fullCode, refs, csVer)
        else
            g_precompAsmId := bridge.CompileModule(fullCode, refs)

        elapsed := A_TickCount - startTick
        edPrecompOut.Value := "✓ Compilation successful!  [" elapsed "ms]"
            . "`r`n  Assembly ID: " g_precompAsmId
            . "`r`n  Class: " className
            . "`r`n  C# Version: " csVer
            . "`r`n`r`n  You can now Export DLL or test in AHK Script with:"
            . "`r`n  bridge := _AhkSharpEngine.Boot()"
            . '`r`n  result := bridge.InvokeModule("' g_precompAsmId '", "' className '", "Run", "")'
            . '`r`n  MsgBox(String(result))'

        ; Try running if Run() exists
        try {
            testResult := bridge.InvokeModule(g_precompAsmId, className, "Run", "")
            edPrecompOut.Value := edPrecompOut.Value
                . "`r`n`r`n═══ Test Run Output ═══"
                . "`r`n" (IsObject(testResult) ? String(testResult) : testResult)
        }

        SetStatus("Compilation successful — " elapsed "ms")
    } catch as e {
        elapsed := A_TickCount - startTick
        g_precompAsmId := ""
        edPrecompOut.Value := "✗ Compilation FAILED  [" elapsed "ms]"
            . "`r`n`r`n" e.Message
        SetStatus("Compilation failed")
    }
}

OnExportDLL(*) {
    global g_precompAsmId
    if (g_precompAsmId == "") {
        edPrecompOut.Value := "⚠ Compile first before exporting."
        return
    }

    className := edClassName.Value
    savePath := FileSelect("S16", A_Desktop "\" className ".dll", "Export Compiled DLL", "DLL Files (*.dll)")
    if (savePath == "")
        return

    try {
        bridge := _AhkSharpEngine.Boot()
        bridge.CopyModuleDLL(g_precompAsmId, savePath)
        edPrecompOut.Value := edPrecompOut.Value
            . "`r`n`r`n✓ DLL exported to: " savePath
        SetStatus("DLL exported: " savePath)
    } catch as e {
        edPrecompOut.Value := edPrecompOut.Value
            . "`r`n`r`n✗ Export failed: " e.Message
        SetStatus("Export failed")
    }
}

OnCacheRefresh(*) {
    lvCache.Delete()

    try {
        ; Get stats
        stats := WBHelper.GetCacheStats()
        statParts := StrSplit(stats, "|")
        if (statParts.Length >= 3) {
            lblCacheStats.Value := "📦 " statParts[1] " compiled modules  •  " statParts[2] " total"
            lblCachePath.Value := "Cache location: " statParts[3]
        }

        ; Get entries
        entries := WBHelper.ScanCache()
        if (entries == "")
            return

        lvCache.Opt("-Redraw")
        for line in StrSplit(entries, "`n", "`r") {
            if (line == "")
                continue
            parts := StrSplit(line, "|")
            if (parts.Length >= 4)
                lvCache.Add("", parts[1], parts[2], parts[3], parts[4])
        }
        lvCache.Opt("+Redraw")
        SetStatus("Cache refreshed — " lvCache.GetCount() " entries")
    } catch as e {
        SetStatus("Cache scan error: " e.Message)
    }
}

OnCacheDelete(*) {
    row := lvCache.GetNext(0, "Focused")
    if (!row) {
        SetStatus("Select a cache entry to delete")
        return
    }
    hash := lvCache.GetText(row, 1)
    classes := lvCache.GetText(row, 4)

    result := MsgBox("Delete cached module?`n`nHash: " hash "`nClasses: " classes,
        "Confirm Delete", "YesNo Icon!")
    if (result != "Yes")
        return

    try {
        WBHelper.DeleteCacheEntry(hash)
        OnCacheRefresh()
        SetStatus("Deleted cache entry: " hash)
    } catch as e {
        SetStatus("Delete error: " e.Message)
    }
}

OnCacheClearAll(*) {
    count := lvCache.GetCount()
    if (count == 0) {
        SetStatus("Cache is already empty")
        return
    }

    result := MsgBox("Clear ALL " count " cached modules?`n`n"
        . "This will force re-compilation next time modules are loaded.`n"
        . "Running scripts may be affected.",
        "Clear Entire Cache", "YesNo Icon!")
    if (result != "Yes")
        return

    try {
        deleted := WBHelper.ClearAllCache()
        OnCacheRefresh()
        SetStatus("Cleared " deleted " files from cache")
    } catch as e {
        SetStatus("Clear error: " e.Message)
    }
}

OnForceGC(*) {
    SetStatus("Forcing garbage collection...")
    beforeInfo := WBHelper.GetMemoryInfo()
    beforeParts := StrSplit(beforeInfo, "|")
    beforeBytes := (beforeParts.Length >= 6) ? beforeParts[6] : 0

    CS.GC()

    afterInfo := WBHelper.GetMemoryInfo()
    afterParts := StrSplit(afterInfo, "|")
    afterBytes := (afterParts.Length >= 6) ? afterParts[6] : 0

    UpdateCLRDisplay(afterInfo)

    ; Clean unused cache files from disk
    cleanedCount := 0
    try {
        cleanedCount := WBHelper.CleanUnusedCache()
    }

    try {
        freed := Integer(beforeBytes) - Integer(afterBytes)
        statusMsg := "GC complete"
        if (freed > 0) {
            freedStr := (freed > 1048576)
                ? Round(freed / 1048576, 2) " MB"
                : Round(freed / 1024, 1) " KB"
            statusMsg .= " — freed " freedStr
        } else {
            statusMsg .= " — no significant memory freed"
        }
        if (cleanedCount > 0) {
            statusMsg .= " — cleaned " cleanedCount " old cache files"
        }
        SetStatus(statusMsg)
    } catch {
        SetStatus("GC complete")
    }
}

OnRefreshCLR(*) {
    try {
        memInfo := WBHelper.GetMemoryInfo()
        UpdateCLRDisplay(memInfo)

        ; List assemblies
        asmData := WBHelper.ListAssemblies()
        lvAssemblies.Opt("-Redraw")
        lvAssemblies.Delete()
        for line in StrSplit(asmData, "`n", "`r") {
            if (line == "")
                continue
            parts := StrSplit(line, "|")
            if (parts.Length >= 5)
                lvAssemblies.Add("", parts[1], parts[2], parts[3], parts[4], parts[5])
        }
        lvAssemblies.Opt("+Redraw")
        SetStatus("CLR diagnostics refreshed — " lvAssemblies.GetCount() " assemblies loaded")
    } catch as e {
        SetStatus("CLR refresh error: " e.Message)
    }
}

OnClrSendToWrapper(*) {
    row := lvAssemblies.GetNext(0, "Focused")
    if (row == 0) {
        SetStatus("Please select an assembly first!")
        return
    }

    asmName := lvAssemblies.GetText(row, 1)
    asmLocation := lvAssemblies.GetText(row, 5)

    ; If location is not in-memory and looks like a valid file path, use it. Otherwise fallback to the assembly name.
    targetAsm := (asmLocation != "" && !InStr(asmLocation, "In-Memory") && FileExist(asmLocation)) ? asmLocation : asmName

    ; Set Wrapper Gen DLL path
    edWrapAsm.Value := targetAsm

    ; Visually switch to Wrapper Gen Tab (Tab 10)
    OnTabClick(customTabs[10])

    ; Load types
    OnWrapLoad()

    SetStatus("Loaded assembly into Wrapper Generator: " targetAsm)
}

UpdateCLRDisplay(memInfo) {
    parts := StrSplit(memInfo, "|")
    if (parts.Length >= 6) {
        lblHeapSize.Value := parts[1]
        lblGen0.Value := parts[2]
        lblGen1.Value := parts[3]
        lblGen2.Value := parts[4]
        lblAsmCount.Value := parts[5]
        rawBytesVal := parts[6]
        lblRawBytes.Value := rawBytesVal " bytes"

        ; If managed heap exceeds 5MB, trigger an auto-GC to keep memory extremely low and clean!
        try {
            rawBytesNum := Integer(rawBytesVal)
            if (rawBytesNum > 5 * 1024 * 1024) {
                CS.GC()
                ; Refresh memory statistics display after auto-GC
                memInfoAfter := WBHelper.GetMemoryInfo()
                partsAfter := StrSplit(memInfoAfter, "|")
                if (partsAfter.Length >= 6) {
                    lblHeapSize.Value := partsAfter[1]
                    lblGen0.Value := partsAfter[2]
                    lblGen1.Value := partsAfter[3]
                    lblGen2.Value := partsAfter[4]
                    lblAsmCount.Value := partsAfter[5]
                    lblRawBytes.Value := partsAfter[6] " bytes"
                    SetStatus("Auto-GC triggered (memory exceeded 5MB)")
                }
            }
        }
    }
}

OnToggleAutoRefresh(*) {
    if (chkAutoRefresh.Value) {
        SetTimer(AutoRefreshCLR, 2000)
        SetStatus("Auto-refresh enabled (every 2s)")
    } else {
        SetTimer(AutoRefreshCLR, 0)
        SetStatus("Auto-refresh disabled")
    }
}

AutoRefreshCLR() {
    try {
        memInfo := WBHelper.GetMemoryInfo()
        UpdateCLRDisplay(memInfo)
    }
}

SetStatus(msg) {
    ts := FormatTime(, "HH:mm:ss")
    lblStatus.Value := "[" ts "]  " msg
}

global g_FiltersPopup := ""
OnFiltersClick(ctrl, *) {
    global g_FiltersPopup
    if (g_FiltersPopup && WinExist(g_FiltersPopup.Hwnd)) {
        g_FiltersPopup.Destroy()
        g_FiltersPopup := ""
        return
    }

    ctrl.GetPos(&cx, &cy, &cw, &ch)
    WinGetPos(&wx, &wy, &ww, &wh, ctrl.Gui.Hwnd)

    p := Gui("+ToolWindow -Caption +Border +Owner" ctrl.Gui.Hwnd)
    p.BackColor := "12121f"
    p.SetFont("s9 c0xd0d0e0", "Segoe UI")

    types := ["Class", "Interface", "Struct", "Enum", "Delegate", "Constructor", "Method", "Property", "Field", "Event"]

    global g_FilterStates
    if (!IsSet(g_FilterStates)) {
        g_FilterStates := Map()
        for t in types
            g_FilterStates[t] := 1
    }

    y := 10
    for t in types {
        chk := p.Add("Checkbox", "x10 y" y " w120 h20", t)
        chk.Value := g_FilterStates[t]
        chk.OnEvent("Click", ((name, c, *) => g_FilterStates[name] := c.Value).Bind(t))
        y += 24
    }

    btn := p.Add("Button", "x10 y" y " w120 h26", "Apply && Close")
    btn.OnEvent("Click", (*) => (p.Destroy(), OnExploreType()))

    p.Show("x" (wx + cx) " y" (wy + cy + ch) " w140 h" (y + 36) " NoActivate")
    g_FiltersPopup := p
}

OnMessage(0x0201, OnLButtonDown)
OnLButtonDown(wParam, lParam, msg, hwnd) {
    global btnDragTarget, btnDragTargetHwnd, gUiaExplorer

    ; 1. Check direct control click
    if (IsSet(btnDragTargetHwnd) && btnDragTargetHwnd && hwnd == btnDragTargetHwnd) {
        TrackTargetDrag()
        return 0
    }

    ; 2. Check parent fall-through click
    if (IsSet(gUiaExplorer) && gUiaExplorer && hwnd == gUiaExplorer.hwnd) {
        x := lParam & 0xFFFF
        y := lParam >> 16
        if (IsSet(btnDragTarget) && btnDragTarget) {
            btnDragTarget.GetPos(&cX, &cY, &cW, &cH)
            if (x >= cX && x <= cX + cW && y >= cY && y <= cY + cH) {
                TrackTargetDrag()
                return 0
            }
        }
    }
}

OnMessage(0x0100, OnWM_KEYDOWN)
OnWM_KEYDOWN(wParam, lParam, msg, hwnd) {
    if (wParam == 8 && GetKeyState("Control", "P")) { ; VK_BACK
        try {
            ctrl := GuiCtrlFromHwnd(hwnd)
            if (!ctrl)
                ctrl := GuiCtrlFromHwnd(DllCall("GetParent", "Ptr", hwnd, "Ptr"))
            if (ctrl && (ctrl.Name == "TypeName" || ctrl.Name == "NuGetSearch")) {
                SetTimer(() => Send("^+{Left}{Backspace}"), -1)
                return 0
            }
        }
    }

    if (wParam == 13) { ; VK_RETURN
        try {
            ctrl := GuiCtrlFromHwnd(hwnd)
            if (!ctrl)
                ctrl := GuiCtrlFromHwnd(DllCall("GetParent", "Ptr", hwnd, "Ptr"))
            if (ctrl && ctrl.Name == "TypeName") {
                SetTimer(OnExploreType, -1)
                return 0
            }
            if (ctrl && ctrl.Name == "NuGetSearch") {
                SetTimer(OnNuGetSearch, -1)
                return 0
            }
        }
    }
}

OnMessage(0x0200, OnMouseMove)
OnMouseMove(wParam, lParam, msg, hwnd) {
    static hoveredHwnd := 0
    if (hwnd != hoveredHwnd) {
        if (hoveredHwnd) {
            try {
                prevCtrl := GuiCtrlFromHwnd(hoveredHwnd)
                if (prevCtrl.HasProp("isCustomButton")) {
                    prevCtrl.Opt("Background0x1f1f30 c" prevCtrl.defaultColor)
                    prevCtrl.Redraw()
                } else if (prevCtrl.HasProp("isCustomTab") && prevCtrl.tabIndex != activeTabIndex) {
                    prevCtrl.Opt("c0x8a8ab0")
                    prevCtrl.Redraw()
                }
            }
        }
        hoveredHwnd := hwnd
        try {
            currCtrl := GuiCtrlFromHwnd(hwnd)
            if (currCtrl.HasProp("isCustomButton")) {
                currCtrl.Opt("Background0x2d2d44 c0x00d4ff")
                currCtrl.Redraw()
            } else if (currCtrl.HasProp("isCustomTab") && currCtrl.tabIndex != activeTabIndex) {
                currCtrl.Opt("c0xffffff")
                currCtrl.Redraw()
            }
        }
    }
}

OnInspectMarsh(*) {
    ahkCode := edMarshAhk.Value
    if (ahkCode == "")
        return
    SetStatus("Inspecting...")
    try {
        obj := ParseAhkLiteral(ahkCode)

        if (Type(obj) == "String" && obj == Trim(ahkCode) && !RegExMatch(Trim(ahkCode), "^['`"].*['`"]$")) {
            try {
                obj := CS.Eval(ahkCode)
            } catch {
            }
        }

        tvMarsh.Opt("-Redraw")
        tvMarsh.Delete()
        BuildAhkTree(tvMarsh, 0, "Root", obj, 0)
        tvMarsh.Opt("+Redraw")
        SetStatus("Inspection complete")
    } catch as e {
        tvMarsh.Opt("-Redraw")
        tvMarsh.Delete()
        tvMarsh.Add("ERROR: " e.Message)
        tvMarsh.Add("! AHK v2 lacks an eval() function.")
        tvMarsh.Add("! Arbitrary AHK expressions cannot be parsed.")
        tvMarsh.Add("! Please use the dropdown examples or type valid C#.")
        tvMarsh.Opt("+Redraw")
        SetStatus("Inspection failed")
    }
}

BuildAhkTree(tv, parentId, name, obj, depth) {
    if (depth > 5) {
        tv.Add("... max depth", parentId)
        return
    }

    nodeText := name
    if (obj == "") {
        tv.Add(nodeText " : null", parentId)
        return
    }

    typeName := Type(obj)
    try {
        if (HasProp(obj, "Type"))
            typeName := obj.Type
    }
    nodeText .= " (" typeName ")"

    if (IsObject(obj) && !HasProp(obj, "__Enum")) {
        id := tv.Add(nodeText, parentId)
        for k, v in obj.OwnProps()
            BuildAhkTree(tv, id, k, v, depth + 1)
        tv.Modify(id, "Expand")
        return
    }

    if (IsObject(obj) && HasProp(obj, "__Enum")) {
        id := tv.Add(nodeText, parentId)
        count := -1
        try count := obj.Length
        catch {
            try count := obj.Count
        }
        if (count >= 0)
            tv.Add("Count: " count, id)

        i := 0
        try {
            for k, v in obj {
                BuildAhkTree(tv, id, "[" k "]", v, depth + 1)
                i++
                if (i > 100) {
                    tv.Add("... (truncated)", id)
                    break
                }
            }
        } catch as e {
            tv.Add("! Enum error: " e.Message, id)
        }
        tv.Modify(id, "Expand")
        return
    }

    tv.Add(nodeText " = " String(obj), parentId)
}

OnPredictOverload(*) {
    tName := edPredType.Value
    mName := edPredMethod.Value
    argsRaw := edPredArgs.Value

    if (tName == "" || mName == "")
        return

    SetStatus("Predicting overload...")
    try {
        argsObj := []
        if (RegExMatch(argsRaw, "^\[(.*)\]$", &m)) {
            parts := StrSplit(m[1], ",")
            for part in parts {
                part := Trim(part)
                if (RegExMatch(part, '^"(.*)"$', &strMatch))
                    argsObj.Push(strMatch[1])
                else if (IsNumber(part))
                    argsObj.Push(part + 0)
                else if (part == "true" || part == "false")
                    argsObj.Push(part == "true")
            }
        } else {
            argsObj := [argsRaw] ; fallback
        }

        csArgs := ComObjArray(0xC, argsObj.Length)
        for i, val in argsObj
            csArgs[i - 1] := val

        result := WBHelper.PredictOverload(tName, mName, csArgs)
        edPredResult.Value := result
        SetStatus("Overload prediction complete")
    } catch as e {
        edPredResult.Value := "ERROR: " e.Message
        SetStatus("Overload prediction failed")
    }
}

OnWrapBrowse(*) {
    selectedFile := FileSelect(1, , "Select .NET Assembly DLL", "DLL Files (*.dll)")
    if (selectedFile != "") {
        edWrapAsm.Value := selectedFile
        OnWrapLoad()
    }
}

global g_WrapClassData := Map()

OnWrapLoad(*) {
    path := edWrapAsm.Value
    if (path == "")
        return
    SetStatus("Loading types from " path "...")
    lvWrapTypes.Opt("-Redraw")
    lvWrapTypes.Delete()
    g_WrapClassData.Clear()

    try {
        typesStr := WBHelper.GetAssemblyTypes(path)
        if (SubStr(typesStr, 1, 6) == "ERROR:") {
            SetStatus(typesStr)
            lvWrapTypes.Opt("+Redraw")
            return
        }

        resolvedClass := ""
        lines := StrSplit(typesStr, "`n", "`r")
        firstLine := lines[1]

        startIdx := 1
        if (SubStr(firstLine, 1, 12) == "RESOLVED_ASM") {
            parts := StrSplit(firstLine, "|")
            actualAsm := parts[2]
            resolvedClass := parts[3]
            if (actualAsm != "") {
                edWrapAsm.Value := actualAsm
            }
            startIdx := 2
        }

        for i, line in lines {
            if (i < startIdx || line == "")
                continue
            parts := StrSplit(line, "|")
            if (parts.Length >= 3) {
                className := parts[1]
                smCount := parts[2] == "" ? 0 : StrSplit(parts[2], ",").Length
                imCount := parts[3] == "" ? 0 : StrSplit(parts[3], ",").Length
                lvWrapTypes.Add("", className, (smCount + imCount))
                g_WrapClassData[className] := { sm: parts[2], im: parts[3] }
            }
        }

        if (resolvedClass != "") {
            foundRow := 0
            Loop lvWrapTypes.GetCount() {
                if (lvWrapTypes.GetText(A_Index, 1) == resolvedClass) {
                    lvWrapTypes.Modify(A_Index, "Check Select Focus")
                    foundRow := A_Index
                    break
                }
            }
            if (foundRow > 0) {
                OnWrapGen()
                SetStatus("Auto-resolved " path " to assembly " edWrapAsm.Value " and auto-generated wrapper!")
            } else {
                SetStatus("Loaded " lvWrapTypes.GetCount() " classes from " edWrapAsm.Value)
            }
        } else {
            SetStatus("Loaded " lvWrapTypes.GetCount() " classes from " edWrapAsm.Value)
        }
    } catch as e {
        SetStatus("Failed to load types: " e.Message)
    }
    lvWrapTypes.Opt("+Redraw")
}

OnWrapGen(*) {
    SetStatus("Generating wrappers...")
    count := lvWrapTypes.GetCount()
    selected := []
    Loop count {
        if (SendMessage(0x102C, A_Index - 1, 0xF000, lvWrapTypes.Hwnd) & 0x2000) ; LVM_GETITEMSTATE, LVIS_STATEIMAGEMASK
            selected.Push(lvWrapTypes.GetText(A_Index, 1))
    }

    if (selected.Length == 0) {
        SetStatus("No classes selected")
        return
    }

    out := "; Auto-Generated AHK# Wrapper for " edWrapAsm.Value "`n"
    out .= "; Generated on " FormatTime(, "yyyy-MM-dd HH:mm") "`n`n"
    out .= "#Include <ahk#>`n`n"

    def := "/**`n * Auto-Generated AHK# IntelliSense Definition for " edWrapAsm.Value "`n"
    def .= " * Generated on " FormatTime(, "yyyy-MM-dd HH:mm") "`n */`n`n"

    for cls in selected {
        shortName := RegExReplace(cls, ".*\.", "")

        methods := Map()
        staticMethods := Map()
        props := Map()
        staticProps := Map()
        events := Map()

        ; Extract full metadata using ExploreType
        metaStr := WBHelper.ExploreType(cls, 0)
        Loop Parse, metaStr, "`n", "`r" {
            parts := StrSplit(A_LoopField, "|")
            if (parts.Length < 3)
                continue

            kind := parts[1]
            name := parts[2]
            sig := parts[3]
            isStatic := (parts.Length >= 4 && parts[4] == "Static")

            if (kind == "Method") {
                mapObj := isStatic ? staticMethods : methods
                if !mapObj.Has(name)
                    mapObj[name] := []
                mapObj[name].Push(sig)
            } else if (kind == "Property") {
                mapObj := isStatic ? staticProps : props
                mapObj[name] := sig
            } else if (kind == "Event") {
                events[name] := sig
            }
        }

        ; 1. Generate Runtime Wrapper
        out .= "class " shortName " {`n"

        if (staticProps.Count > 0 || staticMethods.Count > 0) {
            for mName, sigs in staticMethods
                out .= "    static " mName "(args*) => CS.Import(`"" cls "`")." mName "(args*)`n"
            for pName, sig in staticProps {
                out .= "    static " pName " {`n"
                if InStr(sig, "get")
                    out .= "        get => CS.Import(`"" cls "`")." pName "`n"
                if InStr(sig, "set")
                    out .= "        set => CS.Import(`"" cls "`")." pName " := value`n"
                out .= "    }`n"
            }
            out .= "`n"
        }

        out .= "    __New(args*) {`n"
        out .= "        this._obj := CS(`"" cls "`")(args*)`n"
        out .= "    }`n`n"

        for mName, sigs in methods
            out .= "    " mName "(args*) => this._obj." mName "(args*)`n"

        for pName, sig in props {
            out .= "    " pName " {`n"
            if InStr(sig, "get")
                out .= "        get => this._obj." pName "`n"
            if InStr(sig, "set")
                out .= "        set => this._obj." pName " := value`n"
            out .= "    }`n"
        }

        for eName, sig in events {
            delType := sig
            out .= "    " eName "Event(callback) {`n"
            out .= "        this._obj." eName " := CS.Delegate(callback, `"" delType "`")`n"
            out .= "    }`n"
        }
        out .= "}`n`n"

        ; 2. Generate IntelliSense (.d.ahk)
        def .= "/**`n * @class " shortName "`n */`n"
        def .= "class " shortName " {`n"

        for mName, sigs in staticMethods {
            def .= ParseMethodJSDoc(sigs)
            def .= '    static ' mName '(args*) => ""`n'
        }
        for pName, sig in staticProps {
            def .= "    /** @type {Any} */`n"
            def .= '    static ' pName ' {`n        get => ""`n        set => ""`n    }`n'
        }
        def .= "    __New(args*) {}`n"

        for mName, sigs in methods {
            def .= ParseMethodJSDoc(sigs)
            def .= '    ' mName '(args*) => ""`n'
        }
        for pName, sig in props {
            def .= "    /** @type {Any} */`n"
            def .= '    ' pName ' {`n        get => ""`n        set => ""`n    }`n'
        }
        for eName, sig in events {
            def .= "    /**`n     * Binds a callback to the " eName " event.`n     * @param {Func} callback`n     */`n"
            def .= '    ' eName 'Event(callback) => ""`n'
        }
        def .= "}`n`n"
    }

    edWrapOut.Value := out
    edWrapDef.Value := def
    SetStatus("Wrappers and IntelliSense definitions generated successfully")
}

ParseMethodJSDoc(sigs) {
    doc := "    /**`n"
    if (sigs.Length > 1)
        doc .= "     * Overloads: " sigs.Length "`n"

    bestSig := sigs[1]
    for s in sigs {
        if StrLen(s) > StrLen(bestSig)
            bestSig := s
    }

    if RegExMatch(bestSig, "\((.*)\)\s*->\s*(.*)", &match) {
        prmStr := match[1]
        retStr := match[2]

        if (Trim(prmStr) != "") {
            Loop Parse, prmStr, "," {
                part := Trim(A_LoopField)
                if RegExMatch(part, "^(.*?)\s+(.*)$", &pMatch)
                    doc .= "     * @param {" pMatch[1] "} " pMatch[2] "`n"
                else
                    doc .= "     * @param {Any} " part "`n"
            }
        }
        doc .= "     * @returns {" retStr "}`n"
    }
    doc .= "     */`n"
    return doc
}

OnWrapTest(*) {
    code := edWrapOut.Value
    if (code == "")
        return
    OnTabClick(customTabs[2])
    ddlMode.Choose(3) ; AHK Script

    firstClass := "Class"
    if (g_WrapClassData.Count > 0) {
        for k in g_WrapClassData {
            firstClass := k
            break
        }
    }

    ; Strip #Include <ahk#> and replace with a demo usage
    code := StrReplace(code, "#Include <ahk#>`n`n", "")
    classNameMatch := RegExReplace(firstClass, ".*\.([^.]+)$", "$1")
    demo := "; --- Write your test code here ---`n; instance := " classNameMatch "()`n`n"

    edCode.Value := demo . code
    SetStatus("Copied wrapper to Scratchpad")
}

OnWrapSave(*) {
    code := edWrapOut.Value
    if (code == "")
        return
    path := FileSelect("S16", "MyWrapper.ahk", "Save AHK# Wrapper", "AHK Scripts (*.ahk)")
    if (path != "") {
        if FileExist(path)
            FileDelete(path)
        FileAppend(code, path)
        SetStatus("Saved to " path)
    }
}

OnDefSave(*) {
    code := edWrapDef.Value
    if (code == "")
        return
    path := FileSelect("S16", "MyWrapper.d.ahk", "Save IntelliSense Def", "AHK Definition (*.d.ahk)")
    if (path != "") {
        if FileExist(path)
            FileDelete(path)
        FileAppend(code, path)
        SetStatus("Saved definition to " path)
    }
}

ParseAhkLiteral(str) {
    str := Trim(str, " `t`r`n")
    if (str == "")
        return ""
    if (str == "true")
        return true
    if (str == "false")
        return false
    if (str == "null")
        return ""
    if (IsNumber(str)) {
        if (!InStr(str, ".") && !InStr(str, "e") && !InStr(str, "E")) {
            cleanStr := LTrim(str, "+")
            isNeg := SubStr(cleanStr, 1, 1) == "-"
            absStr := LTrim(isNeg ? SubStr(cleanStr, 2) : cleanStr, "0")
            if (absStr == "")
                absStr := "0"
            if (StrLen(absStr) > 19 || (StrLen(absStr) == 19 && StrCompare(absStr, isNeg ? "9223372036854775808" : "9223372036854775807") > 0))
                return Float(str)
            return Integer(str)
        }
        return Float(str)
    }

    if (RegExMatch(str, '^(?s)"(.*)"$', &m) || RegExMatch(str, "^(?s)'(.*)'$", &m))
        return m[1]

    if (RegExMatch(str, "^(?is)Buffer\((.*)\)$", &m)) {
        size := ParseAhkLiteral(m[1])
        if (IsNumber(size))
            return Buffer(size)
        return Buffer(0)
    }

    if (SubStr(str, 1, 1) == "[" && SubStr(str, -1) == "]") {
        inner := SubStr(str, 2, StrLen(str) - 2)
        arr := []
        if (Trim(inner, " `t`r`n") != "") {
            for part in SplitAhkArgs(inner)
                arr.Push(ParseAhkLiteral(part))
        }
        return arr
    }

    if (SubStr(str, 1, 1) == "{" && SubStr(str, -1) == "}") {
        inner := SubStr(str, 2, StrLen(str) - 2)
        obj := {}
        if (Trim(inner, " `t`r`n") != "") {
            for part in SplitAhkArgs(inner) {
                if (RegExMatch(part, "^(?s)\s*([a-zA-Z0-9_]+|`"[^`"]*`"|'[^']*')\s*:\s*(.*)$", &m)) {
                    key := Trim(m[1], " `"'`t`r`n")
                    val := ParseAhkLiteral(m[2])
                    obj.%key% := val
                }
            }
        }
        return obj
    }

    if (RegExMatch(str, "^(?s)[a-zA-Z0-9_]+\((.*)\)$", &m)) {
        inner := m[1]
        mapObj := Map()
        if (Trim(inner, " `t`r`n") != "") {
            args := SplitAhkArgs(inner)
            i := 1
            while (i <= args.Length) {
                if (i + 1 <= args.Length) {
                    key := ParseAhkLiteral(args[i])
                    val := ParseAhkLiteral(args[i + 1])
                    mapObj[key] := val
                    i += 2
                } else {
                    mapObj[ParseAhkLiteral(args[i])] := ""
                    i++
                }
            }
        }
        return mapObj
    }

    return str
}

SplitAhkArgs(str) {
    args := []
    depth := 0
    inStr := false
    strChar := ""
    current := ""

    Loop Parse, str {
        char := A_LoopField
        if (inStr) {
            current .= char
            if (char == strChar)
                inStr := false
            continue
        }
        if (char == '"' || char == "'") {
            inStr := true
            strChar := char
            current .= char
            continue
        }
        if (char == "[" || char == "{" || char == "(") {
            depth++
            current .= char
            continue
        }
        if (char == "]" || char == "}" || char == ")") {
            depth--
            current .= char
            continue
        }
        if (char == "," && depth == 0) {
            args.Push(Trim(current, " `t`r`n"))
            current := ""
            continue
        }
        current .= char
    }
    if (Trim(current, " `t`r`n") != "")
        args.Push(Trim(current, " `t`r`n"))
    return args
}