; ═══════════════════════════════════════════════════════════════════════════════
; MAIN GUI CONSTRUCTION
; ═══════════════════════════════════════════════════════════════════════════════

WB_InitDarkMode()

; The workbench reports compile errors in its own panes, so suppress the library's modal error window
try CS.Config.ShowErrorGui := false

; Resize support: controls registered with WB_Anchor follow the window (see OnMainSize)
global g_anchors := []
global g_baseW := 0             ; client size the layout was designed for (pixels)
global g_baseH := 0
global g_lastSize := ""         ; last normal (not maximized) client size — saved on exit
global g_runBusy := false       ; a scratchpad run is in progress
global g_runs := []             ; AHK Script processes started from the scratchpad and still running
global g_historyMax := 15       ; run history length kept in workbench.ini
global g_userSnipHeader := false ; "My Snippets" separator already added to the snippet list
global g_nugetReqId := 0        ; id of the newest NuGet search — older (stale) responses are ignored

g := Gui("+Resize", "AHK# Developer Studio")
g.Opt("+MinSize900x560")
WB_DarkWindow(g)
g.BackColor := "0x0f0f1a"
g.MarginX := 8
g.MarginY := 8

; Register a control so it follows window resizes.
; spec: any of  x y w h  optionally followed by a fraction of the size change (default 1),
;       e.g. "w h" grows with the window, "y.5" moves half as far as the window grows.
WB_Anchor(ctrl, spec) {
    a := {ctrl: ctrl, fx: 0, fy: 0, fw: 0, fh: 0, x0: 0, y0: 0, w0: 0, h0: 0}
    pos := 1
    while RegExMatch(spec, "i)([xywh])(\d*\.?\d*)", &m, pos) {
        a.%"f" . StrLower(m[1])% := (m[2] == "") ? 1 : Number(m[2])
        pos := m.Pos + Max(m.Len, 1)
    }
    g_anchors.Push(a)
    return ctrl
}

WB_CaptureAnchors() {
    for a in g_anchors {
        a.ctrl.GetPos(&x, &y, &w, &h)
        a.x0 := x
        a.y0 := y
        a.w0 := w
        a.h0 := h
    }
}

OnMainSize(guiObj, minMax, width, height) {
    global g_lastSize
    if (minMax == -1 || g_baseW == 0)
        return
    if (minMax == 0)
        g_lastSize := [width, height]
    dw := width - g_baseW
    dh := height - g_baseH
    for a in g_anchors {
        try a.ctrl.Move(Round(a.x0 + a.fx * dw), Round(a.y0 + a.fy * dh)
            , Max(4, Round(a.w0 + a.fw * dw)), Max(4, Round(a.h0 + a.fh * dh)))
    }
    SetTimer(WB_RedrawMain, -80)    ; debounced: transparent labels need a parent repaint
}

WB_RedrawMain() {
    DllCall("RedrawWindow", "ptr", g.Hwnd, "ptr", 0, "ptr", 0, "uint", 0x185)
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
WB_Anchor(g.Add("Text", "x10 y38 w1120 h680 Background0x12121f +Border"), "w h")

; ── Premium Tab Button Custom Navigation ──────────────────────────────────────
customTabs := []
tabNames := ["Examples", "Scratchpad", "Type Explorer", "NuGet", "Precompiler", "Cache", "CLR Monitor", "Marshalling", "Overloads", "Wrapper Gen"]
global activeTabIndex := 1

; Draw a beautiful background bar for the tabs
WB_Anchor(g.Add("Text", "x10 y5 w1120 h28 Background0x1a1a2e +Border"), "w")

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
    if (activeTabIndex == TAB_CACHE)
        OnCacheRefresh()
    else if (activeTabIndex == TAB_CLR)
        OnRefreshCLR()
    else if (activeTabIndex == TAB_NUGET)
        OnRefreshInstalled()
}

; ═══════════════════════════════════════════════════════════════════════════════
; TAB 2 — INTERACTIVE SCRATCHPAD
; ═══════════════════════════════════════════════════════════════════════════════
tabs.UseTab(TAB_SCRATCH)

g.SetFont("s9 c0x00d4ff", "Segoe UI")
g.Add("Text", "x20 y50 w55 h22 BackgroundTrans", "Mode:")
g.SetFont("s9 c0xd0d0e0", "Segoe UI")
ddlMode := g.Add("DropDownList", "x75 y48 w130 Background0x1a1a2e", ["C# Expression", "C# Class", "AHK Script"])
ddlMode.Choose(MODE_EXPR)

g.SetFont("s9 c0x00d4ff", "Segoe UI")
g.Add("Text", "x215 y50 w60 h22 BackgroundTrans", "Snippet:")
g.SetFont("s9 c0xd0d0e0", "Segoe UI")
ddlSnippet := g.Add("DropDownList", "x275 y48 w215 Background0x1a1a2e", snippetNames)

btnLoadSnippet := AddButton(g, "x498 y47 w96 h24", "Load Snippet")
btnLoadSnippet.OnEvent("Click", OnLoadSnippet)

btnSaveSnippet := AddButton(g, "x602 y47 w96 h24", "Save Snippet")
btnSaveSnippet.OnEvent("Click", OnSaveSnippet)

btnHistory := AddButton(g, "x706 y47 w80 h24", "History ▾")
btnHistory.OnEvent("Click", OnHistoryClick)

g.SetFont("s9 c0x00d4ff", "Segoe UI")
g.Add("Text", "x800 y50 w60 h22 BackgroundTrans", "C# Ver:")
g.SetFont("s9 c0xd0d0e0", "Segoe UI")
ddlScratchVer := g.Add("DropDownList", "x862 y48 w110 Background0x1a1a2e", ["4.0 (default)", "5.0", "6.0", "7.0", "7.3"])
ddlScratchVer.Choose(1)

; Code Editor
g.SetFont("s9 c0x00d4ff", "Segoe UI")
g.Add("Text", "x20 y78 w200 h18 BackgroundTrans", "◆  Code Input")
g.SetFont("s10 c0xd4d4e8", "Cascadia Code")
edCode := g.Add("Edit", "x20 y98 w1090 h290 Multi WantTab VScroll HScroll Background0x12121f +Border -E0x200", "")

; Button Row
g.SetFont("s10 c0xd0d0e0", "Segoe UI")
btnRun := AddButton(g, "x20 y396 w100 h30", "▸ Run")
btnRun.OnEvent("Click", OnRunCode)

btnStop := AddButton(g, "x128 y396 w90 h30", "■ Stop")
btnStop.OnEvent("Click", OnStopScripts)

btnClearOutput := AddButton(g, "x226 y396 w110 h30", "Clear Output")
btnClearOutput.OnEvent("Click", (*) => edOutput.Value := "")

btnUiaExplorer := AddButton(g, "x344 y396 w130 h30", "▸ UIA Explorer")
btnUiaExplorer.OnEvent("Click", LaunchUiaExplorer)

btnSendToPrecomp := AddButton(g, "x482 y396 w160 h30", "Send to Precompiler")
btnSendToPrecomp.OnEvent("Click", OnSendToPrecompiler)

btnExportModule := AddButton(g, "x650 y396 w130 h30", "Export .ahk")
btnExportModule.OnEvent("Click", OnExportModule)

g.SetFont("s9 c0x6a6a8a", "Segoe UI")
lblRunStatus := g.Add("Text", "x790 y402 w320 h20 BackgroundTrans", "Ready")

g.SetFont("s8 c0x4a5568", "Segoe UI")
lblScratchTip := g.Add("Text", "x20 y428 w1080 h16 BackgroundTrans", "💡 Ctrl+Enter or F5 runs the code.  In C# Class mode add  // NuGet: Package [Version]  (repeatable) or  // Reference: X.dll  to pull in packages and assemblies.")

; Output Area
g.SetFont("s9 c0xa78bfa", "Segoe UI")
lblOutputHdr := g.Add("Text", "x20 y448 w200 h18 BackgroundTrans", "◆  Output")
g.SetFont("s10 c0x4ade80", "Cascadia Code")
edOutput := g.Add("Edit", "x20 y468 w1090 h240 Multi ReadOnly VScroll HScroll Background0x0d0d18 +Border -E0x200", "")
SendMessage(0x00C5, 0, 0, edOutput)  ; EM_LIMITTEXT: lift the default 32K cap — script output can be long

; ═══════════════════════════════════════════════════════════════════════════════
; TAB 3 — .NET TYPE EXPLORER
; ═══════════════════════════════════════════════════════════════════════════════
tabs.UseTab(TAB_TYPES)

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
WB_Anchor(g.Add("Text", "x20 y546 w200 h18 BackgroundTrans", "◆  Generated AHK# Snippet"), "y")
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
WB_Anchor(g.Add("Text", "x20 y682 BackgroundTrans", "Quick:"), "y")
For i, qtype in ["System.Math", "System.IO.File", "System.IO.Path", "System.String", "System.DateTime", "System.Convert", "System.Environment", "System.Text.StringBuilder", "System.Net.WebClient"] {
    if (i > 1) {
        g.SetFont("c0x6a6a8a")
        WB_Anchor(g.Add("Text", "x+8 y682 BackgroundTrans", "|"), "y")
    }
    g.SetFont("c0x00d4ff")
    lbl := WB_Anchor(g.Add("Text", "x+8 y682 BackgroundTrans", qtype), "y")
    lbl.OnEvent("Click", ((typeStr, *) => (edTypeName.Text := typeStr, OnExploreType())).Bind(qtype))
}

; ═══════════════════════════════════════════════════════════════════════════════
; TAB 4 — NUGET PACKAGE MANAGER
; ═══════════════════════════════════════════════════════════════════════════════
tabs.UseTab(TAB_NUGET)

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
WB_Anchor(g.Add("Text", "x20 y364 w200 h18 BackgroundTrans", "◆  Installed Packages"), "y.4")

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
tabs.UseTab(TAB_PRECOMP)

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
WB_Anchor(g.Add("Text", "x20 y436 w90 h22 BackgroundTrans", "References:"), "y.5")
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
WB_Anchor(g.Add("Text", "x20 y504 w200 h18 BackgroundTrans", "◆  Compilation Output"), "y.5")
g.SetFont("s10 c0x4ade80", "Cascadia Code")
edPrecompOut := g.Add("Edit", "x20 y524 w1090 h180 Multi ReadOnly VScroll Background0x0d0d18 +Border -E0x200", "")

global g_precompAsmId := ""

; ═══════════════════════════════════════════════════════════════════════════════
; TAB 6 — CACHE MANAGER
; ═══════════════════════════════════════════════════════════════════════════════
tabs.UseTab(TAB_CACHE)

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
btnCacheRefresh := AddButton(g, "x20 y662 w110 h30", "Refresh")
btnCacheRefresh.OnEvent("Click", OnCacheRefresh)

btnCacheDelete := AddButton(g, "x140 y662 w150 h30", "Delete Selected")
btnCacheDelete.OnEvent("Click", OnCacheDelete)

btnCacheCleanUnused := AddButton(g, "x300 y662 w150 h30", "Clean Unused")
btnCacheCleanUnused.OnEvent("Click", OnCacheCleanUnused)

g.SetFont("s10 c0xf87171", "Segoe UI")
btnCacheClearAll := AddButton(g, "x460 y662 w150 h30", "Clear ALL Cache")
btnCacheClearAll.OnEvent("Click", OnCacheClearAll)

g.SetFont("s9 c0x6a6a8a", "Segoe UI")
WB_Anchor(g.Add("Text", "x625 y667 w485 h22 BackgroundTrans",
    "Note: cache files are only deleted by Clean Unused / Clear ALL — never by Force GC."), "y")

; ═══════════════════════════════════════════════════════════════════════════════
; TAB 7 — CLR LIVE DIAGNOSTICS
; ═══════════════════════════════════════════════════════════════════════════════
tabs.UseTab(TAB_CLR)

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
tabs.UseTab(TAB_MARSH)

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
WB_Anchor(g.Add("Text", "x560 y86 w400 h18 BackgroundTrans", "◆  .NET Resolution (Interactive TreeView)"), "x.5")

g.SetFont("s10 c0xd4d4e8", "Cascadia Code")
global edMarshAhk := g.Add("Edit", "x20 y106 w520 h600 Multi WantTab VScroll HScroll Background0x12121f +Border -E0x200", '[1, 2, "three"]')

g.SetFont("s10 c0x4ade80", "Cascadia Code")
global tvMarsh := g.Add("TreeView", "x560 y106 w550 h600 Background0x12121f c0x4ade80 +Border -E0x200")

cbMarshExample.OnEvent("Change", (*) => edMarshAhk.Value := cbMarshExample.Text)

; ═══════════════════════════════════════════════════════════════════════════════
; TAB 9 — OVERLOAD PREDICTOR
; ═══════════════════════════════════════════════════════════════════════════════
tabs.UseTab(TAB_OVERLOADS)

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
g.Add("Text", "x20 y78 w800 h18 BackgroundTrans", '◆  Arguments — an AHK literal list, e.g.  ["123", 16]   or   [1, "two", true, [3, 4]]')
g.SetFont("s10 c0xd4d4e8", "Cascadia Code")
global edPredArgs := g.Add("Edit", "x20 y98 w1090 h80 Multi WantTab Background0x12121f +Border -E0x200", '["123", 16]')

g.SetFont("s9 c0xa78bfa", "Segoe UI")
g.Add("Text", "x20 y186 w400 h18 BackgroundTrans", "◆  Selected C# Overload")
g.SetFont("s10 c0x4ade80", "Cascadia Code")
global edPredResult := g.Add("Edit", "x20 y206 w1090 h500 Multi ReadOnly Background0x0d0d18 +Border -E0x200", "")

; ═══════════════════════════════════════════════════════════════════════════════
; TAB 10 — VISUAL WRAPPER AUTO-GENERATOR
; ═══════════════════════════════════════════════════════════════════════════════
tabs.UseTab(TAB_WRAPPER)

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
WB_Anchor(g.Add("Text", "x840 y78 w200 h18 BackgroundTrans", "◆  IntelliSense Def (.d.ahk)"), "x.5")

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
tabs.UseTab(TAB_EXAMPLES)

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
WB_Anchor(g.Add("Text", "x20 y570 w360 h80 BackgroundTrans", "💡 Click any example in the scrollable catalogue on the left to see details and raw source code preview.`n`nClick 'Run' to execute in a standalone process."), "y")

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

; ── Resize behaviour ──────────────────────────────────────────────────────────
; Extra window height/width is shared as described per control (see WB_Anchor).
; Examples
WB_Anchor(lvExamples, "h")
WB_Anchor(lblExMode, "x")
WB_Anchor(edExDesc, "w")
WB_Anchor(edExCode, "w h")
WB_Anchor(btnExRun, "y w")
; Scratchpad: the editor and the output pane share the extra height
WB_Anchor(edCode, "w h.5")
for ac in [btnRun, btnStop, btnClearOutput, btnUiaExplorer, btnSendToPrecomp, btnExportModule, lblRunStatus, lblScratchTip, lblOutputHdr]
    WB_Anchor(ac, "y.5")
WB_Anchor(edOutput, "w y.5 h.5")
; Type Explorer
WB_Anchor(lvTypes, "w h")
for ac in [btnGenSnippet, btnCopySnippet, btnSendToWrap]
    WB_Anchor(ac, "y")
WB_Anchor(edSnippet, "w y")
; NuGet
WB_Anchor(lvNuGetResults, "w h.4")
for ac in [btnNuGetInstall, lblInstallStatus, btnRefreshPkgs, btnNuGetSendToWrap, btnNuGetRemove]
    WB_Anchor(ac, "y.4")
WB_Anchor(lvInstalled, "w y.4 h.6")
; Precompiler
WB_Anchor(edPrecompCode, "w h.5")
WB_Anchor(edPrecompRefs, "w y.5")
for ac in [btnCompile, btnExportDLL, btnSendSnippetToScratch]
    WB_Anchor(ac, "y.5")
WB_Anchor(edPrecompOut, "w y.5 h.5")
; Cache
WB_Anchor(lvCache, "w h")
for ac in [btnCacheRefresh, btnCacheDelete, btnCacheCleanUnused, btnCacheClearAll]
    WB_Anchor(ac, "y")
; CLR Monitor
WB_Anchor(lvAssemblies, "w h")
; Marshalling
WB_Anchor(edMarshAhk, "w.5 h")
WB_Anchor(tvMarsh, "x.5 w.5 h")
; Overloads
WB_Anchor(btnPredict, "x")
WB_Anchor(edPredArgs, "w")
WB_Anchor(edPredResult, "w h")
; Wrapper Gen
WB_Anchor(lvWrapTypes, "h")
WB_Anchor(btnWrapGen, "y.5")
WB_Anchor(edWrapOut, "w.5 h")
WB_Anchor(edWrapDef, "x.5 w.5 h")
for ac in [btnWrapTest, btnWrapSave]
    WB_Anchor(ac, "y")
WB_Anchor(btnDefSave, "x.5 w.5 y")
; Status bar
WB_Anchor(lblStatus, "y w")

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

; Force dark mode for all controls (headers, scrollbars, dropdowns) — shared helper
WB_DarkenAll(g, tabs)

; Hook to color ComboBox/DropDownList popup menus dark
OnMessage(0x0134, WM_CTLCOLORLISTBOX)
WM_CTLCOLORLISTBOX(wParam, lParam, msg, hwnd) {
    DllCall("SetTextColor", "ptr", wParam, "uint", 0xE0D0D0) ; Light text
    DllCall("SetBkColor", "ptr", wParam, "uint", 0x2E1A1A)   ; Dark background
    static brush := DllCall("CreateSolidBrush", "uint", 0x2E1A1A, "ptr")
    return brush
}

; ── Restore saved settings, register hotkeys, show ────────────────────────────
WB_LoadUserSnippets()
WB_LoadSettings()

; Ctrl+Enter / F5 run the active tab's code (only while the studio window is active)
HotIf((*) => WinActive("ahk_id " g.Hwnd))
Hotkey("^Enter", OnRunHotkey)
Hotkey("F5", OnRunHotkey)
HotIf()

; The layout is designed for a 1140x748 client area at 96 DPI. Anchors work relative to that size in
; real pixels, while the window itself is sized to fit the screen — so nothing overflows at 125-200% DPI.
dpiScale := A_ScreenDPI / 96
g_baseW := DllCall("MulDiv", "int", 1140, "int", A_ScreenDPI, "int", 96)
g_baseH := DllCall("MulDiv", "int", 748, "int", A_ScreenDPI, "int", 96)
WB_CaptureAnchors()

maxW := Floor(A_ScreenWidth * 0.95 / dpiScale)
maxH := Floor(A_ScreenHeight * 0.85 / dpiScale)
winW := Min(1140, maxW)
winH := Min(748, maxH)
try {
    savedW := Integer(IniRead(WB_IniPath(), "Window", "Width", 0))
    savedH := Integer(IniRead(WB_IniPath(), "Window", "Height", 0))
    if (savedW >= 900 && savedH >= 560) {
        winW := Min(savedW, maxW)
        winH := Min(savedH, maxH)
    }
}

g.OnEvent("Size", OnMainSize)
g.OnEvent("Close", WB_OnClose)
g.Show("w" winW " h" winH " Center")
g.GetClientPos(, , &clientW, &clientH)
OnMainSize(g, 0, clientW, clientH)      ; apply the layout even if Windows sent no size message
try WBSplash.Close()

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
        SplitPath(ex.path, , &exDir)
        Run('"' A_AhkPath '" "' ex.path '"', exDir)
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
        ddlMode.Choose(MODE_EXPR)
    else if (info.mode == "C# Class")
        ddlMode.Choose(MODE_CLASS)
    else
        ddlMode.Choose(MODE_AHK)

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
    OnTabClick(customTabs[TAB_PRECOMP])
    SetStatus("Transferred C# code to Precompiler")
}

OnRunCode(*) {
    global g_runBusy
    if (g_runBusy) {
        SetStatus("A run is already in progress")
        return
    }
    code := edCode.Value
    if (Trim(code) == "") {
        AppendOutput("⚠ No code to run.")
        return
    }

    mode := ddlMode.Text
    g_runBusy := true
    try {
        WB_HistoryPush(mode, code)
        RunScratch(code, mode)
    } finally {
        g_runBusy := false
    }
}

; F5 / Ctrl+Enter — runs whatever the active tab runs
OnRunHotkey(*) {
    if (activeTabIndex == TAB_SCRATCH)
        OnRunCode()
    else if (activeTabIndex == TAB_PRECOMP)
        OnPrecompile()
    else if (activeTabIndex == TAB_EXAMPLES)
        OnExRunClick()
}

RunScratch(code, mode) {
    startTick := A_TickCount
    lblRunStatus.Value := "Running..."
    WB_Repaint()        ; compiling blocks the UI — make "Running..." visible first

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
    } else if (mode == "C# Class") {
        RunScratchClass(code, startTick)
    } else if (mode == "AHK Script") {
        RunScratchAhk(code)
    }
}

RunScratchClass(code, startTick) {
    offset := 0
    try {
        refs := WB_CollectRefs(code, AppendOutput)
        csVer := WB_VersionValue(ddlScratchVer.Text)

        ; Deterministic class name: identical code compiles once and is then served from the cache
        className := "__WB_" WB_Hash(code "|" refs "|" csVer)
        info := WB_BuildClassSource(code, className)
        offset := info.offset

        bridge := _AhkSharpEngine.Boot()
        if (csVer == "")
            asmId := bridge.CompileModule(info.src, refs)
        else
            asmId := bridge.CompileModuleVersioned(info.src, refs, csVer)
        result := bridge.InvokeModule(asmId, info.className, info.method, "")

        elapsed := A_TickCount - startTick
        AppendOutput("═══ C# Class ═══  [" elapsed "ms]  (" info.className "." info.method ")")
        AppendOutput("→ " (IsObject(result) ? String(result) : result))
        lblRunStatus.Value := "Compiled and executed in " elapsed "ms"
    } catch as e {
        elapsed := A_TickCount - startTick
        AppendOutput("═══ C# Class ERROR ═══  [" elapsed "ms]")
        AppendOutput("✗ " WB_RemapCompilerLines(e.Message, offset))
        lblRunStatus.Value := "Compilation/execution error"
    }
}

RunScratchAhk(code) {
    try {
        job := WB_StartAhkScript(code)
        AppendOutput("═══ AHK Script Started ═══  [PID " job.pid "]"
            . (job.captured ? "" : "  (output capture unavailable)"))
        lblRunStatus.Value := "Script running (PID " job.pid ")"
    } catch as e {
        AppendOutput("═══ AHK Script ERROR ═══")
        AppendOutput("✗ " e.Message)
        lblRunStatus.Value := "Launch error"
    }
}

; ── C# helpers shared by the scratchpad and the precompiler ───────────────────

; "4.0 (default)" -> "" (no Roslyn); "7.3" -> "7.3"
WB_VersionValue(text) {
    return (text == "" || text == "4.0 (default)") ? "" : text
}

WB_JoinRefs(a, b) {
    if (a == "")
        return b
    if (b == "")
        return a
    return a ";" b
}

; Blank a piece of source (comments, string contents ...) but keep its length and its line breaks
WB_Blank(s) {
    return RegExReplace(s, "[^\r\n]", " ")
}

; // NuGet: Package [Version]  (repeatable; ids may contain - and _; versions may be pre-release)
; // Reference: A.dll;B.dll    (repeatable)
WB_ParseDirectives(code) {
    d := {nuget: [], refs: []}
    pos := 1
    while RegExMatch(code, "im)^[ \t]*//[ \t]*NuGet:[ \t]*([\w.\-]+)(?:[ \t]+(\d[\w.\-+]*))?", &m, pos) {
        d.nuget.Push({id: m[1], ver: m[2]})
        pos := m.Pos + Max(m.Len, 1)
    }
    pos := 1
    while RegExMatch(code, "im)^[ \t]*//[ \t]*References?:[ \t]*(.+)", &m, pos) {
        d.refs.Push(Trim(m[1], " `t`r`n"))
        pos := m.Pos + Max(m.Len, 1)
    }
    return d
}

; Expand well-known WPF assembly names to full paths; everything else is passed through
WB_ResolveRefs(refLines) {
    fwDir := A_WinDir "\Microsoft.NET\" (A_PtrSize == 8 ? "Framework64" : "Framework") "\v4.0.30319"
    wpf := Map("uiautomationclient.dll", 1, "uiautomationtypes.dll", 1, "windowsbase.dll", 1
        , "presentationcore.dll", 1, "presentationframework.dll", 1)
    out := ""
    for line in refLines {
        for ref in StrSplit(line, ";") {
            ref := Trim(ref)
            if (ref == "")
                continue
            if wpf.Has(StrLower(ref))
                ref := fwDir "\WPF\" ref
            out .= (out == "" ? "" : ";") ref
        }
    }
    return out
}

; Installs/locates every // NuGet: package and returns the ';'-joined reference list
WB_CollectRefs(code, logFn := "") {
    d := WB_ParseDirectives(code)
    refs := ""
    for pkg in d.nuget {
        if (logFn) {
            verText := (pkg.ver != "") ? (" " pkg.ver) : ""
            logFn("📦 Resolving NuGet package: " pkg.id verText)
        }
        pkgRefs := CS.NuGet.Require(pkg.id, pkg.ver)
        refs := WB_JoinRefs(refs, pkgRefs)
    }
    if (d.refs.Length) {
        resolved := WB_ResolveRefs(d.refs)
        if (logFn)
            logFn("📎 Referencing assemblies: " resolved)
        refs := WB_JoinRefs(refs, resolved)
    }
    return refs
}

; Copy of `code` where comments, string/char literals and everything nested deeper than `keepDepth`
; braces is blanked out. Same length and same line breaks as the input, so match positions map 1:1.
WB_CSharpSkeleton(code, keepDepth := 0) {
    out := ""
    n := StrLen(code)
    depth := 0
    i := 1
    while (i <= n) {
        c := SubStr(code, i, 1)
        nx := SubStr(code, i + 1, 1)
        if (c == "/" && nx == "/") {
            j := InStr(code, "`n", true, i)
            if (!j)
                j := n + 1
            out .= WB_Blank(SubStr(code, i, j - i))
            i := j
        } else if (c == "/" && nx == "*") {
            j := InStr(code, "*/", true, i + 2)
            j := j ? j + 2 : n + 1
            out .= WB_Blank(SubStr(code, i, j - i))
            i := j
        } else if (c == '"') {
            verbatim := (i > 1 && SubStr(code, i - 1, 1) == "@")
            j := i + 1
            while (j <= n) {
                ch := SubStr(code, j, 1)
                if (verbatim) {
                    if (ch == '"') {
                        if (SubStr(code, j + 1, 1) == '"') {
                            j += 2
                            continue
                        }
                        break
                    }
                } else {
                    if (ch == "\") {
                        j += 2
                        continue
                    }
                    if (ch == '"' || ch == "`n")
                        break
                }
                j++
            }
            out .= WB_Blank(SubStr(code, i, Min(j, n) - i + 1))
            i := j + 1
        } else if (c == "'") {
            j := i + 1
            while (j <= n) {
                ch := SubStr(code, j, 1)
                if (ch == "\") {
                    j += 2
                    continue
                }
                if (ch == "'" || ch == "`n")
                    break
                j++
            }
            out .= WB_Blank(SubStr(code, i, Min(j, n) - i + 1))
            i := j + 1
        } else if (c == "{") {
            out .= (depth <= keepDepth) ? "{" : " "
            depth++
            i++
        } else if (c == "}") {
            depth := Max(0, depth - 1)
            out .= (depth <= keepDepth) ? "}" : " "
            i++
        } else {
            out .= (depth <= keepDepth || c == "`n" || c == "`r" || c == " " || c == "`t") ? c : " "
            i++
        }
    }
    return out
}

; True when the source consists only of type/namespace declarations (a complete source file)
WB_IsTypeOnlySource(skel) {
    s := RegExReplace(skel, "m)^[ \t]*using[ \t]+[^;{}()\r\n]+;", "")
    s := RegExReplace(s, "m)^[ \t]*#.*$", "")
    s := RegExReplace(s, "(?:\[[^\]]*\]\s*)*(?:\w+\s+)*?(?:class|struct|interface|enum)\s+\w+[^{;]*\{\s*\}", "")
    s := RegExReplace(s, "\bnamespace\s+[\w.]+\s*\{\s*\}", "")
    return (Trim(s, " `t`r`n;") == "")
}

; class/struct declarations in a skeleton -> [{name, isPublic}]
WB_FindTypeDecls(scan) {
    decls := []
    pos := 1
    while RegExMatch(scan, "\b((?:(?:public|internal|static|sealed|abstract|partial|unsafe)\s+)*)(class|struct)\s+(\w+)", &m, pos) {
        pos := m.Pos + m.Len
        lastCh := SubStr(RTrim(SubStr(scan, 1, m.Pos - 1), " `t`r`n"), -1)
        if (lastCh == ":" || lastCh == ",")
            continue            ; generic constraint (where T : class ...), not a declaration
        decls.Push({name: m[3], isPublic: InStr(m[1], "public") > 0})
    }
    return decls
}

; Name of the public static method to invoke: Run, else Main, else the first one found
WB_FindEntryMethod(skel, className := "") {
    start := 1
    if (className != "" && RegExMatch(skel, "\b(?:class|struct)\s+" className "\b", &cm))
        start := cm.Pos + cm.Len
    names := []
    pos := start
    while RegExMatch(skel, "\b(?:public\s+static|static\s+public)\s+(?:(?:unsafe|async|new|extern)\s+)*[\w.<>\[\],?\s]+?\s+(\w+)\s*\(", &m, pos) {
        names.Push(m[1])
        pos := m.Pos + m.Len
    }
    for n in names {
        if (n == "Run")
            return n
    }
    for n in names {
        if (n == "Main")
            return n
    }
    return names.Length ? names[1] : "Run"
}

; Turn editor code into a compilable C# source. Returns
;   {src, className, shortName, method, offset, wrapped}
; * Code made only of type declarations is used as is (never nested inside a wrapper type).
; * Otherwise the members are wrapped in `public class <className>`. Every line of the wrapper's
;   prologue sits on ONE line and the code's own `using` lines are hoisted into it, so compiler
;   line N is editor line N - offset (offset 1 when wrapped, 0 when not).
WB_BuildClassSource(code, className) {
    if !RegExMatch(className, "^[A-Za-z_]\w*$")
        throw ValueError("Not a valid C# class name: " className)

    baseUsings := "using System; using System.Linq; using System.Collections.Generic;"
    skel0 := WB_CSharpSkeleton(code, 0)

    if (WB_IsTypeOnlySource(skel0)) {
        ns := ""
        scan := skel0
        if RegExMatch(skel0, "\bnamespace\s+([\w.]+)", &nm) {
            ns := nm[1]
            scan := WB_CSharpSkeleton(code, 1)
        }
        decls := WB_FindTypeDecls(scan)
        if (decls.Length) {
            entry := decls[1].name
            for d in decls {
                if (d.isPublic) {
                    entry := d.name
                    break
                }
            }
            bodySkel := WB_CSharpSkeleton(code, (ns != "") ? 2 : 1)
            method := WB_FindEntryMethod(bodySkel, entry)
            pre := RegExMatch(code, "i)\busing\s+System\b") ? "" : (baseUsings " ")
            fullName := (ns != "") ? (ns "." entry) : entry
            return {src: pre . code, className: fullName, shortName: entry, method: method, offset: 0, wrapped: false}
        }
    }

    ; Members only: wrap. Hoist top-level using directives into the prologue, blanking their old lines.
    usings := baseUsings
    stripped := ""
    pos := 1
    while RegExMatch(skel0, "m)^[ \t]*using[ \t]+[^;{}()\r\n]+;", &um, pos) {
        stripped .= SubStr(code, pos, um.Pos - pos) WB_Blank(SubStr(code, um.Pos, um.Len))
        usings .= " " Trim(SubStr(code, um.Pos, um.Len))
        pos := um.Pos + um.Len
    }
    stripped .= SubStr(code, pos)

    method := WB_FindEntryMethod(skel0)
    src := usings " public class " className " {`n" stripped "`n}"
    return {src: src, className: className, shortName: className, method: method, offset: 1, wrapped: true}
}

; Compiler messages say "Line N: ..." relative to the generated source — map them to editor lines
WB_RemapCompilerLines(msg, offset) {
    if (offset <= 0)
        return msg
    out := ""
    pos := 1
    while RegExMatch(msg, "i)\bLine (\d+):", &m, pos) {
        n := Integer(m[1])
        out .= SubStr(msg, pos, m.Pos - pos) "Line " (n > offset ? n - offset : "0 (generated header)") ":"
        pos := m.Pos + m.Len
    }
    return out SubStr(msg, pos)
}

; ── AHK Script mode: run in a separate process, capture its output, clean up afterwards ──

; Make relative `#Include` lines resolve: the script runs from a temp folder, so anything relative
; to the studio's folder (lib\, ext\, <ahk#> ...) is rewritten to an absolute path. Line count is unchanged.
WB_AbsolutizeIncludes(code) {
    if !InStr(code, "#Include")
        return code
    out := ""
    Loop Parse, code, "`n", "`r" {
        line := A_LoopField
        if RegExMatch(line, "i)^(\s*#Include(?:Again)?\s+)(\*i\s+)?(.*)$", &m) {
            rest := RTrim(RegExReplace(m[3], "\s+;.*$", ""))
            path := ""
            libName := ""
            if RegExMatch(rest, "^<([^>]+)>$", &lm) {
                libName := lm[1]
            } else if RegExMatch(rest, '^"([^"]*)"$', &qm) || RegExMatch(rest, "^'([^']*)'$", &qm) {
                path := qm[1]
            } else {
                path := rest
            }

            newPath := ""
            if (libName != "") {
                for dirName in ["lib", "ext"] {
                    cand := A_ScriptDir "\" dirName "\" libName ".ahk"
                    if FileExist(cand) {
                        newPath := cand
                        break
                    }
                }
            } else if (path != "" && !RegExMatch(path, "^([A-Za-z]:|\\\\)")) {
                newPath := A_ScriptDir "\" StrReplace(path, "/", "\")
                if !FileExist(newPath) {
                    ; examples use "..\lib\ahk#.ahk" relative to their own folder
                    alt := A_ScriptDir "\" RegExReplace(StrReplace(path, "/", "\"), "^(\.\.\\)+", "")
                    if FileExist(alt)
                        newPath := alt
                }
            }
            if (newPath != "")
                line := m[1] m[2] '"' newPath '"'
        }
        out .= line "`n"
    }
    return out
}

; Start `cmd` with stdout+stderr redirected to a file. Returns true on success (pid/hProc by ref).
WB_Spawn(cmd, workDir, outFile, &pid, &hProc) {
    pid := 0
    hProc := 0

    sa := Buffer(A_PtrSize == 8 ? 24 : 12, 0)      ; SECURITY_ATTRIBUTES, inheritable
    NumPut("UInt", sa.Size, sa, 0)
    NumPut("Int", 1, sa, A_PtrSize == 8 ? 16 : 8)

    hOut := DllCall("CreateFileW", "wstr", outFile, "uint", 0x40000000, "uint", 3, "ptr", sa
        , "uint", 2, "uint", 0x80, "ptr", 0, "ptr")          ; GENERIC_WRITE, share R|W, CREATE_ALWAYS
    if (hOut == -1 || !hOut)
        return false
    hIn := DllCall("CreateFileW", "wstr", "NUL", "uint", 0x80000000, "uint", 3, "ptr", sa
        , "uint", 3, "uint", 0x80, "ptr", 0, "ptr")          ; stdin = NUL
    if (hIn == -1)
        hIn := 0

    si := Buffer(A_PtrSize == 8 ? 104 : 68, 0)               ; STARTUPINFOW
    NumPut("UInt", si.Size, si, 0)
    NumPut("UInt", 0x100, si, A_PtrSize == 8 ? 60 : 44)      ; STARTF_USESTDHANDLES
    NumPut("Ptr", hIn, si, A_PtrSize == 8 ? 80 : 56)
    NumPut("Ptr", hOut, si, A_PtrSize == 8 ? 88 : 60)
    NumPut("Ptr", hOut, si, A_PtrSize == 8 ? 96 : 64)

    pi := Buffer(A_PtrSize == 8 ? 24 : 16, 0)                ; PROCESS_INFORMATION
    cmdBuf := Buffer((StrLen(cmd) + 1) * 2, 0)               ; CreateProcessW may modify its command line
    StrPut(cmd, cmdBuf)
    ok := DllCall("CreateProcessW", "ptr", 0, "ptr", cmdBuf, "ptr", 0, "ptr", 0, "int", true
        , "uint", 0, "ptr", 0, "wstr", workDir, "ptr", si, "ptr", pi)

    DllCall("CloseHandle", "ptr", hOut)
    if (hIn)
        DllCall("CloseHandle", "ptr", hIn)
    if (!ok)
        return false

    hProc := NumGet(pi, 0, "Ptr")
    DllCall("CloseHandle", "ptr", NumGet(pi, A_PtrSize, "Ptr"))
    pid := NumGet(pi, 2 * A_PtrSize, "UInt")
    return true
}

; Write the code to a unique temp folder and run it with /ErrorStdOut.
;   user.ahk  — the editor text, byte for byte (so error line numbers match the editor)
;   main.ahk  — #Requires + the AHK# includes + #Include user.ahk
WB_StartAhkScript(code) {
    global g_runs
    dir := A_Temp "\ahksharp_wb_" A_TickCount
    while DirExist(dir)
        dir .= "_"
    DirCreate(dir)

    userFile := dir "\user.ahk"
    mainFile := dir "\main.ahk"
    outFile := dir "\out.txt"
    try {
        FileAppend(WB_AbsolutizeIncludes(code), userFile, "UTF-8")
        hdr := "#Requires AutoHotkey v2.0`n#SingleInstance Force`n"
        hdr .= '#Include "' A_ScriptDir '\lib\ahk#.ahk"`n'
        hdr .= '#Include "' A_ScriptDir '\ext\ahk#.http.ahk"`n'
        hdr .= '#Include "' userFile '"`n'
        FileAppend(hdr, mainFile, "UTF-8")
    } catch as e {
        WB_DeleteDirLater(dir, 1)
        throw e
    }

    cmd := '"' A_AhkPath '" /ErrorStdOut "' mainFile '"'
    job := {pid: 0, hProc: 0, dir: dir, outFile: outFile, f: 0, started: A_TickCount, captured: false}
    pid := 0
    hProc := 0
    if WB_Spawn(cmd, A_ScriptDir, outFile, &pid, &hProc) {
        job.captured := true
        job.pid := pid
        job.hProc := hProc
        try job.f := FileOpen(outFile, "r", "UTF-8-RAW")
    } else {
        Run(cmd, A_ScriptDir, , &pid)       ; fallback: no output capture
        job.pid := pid
    }

    g_runs.Push(job)
    SetTimer(WB_PollRuns, 150)
    return job
}

WB_DrainRunOutput(r) {
    if (!r.f)
        return
    try {
        if (r.f.Pos < r.f.Length) {
            chunk := r.f.Read()
            if (chunk != "")
                WB_OutAppend(edOutput, chunk)
        }
    }
}

WB_PollRuns() {
    global g_runs
    i := g_runs.Length
    while (i >= 1) {
        r := g_runs[i]
        WB_DrainRunOutput(r)
        if (r.hProc)
            alive := (DllCall("WaitForSingleObject", "ptr", r.hProc, "uint", 0, "uint") == 0x102)
        else
            alive := ProcessExist(r.pid)
        if (!alive) {
            WB_DrainRunOutput(r)
            exitText := ""
            if (r.hProc) {
                exitCode := 0
                DllCall("GetExitCodeProcess", "ptr", r.hProc, "uint*", &exitCode)
                exitText := "  exit code " exitCode
            }
            AppendOutput("═══ Script exited (PID " r.pid ")" exitText " ═══  [" Round((A_TickCount - r.started) / 1000, 1) "s]")
            WB_FinalizeRun(r)
            g_runs.RemoveAt(i)
        }
        i--
    }
    if (g_runs.Length == 0) {
        SetTimer(WB_PollRuns, 0)
        lblRunStatus.Value := "Script finished"
    } else {
        lblRunStatus.Value := g_runs.Length " script(s) running"
    }
}

; Release handles and delete the temp folder (retried: the child may still hold out.txt for a moment)
WB_FinalizeRun(r) {
    try r.f.Close()
    r.f := 0
    if (r.hProc)
        DllCall("CloseHandle", "ptr", r.hProc)
    r.hProc := 0
    WB_DeleteDirLater(r.dir, 4)
}

WB_DeleteDirLater(dir, tries := 3) {
    try {
        if DirExist(dir)
            DirDelete(dir, true)
    } catch {
        if (tries > 1)
            SetTimer(WB_DeleteDirLater.Bind(dir, tries - 1), -2000)
    }
}

WB_KillRun(r) {
    if (r.hProc)
        DllCall("TerminateProcess", "ptr", r.hProc, "uint", 1)
    else if (r.pid)
        try ProcessClose(r.pid)
}

OnStopScripts(*) {
    global g_runs
    if (g_runs.Length == 0) {
        SetStatus("No script is running")
        return
    }
    count := g_runs.Length
    for r in g_runs
        WB_KillRun(r)
    AppendOutput("■ Stop requested for " count " script(s)")
}

; ── Output pane ───────────────────────────────────────────────────────────────

AppendOutput(text) {
    ts := FormatTime(, "HH:mm:ss")
    WB_OutAppend(edOutput, "[" ts "] " text "`r`n")
}

; Append at the end of an Edit control without touching the rest of its text, then scroll to the end.
; Line breaks are normalised to CRLF (a lone LF shows up as a box in an Edit control).
WB_OutAppend(ctrl, text) {
    static EM_SETSEL := 0x00B1
    static EM_REPLACESEL := 0x00C2
    static EM_SCROLLCARET := 0x00B7
    static EM_SETREADONLY := 0x00CF
    static WM_GETTEXTLENGTH := 0x000E
    static WM_VSCROLL := 0x0115
    static MAXCHARS := 400000

    hwnd := ctrl.Hwnd
    text := RegExReplace(text, "\r\n|\r|\n", "`r`n")
    len := SendMessage(WM_GETTEXTLENGTH, 0, 0, hwnd)

    SendMessage(EM_SETREADONLY, 0, 0, hwnd)     ; EM_REPLACESEL is refused by read-only edits on some systems
    if (len > MAXCHARS) {                       ; keep the pane bounded: drop the oldest half
        SendMessage(EM_SETSEL, 0, len - MAXCHARS // 2, hwnd)
        DllCall("SendMessageW", "ptr", hwnd, "uint", EM_REPLACESEL, "ptr", 0, "wstr", "[… older output trimmed …]`r`n", "ptr")
        len := SendMessage(WM_GETTEXTLENGTH, 0, 0, hwnd)
    }
    SendMessage(EM_SETSEL, len, len, hwnd)
    DllCall("SendMessageW", "ptr", hwnd, "uint", EM_REPLACESEL, "ptr", 0, "wstr", text, "ptr")
    SendMessage(EM_SCROLLCARET, 0, 0, hwnd)
    SendMessage(WM_VSCROLL, 7, 0, hwnd)         ; SB_BOTTOM
    SendMessage(EM_SETREADONLY, 1, 0, hwnd)
}


; ═══════════════════════════════════════════════════════════════════════════════
; SETTINGS, RUN HISTORY, USER SNIPPETS  (%AppData%\AHKSharp\workbench.ini)
; ═══════════════════════════════════════════════════════════════════════════════

; The ini is created as UTF-16 so code containing any character survives IniWrite/IniRead
WB_IniPath() {
    static path := ""
    if (path != "")
        return path
    dir := A_AppData "\AHKSharp"
    try DirCreate(dir)
    p := dir "\workbench.ini"
    try {
        if !FileExist(p)
            FileAppend("; AHK# Developer Studio settings`r`n", p, "UTF-16")
    }
    path := p
    return path
}

; Values are stored as  ~mode|time|text~  — the ~ guards against the ini API trimming spaces or quotes,
; and line breaks are escaped so a whole script fits on one ini line.
WB_EncodeText(s) {
    s := StrReplace(s, "`r`n", "`n")
    s := StrReplace(s, "%", "%25")
    s := StrReplace(s, "`n", "%0A")
    return s
}

WB_DecodeText(s) {
    s := StrReplace(s, "%0A", "`r`n")
    s := StrReplace(s, "%25", "%")
    return s
}

WB_PackEntry(e) {
    return "~" e.mode "|" e.time "|" WB_EncodeText(e.code) "~"
}

WB_UnpackEntry(raw) {
    if (StrLen(raw) < 4 || SubStr(raw, 1, 1) != "~" || SubStr(raw, -1) != "~")
        return ""
    body := SubStr(raw, 2, StrLen(raw) - 2)
    p1 := InStr(body, "|")
    p2 := InStr(body, "|", , p1 + 1)
    if (!p1 || !p2)
        return ""
    return {mode: SubStr(body, 1, p1 - 1), time: SubStr(body, p1 + 1, p2 - p1 - 1), code: WB_DecodeText(SubStr(body, p2 + 1))}
}

WB_HistoryLoad() {
    list := []
    n := 0
    try n := Integer(IniRead(WB_IniPath(), "History", "Count", 0))
    Loop n {
        raw := ""
        try raw := IniRead(WB_IniPath(), "History", "E" A_Index, "")
        e := WB_UnpackEntry(raw)
        if IsObject(e)
            list.Push(e)
    }
    return list
}

WB_HistoryPush(mode, code) {
    global g_historyMax
    if (StrLen(code) > 8000)        ; ini values are limited to ~32K characters
        return
    code := StrReplace(code, "`r`n", "`n")
    try {
        list := WB_HistoryLoad()
        for i, e in list {
            if (e.mode == mode && StrReplace(e.code, "`r`n", "`n") == code) {
                list.RemoveAt(i)
                break
            }
        }
        list.InsertAt(1, {mode: mode, time: A_Now, code: code})
        while (list.Length > g_historyMax)
            list.Pop()

        ini := WB_IniPath()
        try IniDelete(ini, "History")
        IniWrite(list.Length, ini, "History", "Count")
        for i, e in list
            IniWrite(WB_PackEntry(e), ini, "History", "E" i)
    }
}

OnHistoryClick(*) {
    list := WB_HistoryLoad()
    if (list.Length == 0) {
        SetStatus("No run history yet — press Run first")
        return
    }
    m := Menu()
    for i, e in list {
        first := ""
        Loop Parse, e.code, "`n", "`r" {
            if (Trim(A_LoopField) != "") {
                first := Trim(A_LoopField)
                break
            }
        }
        if (StrLen(first) > 60)
            first := SubStr(first, 1, 57) "..."
        first := StrReplace(first, "&", "&&")
        label := i ". " FormatTime(e.time, "MM-dd HH:mm") "  [" e.mode "]  " first
        m.Add(label, WB_HistoryPick.Bind(e))
    }
    m.Show()
}

WB_HistoryPick(e, *) {
    edCode.Value := e.code
    try ddlMode.Choose(e.mode)
    SetStatus("Loaded run from history (" e.mode ")")
}

WB_LoadUserSnippets() {
    global snippetCode, g_userSnipHeader
    sect := ""
    try sect := IniRead(WB_IniPath(), "Snippets")
    names := []
    Loop Parse, sect, "`n", "`r" {
        p := InStr(A_LoopField, "=")
        if (p < 2)
            continue
        name := SubStr(A_LoopField, 1, p - 1)
        e := WB_UnpackEntry(SubStr(A_LoopField, p + 1))
        if !IsObject(e)
            continue
        snippetCode["★ " name] := {mode: e.mode, code: e.code}
        names.Push("★ " name)
    }
    if (names.Length) {
        ddlSnippet.Add(["── My Snippets ──"])
        ddlSnippet.Add(names)
        g_userSnipHeader := true
    }
}

OnSaveSnippet(*) {
    global snippetCode, g_userSnipHeader
    code := edCode.Value
    if (Trim(code) == "") {
        SetStatus("Nothing to save — the code editor is empty")
        return
    }
    if (StrLen(code) > 8000) {
        SetStatus("Snippet too large to save (8000 character limit)")
        return
    }
    ib := InputBox("Name for this snippet:", "Save Snippet", "w340 h130")
    if (ib.Result != "OK")
        return
    name := Trim(RegExReplace(ib.Value, "[=\[\];\r\n]", " "))
    if (name == "")
        return

    mode := ddlMode.Text
    try {
        IniWrite(WB_PackEntry({mode: mode, time: A_Now, code: code}), WB_IniPath(), "Snippets", name)
    } catch as e {
        SetStatus("Could not save snippet: " e.Message)
        return
    }

    key := "★ " name
    isNew := !snippetCode.Has(key)
    snippetCode[key] := {mode: mode, code: code}
    if (isNew) {
        if (!g_userSnipHeader) {
            ddlSnippet.Add(["── My Snippets ──"])
            g_userSnipHeader := true
        }
        ddlSnippet.Add([key])
    }
    try ddlSnippet.Choose(key)
    SetStatus("Saved snippet: " name)
}

WB_LoadSettings() {
    ini := WB_IniPath()
    try {
        m := Integer(IniRead(ini, "Scratchpad", "Mode", MODE_EXPR))
        if (m >= 1 && m <= 3)
            ddlMode.Choose(m)
    }
    try {
        v := IniRead(ini, "Scratchpad", "CSVersion", "")
        if (v != "")
            ddlScratchVer.Choose(v)
    }
    try {
        v := IniRead(ini, "Precompiler", "CSVersion", "")
        if (v != "")
            ddlCSVer.Choose(v)
    }
}

WB_SaveSettings() {
    ini := WB_IniPath()
    try IniWrite(ddlMode.Value, ini, "Scratchpad", "Mode")
    try IniWrite(ddlScratchVer.Text, ini, "Scratchpad", "CSVersion")
    try IniWrite(ddlCSVer.Text, ini, "Precompiler", "CSVersion")
    try {
        if IsObject(g_lastSize) {
            IniWrite(Round(g_lastSize[1] * 96 / A_ScreenDPI), ini, "Window", "Width")
            IniWrite(Round(g_lastSize[2] * 96 / A_ScreenDPI), ini, "Window", "Height")
        }
    }
}

WB_OnClose(*) {
    global g_runs
    if (g_runs.Length) {
        r := MsgBox(g_runs.Length " script(s) started from the workbench are still running.`n`n"
            . "Yes = stop them and exit`nNo = exit and leave them running`nCancel = keep the workbench open"
            , "AHK# Developer Studio", "YesNoCancel Icon?")
        if (r == "Cancel")
            return true             ; a true return value cancels the close
        if (r == "Yes") {
            for job in g_runs
                WB_KillRun(job)
            Sleep(250)
            for job in g_runs
                WB_FinalizeRun(job)
        }
    }
    WB_SaveSettings()
    ExitApp()
}

; ═══════════════════════════════════════════════════════════════════════════════
; EXPORT — scratchpad C# Class code as a ready-to-#Include CSModule .ahk
; ═══════════════════════════════════════════════════════════════════════════════

; Escape one line of text for use inside an AHK v2 double-quoted string literal
WB_AhkQuote(s) {
    s := StrReplace(s, "``", "````")
    s := StrReplace(s, '"', '``"')
    return s
}

OnExportModule(*) {
    code := edCode.Value
    if (Trim(code) == "") {
        SetStatus("Nothing to export — the code editor is empty")
        return
    }
    if (ddlMode.Text != "C# Class") {
        SetStatus("Export as CSModule works on C# Class code — switch Mode to C# Class")
        return
    }

    ib := InputBox("Class name for the exported CSModule:", "Export as CSModule .ahk", "w340 h130", "MyModule")
    if (ib.Result != "OK")
        return
    modName := Trim(ib.Value)

    try {
        info := WB_BuildClassSource(code, modName)
    } catch as e {
        SetStatus("Cannot export: " e.Message)
        return
    }
    ; When the code already declares its own class, the AHK class must carry that name
    if (!info.wrapped)
        modName := info.shortName

    d := WB_ParseDirectives(code)
    parts := []
    for pkg in d.nuget
        parts.Push('CS.NuGet.Require("' WB_AhkQuote(pkg.id) '", "' WB_AhkQuote(pkg.ver) '")')
    if (d.refs.Length)
        parts.Push('"' WB_AhkQuote(WB_ResolveRefs(d.refs)) '"')
    refsExpr := ""
    for i, part in parts {
        if (i > 1)
            refsExpr .= ' ";" '
        refsExpr .= part
    }
    csVer := WB_VersionValue(ddlScratchVer.Text)

    out := "; CSModule exported from AHK# Developer Studio  (" FormatTime(, "yyyy-MM-dd HH:mm") ")`n"
    out .= "; ahk#.ahk must be reachable through #Include <ahk#>  (e.g. a Lib folder next to this script).`n"
    out .= "#Requires AutoHotkey v2.0`n"
    out .= "#Include <ahk#>`n`n"
    out .= "class " modName " extends _CSModule {`n"
    if (refsExpr != "")
        out .= "    static References := " refsExpr "`n"
    if (csVer != "")
        out .= '    static CSVersion := "' csVer '"`n'
    out .= '    static CSharp := ""`n'
    Loop Parse, code, "`n", "`r"
        out .= '        . "' WB_AhkQuote(A_LoopField) '``n"`n'
    out .= "}`n`n"
    out .= "; Usage:  MsgBox(String(" modName "." info.method "()))`n"

    path := FileSelect("S16", A_Desktop "\" modName ".ahk", "Export CSModule", "AHK Scripts (*.ahk)")
    if (path == "")
        return
    try {
        if FileExist(path)
            FileDelete(path)
        FileAppend(out, path, "UTF-8")
        SetStatus("Exported CSModule to " path)
        AppendOutput("✓ Exported CSModule '" modName "' to " path)
    } catch as e {
        SetStatus("Export failed: " e.Message)
    }
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

; AHK# expression for a type: nested and generic types cannot be written as a dotted CS.A.B path
WB_TypeRef(fullName) {
    if (InStr(fullName, "+") || InStr(fullName, "``"))
        return 'CS("' StrReplace(fullName, "``", "````") '")'
    return "CS." fullName
}

OnGenSnippet(*) {
    row := lvTypes.GetNext(0, "Focused")
    if (!row) {
        edSnippet.Value := "; Select a member from the list first"
        return
    }
    memberType := lvTypes.GetText(row, 1)
    memberName := lvTypes.GetText(row, 2)
    memberSig := lvTypes.GetText(row, 3)
    typeName := g_currentTypeSearch

    if (memberType == "Class" || memberType == "Interface" || memberType == "Struct" || memberType == "Enum" || memberType == "Delegate") {
        ref := WB_TypeRef(memberSig)
        if (memberType == "Enum")
            edSnippet.Value := "; Enum " memberSig "`r`nvalue := " ref ".MemberName"
        else
            edSnippet.Value := "obj := " ref "()"
        SetStatus("Snippet generated for Type: " memberSig)
        return
    }

    try {
        ; The signature column identifies the exact overload the user selected
        snippet := WBHelper.GenerateSnippet(typeName, memberName, memberType, memberSig)
        edSnippet.Value := RegExReplace(snippet, "\r?\n", "`r`n")
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

    ; Visually switch to the Wrapper Gen tab
    OnTabClick(customTabs[TAB_WRAPPER])

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
    global g_nugetReqId
    query := Trim(edNuGetSearch.Value)
    if (query == "") {
        SetStatus("Enter a package name to search")
        return
    }

    g_nugetReqId++
    reqId := g_nugetReqId
    lblNuGetStatus.Value := "Searching..."
    lvNuGetResults.Delete()
    SetStatus("Searching NuGet for: " query)

    ; Async keeps the UI responsive; each callback carries its request id so a slow, older
    ; search can never overwrite the results of a newer one.
    try {
        p := WBHelper.Async.SearchNuGet(query)
        p.Then(OnNuGetResults.Bind(reqId))
        p.Catch(OnNuGetFailed.Bind(reqId))
    } catch as e {
        lblNuGetStatus.Value := "Error!"
        SetStatus("NuGet search could not start: " e.Message)
    }
}

OnNuGetFailed(reqId, err) {
    if (reqId != g_nugetReqId)
        return
    lblNuGetStatus.Value := "Error!"
    SetStatus("NuGet search failed: " (IsObject(err) ? err.Message : err))
}

OnNuGetResults(reqId, result) {
    if (reqId != g_nugetReqId)
        return
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
    WB_Repaint()

    try {
        CS.NuGet.Install(pkgName, pkgVer)
        ; Never trust the call alone: report what is really on disk
        if (!CS.NuGet.IsInstalled(pkgName, pkgVer))
            throw Error("the package files were not found after the install")
        lblInstallStatus.Value := "✓ Installed " pkgName " " pkgVer
        SetStatus("Successfully installed " pkgName " " pkgVer)
        OnRefreshInstalled()
    } catch as e {
        lblInstallStatus.Value := "✗ Install failed: " SubStr(e.Message, 1, 80)
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

        ; Visually switch to the Wrapper Gen tab
        OnTabClick(customTabs[TAB_WRAPPER])

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
    UninstallPackage(lvInstalled.GetText(row, 1), lvInstalled.GetText(row, 2))
}

OnNuGetInstalledContextMenu(ctrl, itemIndex, isRightClick, x, y) {
    if (!itemIndex)
        return
        
    pkgName := lvInstalled.GetText(itemIndex, 1)
    pkgVer := lvInstalled.GetText(itemIndex, 2)
    
    InstalledPkgMenu := Menu()
    InstalledPkgMenu.Add("Uninstall " pkgName " (" pkgVer ")", (*) => UninstallPackage(pkgName, pkgVer))
    InstalledPkgMenu.Add("Send to Wrapper Gen", (*) => (lvInstalled.Modify(itemIndex, "Select Focus"), OnNuGetSendToWrapper()))
    InstalledPkgMenu.Show()
}

; The one and only uninstall path (button and context menu both end up here)
UninstallPackage(pkgName, pkgVer) {
    if (MsgBox("Are you sure you want to uninstall " pkgName " (version " pkgVer ")?", "Confirm Uninstall", "YesNo Icon! Default2") != "Yes")
        return

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
    ddlMode.Choose(MODE_AHK)
    OnTabClick(customTabs[TAB_SCRATCH])
    SetStatus("Sent compiled test script to Scratchpad!")
}

OnPrecompile(*) {
    global g_precompAsmId
    code := edPrecompCode.Value
    className := Trim(edClassName.Value)
    refs := Trim(edPrecompRefs.Value)
    csVer := WB_VersionValue(ddlCSVer.Text)

    if (Trim(code) == "" || className == "") {
        edPrecompOut.Value := "⚠ Enter a class name and C# code first."
        return
    }

    edPrecompOut.Value := "Compiling..."
    WB_Repaint()
    startTick := A_TickCount
    offset := 0

    try {
        ; Same wrapping as the scratchpad: members are wrapped, complete classes are used as they are
        refs := WB_JoinRefs(refs, WB_CollectRefs(code))
        info := WB_BuildClassSource(code, className)
        offset := info.offset
        cls := info.className

        bridge := _AhkSharpEngine.Boot()
        if (csVer != "")
            g_precompAsmId := bridge.CompileModuleVersioned(info.src, refs, csVer)
        else
            g_precompAsmId := bridge.CompileModule(info.src, refs)

        elapsed := A_TickCount - startTick
        out := "✓ Compilation successful!  [" elapsed "ms]"
        out .= "`r`n  Assembly ID: " g_precompAsmId
        clsNote := info.wrapped ? "" : "  (declared in your code)"
        verLabel := (csVer != "") ? csVer : "4.0 (default)"
        out .= "`r`n  Class: " cls clsNote
        out .= "`r`n  C# Version: " verLabel
        out .= "`r`n`r`n  You can now Export DLL or test in AHK Script with:"
        out .= "`r`n  bridge := _AhkSharpEngine.Boot()"
        out .= '`r`n  result := bridge.InvokeModule("' g_precompAsmId '", "' cls '", "' info.method '", "")'
        out .= '`r`n  MsgBox(String(result))'
        edPrecompOut.Value := out

        ; Try the entry method (Run / Main / first public static)
        try {
            testResult := bridge.InvokeModule(g_precompAsmId, cls, info.method, "")
            edPrecompOut.Value := edPrecompOut.Value
                . "`r`n`r`n═══ Test Run Output (" info.method ") ═══"
                . "`r`n" (IsObject(testResult) ? String(testResult) : testResult)
        }

        SetStatus("Compilation successful — " elapsed "ms")
    } catch as e {
        elapsed := A_TickCount - startTick
        g_precompAsmId := ""
        edPrecompOut.Value := "✗ Compilation FAILED  [" elapsed "ms]"
            . "`r`n`r`n" WB_RemapCompilerLines(e.Message, offset)
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
        if (WBHelper.DeleteCacheEntry(hash)) {
            OnCacheRefresh()
            SetStatus("Deleted cache entry: " hash)
        } else {
            SetStatus("Could not delete " hash " — the DLL is in use by this process")
        }
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

OnCacheCleanUnused(*) {
    count := 0
    try count := WBHelper.CountUnusedCache()
    if (!count) {
        SetStatus("Nothing to clean — every cached module is loaded in this session")
        return
    }

    result := MsgBox("Delete " count " cached module(s) that are not loaded in this session?`n`n"
        . "They are recompiled the next time they are needed.",
        "Clean Unused Cache", "YesNo Icon!")
    if (result != "Yes")
        return

    try {
        deleted := WBHelper.CleanUnusedCache()
        OnCacheRefresh()
        SetStatus("Removed " deleted " unused cache file(s)")
    } catch as e {
        SetStatus("Clean error: " e.Message)
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

    ; Force GC only collects memory. It never touches the compile cache on disk —
    ; use the Cache tab (Clean Unused / Clear ALL Cache) for that.
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

    ; Visually switch to the Wrapper Gen tab
    OnTabClick(customTabs[TAB_WRAPPER])

    ; Load types
    OnWrapLoad()

    SetStatus("Loaded assembly into Wrapper Generator: " targetAsm)
}

UpdateCLRDisplay(memInfo) {
    ; Display only: refreshing (or the 2s auto-refresh) must never change what it measures,
    ; so no GC is triggered here — the "Force GC" button is the only thing that collects.
    parts := StrSplit(memInfo, "|")
    if (parts.Length >= 6) {
        lblHeapSize.Value := parts[1]
        lblGen0.Value := parts[2]
        lblGen1.Value := parts[3]
        lblGen2.Value := parts[4]
        lblAsmCount.Value := parts[5]
        lblRawBytes.Value := parts[6] " bytes"
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
    tName := Trim(edPredType.Value)
    mName := Trim(edPredMethod.Value)
    argsRaw := edPredArgs.Value

    if (tName == "" || mName == "")
        return

    SetStatus("Predicting overload...")
    try {
        ; Same literal parser as the Marshalling tab: [ "123", 16, true, [1, 2], {a: 1}, Map(...) ]
        argsObj := []
        if (Trim(argsRaw) != "") {
            parsed := ParseAhkLiteral(argsRaw)
            argsObj := (parsed is Array) ? parsed : [parsed]
        }

        csArgs := ComObjArray(0xC, argsObj.Length)
        for i, val in argsObj
            csArgs[i - 1] := val

        result := WBHelper.PredictOverload(tName, mName, csArgs)
        edPredResult.Value := RegExReplace(result, "\r?\n", "`r`n")
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

; A valid, unique AHK class name for a .NET type: drops the namespace, the `N generic-arity marker
; and the '+' of nested types, and avoids AHK's built-in class names.
WB_WrapperName(cls, used) {
    static reserved := Map("array", 1, "map", 1, "object", 1, "string", 1, "number", 1, "integer", 1
        , "float", 1, "buffer", 1, "error", 1, "gui", 1, "menu", 1, "file", 1, "func", 1, "class", 1
        , "any", 1, "cs", 1, "enumerator", 1, "primitive", 1, "regexmatchinfo", 1, "inputhook", 1
        , "comobject", 1, "closure", 1, "boundfunc", 1, "menubar", 1, "varref", 1)
    name := RegExReplace(cls, "^.*\.", "")
    name := RegExReplace(name, "``\d+", "")
    name := RegExReplace(name, "\W", "_")
    if (name == "" || RegExMatch(name, "^\d"))
        name := "T_" name
    if reserved.Has(StrLower(name))
        name := "Cs" name
    baseName := name
    n := 2
    while used.Has(StrLower(name)) {
        name := baseName "_" n
        n++
    }
    used[StrLower(name)] := true
    return name
}

; Read accessors from the accessor block of a property signature ("String {get/set}" or "{ get; set; }").
; Only whole tokens count, so names such as HashSet or Widget can never be mistaken for get/set.
WB_PropAccess(sig, &canGet, &canSet) {
    canGet := false
    canSet := false
    if RegExMatch(sig, "\{([^{}]*)\}\s*$", &m) {
        for tok in StrSplit(m[1], [";", "/", ",", " ", "`t"], " `t") {
            t := StrLower(tok)
            if (t == "get")
                canGet := true
            else if (t == "set")
                canSet := true
        }
    }
    if (!canGet && !canSet)
        canGet := true
}

; Assemblies that ship with .NET load by name; everything else (NuGet, custom DLLs) must be loaded by path
WB_NeedsLoadAssembly(asmPath) {
    if (asmPath == "" || asmPath == "Dynamic" || !FileExist(asmPath))
        return false
    if (InStr(asmPath, A_WinDir "\Microsoft.NET\") == 1 || InStr(asmPath, A_WinDir "\assembly\") == 1)
        return false
    return true
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

    stamp := FormatTime(, "yyyy-MM-dd HH:mm")
    out := "; Auto-Generated AHK# Wrapper for " edWrapAsm.Value "`n"
    out .= "; Generated on " stamp "`n`n"
    out .= "#Include <ahk#>`n`n"

    def := "/**`n * Auto-Generated AHK# IntelliSense Definition for " edWrapAsm.Value "`n"
    def .= " * Generated on " stamp "`n */`n`n"

    used := Map()
    for cls in selected {
        shortName := WB_WrapperName(cls, used)
        clsLit := StrReplace(cls, "``", "````")     ; the generic-arity backtick must be doubled inside an AHK string

        ; Extract full metadata using ExploreType
        metaStr := WBHelper.ExploreType(cls, 0)
        if (SubStr(metaStr, 1, 6) == "ERROR:") {
            out .= "; " cls " skipped — " metaStr "`n`n"
            continue
        }

        methods := Map()
        staticMethods := Map()
        props := Map()
        staticProps := Map()
        events := Map()
        asmLoc := ""

        Loop Parse, metaStr, "`n", "`r" {
            parts := StrSplit(A_LoopField, "|")
            if (parts.Length < 3)
                continue

            kind := parts[1]
            name := parts[2]
            sig := parts[3]
            if (kind == "Assembly") {
                asmLoc := sig
                continue
            }
            isStatic := (parts.Length >= 4 && parts[4] == "Static")

            if (kind == "Method") {
                mapObj := isStatic ? staticMethods : methods
                if !mapObj.Has(name)
                    mapObj[name] := []
                mapObj[name].Push(sig)
            } else if (kind == "Property") {
                if (name == "Item")             ; indexer: not expressible as an AHK property
                    continue
                mapObj := isStatic ? staticProps : props
                mapObj[name] := sig
            } else if (kind == "Event") {
                events[name] := sig
            }
        }

        hasInstance := (methods.Count > 0 || props.Count > 0 || events.Count > 0)

        ; 1. Generate Runtime Wrapper
        out .= "class " shortName " {`n"

        if (WB_NeedsLoadAssembly(asmLoc)) {
            ; Not a framework assembly: it has to be loaded by path before its types can be used
            out .= "    static __New() {`n"
            out .= "        CS.LoadAssembly(`"" StrReplace(asmLoc, "``", "````") "`")`n"
            out .= "    }`n`n"
        }

        if (staticProps.Count > 0 || staticMethods.Count > 0) {
            for mName, sigs in staticMethods
                out .= "    static " mName "(args*) => CS(`"" clsLit "`")." mName "(args*)`n"
            for pName, sig in staticProps {
                WB_PropAccess(sig, &canGet, &canSet)
                out .= "    static " pName " {`n"
                if (canGet)
                    out .= "        get => CS(`"" clsLit "`")." pName "`n"
                if (canSet)
                    out .= "        set => CS(`"" clsLit "`")." pName " := value`n"
                out .= "    }`n"
            }
            out .= "`n"
        }

        if (hasInstance) {
            out .= "    __New(args*) {`n"
            out .= "        this._obj := CS(`"" clsLit "`")(args*)`n"
            out .= "    }`n`n"
        }

        for mName, sigs in methods
            out .= "    " mName "(args*) => this._obj." mName "(args*)`n"

        for pName, sig in props {
            WB_PropAccess(sig, &canGet, &canSet)
            out .= "    " pName " {`n"
            if (canGet)
                out .= "        get => this._obj." pName "`n"
            if (canSet)
                out .= "        set => this._obj." pName " := value`n"
            out .= "    }`n"
        }

        for eName, sig in events {
            out .= "    " eName "Event(callback) {`n"
            out .= "        this._obj.On(`"" eName "`", callback)`n"
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
        if (hasInstance)
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
            def .= "    /**`n     * Binds a callback to the " eName " event (the callback receives the event args).`n     * @param {Func} callback`n     */`n"
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
    OnTabClick(customTabs[TAB_SCRATCH])
    ddlMode.Choose(MODE_AHK) ; AHK Script

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