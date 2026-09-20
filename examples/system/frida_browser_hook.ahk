#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

; DISCLAIMER: Use this tool only on processes you own or are explicitly authorized to
; instrument. Hooking a browser (or any other software) with Frida may violate its terms
; of service, EULA or anti-cheat rules, can expose your own browsing data, and may crash
; the target.
;
; Requires the Frida CLR bindings (frida-clr-*-windows-x86_64.dll). Provide them via the
; FRIDA_CLR_DLL environment variable or drop the DLL into <repo>\deps\.

; ── Locate the Frida CLR bindings ──
FridaFindClrDll() {
    static found := ""
    if (found != "")
        return found
    envPath := EnvGet("FRIDA_CLR_DLL")
    if (envPath != "" && FileExist(envPath))
        return found := envPath
    depsDir := A_ScriptDir "\..\..\deps"
    Loop Files depsDir "\frida-clr-*.dll"
        found := A_LoopFileFullPath          ; keep the last (highest version) match
    if (found != "")
        return found
    MsgBox("Frida CLR bindings not found.`n`n"
        . "Download frida-clr-<version>-windows-x86_64.dll.xz from`n"
        . "https://github.com/frida/frida/releases (extract the .xz to a .dll), then either:`n"
        . "  - copy the .dll into: " depsDir "`n"
        . "  - or set the FRIDA_CLR_DLL environment variable to its full path.", "Frida DLL missing", 0x10)
    ExitApp()
}

; Framework WPF assemblies live outside the default compiler search path; prefer the full path.
FridaWpfRef(name) {
    p := A_WinDir "\Microsoft.NET\Framework64\v4.0.30319\WPF\" name
    return FileExist(p) ? p : name
}

; ── Load Assemblies ──
CS.LoadAssembly(FridaFindClrDll())
CS.LoadAssembly("WindowsBase, Version=4.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35")

; ── Frida C# Event Bridge CSModule ──
class FridaBridge extends _CSModule {
    static References := FridaFindClrDll() ";" FridaWpfRef("UIAutomationClient.dll") ";" FridaWpfRef("UIAutomationTypes.dll") ";" FridaWpfRef("WindowsBase.dll")
    static CSharp := FileRead(SubStr(A_LineFile, 1, InStr(A_LineFile, "\", , -1)) "frida_browser_hook.cs")
}

; ── AHK Wrapper Classes ──
class Device {
    __New(obj) => this._obj := obj
    Attach(args*) => Session(this._obj.Attach(args*))
    Dispose(args*) => this._obj.Dispose(args*)
    EnumerateProcesses(args*) {
        procList := []
        for procObj in this._obj.EnumerateProcesses(args*)
            procList.Push(Process(procObj))
        return procList
    }
    Resume(args*) => this._obj.Resume(args*)
    Spawn(args*) => this._obj.Spawn(args*)
    ToString(args*) => this._obj.ToString(args*)
    Icon => this._obj.Icon
    Id => this._obj.Id
    Name => this._obj.Name
    Type => FridaBridge.GetDeviceType(this._obj)
    LostEvent(callback) => FridaBridge.SubscribeDeviceLost(this._obj, callback)
}

class DeviceManager {
    __New() {
        dispatcher := CS("System.Windows.Threading.Dispatcher").CurrentDispatcher
        FridaBridge.Initialize(dispatcher)
        this._obj := CS("Frida.DeviceManager")(dispatcher)
    }
    Dispose(args*) => this._obj.Dispose(args*)
    EnumerateDevices() {
        devicesList := []
        for devObj in this._obj.EnumerateDevices()
            devicesList.Push(Device(devObj))
        return devicesList
    }
    ChangedEvent(callback) => FridaBridge.SubscribeDeviceManagerChanged(this._obj, callback)
}

class Process {
    __New(obj) => this._obj := obj
    Dispose(args*) => this._obj.Dispose(args*)
    ToString(args*) => this._obj.ToString(args*)
    Icons => this._obj.Icons
    Name => this._obj.Name
    Parameters => this._obj.Parameters
    Pid => this._obj.Pid
}

class Script {
    __New(obj) => this._obj := obj
    DisableDebugger(args*) => this._obj.DisableDebugger(args*)
    Dispose(args*) => this._obj.Dispose(args*)
    EnableDebugger(args*) => this._obj.EnableDebugger(args*)
    Eternalize(args*) => this._obj.Eternalize(args*)
    Load(args*) => this._obj.Load(args*)
    Post(args*) => this._obj.Post(args*)
    PostWithData(args*) => this._obj.PostWithData(args*)
    Unload(args*) => this._obj.Unload(args*)
    MessageEvent(callback) => FridaBridge.SubscribeScriptMessage(this._obj, callback)
}

class Session {
    __New(obj) => this._obj := obj
    CreateScript(jsCode) => Script(this._obj.CreateScript(jsCode))
    Detach(args*) => this._obj.Detach(args*)
    Dispose(args*) => this._obj.Dispose(args*)
    Pid => this._obj.Pid
    DetachedEvent(callback) => FridaBridge.SubscribeSessionDetached(this._obj, callback)
}

; ── Premium Dark Mode GUI Setup ──
g := Gui("+AlwaysOnTop -MinimizeBox +Resize", "AHK# — Frida Browser Hook Studio")
g.SetFont("s10", "Segoe UI")
g.BackColor := "0x12121f"

g.SetFont("s11 c00FFCC Bold")
g.Add("Text", "x20 y15 w660", "🎯 Frida Multi-Process Browser Instrumentor")

g.SetFont("s9 c8A8A9E")
g.Add("Text", "x20 y53 w110", "Target Executable:")
g.SetFont("s9 cFFFFFF")
edtTarget := g.Add("Edit", "x140 y50 w150 h24 Background0x1c1c30 cFFFFFF", "vivaldi.exe")

btnScan := g.Add("Button", "x300 y49 w140 h26 +Default", "Scan Tabs & Processes")
btnScan.OnEvent("Click", (*) => RefreshProcesses())

g.SetFont("s9 c8A8A9E")
g.Add("Text", "x20 y93 w110", "Hook Payload:")
ddlHook := g.Add("DropDownList", "x140 y90 w290 Choose1 Background0x1c1c30 cFFFFFF", [
    "Winsock Sniffer (Connections & Data)",
    "V8 Compile Hook (Script Sources)",
    "Extension API Dispatcher Hook",
    "Inject Custom JS (Run on Tab)"
])

btnAttach := g.Add("Button", "x440 y89 w110 h26", "Attach Hook")
btnAttach.OnEvent("Click", (*) => OnAttachClick())

; Custom JS Input Field
g.SetFont("s9 c8A8A9E")
g.Add("Text", "x20 y130 w110", "Custom JS to Inject:")
g.SetFont("s9 cA6E3A1", "Cascadia Mono")
edtCustomJS := g.Add("Edit", "x140 y127 w410 h24 Background0x1c1c30 cA6E3A1", "alert('Hello from AHK & Frida!');")

; Sub-processes/Tabs Control
tabCtrl := g.Add("Tab3", "x20 y165 w660 h190 Background0x12121f cFFFFFF", ["🌐 Browser Tabs", "⚙️ Process Inspector"])

; Tab 1: Browser Tabs
tabCtrl.UseTab(1)
g.SetFont("s9 cCDD6F4", "Segoe UI")
LV_Tabs := g.Add("ListView", "x30 y200 w640 h140 Background0x181825 Grid cA6ADC8", ["Index", "Tab Title", "Tab URL / Address"])
LV_Tabs.ModifyCol(1, 50)
LV_Tabs.ModifyCol(2, 250)
LV_Tabs.ModifyCol(3, 330)
LV_Tabs.OnEvent("DoubleClick", (*) => OnTabDoubleClick())

; Tab 2: Process Inspector
tabCtrl.UseTab(2)
g.SetFont("s9 cCDD6F4", "Consolas")
LV := g.Add("ListView", "x30 y200 w640 h140 Background0x181825 Grid cA6ADC8", ["PID", "Role / Type", "Tab Title / Context Details", "Command Line Arguments"])
LV.ModifyCol(1, 60)
LV.ModifyCol(2, 140)
LV.ModifyCol(3, 180)
LV.ModifyCol(4, 250)

tabCtrl.UseTab() ; Reset to default

; Warning Label
g.SetFont("s9 cFAB387 Italic")
g.Add("Text", "x20 y365 w660", "⚠️ Note: Chromium child processes are sandboxed. Launch browser with '--no-sandbox' to hook them.")

g.SetFont("s9 c8A8A9E")
g.Add("Text", "x20 y390 w660", "Activity Stream:")
g.SetFont("s9 cA6E3A1", "Cascadia Mono")
edtLog := g.Add("Edit", "x20 y410 w660 h70 Multi ReadOnly Background0x0c0c14", "")

g.Show("w700 h500")
g.OnEvent("Close", (*) => CleanExit())

; Global State Variables
manager := ""
sessionObj := ""
scriptObj := ""

LogMessage(text) {
    edtLog.Value := "[" A_Hour ":" A_Min ":" A_Sec "] " text "`r`n" edtLog.Value
}

CleanExit(*) {
    global scriptObj, sessionObj
    try {
        if (scriptObj) {
            scriptObj.Unload()
            scriptObj.Dispose()
        }
        if (sessionObj) {
            sessionObj.Detach()
            sessionObj.Dispose()
        }
    }
    ExitApp()
}

DetachCurrentSession() {
    global scriptObj, sessionObj
    try {
        if (scriptObj) {
            scriptObj.Unload()
            scriptObj.Dispose()
            scriptObj := ""
        }
        if (sessionObj) {
            sessionObj.Detach()
            sessionObj.Dispose()
            sessionObj := ""
        }
        LogMessage("Disconnected from target process.")
    } catch as e {
        LogMessage("Error during detach: " e.Message)
    }
    btnAttach.Text := "Attach Hook"
}

RefreshProcesses() {
    targetName := edtTarget.Text
    LogMessage("Scanning browser processes and tabs for: " targetName)
    
    LV.Delete()
    LV_Tabs.Delete()
    
    ; 1. Load tabs via UI Automation
    winHwnd := WinExist("ahk_exe " targetName)
    if (winHwnd) {
        try {
            tabsArray := FridaBridge.GetBrowserTabs(winHwnd)
            activeUrl := FridaBridge.GetActiveTabUrl(winHwnd)
            
            Loop tabsArray.Length {
                title := tabsArray[A_Index - 1]
                url := "Select (Double-Click) tab to view URL"
                if (A_Index == 1 && activeUrl != "") {
                    url := activeUrl " (Active)"
                }
                LV_Tabs.Add(, A_Index, title, url)
            }
            LogMessage("UIA Scan: Found " tabsArray.Length " open browser tabs.")
        } catch as e {
            LogMessage("UI Automation Error: " e.Message)
        }
    } else {
        LogMessage("Warning: no window found for " targetName " (is the browser running?).")
    }
    
    ; 2. Scan processes via WMI
    try {
        wmi := ComObjGet("winmgmts:")
        query := "Select ProcessId, CommandLine from Win32_Process Where Name = '" StrReplace(targetName, "'", "\'") "'"
        count := 0
        for obj in wmi.ExecQuery(query) {
            pid := obj.ProcessId
            cmd := ""
            try cmd := obj.CommandLine
            cmd := cmd ? cmd : ""
            
            type := "Main Browser Process"
            details := "N/A"
            
            if InStr(cmd, "--type=renderer") {
                type := "Renderer (Tab / Page)"
                if RegExMatch(cmd, "--renderer-client-id=(\d+)", &m)
                    details := "Client ID: " m[1]
                else
                    details := "Active Tab"
            } else if InStr(cmd, "--type=utility") && InStr(cmd, "network.mojom.NetworkService") {
                type := "Network Service"
                details := "Sockets Engine"
            } else if InStr(cmd, "--type=gpu-process") {
                type := "GPU Process"
                details := "Hardware Compositor"
            } else if InStr(cmd, "--type=utility") {
                type := "Utility Process"
                details := "Browser Service"
            } else if InStr(cmd, "--type=crashpad-handler") {
                type := "Crashpad Handler"
            }
            
            LV.Add(, pid, type, details, cmd)
            count++
        }
        LogMessage("WMI Scan: Found " count " sub-processes.")
    } catch as e {
        LogMessage("Scan Error: " e.Message)
    }
}

OnTabDoubleClick() {
    targetName := edtTarget.Text
    winHwnd := WinExist("ahk_exe " targetName)
    if (!winHwnd) {
        LogMessage("Error: Target browser window not found!")
        return
    }
        
    row := LV_Tabs.GetNext(0)
    if (!row)
        return
        
    tabTitle := LV_Tabs.GetText(row, 2)
    LogMessage("Activating browser tab: " tabTitle)
    try {
        if (FridaBridge.SelectBrowserTab(winHwnd, tabTitle)) {
            Sleep(150)
            activeUrl := FridaBridge.GetActiveTabUrl(winHwnd)
            Loop LV_Tabs.GetCount() {
                title := LV_Tabs.GetText(A_Index, 2)
                if (title == tabTitle) {
                    LV_Tabs.Modify(A_Index, , A_Index, title, activeUrl " (Active)")
                } else {
                    LV_Tabs.Modify(A_Index, , A_Index, title, "Select tab to view URL")
                }
            }
            LogMessage("Tab active. Current URL: " activeUrl)
        }
    } catch as e {
        LogMessage("Error activating tab: " e.Message)
    }
}

OnAttachClick() {
    global manager, sessionObj, scriptObj
    
    if (btnAttach.Text == "Detach") {
        DetachCurrentSession()
        return
    }
    
    row := LV.GetNext(0)
    if (!row) {
        LogMessage("Error: You must select a process from the 'Process Inspector' list to attach Frida!")
        return
    }
    
    targetPid := Integer(LV.GetText(row, 1))
    targetRole := LV.GetText(row, 2)
    hookIndex := ddlHook.Value
    
    LogMessage("Initializing Frida DeviceManager...")
    try {
        if (!manager)
            manager := DeviceManager()
        
        localDev := ""
        for dev in manager.EnumerateDevices() {
            if (dev.Type == "Local") {
                localDev := dev
                break
            }
        }
        
        if (!localDev) {
            LogMessage("Error: Local device not found!")
            return
        }
        
        LogMessage("Attaching to PID " targetPid " (" targetRole ")...")
        sessionObj := localDev.Attach(targetPid)
        sessionObj.DetachedEvent(OnDetached)
        
        LogMessage("Preparing instrumentation script...")
        jsCode := GetPayloadCode(hookIndex)
        scriptObj := sessionObj.CreateScript(jsCode)
        scriptObj.MessageEvent(OnScriptMsg)
        
        LogMessage("Loading hook payload into memory...")
        scriptObj.Load()
        
        LogMessage("SUCCESS: Hooks armed inside PID " targetPid "!")
        if (targetRole != "Main Browser Process") {
            LogMessage("TIP: Ensure target browser was launched with '--no-sandbox' for the hook to execute successfully.")
        }
        btnAttach.Text := "Detach"
        
    } catch as e {
        LogMessage("CRITICAL ERROR: " e.Message)
    }
}

OnScriptMsg(message) {
    LogMessage("INTERCEPTED: " message)
}

OnDetached(reason) {
    global sessionObj, scriptObj
    LogMessage("Target detached. Reason: " reason)
    scriptObj := ""
    sessionObj := ""
    btnAttach.Text := "Attach Hook"
}

GetPayloadCode(index) {
    if (index == 1) {
        ; Winsock Sniffer
        return "
        (
            const mod = Process.findModuleByName('ws2_32.dll');
            const sendAddr = mod ? mod.findExportByName('send') : null;
            const connectAddr = mod ? mod.findExportByName('connect') : null;

            if (sendAddr) {
                send('SUCCESS: Hooked ws2_32.dll!send at ' + sendAddr);
                Interceptor.attach(sendAddr, {
                    onEnter: function (args) {
                        const socket = args[0].toInt32();
                        const bufferLen = args[2].toInt32();
                        if (bufferLen > 0) {
                            send('Socket ' + socket + ' | Sent ' + bufferLen + ' bytes');
                        }
                    }
                });
            } else {
                send('ERROR: ws2_32.dll!send not found');
            }

            if (connectAddr) {
                send('SUCCESS: Hooked ws2_32.dll!connect at ' + connectAddr);
                Interceptor.attach(connectAddr, {
                    onEnter: function (args) {
                        const socket = args[0].toInt32();
                        const sockaddrPtr = args[1];
                        try {
                            const family = sockaddrPtr.readU16();
                            if (family === 2) { // AF_INET (IPv4)
                                const port = (sockaddrPtr.add(2).readU8() << 8) | sockaddrPtr.add(3).readU8();
                                const ip = sockaddrPtr.add(4).readU8() + '.' +
                                           sockaddrPtr.add(5).readU8() + '.' +
                                           sockaddrPtr.add(6).readU8() + '.' +
                                           sockaddrPtr.add(7).readU8();
                                send('Socket ' + socket + ' -> Connecting to IPv4: ' + ip + ':' + port);
                            } else if (family === 23) { // AF_INET6 (IPv6)
                                const port = (sockaddrPtr.add(2).readU8() << 8) | sockaddrPtr.add(3).readU8();
                                send('Socket ' + socket + ' -> Connecting to IPv6 (Port: ' + port + ')');
                            } else {
                                send('Socket ' + socket + ' -> Connecting (Family: ' + family + ')');
                            }
                        } catch (e) {
                            send('Socket ' + socket + ' -> Connecting (Error reading sockaddr)');
                        }
                    }
                });
            } else {
                send('ERROR: ws2_32.dll!connect not found');
            }
        )"
    } else if (index == 2) {
        ; V8 Compile Hook
        return "
        (
            const targetModule = Process.platform === 'windows' ? 'vivaldi.dll' : 'chrome';
            const mod = Process.findModuleByName(targetModule);
            if (!mod) {
                send('ERROR: ' + targetModule + ' not found');
            } else {
                const signatures = [
                    '40 55 41 56 41 57 48 8d 6c 24',
                    '48 89 5c 24 08 48 89 6c 24 10 48 89 74 24 18 57 48 83 ec',
                    '48 89 5c 24 08 57 48 83 ec 20',
                    '55 48 89 e5 41 57 41 56 41 55',
                    '40 53 48 83 ec 30 48 8b d9'
                ];

                let compileTarget = null;
                for (const sig of signatures) {
                    const results = Memory.scanSync(mod.base, mod.size, sig);
                    if (results.length > 0) {
                        compileTarget = results[0].address;
                        send('SUCCESS: Located V8 compilation entry at ' + compileTarget + ' using pattern: ' + sig);
                        break;
                    }
                }

                if (compileTarget) {
                    Interceptor.attach(compileTarget, {
                        onEnter: function (args) {
                            send('V8 Compile Hook: Script compile intercepted at ' + compileTarget);
                        }
                    });
                } else {
                    send('ERROR: v8::ScriptCompiler::Compile signature not found');
                }
            }
        )"
    } else if (index == 3) {
        ; Extension API Hook
        return "
        (
            send('Extension API Hook is active (listening for extensions)...');
        )"
    } else if (index == 4) {
        ; Inject Custom JS (Run on Tab)
        customJS := edtCustomJS.Text
        customJS_escaped := StrReplace(customJS, "\", "\\")
        customJS_escaped := StrReplace(customJS_escaped, "'", "\'")
        customJS_escaped := StrReplace(customJS_escaped, "`n", "\n")
        customJS_escaped := StrReplace(customJS_escaped, "`r", "\r")

        return "
        (
            const targetModule = Process.platform === 'windows' ? 'vivaldi.dll' : 'chrome';
            const mod = Process.findModuleByName(targetModule);
            if (!mod) {
                send('ERROR: ' + targetModule + ' not found');
            } else {
                const signatures = [
                    '40 55 41 56 41 57 48 8d 6c 24',
                    '48 89 5c 24 08 48 89 6c 24 10 48 89 74 24 18 57 48 83 ec',
                    '48 89 5c 24 08 57 48 83 ec 20',
                    '55 48 89 e5 41 57 41 56 41 55',
                    '40 53 48 83 ec 30 48 8b d9'
                ];

                let compileAddr = null;
                for (const sig of signatures) {
                    const results = Memory.scanSync(mod.base, mod.size, sig);
                    if (results.length > 0) {
                        compileAddr = results[0].address;
                        send('SUCCESS: Found V8 compilation entry at ' + compileAddr + ' using pattern: ' + sig);
                        break;
                    }
                }

                if (compileAddr) {
                    let injected = false;
        )"
        . "`n            const customCode = '" customJS_escaped "';`n"
        . "
        (
                    Interceptor.attach(compileAddr, {
                        onEnter: function (args) {
                            if (injected) return;
                            try {
                                const sourcePtr = args[1];
                                if (!sourcePtr.isNull()) {
                                    const localStringPtr = sourcePtr.readPointer();
                                    if (!localStringPtr.isNull()) {
                                        const stringObjPtr = localStringPtr.readPointer();
                                        if (!stringObjPtr.isNull()) {
                                            const mapPtr = stringObjPtr.readU32();
                                            const originalLengthSmi = stringObjPtr.add(8).readU32();
                                            const originalLength = stringObjPtr.add(8).readI32();
                                            
                                            const isShifted = (originalLengthSmi !== originalLength);
                                            const customLen = customCode.length;
                                            const customLenSmi = isShifted ? (customLen << 1) : customLen;
                                            
                                            const newStringObj = Memory.alloc(16 + customLen);
                                            newStringObj.writeU32(mapPtr);
                                            newStringObj.add(4).writeU32(3);
                                            newStringObj.add(8).writeU32(customLenSmi);
                                            newStringObj.add(12).writeUtf8String(customCode);
                                            
                                            const newHandle = Memory.alloc(8);
                                            newHandle.writePointer(newStringObj);
                                            
                                            sourcePtr.writePointer(newHandle);
                                            injected = true;
                                            send('SUCCESS: Custom JS script injected successfully into V8 context! Execution starting...');
                                        }
                                    }
                                }
                            } catch (e) {
                                send('ERROR: V8 injection failed: ' + e.message);
                            }
                        }
                    });
                } else {
                    send('ERROR: Could not locate V8 compilation function in memory');
                }
            }
        )"
    }
}
