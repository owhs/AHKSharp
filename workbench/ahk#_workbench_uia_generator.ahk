RegenerateScriptCode() {
    global g_automationSteps, edCodePreview, g_targetHwnd
    
    processName := "Unknown"
    try {
        processName := WinGetProcessName("ahk_id " g_targetHwnd)
        processName := RegExReplace(processName, "(?is)\.exe$", "")
    } catch {
        processName := "Unknown"
    }

    code := '// Reference: UIAutomationClient.dll;UIAutomationTypes.dll;WindowsBase.dll;System.Windows.Forms.dll`r`n'
    code .= 'using System;`r`n'
    code .= 'using System.Windows.Automation;`r`n'
    code .= 'using System.Diagnostics;`r`n'
    code .= 'using System.Linq;`r`n'
    code .= 'using System.Collections.Generic;`r`n'
    code .= 'using System.Runtime.InteropServices;`r`n'
    code .= 'using System.Windows;`r`n`r`n'
    code .= 'public static string Run() {`r`n'
    code .= '    var sb = new System.Text.StringBuilder();`r`n'
    code .= '    sb.AppendLine("🤖 Running generated UIA search...");`r`n`r`n'
    code .= '    AutomationElement winEl = null;`r`n'
    code .= '    AutomationElement element = null;`r`n`r`n'
    
    for index, step in g_automationSteps {
        code .= '    // Step ' index ': ' step.type ' (' step.detail ')`r`n'
        code .= '    {`r`n'
        
        if (step.type == "Window Target") {
            targetMode := step.detail
            
            ; Lookahead for next step to find the target element condition
            hasCondition := false
            csharpType := ""
            csharpName := ""
            csharpId := ""
            csharpClassName := ""
            
            if (index < g_automationSteps.Length) {
                nextStep := g_automationSteps[index + 1]
                if (nextStep.type == "Find Element") {
                    hasCondition := true
                    csharpType := RegExReplace(nextStep.ctrlType, "^ControlType\.", "")
                    csharpName := StrReplace(nextStep.name, '"', '\"')
                    csharpId := StrReplace(nextStep.id, '"', '\"')
                    csharpClassName := StrReplace(nextStep.className, '"', '\"')
                }
            }
            
            if (targetMode == "Static HWND") {
                code .= '        IntPtr hwnd = (IntPtr)' g_targetHwnd ';`r`n'
                code .= '        winEl = AutomationElement.FromHandle(hwnd);`r`n'
                code .= '        if (winEl == null) {`r`n'
                code .= '            return "✗ Failed to get Automation Element for HWND: " + hwnd;`r`n'
                code .= '        }`r`n'
            } else if (targetMode == "Active Window") {
                code .= '        var proc = Process.GetProcessesByName("' processName '")`r`n'
                code .= '            .FirstOrDefault(p => p.MainWindowHandle != IntPtr.Zero);`r`n'
                code .= '        if (proc == null) {`r`n'
                code .= '            return "✗ Active process \"' processName '\" with a main window was not found.";`r`n'
                code .= '        }`r`n'
                code .= '        IntPtr hwnd = proc.MainWindowHandle;`r`n'
                code .= '        winEl = AutomationElement.FromHandle(hwnd);`r`n'
                code .= '        if (winEl == null) {`r`n'
                code .= '            return "✗ Failed to get Automation Element for HWND: " + hwnd;`r`n'
                code .= '        }`r`n'
            } else if (targetMode == "Background Scan") {
                code .= '        var procs = Process.GetProcessesByName("' processName '");`r`n'
                code .= '        foreach (var p in procs) {`r`n'
                code .= '            if (p.MainWindowHandle != IntPtr.Zero) {`r`n'
                code .= '                winEl = AutomationElement.FromHandle(p.MainWindowHandle);`r`n'
                code .= '                break;`r`n'
                code .= '            }`r`n'
                code .= '        }`r`n'
                code .= '        if (winEl == null) {`r`n'
                code .= '            return "✗ Could not find any window associated with process \"' processName '\".";`r`n'
                code .= '        }`r`n'
            } else { ; Deep Scan (incl. Minimized)
                code .= '        var procs = Process.GetProcessesByName("' processName '");`r`n'
                code .= '        var procIds = procs.Select(p => p.Id).ToList();`r`n'
                code .= '        if (procIds.Count > 0) {`r`n'
                code .= '            var topWindows = AutomationElement.RootElement.FindAll(TreeScope.Children, Condition.TrueCondition);`r`n'
                code .= '            foreach (AutomationElement w in topWindows) {`r`n'
                code .= '                try {`r`n'
                code .= '                    if (procIds.Contains(w.Current.ProcessId)) {`r`n'
                code .= '                        IntPtr hwnd = (IntPtr)w.Current.NativeWindowHandle;`r`n'
                if (hasCondition) {
                    code .= '                        bool wasMinimized = IsIconic(hwnd);`r`n'
                    code .= '                        if (wasMinimized) {`r`n'
                    code .= '                            ShowWindow(hwnd, SW_SHOWNOACTIVATE);`r`n'
                    code .= '                            System.Threading.Thread.Sleep(300);`r`n'
                    code .= '                        }`r`n'
                    code .= '                        var condList = new List<Condition>();`r`n'
                    code .= '                        condList.Add(new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.' csharpType '));`r`n'
                    if (csharpId != "") {
                        code .= '                        condList.Add(new PropertyCondition(AutomationElement.AutomationIdProperty, "' csharpId '"));`r`n'
                    }
                    if (csharpName != "") {
                        code .= '                        condList.Add(new PropertyCondition(AutomationElement.NameProperty, "' csharpName '"));`r`n'
                    }
                    if (csharpClassName != "") {
                        code .= '                        condList.Add(new PropertyCondition(AutomationElement.ClassNameProperty, "' csharpClassName '"));`r`n'
                    }
                    code .= '                        var cond = new AndCondition(condList.ToArray());`r`n'
                    code .= '                        var found = w.FindFirst(TreeScope.Descendants | TreeScope.Children, cond);`r`n'
                    code .= '                        if (found != null) {`r`n'
                    code .= '                            winEl = w;`r`n'
                    code .= '                            break;`r`n'
                    code .= '                        } else if (wasMinimized) {`r`n'
                    code .= '                            ShowWindow(hwnd, SW_MINIMIZE);`r`n'
                    code .= '                        }`r`n'
                } else {
                    code .= '                        winEl = w;`r`n'
                    code .= '                        if (IsIconic(hwnd)) {`r`n'
                    code .= '                            ShowWindow(hwnd, SW_SHOWNOACTIVATE);`r`n'
                    code .= '                            System.Threading.Thread.Sleep(300);`r`n'
                    code .= '                        }`r`n'
                    code .= '                        break;`r`n'
                }
                code .= '                    }`r`n'
                code .= '                } catch {}`r`n'
                code .= '            }`r`n'
                code .= '        }`r`n'
                code .= '        if (winEl == null) {`r`n'
                code .= '            return "✗ Could not find any matching window for process \"' processName '\".";`r`n'
                code .= '        }`r`n'
            }
            code .= '        element = winEl;`r`n'
            code .= '        sb.AppendLine("✓ Found Window: " + winEl.Current.Name);`r`n'
            
        } else if (step.type == "Find Element") {
            csharpType := RegExReplace(step.ctrlType, "^ControlType\.", "")
            csharpName := StrReplace(step.name, '"', '\"')
            csharpId := StrReplace(step.id, '"', '\"')
            csharpClassName := StrReplace(step.className, '"', '\"')
            
            searchRoot := step.HasProp("searchRoot") ? step.searchRoot : "Window"
            
            if (searchRoot == "Context") {
                code .= '        if (element == null) return "✗ Element context is null. Step ' index ' requires a preceding element context.";`r`n'
                code .= '        var condList = new List<Condition>();`r`n'
                code .= '        condList.Add(new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.' csharpType '));`r`n'
                if (step.id != "") {
                    code .= '        condList.Add(new PropertyCondition(AutomationElement.AutomationIdProperty, "' csharpId '"));`r`n'
                }
                if (step.name != "") {
                    code .= '        condList.Add(new PropertyCondition(AutomationElement.NameProperty, "' csharpName '"));`r`n'
                }
                if (step.className != "") {
                    code .= '        condList.Add(new PropertyCondition(AutomationElement.ClassNameProperty, "' csharpClassName '"));`r`n'
                }
                code .= '        var cond = new AndCondition(condList.ToArray());`r`n'
                code .= '        var subElement = element.FindFirst(TreeScope.Descendants | TreeScope.Children, cond);`r`n'
                code .= '        if (subElement == null) {`r`n'
                code .= '            return sb.ToString() + "✗ Step ' index ': Could not find ' csharpType ' element under the current context.";`r`n'
                code .= '        }`r`n'
                code .= '        element = subElement;`r`n'
                code .= '        sb.AppendLine("✓ Found target element under current context: " + element.Current.Name);`r`n'
            } else {
                code .= '        if (winEl == null) return "✗ WinEl context is null. Step ' index ' requires a preceding Target Window step.";`r`n'
                code .= '        var condList = new List<Condition>();`r`n'
                code .= '        condList.Add(new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.' csharpType '));`r`n'
                if (step.id != "") {
                    code .= '        condList.Add(new PropertyCondition(AutomationElement.AutomationIdProperty, "' csharpId '"));`r`n'
                }
                if (step.name != "") {
                    code .= '        condList.Add(new PropertyCondition(AutomationElement.NameProperty, "' csharpName '"));`r`n'
                }
                if (step.className != "") {
                    code .= '        condList.Add(new PropertyCondition(AutomationElement.ClassNameProperty, "' csharpClassName '"));`r`n'
                }
                code .= '        var cond = new AndCondition(condList.ToArray());`r`n'
                code .= '        element = winEl.FindFirst(TreeScope.Descendants | TreeScope.Children, cond);`r`n'
                code .= '        if (element == null) {`r`n'
                code .= '            return sb.ToString() + "✗ Step ' index ': Could not find ' csharpType ' element.";`r`n'
                code .= '        }`r`n'
                code .= '        sb.AppendLine("✓ Found target element: " + element.Current.Name);`r`n'
            }
            
        } else if (step.type == "Traverse") {
            code .= '        if (element == null) return "✗ Element context is null. Step ' index ' requires a preceding element context.";`r`n'
            code .= '        var walker = TreeWalker.ControlViewWalker;`r`n'
            
            traverseMode := step.HasProp("traverseMode") ? step.traverseMode : "CD"
            traverseType := step.HasProp("traverseType") ? step.traverseType : step.detail
            traverseType := RegExReplace(traverseType, "\s*↳.*$", "")
            
            if (traverseType == "Up to Parent") {
                code .= '        var traversed = walker.GetParent(element);`r`n'
                code .= '        if (traversed == null) {`r`n'
                code .= '            return sb.ToString() + "✗ Step ' index ': Could not traverse to Parent.";`r`n'
                code .= '        }`r`n'
                code .= '        var tempElement = traversed;`r`n'
            } else {
                typeLabel := RegExReplace(traverseType, "^Up to ", "")
                code .= '        var parent = walker.GetParent(element);`r`n'
                code .= '        while (parent != null && parent.Current.ControlType != ControlType.' typeLabel ') {`r`n'
                code .= '            parent = walker.GetParent(parent);`r`n'
                code .= '        }`r`n'
                code .= '        if (parent == null) {`r`n'
                code .= '            return sb.ToString() + "✗ Step ' index ': Could not find ' typeLabel ' ancestor during traversal.";`r`n'
                code .= '        }`r`n'
                code .= '        var tempElement = parent;`r`n'
            }
            
            if (traverseMode == "CD") {
                code .= '        element = tempElement;`r`n'
                code .= '        sb.AppendLine("✓ Traversed and updated active context to: " + element.Current.Name);`r`n'
            } else {
                code .= '        sb.AppendLine("✓ Traversed to ancestor: " + tempElement.Current.Name);`r`n'
            }
            
        } else if (step.type == "Delay") {
            ms := 500
            if (step.detail == "Wait 1 Second")
                ms := 1000
            else if (step.detail == "Wait 2 Seconds")
                ms := 2000
            code .= '        System.Threading.Thread.Sleep(' ms ');`r`n'
            code .= '        sb.AppendLine("✓ Waited ' ms 'ms.");`r`n'
        }
        
        ; Apply actions
        if (step.HasProp("action") && step.action != "None") {
            actionOpt := step.action
            targetVar := "element"
            if (step.type == "Traverse" && step.HasProp("traverseMode") && step.traverseMode == "ActionOnly") {
                targetVar := "tempElement"
            }
            code .= '        if (' targetVar ' == null) return "✗ Element context is null. Action cannot be performed.";`r`n'
            
            if (actionOpt == "Query Info") {
                code .= '        sb.AppendLine("✓ Successfully found target element!");`r`n'
                code .= '        sb.AppendLine("  Name:      " + ' targetVar '.Current.Name);`r`n'
                code .= '        sb.AppendLine("  Type:      " + ' targetVar '.Current.ControlType.ProgrammaticName.Replace("ControlType.", ""));`r`n'
                code .= '        sb.AppendLine("  ID:        " + ' targetVar '.Current.AutomationId);`r`n'
                code .= '        sb.AppendLine("  ClassName: " + ' targetVar '.Current.ClassName);`r`n'
            } else if (actionOpt == "Click/Invoke") {
                code .= '        object pattern;`r`n'
                code .= '        if (' targetVar '.TryGetCurrentPattern(InvokePattern.Pattern, out pattern)) {`r`n'
                code .= '            ((InvokePattern)pattern).Invoke();`r`n'
                code .= '            sb.AppendLine("✓ Successfully clicked element using InvokePattern!");`r`n'
                code .= '        } else if (' targetVar '.TryGetCurrentPattern(SelectionItemPattern.Pattern, out pattern)) {`r`n'
                code .= '            ((SelectionItemPattern)pattern).Select();`r`n'
                code .= '            sb.AppendLine("✓ Successfully selected item using SelectionItemPattern!");`r`n'
                code .= '        } else {`r`n'
                code .= '            try {`r`n'
                code .= '                ' targetVar '.SetFocus();`r`n'
                code .= '                sb.AppendLine("✓ Fallback: Set focus to element (Invoke/Selection patterns unsupported).");`r`n'
                code .= '            } catch (Exception ex) {`r`n'
                code .= '                sb.AppendLine("✗ Element does not support InvokePattern, SelectionItemPattern, or SetFocus: " + ex.Message);`r`n'
                code .= '            }`r`n'
                code .= '        }`r`n'
            } else if (actionOpt == "Focus Element") {
                code .= '        ' targetVar '.SetFocus();`r`n'
                code .= '        sb.AppendLine("✓ Successfully set focus to the element!");`r`n'
            } else if (actionOpt == "Set Value") {
                code .= '        object pattern;`r`n'
                code .= '        if (' targetVar '.TryGetCurrentPattern(ValuePattern.Pattern, out pattern)) {`r`n'
                code .= '            ((ValuePattern)pattern).SetValue("New Value");`r`n'
                code .= '            sb.AppendLine("✓ Successfully set element value using ValuePattern!");`r`n'
                code .= '        } else {`r`n'
                code .= '            sb.AppendLine("✗ Element does not support ValuePattern.");`r`n'
                code .= '        }`r`n'
            } else if (actionOpt == "Send Enter Key") {
                code .= '        var topHwnd = (IntPtr)winEl.Current.NativeWindowHandle;`r`n'
                code .= '        if (topHwnd != IntPtr.Zero) {`r`n'
                code .= '            if (IsIconic(topHwnd)) {`r`n'
                code .= '                ShowWindow(topHwnd, SW_RESTORE);`r`n'
                code .= '            }`r`n'
                code .= '            SetForegroundWindow(topHwnd);`r`n'
                code .= '            System.Threading.Thread.Sleep(200);`r`n'
                code .= '        }`r`n'
                code .= '        ' targetVar '.SetFocus();`r`n'
                code .= '        System.Threading.Thread.Sleep(100);`r`n'
                code .= '        System.Windows.Forms.SendKeys.SendWait("{ENTER}");`r`n'
                code .= '        sb.AppendLine("✓ Successfully set focus and sent Enter key!");`r`n'
            } else if (actionOpt == "Send Space Key") {
                code .= '        var topHwnd = (IntPtr)winEl.Current.NativeWindowHandle;`r`n'
                code .= '        if (topHwnd != IntPtr.Zero) {`r`n'
                code .= '            if (IsIconic(topHwnd)) {`r`n'
                code .= '                ShowWindow(topHwnd, SW_RESTORE);`r`n'
                code .= '            }`r`n'
                code .= '            SetForegroundWindow(topHwnd);`r`n'
                code .= '            System.Threading.Thread.Sleep(200);`r`n'
                code .= '        }`r`n'
                code .= '        ' targetVar '.SetFocus();`r`n'
                code .= '        System.Threading.Thread.Sleep(100);`r`n'
                code .= '        System.Windows.Forms.SendKeys.SendWait(" ");`r`n'
                code .= '        sb.AppendLine("✓ Successfully set focus and sent Space key!");`r`n'
            } else if (actionOpt == "Mouse Click") {
                code .= '        var topHwnd = (IntPtr)winEl.Current.NativeWindowHandle;`r`n'
                code .= '        if (topHwnd != IntPtr.Zero) {`r`n'
                code .= '            if (IsIconic(topHwnd)) {`r`n'
                code .= '                ShowWindow(topHwnd, SW_RESTORE);`r`n'
                code .= '            }`r`n'
                code .= '            SetForegroundWindow(topHwnd);`r`n'
                code .= '            System.Threading.Thread.Sleep(200);`r`n'
                code .= '        }`r`n'
                code .= '        System.Windows.Point clickPoint;`r`n'
                code .= '        try {`r`n'
                code .= '            clickPoint = ' targetVar '.GetClickablePoint();`r`n'
                code .= '        } catch (NoClickablePointException) {`r`n'
                code .= '            var rect = ' targetVar '.Current.BoundingRectangle;`r`n'
                code .= '            clickPoint = new System.Windows.Point(rect.X + rect.Width / 2, rect.Y + rect.Height / 2);`r`n'
                code .= '        }`r`n'
                code .= '        int clickX = (int)clickPoint.X;`r`n'
                code .= '        int clickY = (int)clickPoint.Y;`r`n'
                code .= '        SetCursorPos(clickX, clickY);`r`n'
                code .= '        System.Threading.Thread.Sleep(50);`r`n'
                code .= '        mouse_event(MOUSEEVENTF_LEFTDOWN, (uint)clickX, (uint)clickY, 0, UIntPtr.Zero);`r`n'
                code .= '        System.Threading.Thread.Sleep(50);`r`n'
                code .= '        mouse_event(MOUSEEVENTF_LEFTUP, (uint)clickX, (uint)clickY, 0, UIntPtr.Zero);`r`n'
                code .= '        sb.AppendLine(string.Format("✓ Successfully performed Mouse Click at ({0}, {1})!", clickX, clickY));`r`n'
            }
        }
        
        code .= '    }`r`n`r`n'
    }
    
    code .= '    return sb.ToString();`r`n'
    code .= '}`r`n`r`n'
    code .= '[DllImport("user32.dll")]`r`n'
    code .= 'private static extern bool SetForegroundWindow(IntPtr hWnd);`r`n`r`n'
    code .= '[DllImport("user32.dll")]`r`n'
    code .= 'private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);`r`n`r`n'
    code .= '[DllImport("user32.dll")]`r`n'
    code .= 'private static extern bool SetCursorPos(int x, int y);`r`n`r`n'
    code .= '[DllImport("user32.dll")]`r`n'
    code .= 'private static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);`r`n`r`n'
    code .= '[DllImport("user32.dll")]`r`n'
    code .= 'private static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);`r`n`r`n'
    code .= 'private const int SW_RESTORE = 9;`r`n'
    code .= 'private const int SW_MINIMIZE = 6;`r`n'
    code .= 'private const int SW_SHOWNOACTIVATE = 4;`r`n'
    code .= 'private const uint MOUSEEVENTF_LEFTDOWN = 0x0002;`r`n'
    code .= 'private const uint MOUSEEVENTF_LEFTUP = 0x0004;`r`n`r`n'
    code .= '[DllImport("user32.dll")]`r`n'
    code .= 'private static extern bool IsIconic(IntPtr hWnd);`r`n'
    
    edCodePreview.Value := code
    return code
}

OnSendToScratchpad(*) {
    global edCodePreview, ddlMode, edCode, customTabs
    code := edCodePreview.Value
    if (code == "") {
        MsgBox("Please select a UIA element with search code generated first.", "No Code to Send", "Iconi")
        return
    }
    
    ; Activate the interactive Scratchpad tab
    OnTabClick(customTabs[TAB_SCRATCH])
    
    ; Set the Mode to "C# Class"
    ddlMode.Choose(MODE_CLASS)
    
    ; Set the code editor value
    edCode.Value := code
    
    ; Focus the code editor
    edCode.Focus()
    
    SetStatus("Transferred UIA search code to Scratchpad")
}
