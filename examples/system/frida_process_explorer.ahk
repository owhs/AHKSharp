#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

; DISCLAIMER: Use this tool only on processes you own or are explicitly authorized to
; instrument. Attaching Frida to other software (games, browsers, security products)
; may violate its terms of service or anti-cheat/EULA rules and can crash the target.
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
class FridaExplorerBridge extends _CSModule {
    static References := FridaFindClrDll() ";" FridaWpfRef("WindowsBase.dll")
    static CSharp := FileRead(SubStr(A_LineFile, 1, InStr(A_LineFile, "\", , -1)) "frida_process_explorer.cs")
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
    Type => FridaExplorerBridge.GetDeviceType(this._obj)
    LostEvent(callback) => FridaExplorerBridge.SubscribeDeviceLost(this._obj, callback)
}

class DeviceManager {
    __New() {
        dispatcher := CS("System.Windows.Threading.Dispatcher").CurrentDispatcher
        FridaExplorerBridge.Initialize(dispatcher)
        this._obj := CS("Frida.DeviceManager")(dispatcher)
    }
    Dispose(args*) => this._obj.Dispose(args*)
    EnumerateDevices() {
        devicesList := []
        for devObj in this._obj.EnumerateDevices()
            devicesList.Push(Device(devObj))
        return devicesList
    }
    ChangedEvent(callback) => FridaExplorerBridge.SubscribeDeviceManagerChanged(this._obj, callback)
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
    MessageEvent(callback) => FridaExplorerBridge.SubscribeScriptMessage(this._obj, callback)
}

class Session {
    __New(obj) => this._obj := obj
    CreateScript(jsCode) => Script(this._obj.CreateScript(jsCode))
    Detach(args*) => this._obj.Detach(args*)
    Dispose(args*) => this._obj.Dispose(args*)
    Pid => this._obj.Pid
    DetachedEvent(callback) => FridaExplorerBridge.SubscribeSessionDetached(this._obj, callback)
}

; ── Premium Dark Mode GUI Setup ──
g := Gui("+AlwaysOnTop -MinimizeBox +Resize", "AHK# — Frida Process Explorer Studio")
g.SetFont("s10", "Segoe UI")
g.BackColor := "0x12121f"

g.SetFont("s11 c00FFCC Bold")
g.Add("Text", "x20 y15 w660", "🔍 Frida System-Wide Process Explorer & Dynamic Instrumentor")

g.SetFont("s9 c8A8A9E")
g.Add("Text", "x20 y53 w90", "Search Process:")
g.SetFont("s9 cFFFFFF")
edtFilter := g.Add("Edit", "x110 y50 w150 h24 Background0x1c1c30 cFFFFFF", "")
edtFilter.OnEvent("Change", (*) => FilterProcesses())

btnRefresh := g.Add("Button", "x270 y49 w110 h26", "Refresh Processes")
btnRefresh.OnEvent("Click", (*) => PopulateProcesses())

btnAttach := g.Add("Button", "x570 y49 w110 h26", "Attach")
btnAttach.OnEvent("Click", (*) => ToggleAttach())

; Tabs Control
tabCtrl := g.Add("Tab3", "x20 y90 w660 h300 Background0x12121f cFFFFFF", ["🔍 Processes", "📦 Modules", "⚙️ Exports & Hooks"])

; Tab 1: Processes list
tabCtrl.UseTab(1)
g.SetFont("s9 cCDD6F4", "Segoe UI")
LV_Proc := g.Add("ListView", "x30 y125 w640 h250 Background0x181825 Grid cA6ADC8", ["PID", "Process Name", "Command Line / Path"])
LV_Proc.ModifyCol(1, 70)
LV_Proc.ModifyCol(2, 180)
LV_Proc.ModifyCol(3, 370)
LV_Proc.OnEvent("DoubleClick", (*) => AutoInspectProcess())

; Tab 2: Modules list
tabCtrl.UseTab(2)
g.SetFont("s9 cCDD6F4", "Segoe UI")
LV_Mod := g.Add("ListView", "x30 y125 w640 h250 Background0x181825 Grid cA6ADC8", ["Module Name", "Base Address", "Size (Bytes)", "Path"])
LV_Mod.ModifyCol(1, 180)
LV_Mod.ModifyCol(2, 110)
LV_Mod.ModifyCol(3, 100)
LV_Mod.ModifyCol(4, 230)
LV_Mod.OnEvent("DoubleClick", (*) => AutoInspectModule())

; Tab 3: Exports & Hooks Console
tabCtrl.UseTab(3)
g.SetFont("s9 c8A8A9E")
g.Add("Text", "x30 y128 w90", "Filter Exports:")
g.SetFont("s9 cFFFFFF")
edtExpFilter := g.Add("Edit", "x120 y125 w150 h24 Background0x1c1c30 cFFFFFF", "")
edtExpFilter.OnEvent("Change", (*) => FilterExports())

g.SetFont("s9 cCDD6F4", "Segoe UI")
LV_Exp := g.Add("ListView", "x30 y155 w310 h220 Background0x181825 Grid cA6ADC8", ["Exported Function", "Address"])
LV_Exp.ModifyCol(1, 180)
LV_Exp.ModifyCol(2, 110)

g.SetFont("s9 c8A8A9E")
g.Add("Text", "x360 y128 w200", "Dynamic Hook Script (JS):")
g.SetFont("s9 cA6E3A1", "Cascadia Mono")
edtHookJS := g.Add("Edit", "x360 y155 w310 h180 Multi Background0x1c1c30 cA6E3A1", "")
SetDefaultScriptTemplate()

btnHook := g.Add("Button", "x360 y345 w150 h26", "Inject/Update Hook")
btnHook.OnEvent("Click", (*) => ApplyCustomHook())

btnUnhook := g.Add("Button", "x520 y345 w150 h26", "Unload Hook")
btnUnhook.OnEvent("Click", (*) => UnloadCurrentHook())

tabCtrl.UseTab() ; Reset

g.SetFont("s9 c8A8A9E")
g.Add("Text", "x20 y400 w660", "Activity Stream & Intercepted Arguments:")
g.SetFont("s9 cA6E3A1", "Cascadia Mono")
edtLog := g.Add("Edit", "x20 y420 w660 h100 Multi ReadOnly Background0x0c0c14", "")

g.Show("w700 h540")
g.OnEvent("Close", (*) => CleanExit())

; Global Variables
manager := ""
deviceObj := ""
sessionObj := ""
scriptObj := ""
attachedPid := 0
processCache := []
moduleCache := []
exportCache := []

LogMessage(text) {
    edtLog.Value := "[" A_Hour ":" A_Min ":" A_Sec "] " text "`r`n" edtLog.Value
}

CleanExit(*) {
    UnloadCurrentHook()
    DetachCurrentSession()
    ExitApp()
}

DetachCurrentSession() {
    global sessionObj, attachedPid
    try {
        if (sessionObj) {
            sessionObj.Detach()
            sessionObj.Dispose()
            sessionObj := ""
        }
        attachedPid := 0
        LogMessage("Disconnected from target process.")
    } catch as e {
        LogMessage("Error detaching session: " e.Message)
    }
    btnAttach.Text := "Attach"
}

UnloadCurrentHook() {
    global scriptObj
    try {
        if (scriptObj) {
            scriptObj.Unload()
            scriptObj.Dispose()
            scriptObj := ""
        }
        LogMessage("Hooks successfully unloaded.")
    } catch as e {
        LogMessage("Error unloading hooks: " e.Message)
    }
}

PopulateProcesses() {
    global manager, deviceObj, processCache
    LogMessage("Scanning system-wide processes...")
    try {
        if (!manager)
            manager := DeviceManager()
        
        if (!deviceObj) {
            for dev in manager.EnumerateDevices() {
                if (dev.Type == "Local") {
                    deviceObj := dev
                    break
                }
            }
        }
        
        if (!deviceObj) {
            LogMessage("Error: Local Frida device not found.")
            return
        }

        ; Query WMI to get paths/commandlines mapped by PID
        pathsMap := Map()
        try {
            wmi := ComObjGet("winmgmts:")
            for procInfo in wmi.ExecQuery("Select ProcessId, ExecutablePath, CommandLine from Win32_Process") {
                pid := procInfo.ProcessId
                path := ""
                try path := procInfo.ExecutablePath
                if (!path) {
                    try path := procInfo.CommandLine
                }
                if (path) {
                    pathsMap[pid] := path
                }
            }
        }

        processCache := []
        for proc in deviceObj.EnumerateProcesses() {
            pid := proc.Pid
            path := pathsMap.Has(pid) ? pathsMap[pid] : "Access Denied / System Process"
            processCache.Push({ pid: pid, name: proc.Name, path: path })
        }

        FilterProcesses()
        LogMessage("Found " processCache.Length " running processes.")
    } catch as e {
        LogMessage("Failed to list processes: " e.Message)
    }
}

FilterProcesses() {
    filter := edtFilter.Text
    LV_Proc.Delete()
    Loop processCache.Length {
        item := processCache[A_Index]
        if (filter == "" || InStr(item.name, filter) || InStr(String(item.pid), filter)) {
            LV_Proc.Add(, item.pid, item.name, item.path)
        }
    }
}

ToggleAttach() {
    global sessionObj, attachedPid
    if (btnAttach.Text == "Detach") {
        DetachCurrentSession()
        return
    }

    row := LV_Proc.GetNext(0)
    if (!row) {
        LogMessage("Error: You must select a process from the 'Processes' list to attach.")
        return
    }

    pid := Integer(LV_Proc.GetText(row, 1))
    name := LV_Proc.GetText(row, 2)

    LogMessage("Attaching to PID " pid " (" name ")...")
    try {
        sessionObj := deviceObj.Attach(pid)
        sessionObj.DetachedEvent(OnSessionDetached)
        attachedPid := pid
        btnAttach.Text := "Detach"
        LogMessage("Attached successfully to PID " pid "!")

        ; Auto switch to Modules tab and list modules
        tabCtrl.Choose(2)
        PopulateModules()
    } catch as e {
        LogMessage("Failed to attach to process: " e.Message)
    }
}

OnSessionDetached(reason) {
    global sessionObj, attachedPid
    LogMessage("Target detached. Reason: " reason)
    sessionObj := ""
    attachedPid := 0
    btnAttach.Text := "Attach"
}

AutoInspectProcess() {
    ToggleAttach()
}

PopulateModules() {
    global sessionObj, moduleCache
    if (!sessionObj) {
        LogMessage("Error: You must attach to a process first.")
        return
    }

    LogMessage("Enumerating process modules...")
    moduleCache := []
    LV_Mod.Delete()

    jsCode := "
    (
        const modules = Process.enumerateModules();
        send({type: 'modules', payload: modules});
    )"

    try {
        tempScript := sessionObj.CreateScript(jsCode)
        tempScript.MessageEvent(OnModulesReceived)
        tempScript.Load()
    } catch as e {
        LogMessage("Failed to load module enumeration helper: " e.Message)
    }
}

OnModulesReceived(message) {
    global moduleCache
    try {
        if InStr(message, '"type":"modules"') {
            rawList := ExtractJSONArray(message)
            if (rawList != "") {
                ; Parse JSON modules array
                moduleCache := []
                pos := 1
                while RegExMatch(rawList, '\{"name":"([^"]+)","base":"([^"]+)","size":(\d+),"path":"([^"]+)"\}', &mod, pos) {
                    name := mod[1]
                    baseAddr := mod[2]
                    size := mod[3]
                    path := StrReplace(mod[4], "\\", "\")
                    moduleCache.Push({ name: name, base: baseAddr, size: size, path: path })
                    pos := mod.Pos + mod.Len
                }

                ; Populate UI listview
                LV_Mod.Delete()
                for item in moduleCache {
                    LV_Mod.Add(, item.name, item.base, item.size, item.path)
                }
                LogMessage("Found " moduleCache.Length " loaded modules.")
            }
        }
    } catch as e {
        LogMessage("Error parsing modules response: " e.Message)
    }
}

AutoInspectModule() {
    row := LV_Mod.GetNext(0)
    if (!row)
        return
    modName := LV_Mod.GetText(row, 1)

    ; Switch to Exports & Hooks and populate
    tabCtrl.Choose(3)
    PopulateExports(modName)
}

PopulateExports(modName) {
    global sessionObj, exportCache
    if (!sessionObj) {
        LogMessage("Error: You must attach to a process first.")
        return
    }

    LogMessage("Enumerating exports for module: " modName "...")
    exportCache := []
    LV_Exp.Delete()

    ; Escape the module name before embedding it in a JS string literal
    jsName := StrReplace(StrReplace(modName, "\", "\\"), "'", "\'")
    ; NOTE: variables are NOT expanded inside a continuation section, so build the script by concatenation
    jsCode := "try {`n"
        . "    const exports = Module.enumerateExports('" jsName "');`n"
        . "    send({type: 'exports', module: '" jsName "', payload: exports});`n"
        . "} catch (e) {`n"
        . "    send({type: 'error', message: e.toString()});`n"
        . "}"

    try {
        tempScript := sessionObj.CreateScript(jsCode)
        tempScript.MessageEvent(OnExportsReceived)
        tempScript.Load()
    } catch as e {
        LogMessage("Failed to load exports helper: " e.Message)
    }
}

OnExportsReceived(message) {
    global exportCache
    try {
        if InStr(message, '"type":"error"') {
            RegExMatch(message, '"message":"([^"]+)"', &m)
            LogMessage("Error: " m[1])
            return
        }

        if InStr(message, '"type":"exports"') {
            rawList := ExtractJSONArray(message)
            if (rawList != "") {
                exportCache := []
                pos := 1
                while RegExMatch(rawList, '\{"type":"[^"]+","name":"([^"]+)","address":"([^"]+)"\}', &exp, pos) {
                    name := exp[1]
                    addr := exp[2]
                    exportCache.Push({ name: name, address: addr })
                    pos := exp.Pos + exp.Len
                }

                FilterExports()
                LogMessage("Found " exportCache.Length " exported functions.")
            }
        }
    } catch as e {
        LogMessage("Error parsing exports response: " e.Message)
    }
}

ExtractJSONArray(jsonStr) {
    start := InStr(jsonStr, "[")
    end := InStr(jsonStr, "]", , -1)
    if (start && end && end > start) {
        return SubStr(jsonStr, start, end - start + 1)
    }
    return ""
}

FilterExports() {
    filter := edtExpFilter.Text
    LV_Exp.Delete()
    for item in exportCache {
        if (filter == "" || InStr(item.name, filter)) {
            LV_Exp.Add(, item.name, item.address)
        }
    }
}

SetDefaultScriptTemplate() {
    edtHookJS.Value := "
    (
        // Enter your custom JavaScript hooks below.
        // Example interceptor attaching to a function:
        const modName = 'ws2_32.dll'; // target module
        const expName = 'send';       // target export name
        
        const target = Module.findExportByName(modName, expName);
        if (target) {
            send('Interception armed at: ' + target);
            Interceptor.attach(target, {
                onEnter: function (args) {
                    const socket = args[0].toInt32();
                    const len = args[2].toInt32();
                    send('Intercepted: send() socket=' + socket + ' bytes=' + len);
                },
                onLeave: function (retval) {
                    // send('Return value: ' + retval);
                }
            });
        } else {
            send('Error: Export not found!');
        }
    )"
}

ApplyCustomHook() {
    global sessionObj, scriptObj
    if (!sessionObj) {
        LogMessage("Error: You must attach to a process first.")
        return
    }

    UnloadCurrentHook()

    jsCode := edtHookJS.Text
    LogMessage("Loading dynamic hook script...")
    try {
        scriptObj := sessionObj.CreateScript(jsCode)
        scriptObj.MessageEvent(OnHookMessageReceived)
        scriptObj.Load()
        LogMessage("Hooks successfully injected & active.")
    } catch as e {
        LogMessage("Failed to inject hook script: " e.Message)
    }
}

OnHookMessageReceived(message) {
    LogMessage("NOTIFICATION: " message)
}

; Initial load of running processes
PopulateProcesses()