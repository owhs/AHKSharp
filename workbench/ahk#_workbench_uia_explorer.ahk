; ═══════════════════════════════════════════════════════════════════════════════
; UIA AUTOMATION EXPLORER SIDECAR APPLICATION
; ═══════════════════════════════════════════════════════════════════════════════

global gUiaExplorer := 0
global btnDragTarget := 0
global btnDragTargetHwnd := 0
global lblTargetWindow := 0
global edTreeSearch := 0
global tvUia := 0
global lvProps := 0
global edCodePreview := 0
global g_uiaNodeMetadata := Map()
global g_targetHwnd := 0
global g_UiaHideTimer := () => UiaHighlighter.Hide()
global g_lastSearchText := ""
global g_lastSearchNodeID := 0
global lvSteps := 0
global g_automationSteps := []

LaunchUiaExplorer(*) {
    global gUiaExplorer, btnDragTarget, btnDragTargetHwnd, lblTargetWindow, edTreeSearch, tvUia, lvProps, edCodePreview, g_uiaNodeMetadata, g_targetHwnd, lvSteps, g_automationSteps
    
    if (gUiaExplorer) {
        try gUiaExplorer.Destroy()
    }
    
    ; Create sidecar Gui
    gUiaExplorer := Gui("+Owner" g.Hwnd, "AHK# UIA Automation Explorer")
    gUiaExplorer.BackColor := "0x0f0f1a"
    gUiaExplorer.MarginX := 12
    gUiaExplorer.MarginY := 12
    
    WB_DarkWindow(gUiaExplorer)
        
    ; Title / Header
    gUiaExplorer.SetFont("s11 c0x00d4ff bold", "Segoe UI")
    gUiaExplorer.Add("Text", "x12 y12 w350 h24 BackgroundTrans", "UI Automation Explorer Sidecar")
    
    ; Target Selector Group
    gUiaExplorer.SetFont("s9 c0xd0d0e0 norm", "Segoe UI")
    btnDragTarget := AddButton(gUiaExplorer, "x12 y42 w160 h30", "☉ Drag && Target Window")
    btnDragTargetHwnd := btnDragTarget.hwnd
    
    gUiaExplorer.SetFont("s9 c0xa78bfa bold", "Segoe UI")
    lblTargetWindow := gUiaExplorer.Add("Text", "x182 y48 w600 h20 BackgroundTrans", "Target: None (Drag button onto a window)")
    
    ; TreeView for UIA Tree
    gUiaExplorer.SetFont("s9 c0x00d4ff bold", "Segoe UI")
    gUiaExplorer.Add("Text", "x12 y86 w370 h20 BackgroundTrans", "◆  UIA Element Hierarchy")
    
    ; Tree Search Bar
    gUiaExplorer.SetFont("s9 c0xd0d0e0 norm", "Segoe UI")
    edTreeSearch := gUiaExplorer.Add("Edit", "x12 y110 w260 h24 Background0x12121f c0xd0d0e0 -E0x200", "")
    btnSearchTree := AddButton(gUiaExplorer, "x282 y109 w100 h26", "Find Next")
    btnSearchTree.OnEvent("Click", OnSearchTree)
    
    tvUia := gUiaExplorer.Add("TreeView", "x12 y140 w370 h326 Background0x12121f c0xd0d0e0 -E0x200")
    tvUia.OnEvent("ItemSelect", OnTvUiaSelect)
    
    ; Properties ListView
    gUiaExplorer.SetFont("s9 c0x00d4ff bold", "Segoe UI")
    gUiaExplorer.Add("Text", "x394 y86 w394 h20 BackgroundTrans", "◆  Element Properties")
    
    gUiaExplorer.SetFont("s9 c0xd0d0e0 norm", "Segoe UI")
    lvProps := gUiaExplorer.Add("ListView", "x394 y106 w394 h90 Background0x12121f c0xd0d0e0 -E0x200", ["Property", "Value"])
    lvProps.ModifyCol(1, 130)
    lvProps.ModifyCol(2, 240)
    
    ; WIZARD DYNAMIC GENERATOR STEPS
    gUiaExplorer.SetFont("s9 c0x00d4ff bold", "Segoe UI")
    gUiaExplorer.Add("Text", "x394 y202 w394 h16 BackgroundTrans", "◆  Automation Macro Steps")
    
    gUiaExplorer.SetFont("s9 c0xd0d0e0 norm", "Segoe UI")
    lvSteps := gUiaExplorer.Add("ListView", "x394 y220 w394 h96 Background0x12121f c0xd0d0e0 -E0x200", ["Step & Type", "Details", "Action"])
    lvSteps.OnEvent("ContextMenu", OnStepsContextMenu)
    lvSteps.ModifyCol(1, 120)
    lvSteps.ModifyCol(2, 160)
    lvSteps.ModifyCol(3, 100)
    
    btnAddCurrent := AddButton(gUiaExplorer, "x394 y322 w124 h26", "➕ Add Current")
    btnAddCurrent.OnEvent("Click", OnAddCurrentStep)
    btnAddCustom := AddButton(gUiaExplorer, "x523 y322 w124 h26", "⚙ Add Custom")
    btnAddCustom.OnEvent("Click", OnAddCustomStep)
    btnRemoveStep := AddButton(gUiaExplorer, "x652 y322 w136 h26", "❌ Remove Step")
    btnRemoveStep.OnEvent("Click", OnRemoveStep)
    
    ; Code Generation Preview
    gUiaExplorer.SetFont("s9 c0x00d4ff bold", "Segoe UI")
    gUiaExplorer.Add("Text", "x394 y354 w394 h16 BackgroundTrans", "◆  Generated C# Lookup Code")
    
    gUiaExplorer.SetFont("s9.5 c0x4ade80", "Cascadia Code")
    edCodePreview := gUiaExplorer.Add("Edit", "x394 y372 w394 h100 Multi ReadOnly VScroll HScroll Background0x12121f +Border -E0x200", "")
    
    ; Action Buttons (Bottom)
    gUiaExplorer.SetFont("s10 c0xd0d0e0", "Segoe UI")
    btnSendToScratch := AddButton(gUiaExplorer, "x394 y480 w190 h32", "▸ Send to Scratchpad")
    btnSendToScratch.OnEvent("Click", OnSendToScratchpad)
    
    btnCloseExplorer := AddButton(gUiaExplorer, "x598 y480 w190 h32", "Close")
    btnCloseExplorer.OnEvent("Click", (*) => gUiaExplorer.Destroy())
    
    ; Fully dark themed scrollbars, headers and inputs (shared helper from the playground)
    for darkCtrl in [tvUia, lvProps, lvSteps, edCodePreview, edTreeSearch]
        WB_DarkControl(darkCtrl)
    
    g_automationSteps := []
    g_automationSteps.Push({
        type: "Window Target",
        detail: "Deep Scan (incl. Minimized)",
        action: "None",
        post: "None",
        targetMode: "Deep Scan (incl. Minimized)"
    })
    UpdateStepsListView()
    RegenerateScriptCode()
    
    ; Position next to main studio
    g.GetPos(&x, &y, &w, &h)
    sidecarX := x + w + 10
    sidecarY := y
    
    ; Show GUI
    gUiaExplorer.Show("x" sidecarX " y" sidecarY " w800 h530")
}

; True when hwnd (or one of its parents) is the studio or the explorer window itself
UiaIsOurWindow(hwnd) {
    global gUiaExplorer
    cur := hwnd
    while (cur) {
        if (cur == gUiaExplorer.Hwnd || cur == g.Hwnd)
            return true
        try {
            cur := DllCall('GetParent', 'ptr', cur, 'ptr')
        } catch {
            break
        }
    }
    return false
}

; Ask UI Automation what is under the cursor, outline it, and return the tooltip text
UiaPointTip(mX, mY, targetHwnd) {
    title := WinGetTitle('ahk_id ' targetHwnd)
    class := WinGetClass('ahk_id ' targetHwnd)
    plainTip := 'Target: ' title '`nClass: ' class '`nHWND: ' targetHwnd '`nRelease to explore.'

    elementStr := ''
    try elementStr := WBHelper.GetUiaElementAtPoint(mX, mY)
    parts := StrSplit(elementStr, '|')
    if (elementStr == '' || parts.Length < 5) {
        UiaHighlighter.Hide()
        return plainTip
    }

    elName := parts[1]
    elType := parts[2]
    elId := parts[3]
    elClassName := parts[4]
    rectParts := StrSplit(parts[5], ',')
    if (rectParts.Length != 4) {
        UiaHighlighter.Hide()
        return plainTip
    }
    rW := Integer(rectParts[3])
    rH := Integer(rectParts[4])
    if (rW <= 0 || rH <= 0) {
        UiaHighlighter.Hide()
        return plainTip
    }

    UiaHighlighter.Show(Integer(rectParts[1]), Integer(rectParts[2]), rW, rH)
    displayText := elType
    if (elName != '')
        displayText .= ' : "' elName '"'
    else if (elId != '')
        displayText .= ' [ID: ' elId ']'
    else if (elClassName != '')
        displayText .= ' (Class: ' elClassName ')'
    return 'Target: ' title '`nClass: ' class '`n`nComponent: ' displayText '`nRelease to explore.'
}

TrackTargetDrag() {
    global gUiaExplorer, btnDragTarget, lblTargetWindow, g_targetHwnd

    SetMouseDelay(-1)
    ToolTip('Drag over the target window and release left mouse button...')

    ; Change the drag button's visual state
    btnDragTarget.Text := '☉ Dragging...'
    btnDragTarget.Opt('+Background0x2d3748')

    ; UIA element lookups are cross-process and slow: only ask again when the mouse has moved
    ; a few pixels (or every so often), otherwise reuse the previous tooltip.
    lastX := -999
    lastY := -999
    lastTick := 0
    tip := ''
    Loop {
        if !GetKeyState('LButton', 'P')
            break

        MouseGetPos(&mX, &mY, &targetHwnd)
        if targetHwnd {
            if UiaIsOurWindow(targetHwnd) {
                UiaHighlighter.Hide()
                tip := 'Target: [Our Window]`nRelease is disabled.'
                lastX := -999
            } else if (Abs(mX - lastX) > 3 || Abs(mY - lastY) > 3 || A_TickCount - lastTick > 600) {
                tip := UiaPointTip(mX, mY, targetHwnd)
                lastX := mX
                lastY := mY
                lastTick := A_TickCount
            }
            ToolTip(tip)
        }
        Sleep(50)
    }

    UiaHighlighter.Hide()
    ToolTip()
    btnDragTarget.Text := '☉ Drag && Target Window'
    btnDragTarget.Opt('+Background0x1f1f30')

    MouseGetPos(&mX, &mY, &targetHwnd)
    if !targetHwnd
        return

    if UiaIsOurWindow(targetHwnd) {
        MsgBox('Cannot target the Developer Studio or UIA Explorer window itself.', 'Invalid Target', 'Iconi')
        return
    }

    releasedElementStr := ''
    try releasedElementStr := WBHelper.GetUiaElementAtPoint(mX, mY)

    g_targetHwnd := targetHwnd
    title := WinGetTitle('ahk_id ' targetHwnd)
    lblTargetWindow.Value := 'Target: ' title ' (ahk_id ' targetHwnd ')'

    LoadUiaTree(targetHwnd)

    ; Auto-select released element in tree!
    if (releasedElementStr != '') {
        parts := StrSplit(releasedElementStr, '|')
        if (parts.Length >= 5) {
            elName := parts[1]
            elType := parts[2]
            elId := parts[3]
            elClassName := parts[4]

            bestNode := 0
            for nodeID, meta in g_uiaNodeMetadata {
                if (meta.type == elType) {
                    if (elId != '' && meta.id == elId) {
                        bestNode := nodeID
                        break
                    }
                    if (elName != '' && meta.name == elName) {
                        bestNode := nodeID
                        break
                    }
                    if (elClassName != '' && meta.className == elClassName) {
                        bestNode := nodeID
                    }
                    if (!bestNode) {
                        bestNode := nodeID
                    }
                }
            }

            if (bestNode) {
                tvUia.Modify(bestNode, 'Select Vis')
            }
        }
    }
}

LoadUiaTree(hwnd) {
    global tvUia, g_uiaNodeMetadata, gUiaExplorer
    tvUia.Delete()
    g_uiaNodeMetadata := Map()

    SetStatus('Reading the UI Automation tree...')
    WB_Repaint(gUiaExplorer.Hwnd)

    treeStr := ''
    try {
        treeStr := WBHelper.GetUiaTree(hwnd)
    } catch as ex {
        MsgBox('Failed to query UIA tree: ' ex.Message, 'UIA Explorer Error', 'Iconx')
        return
    }

    if (SubStr(treeStr, 1, 6) == 'ERROR:') {
        MsgBox('Failed to retrieve UIA tree: ' treeStr, 'UIA Explorer Error', 'Iconx')
        return
    }

    truncated := false
    parentMap := Map()
    parentMap[0] := 0

    tvUia.Opt('-Redraw')
    Loop Parse, treeStr, '`n', '`r' {
        if (Trim(A_LoopField) == '')
            continue
        if (SubStr(A_LoopField, 1, 10) == '#TRUNCATED') {     ; the helper hit its node/time cap
            truncated := true
            continue
        }
        parts := StrSplit(A_LoopField, '|')
        if (parts.Length < 5)
            continue

        depth := Integer(parts[1])
        name := parts[2]
        type := parts[3]
        id := parts[4]
        className := parts[5]

        rectStr := ''
        if (parts.Length >= 6) {
            rectStr := parts[6]
        }

        displayText := type
        if (name != '')
            displayText .= ' : "' name '"'
        else if (id != '')
            displayText .= ' [ID: ' id ']'
        else if (className != '')
            displayText .= ' (Class: ' className ')'

        parentID := 0
        if (depth > 0 && parentMap.Has(depth - 1)) {
            parentID := parentMap[depth - 1]
        }

        nodeID := tvUia.Add(displayText, parentID, (depth == 0 ? 'Expand' : ''))
        g_uiaNodeMetadata[nodeID] := { name: name, type: type, id: id, className: className, rect: rectStr }
        parentMap[depth] := nodeID
    }
    tvUia.Opt('+Redraw')

    if (truncated)
        SetStatus('UIA tree truncated at ' g_uiaNodeMetadata.Count ' elements (node/time limit) — target a smaller pane for the rest')
    else
        SetStatus('UIA tree loaded — ' g_uiaNodeMetadata.Count ' elements')
}

OnTvUiaSelect(ctrl, itemID) {
    global g_uiaNodeMetadata, lvProps, edCodePreview, g_targetHwnd, g_UiaHideTimer, ddlUiaAction, ddlUiaTarget, ddlUiaTraverse
    if (!g_uiaNodeMetadata.Has(itemID))
        return
        
    meta := g_uiaNodeMetadata[itemID]
    
    lvProps.Delete()
    lvProps.Add(, 'ControlType', meta.type)
    lvProps.Add(, 'Name', meta.name)
    lvProps.Add(, 'AutomationId', meta.id)
    lvProps.Add(, 'ClassName', meta.className)
    
    if (meta.HasProp('rect') && meta.rect != '') {
        lvProps.Add(, 'BoundingRect', meta.rect)
        
        rectParts := StrSplit(meta.rect, ',')
        if (rectParts.Length == 4) {
            rX := Integer(rectParts[1])
            rY := Integer(rectParts[2])
            rW := Integer(rectParts[3])
            rH := Integer(rectParts[4])
            
            if (rW > 0 && rH > 0) {
                UiaHighlighter.Show(rX, rY, rW, rH)
                SetTimer(g_UiaHideTimer, -2000)
            } else {
                UiaHighlighter.Hide()
                SetTimer(g_UiaHideTimer, 0)
            }
        } else {
            UiaHighlighter.Hide()
            SetTimer(g_UiaHideTimer, 0)
        }
    } else {
        UiaHighlighter.Hide()
        SetTimer(g_UiaHideTimer, 0)
    }
}

OnSearchTree(*) {
    global edTreeSearch, tvUia, g_uiaNodeMetadata, g_lastSearchText, g_lastSearchNodeID
    
    searchText := Trim(edTreeSearch.Value)
    if (searchText == '') {
        return
    }
    
    if (searchText != g_lastSearchText) {
        g_lastSearchText := searchText
        g_lastSearchNodeID := 0
    }
    
    foundNode := 0
    startSearching := (g_lastSearchNodeID == 0)
    
    Loop 2 {
        for nodeID, meta in g_uiaNodeMetadata {
            if (!startSearching) {
                if (nodeID == g_lastSearchNodeID) {
                    startSearching := true
                }
                continue
            }
            
            if (InStr(meta.name, searchText) || InStr(meta.type, searchText) || InStr(meta.id, searchText) || InStr(meta.className, searchText)) {
                foundNode := nodeID
                break 2
            }
        }
        startSearching := true
        g_lastSearchNodeID := 0
    }
    
    if (foundNode) {
        g_lastSearchNodeID := foundNode
        tvUia.Modify(foundNode, 'Select Vis')
        ControlFocus(tvUia.Hwnd, gUiaExplorer)
    } else {
        MsgBox('No matches found for "' searchText '"', 'Search UIA Tree', 'Iconi')
        g_lastSearchNodeID := 0
    }
}

OnAddCurrentStep(*) {
    global tvUia, g_uiaNodeMetadata
    selectedItem := tvUia.GetSelection()
    if (!selectedItem || !g_uiaNodeMetadata.Has(selectedItem)) {
        MsgBox("Please select an element in the UIA Hierarchy first.", "No Selection", "Iconi")
        return
    }
    meta := g_uiaNodeMetadata[selectedItem]
    
    AddStepMenu := Menu()
    
    WindowSubmenu := Menu()
    WindowSubmenu.Add("Click/Invoke", (itemName, *) => PushedCurrentStep(meta, "Click/Invoke", "Window"))
    WindowSubmenu.Add("Mouse Click (Physical)", (itemName, *) => PushedCurrentStep(meta, "Mouse Click", "Window"))
    WindowSubmenu.Add("Send Enter Key", (itemName, *) => PushedCurrentStep(meta, "Send Enter Key", "Window"))
    WindowSubmenu.Add("Send Space Key", (itemName, *) => PushedCurrentStep(meta, "Send Space Key", "Window"))
    WindowSubmenu.Add("Focus Element", (itemName, *) => PushedCurrentStep(meta, "Focus Element", "Window"))
    WindowSubmenu.Add("Set Value (Text)", (itemName, *) => PushedCurrentStep(meta, "Set Value", "Window"))
    WindowSubmenu.Add("Query Info Only", (itemName, *) => PushedCurrentStep(meta, "Query Info", "Window"))
    
    ContextSubmenu := Menu()
    ContextSubmenu.Add("Click/Invoke", (itemName, *) => PushedCurrentStep(meta, "Click/Invoke", "Context"))
    ContextSubmenu.Add("Mouse Click (Physical)", (itemName, *) => PushedCurrentStep(meta, "Mouse Click", "Context"))
    ContextSubmenu.Add("Send Enter Key", (itemName, *) => PushedCurrentStep(meta, "Send Enter Key", "Context"))
    ContextSubmenu.Add("Send Space Key", (itemName, *) => PushedCurrentStep(meta, "Send Space Key", "Context"))
    ContextSubmenu.Add("Focus Element", (itemName, *) => PushedCurrentStep(meta, "Focus Element", "Context"))
    ContextSubmenu.Add("Set Value (Text)", (itemName, *) => PushedCurrentStep(meta, "Set Value", "Context"))
    ContextSubmenu.Add("Query Info Only", (itemName, *) => PushedCurrentStep(meta, "Query Info", "Context"))
    
    AddStepMenu.Add("Find from Window Root", WindowSubmenu)
    AddStepMenu.Add("Find from Current Element Context", ContextSubmenu)
    AddStepMenu.Show()
}

PushedCurrentStep(meta, actionName, searchRoot := "Window") {
    global g_automationSteps
    csharpType := RegExReplace(meta.type, "^ControlType\.", "")
    detailStr := csharpType
    if (meta.name != "")
        detailStr .= ': "' meta.name '"'
    else if (meta.id != "")
        detailStr .= ' [ID: ' meta.id ']'
    else if (meta.className != "")
        detailStr .= ' (Class: ' meta.className ')'
        
    scopeLabel := (searchRoot == "Context") ? "↳ Sub-find: " : ""
    
    g_automationSteps.Push({
        type: "Find Element",
        detail: scopeLabel . detailStr,
        action: actionName,
        post: "None",
        name: meta.name,
        ctrlType: meta.type,
        id: meta.id,
        className: meta.className,
        searchRoot: searchRoot
    })
    UpdateStepsListView()
    RegenerateScriptCode()
}

OnAddCustomStep(*) {
    AddCustomMenu := Menu()
    
    ; Traversal submenu
    TraverseMenu := Menu()
    TraverseMenu.Add("Up to Parent", (itemName, *) => PushedCustomStep("Traverse", "Up to Parent"))
    TraverseMenu.Add("Up to TabItem", (itemName, *) => PushedCustomStep("Traverse", "Up to TabItem"))
    TraverseMenu.Add("Up to Window", (itemName, *) => PushedCustomStep("Traverse", "Up to Window"))
    TraverseMenu.Add("Up to Pane", (itemName, *) => PushedCustomStep("Traverse", "Up to Pane"))
    TraverseMenu.Add("Up to Document", (itemName, *) => PushedCustomStep("Traverse", "Up to Document"))
    TraverseMenu.Add("Up to Group", (itemName, *) => PushedCustomStep("Traverse", "Up to Group"))
    AddCustomMenu.Add("Traversal Upwards", TraverseMenu)
    
    ; Delay submenu
    DelayMenu := Menu()
    DelayMenu.Add("Wait 500ms", (itemName, *) => PushedCustomStep("Delay", "Wait 500ms"))
    DelayMenu.Add("Wait 1 Second", (itemName, *) => PushedCustomStep("Delay", "Wait 1 Second"))
    DelayMenu.Add("Wait 2 Seconds", (itemName, *) => PushedCustomStep("Delay", "Wait 2 Seconds"))
    AddCustomMenu.Add("Delay / Sleep", DelayMenu)
    
    ; Target submenu
    TargetMenu := Menu()
    TargetMenu.Add("Deep Scan (incl. Minimized)", (itemName, *) => PushedCustomStep("Window Target", "Deep Scan (incl. Minimized)"))
    TargetMenu.Add("Background Scan", (itemName, *) => PushedCustomStep("Window Target", "Background Scan"))
    TargetMenu.Add("Active Window", (itemName, *) => PushedCustomStep("Window Target", "Active Window"))
    TargetMenu.Add("Static HWND", (itemName, *) => PushedCustomStep("Window Target", "Static HWND"))
    AddCustomMenu.Add("Change Window Target", TargetMenu)
    
    AddCustomMenu.Show()
}

PushedCustomStep(type, detail) {
    global g_automationSteps
    
    if (type == "Traverse") {
        ModeMenu := Menu()
        ModeMenu.Add("Change Active Context (CD)", (itemName, *) => ShowTraverseActions(detail, "CD"))
        ModeMenu.Add("Action Only (Keep Context)", (itemName, *) => ShowTraverseActions(detail, "ActionOnly"))
        ModeMenu.Show()
        return
    }
    
    g_automationSteps.Push({
        type: type,
        detail: detail,
        action: "None",
        post: "None"
    })
    UpdateStepsListView()
    RegenerateScriptCode()
}

ShowTraverseActions(detail, traverseMode) {
    ActionMenu := Menu()
    if (traverseMode == "CD") {
        ActionMenu.Add("None (Just CD)", (itemName, *) => PushTraverseWithModeAction(detail, traverseMode, "None"))
    }
    ActionMenu.Add("Click/Invoke", (itemName, *) => PushTraverseWithModeAction(detail, traverseMode, "Click/Invoke"))
    ActionMenu.Add("Mouse Click (Physical)", (itemName, *) => PushTraverseWithModeAction(detail, traverseMode, "Mouse Click"))
    ActionMenu.Add("Send Enter Key", (itemName, *) => PushTraverseWithModeAction(detail, traverseMode, "Send Enter Key"))
    ActionMenu.Add("Send Space Key", (itemName, *) => PushTraverseWithModeAction(detail, traverseMode, "Send Space Key"))
    ActionMenu.Add("Focus Element", (itemName, *) => PushTraverseWithModeAction(detail, traverseMode, "Focus Element"))
    ActionMenu.Show()
}

PushTraverseWithModeAction(detail, traverseMode, action) {
    global g_automationSteps, tvUia, g_uiaNodeMetadata
    
    ; Auto-insert Find Element step if active context is still the Window Target,
    ; but the user has an element selected in the tree hierarchy!
    if (g_automationSteps.Length == 1 && g_automationSteps[1].type == "Window Target") {
        selectedItem := tvUia.GetSelection()
        if (selectedItem && g_uiaNodeMetadata.Has(selectedItem)) {
            meta := g_uiaNodeMetadata[selectedItem]
            csharpType := RegExReplace(meta.type, "^ControlType\.", "")
            detailStr := csharpType
            if (meta.name != "")
                detailStr .= ': "' meta.name '"'
            else if (meta.id != "")
                detailStr .= ' [ID: ' meta.id ']'
            else if (meta.className != "")
                detailStr .= ' (Class: ' meta.className ')'
                
            g_automationSteps.Push({
                type: "Find Element",
                detail: detailStr,
                action: "None",
                post: "None",
                name: meta.name,
                ctrlType: meta.type,
                id: meta.id,
                className: meta.className,
                searchRoot: "Window"
            })
        }
    }
    
    modeLabel := (traverseMode == "CD") ? " ↳ CD" : " ↳ ActOnly"
    
    g_automationSteps.Push({
        type: "Traverse",
        detail: detail . modeLabel,
        action: action,
        post: "None",
        traverseMode: traverseMode,
        traverseType: detail
    })
    UpdateStepsListView()
    RegenerateScriptCode()
}

OnRemoveStep(*) {
    global lvSteps, g_automationSteps
    selectedRow := lvSteps.GetNext()
    if (!selectedRow) {
        MsgBox("Please select a step in the automation steps list to remove.", "No Selection", "Iconi")
        return
    }
    RemoveStepByIndex(selectedRow)
}

OnStepsContextMenu(ctrl, itemIndex, isRightClick, x, y) {
    if (!itemIndex)
        return
        
    StepsMenu := Menu()
    StepsMenu.Add("Move Step Up", (itemName, *) => MoveStep(itemIndex, -1))
    StepsMenu.Add("Move Step Down", (itemName, *) => MoveStep(itemIndex, 1))
    StepsMenu.Add("Remove Step", (itemName, *) => RemoveStepByIndex(itemIndex))
    
    ; Disable move up if first item (index 1 is Window Target, which should always be first)
    if (itemIndex <= 2) {
        StepsMenu.Disable("Move Step Up")
    }
    if (itemIndex == g_automationSteps.Length) {
        StepsMenu.Disable("Move Step Down")
    }
    
    StepsMenu.Show()
}

MoveStep(itemIndex, direction) {
    global g_automationSteps
    targetIndex := itemIndex + direction
    if (targetIndex < 2 || targetIndex > g_automationSteps.Length)
        return
        
    ; Swap items
    temp := g_automationSteps[itemIndex]
    g_automationSteps[itemIndex] := g_automationSteps[targetIndex]
    g_automationSteps[targetIndex] := temp
    
    UpdateStepsListView()
    RegenerateScriptCode()
    
    ; Maintain selection on the moved item
    global lvSteps
    lvSteps.Modify(targetIndex, "Select Focus")
}

RemoveStepByIndex(itemIndex) {
    global g_automationSteps
    if (itemIndex == 1) {
        MsgBox("Cannot remove the initial Window Target step.", "Protected Step", "Iconi")
        return
    }
    g_automationSteps.RemoveAt(itemIndex)
    UpdateStepsListView()
    RegenerateScriptCode()
}

UpdateStepsListView() {
    global lvSteps, g_automationSteps
    lvSteps.Delete()
    for index, step in g_automationSteps {
        lvSteps.Add(, "Step " index ": " step.type, step.detail, step.action)
    }
}

; ═══════════════════════════════════════════════════════════════════════════════
; UIA HIGHLIGHTER OVERLAY SERVICE
; ═══════════════════════════════════════════════════════════════════════════════

class UiaHighlighter {
    static borders := []
    
    static Show(x, y, w, h) {
        if (this.borders.Length == 0) {
            Loop 4 {
                b := Gui("-Caption +AlwaysOnTop +ToolWindow +Disabled -DPIScale +E0x20")
                b.BackColor := "0x00d4ff"
                this.borders.Push(b)
            }
        }
        
        if (w <= 0 || h <= 0) {
            this.Hide()
            return
        }
        
        thickness := 4
        
        ; Top border
        this.borders[1].Show("x" x " y" y " w" w " h" thickness " NoActivate")
        ; Bottom border
        this.borders[2].Show("x" x " y" (y + h - thickness) " w" w " h" thickness " NoActivate")
        ; Left border
        this.borders[3].Show("x" x " y" y " w" thickness " h" h " NoActivate")
        ; Right border
        this.borders[4].Show("x" (x + w - thickness) " y" y " w" thickness " h" h " NoActivate")
    }
    
    static Hide() {
        for b in this.borders {
            try b.Hide()
        }
    }
}
