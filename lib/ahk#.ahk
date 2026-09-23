;; ═══════════════════════════════════════════════════════════════════════════════
;; AHK#
;; Bridges the entire .NET CLR into AutoHotkey v2 through a fluid, native syntax.
;;
;; Version: 2.0.0
;; CLR Target: v4.0.30319 (C# 4.0 — widest native Windows compatibility)
;; Compatibility: Windows 7 SP1+ / 8 / 8.1 / 10 / 11 (zero install required)
;;
;; Usage:
;;   #Include <ahk#>
;;   result := CS.System.Math.Pow(5, 3)         ; → 125
;;   sb := CS.System.Text.StringBuilder()       ; → new instance
;;   sb.Append("hello").Append(" world")        ; → fluid chaining
;;   text := sb.ToString()                      ; → "hello world"
;;   result := CS.Eval("Math.Sqrt(144)")        ; → 12.0 (one-liner)
;;   IO := CS.Import("System.IO")               ; → namespace alias
;;
;; The CS class, at a glance (docs\15_api_reference.md has the details):
;;   CS.System.…                    any .NET type: static calls, constructors, properties, events
;;   CS.Eval / CS.Run               C# expression / multi-statement body      CS.Fast.Map/Filter/Reduce
;;   CS.Implement(iface, {…})       implement a .NET interface with AHK functions
;;   CS.CallGeneric / CS.Wrap       explicit generic arguments / generate an AHK class for a type
;;   CS.NuGet.Require(…)            download + verify + reference a NuGet package
;;   CS.Promise / proxy.Await()     promises for .Async calls and .NET Tasks
;;   CS.Using / CS.Same / CS.Bool   scoped Dispose / identity / a real .NET bool
;;   CS.ErrorIs(e, "IOException")   typed .NET exceptions (e.NetType, e.NetStack …)
;;   CS.Members / CS.Types          discover: members of a type or object / types in a namespace
;;   CS.Declare("System.IO", …)     write ahk#.d.ahk: completion + hover for those types in VS Code (AutoHotkey v2 LS)
;;   CS.Explain / CS.Config.Trace   see how overloads are chosen / log every call
;;   CS.Stats() / CS.GC()           bridge counters (leak checks) / force a collection
;;   CS.Config.*                    ShowErrorGui, NuGetGui, VerifyBridge, BridgeDll, VerifyNuGet, …
;;
;; ═══════════════════════════════════════════════════════════════════════════════

#Requires AutoHotkey v2.0

;; ── Version Constants ───────────────────────────────────────────────────────
AHK_SHARP_VERSION := "2.0.0"
AHK_SHARP_CLR := "v4.0.30319"

; SHA-256 of lib\ahk#.bridge.dll, written by lib\build.ps1 on every build. Boot() refuses a DLL that does not match
; (CS.Config.VerifyBridge := false turns the check off; AHKSHARP_DEV=1 skips it while you rebuild from src\).
AHK_SHARP_BRIDGE_SHA256 := "d943a9d71a6f18d1c523ee416a53d3a14e0f98ebf4e877a5a09ff71d31dfb582"

;; ── Global Bridge Bootstrap ─────────────────────────────────────────────────

class _AhkSharpEngine {
    static _bridge := ""
    static _clrStarted := false
    static _dllPath := ""
    static _appDomain := ""
    static _callbackHwnd := 0
    static _WM_ASYNC := 0x8001  ; WM_APP+1
    static _WM_PUMP := 0x8003   ; WM_APP+3 (callbacks from .NET worker threads)

    static Boot() {
        if (this._clrStarted)
            return this._bridge

        ; Locate the bridge DLL relative to this script
        scriptDir := RegExReplace(A_LineFile, "\\[^\\]+$", "")
        this._dllPath := _CSConfig.BridgeDll != "" ? _CSConfig.BridgeDll : scriptDir "\ahk#.bridge.dll"

        ; Build when the DLL is missing, or on every start when AHKSHARP_DEV is set
        ; (build.ps1 hashes src\*.cs, so an up-to-date DLL is a ~1s no-op).
        buildScript := scriptDir "\build.ps1"
        if (FileExist(buildScript) && (!FileExist(this._dllPath) || EnvGet("AHKSHARP_DEV") != "")) {
            rc := RunWait('powershell -NoProfile -ExecutionPolicy Bypass -File "' buildScript '"', "", "Hide")
            if (rc != 0)
                throw Error("AHK# bridge build failed (exit code " rc "). Run lib\build.ps1 -Verbose to see the compiler output.")
        }
        if !FileExist(this._dllPath)
            throw Error("AHK# bridge DLL not found: " this._dllPath "`nRun lib\build.ps1 first.")

        ; Integrity: the DLL must be the one this ahk#.ahk was built with
        if (AHK_SHARP_BRIDGE_SHA256 != "" && _CSConfig.VerifyBridge && EnvGet("AHKSHARP_DEV") == "") {
            actual := this._FileSha256(this._dllPath)
            if (actual != AHK_SHARP_BRIDGE_SHA256)
                throw Error("AHK# bridge DLL does not match the hash pinned in ahk#.ahk — refusing to load it.`n"
                    . "  expected " AHK_SHARP_BRIDGE_SHA256 "`n  found    " actual "`n"
                    . "Rebuild it with lib\build.ps1 -Force, restore the original file, or set CS.Config.VerifyBridge := false.")
        }

        ; ── Bootstrap CLR v4.0 via ICorRuntimeHost ────────────────────────
        ; CLSID_CorRuntimeHost = {CB2F6723-AB3A-11D2-9C40-00C04FA30A3E}
        ; IID_ICorRuntimeHost  = {CB2F6722-AB3A-11D2-9C40-00C04FA30A3E}
        CLSID := Buffer(16), IID := Buffer(16)
        DllCall("ole32\CLSIDFromString", "WStr", "{CB2F6723-AB3A-11D2-9C40-00C04FA30A3E}", "Ptr", CLSID)
        DllCall("ole32\CLSIDFromString", "WStr", "{CB2F6722-AB3A-11D2-9C40-00C04FA30A3E}", "Ptr", IID)

        hr := DllCall("mscoree\CorBindToRuntimeEx"
            , "WStr", "v4.0.30319"  ; MUST specify v4.0 — null loads v2.0!
            , "Ptr", 0              ; workstation build flavor
            , "UInt", 0             ; startup flags
            , "Ptr", CLSID, "Ptr", IID
            , "Ptr*", &pHost := 0, "Int")
        if (hr < 0)
            throw Error("CorBindToRuntimeEx failed: " Format("0x{:08X}", hr))

        ComCall(10, pHost, "Int")   ; ICorRuntimeHost::Start
        ComCall(13, pHost, "Ptr*", &pDomain := 0, "Int")  ; GetDefaultDomain

        ; Wrap as VT_DISPATCH directly — do NOT QI for _AppDomain (has stub methods)
        this._appDomain := ComValue(9, pDomain)

        ; ── Load bridge DLL via Assembly.Load(byte[]) reflection ──────────
        ; Path: AppDomain.GetType().Assembly → mscorlib → GetType_2("System.Reflection.Assembly")
        ;   → InvokeMember_3("Load", ..., byteArray) → loaded Assembly
        domType := this._appDomain.GetType()
        mscorlib := domType.Assembly
        asmType := mscorlib.GetType_2("System.Reflection.Assembly")

        ; Read the bridge DLL into a COM byte array (VT_UI1 SafeArray)
        bytes := this._FileToByteArray(this._dllPath)

        ; Load via reflection: Assembly.Load(byte[])
        static nullObj := ComValue(13, 0)
        loadArgs := ComObjArray(0xC, 1)
        loadArgs[0] := bytes
        bridgeAsm := asmType.InvokeMember_3("Load", 0x158, nullObj, nullObj, loadArgs)

        ; Create the bridge singleton
        this._bridge := bridgeAsm.CreateInstance("AhkSharpBridge")
        this._clrStarted := true

        ; Store reflection references for RuntimeCompiler
        this._mscorlib := mscorlib
        this._asmType := asmType

        ; Set up async callback receiver
        this._SetupAsyncReceiver()

        return this._bridge
    }

    ; ── Assembly Loading (via proven reflection path) ─────────────────────
    static _CLR_LoadLibrary(assemblyPath, appDomain := 0) {
        ; For file paths, read bytes and use Assembly.Load(byte[]) via reflection
        if (FileExist(assemblyPath)) {
            bytes := this._FileToByteArray(assemblyPath)
            static nullObj := ComValue(13, 0)
            loadArgs := ComObjArray(0xC, 1)
            loadArgs[0] := bytes
            return this._asmType.InvokeMember_3("Load", 0x158, nullObj, nullObj, loadArgs)
        }

        throw Error("Assembly not found: " assemblyPath)
    }

    ; SHA-256 of a file via Windows CNG (bcrypt.dll — available since Vista)
    static _FileSha256(path) {
        f := FileOpen(path, "r")
        size := f.Length
        buf := Buffer(size)
        f.RawRead(buf, size)
        f.Close()
        hAlg := hHash := 0
        DllCall("bcrypt\BCryptOpenAlgorithmProvider", "Ptr*", &hAlg, "WStr", "SHA256", "Ptr", 0, "UInt", 0, "UInt")
        DllCall("bcrypt\BCryptCreateHash", "Ptr", hAlg, "Ptr*", &hHash, "Ptr", 0, "UInt", 0, "Ptr", 0, "UInt", 0, "UInt", 0, "UInt")
        DllCall("bcrypt\BCryptHashData", "Ptr", hHash, "Ptr", buf, "UInt", size, "UInt", 0, "UInt")
        digest := Buffer(32)
        DllCall("bcrypt\BCryptFinishHash", "Ptr", hHash, "Ptr", digest, "UInt", 32, "UInt", 0, "UInt")
        DllCall("bcrypt\BCryptDestroyHash", "Ptr", hHash)
        DllCall("bcrypt\BCryptCloseAlgorithmProvider", "Ptr", hAlg, "UInt", 0)
        hex := ""
        Loop 32
            hex .= Format("{:02x}", NumGet(digest, A_Index - 1, "UChar"))
        return hex
    }

    ; File → VT_UI1 SafeArray (byte[]) with a single memcpy
    static _FileToByteArray(path) {
        fileObj := FileOpen(path, "r")
        size := fileObj.Length
        buf := Buffer(size)
        fileObj.RawRead(buf, size)
        fileObj.Close()
        return _BufferToByteArray(buf, size)
    }

    static _SetupAsyncReceiver() {
        ; Create a hidden window to receive async completion messages
        static receiver := Gui()
        this._callbackHwnd := receiver.Hwnd
        callback := ObjBindMethod(this, "_OnAsyncComplete")
        OnMessage(this._WM_ASYNC, callback)

        ; .NET worker threads that call AHK functions wake the AHK thread with this message
        this._bridge.SetAhkWindow(receiver.Hwnd, this._WM_PUMP)
        this._bridge.SetCallbackTimeout(_CSConfig.CallbackTimeoutMs)
        OnMessage(this._WM_PUMP, ObjBindMethod(this, "_OnPump"))
    }

    ; OnMessage sees these message numbers for EVERY window on the thread, and
    ; returning a value swallows the message. WM_APP+n is used by other windows
    ; too (the WebBrowser control's own navigation among them), so only the
    ; receiver's messages are ours: anything else returns nothing and goes on
    ; to its window untouched.
    static _OnPump(wParam, lParam, msg, hwnd) {
        if (hwnd != this._callbackHwnd)
            return
        try this._bridge.PumpCallbacks()
        return 0
    }

    static _OnAsyncComplete(wParam, lParam, msg, hwnd) {
        if (hwnd != this._callbackHwnd)
            return
        taskId := wParam
        if _CSPromise._pending.Has(taskId) {
            promise := _CSPromise._pending[taskId]
            promise._Complete()
        }
        return 0
    }
}

;; ── CS — The Global Namespace Router ────────────────────────────────────────
;; CS.System.Math.Pow(5, 3) starts here.
;; Key insight: AHK v2 dispatches obj.Method(args) → __Call(name, args)
;;              and obj.Prop → __Get(name, params)
;; So both CSNamespace and CS need __Call for method-style invocations.

;; ── _CSConfig — Global switches ─────────────────────────────────────────────
;; CS.Config.ShowErrorGui := false   ; never open the compile-error window (headless / scheduled scripts)
;; CS.Config.NuGetGui := false       ; never open the NuGet progress window

class _CSConfig {
    static ShowErrorGui := true
    static NuGetGui := true

    ; CS.Config.Trace := (line) => OutputDebug(line)   ; log every .NET call with its timing
    static Trace := ""

    ; Refuse to load a bridge DLL whose SHA-256 differs from the one pinned in AHK_SHARP_BRIDGE_SHA256
    static VerifyBridge := true

    ; Load the bridge from here instead of lib\ (e.g. a copy extracted with FileInstall in a compiled script)
    static BridgeDll := ""

    ; NuGet downloads are checked against the SHA-512 nuget.org publishes for that exact version.
    ;   VerifyNuGet := false    skip the check
    ;   NuGetStrict := true     also fail when the hash cannot be fetched (default: warn and continue)
    static VerifyNuGet := true
    static NuGetStrict := false

    ; How long a .NET worker thread waits for the AHK thread to run one of your functions
    static _cbTimeout := 5000
    static CallbackTimeoutMs {
        get => this._cbTimeout
        set {
            this._cbTimeout := value
            if _AhkSharpEngine._clrStarted
                _AhkSharpEngine._bridge.SetCallbackTimeout(value)
        }
    }
}

class CS {
    ; CS.System → CSNamespace(["System"])
    ; CS.Fast → _CSFast parallel engine
    ; CS.NuGet → _CSNuGet package manager
    static __Get(name, params) {
        if (name == "Fast")
            return _CSFast
        if (name == "NuGet")
            return _CSNuGet
        if (name == "Config")
            return _CSConfig
        if (name == "Promise")
            return _CSPromise
        return _CSNamespace.Root(name)
    }

    ; CS("TypeName") → direct type reference
    static Call(typeName := "") {
        if (typeName != "")
            return _CSType(typeName)
        return this
    }

    ; ── CS.Eval — One-liner C# expression evaluator ───────────────────────
    ; Usage: result := CS.Eval("Math.Sqrt(144) + Math.PI")
    ;        guid := CS.Eval("Guid.NewGuid().ToString()")
    static Eval(expression, refs := "") {
        bridge := _AhkSharpEngine.Boot()
        try
            result := bridge.EvalExpression(expression, refs)
        catch as e
            throw _CSError(e, "CS.Eval")
        return _WrapResult(result)
    }

    ; ── CS.Import — Namespace aliasing for cleaner code ───────────────────
    ; Usage: IO := CS.Import("System.IO")
    ;        IO.File.WriteAllText("test.txt", "Hello")
    static Import(namespaceName) {
        segments := StrSplit(namespaceName, ".")
        return _CSNamespace.Resolve(segments)
    }

    ; ── CS.GC — Force garbage collection ──────────────────────────────────
    ; Usage: CS.GC()  ; triggers full GC cycle
    static GC() {
        bridge := _AhkSharpEngine.Boot()
        bridge.ForceGC()
    }

    ; ── CS.Memory — Get managed heap usage ────────────────────────────────
    ; Usage: bytes := CS.Memory()  ; returns heap size in bytes
    static Memory() {
        bridge := _AhkSharpEngine.Boot()
        return bridge.GetMemoryUsage()
    }

    ; ── CS.Delegate — Wrap AHK function as C# event handler ──────────────
    ; Usage: del := CS.Delegate(myFunc)
    ;        proxy.On("EventName", myFunc)
    static Delegate(fn) => _CSDelegate.Wrap(fn)

    ; ── CS.ModuleRef — Get reference paths from compiled CSModules ────────
    ; Usage: static References := CS.ModuleRef(MathCore, StringTools)
    static ModuleRef(moduleClasses*) {
        refs := ""
        bridge := _AhkSharpEngine.Boot()
        for cls in moduleClasses {
            if (cls.HasProp("_assemblyId") && cls._assemblyId != "") {
                path := bridge.GetModulePath(cls._assemblyId)
                refs .= (refs != "" ? ";" : "") . path
            }
        }
        return refs
    }

    ; ── CS.LoadAssembly — Load a custom .NET assembly dynamically ─────────
    static LoadAssembly(assemblyPath) {
        bridge := _AhkSharpEngine.Boot()
        try
            bridge.LoadAssembly(assemblyPath)
        catch as e
            throw _CSError(e, "CS.LoadAssembly")
        _CSNamespace.Invalidate()
    }

    ; ── CS.Implement — an object implementing a .NET interface with AHK functions ─
    ;   cmp := CS.Implement(CS.System.Collections.IComparer, Map("Compare", (a, b) => a - b))
    ; handlers: a Map or object literal of  name → function.  Property accessors use
    ; "get_Name"/"set_Name" (or just "Name"). A class deriving MarshalByRefObject also works.
    ; The functions run on the AHK thread even if .NET calls the object from a worker thread.
    static Implement(iface, handlers) {
        bridge := _AhkSharpEngine.Boot()
        pairs := Map()
        if (handlers is Map) {
            for k, v in handlers
                pairs[k] := v
        } else {
            for name in ObjOwnProps(handlers)
                pairs[name] := handlers.%name%
        }
        try
            res := bridge.Implement(_ToBridgeValue(iface), _ToBridgeValue(pairs))
        catch as e
            throw _CSError(e, "CS.Implement")
        return _CSProxy(res)
    }

    ; ── CS.Run — a multi-statement C# body; `return` a value (or fall off the end → "") ──
    ;   total := CS.Run("int s = 0; for (int i = 1; i <= 10; i++) s += i; return s;")      ; 55
    static Run(statements, refs := "") {
        bridge := _AhkSharpEngine.Boot()
        try
            result := bridge.RunStatements(statements, refs)
        catch as e
            throw _CSError(e, "CS.Run")
        return _WrapResult(result)
    }

    ; ── CS.CallGeneric — explicit generic type arguments (inference cannot guess these) ──
    ;   CS.CallGeneric(CS.System.Linq.Enumerable, "Empty", CS.System.Int32)       ; Enumerable.Empty<int>()
    ;   CS.CallGeneric(CS.System.Activator, "CreateInstance", [CS.System.Text.StringBuilder])
    ;   CS.CallGeneric(someProxy, "Method", [TypeA, TypeB], args*)                ; instance method
    static CallGeneric(target, method, typeArgs, args*) {
        bridge := _AhkSharpEngine.Boot()
        ta := _PackArgs(typeArgs is Array ? typeArgs : [typeArgs])
        try {
            if (target is _CSProxy)
                result := bridge.InvokeGenericMember(target._obj, method, ta, _PackArgs(args))
            else
                result := bridge.InvokeGeneric((target is _CSType) ? target._typeName : target, method, ta, _PackArgs(args))
        } catch as e
            throw _CSError(e, "CS.CallGeneric")
        return _WrapResult(result)
    }

    ; ── CS.ErrorIs — was this AHK error caused by that .NET exception type (or a subclass)? ──
    ;   try CS.System.IO.File.ReadAllText("nope")
    ;   catch as e
    ;       if CS.ErrorIs(e, "IOException")     ; matches FileNotFoundException, DirectoryNotFoundException ...
    static ErrorIs(e, typeName) {
        if !HasProp(e, "NetType")
            return false
        if _CSTypeMatches(e.NetType, typeName)
            return true
        for b in e.NetBases
            if _CSTypeMatches(b, typeName)
                return true
        return false
    }

    ; ── CS.Stats — the bridge's internal counters (for leak checks and monitoring) ──
    ;   s := CS.Stats()     ; Map: ManagedHeapBytes, Delegates, PendingAsyncTasks, ResolvedTypes,
    ;                       ;      OverloadCacheEntries, BoundCallCacheEntries, QueuedCallbacks
    ; Delegates / PendingAsyncTasks / QueuedCallbacks should return to 0 when you are done with them.
    static Stats() {
        raw := _AhkSharpEngine.Boot().Stats()
        names := ["ManagedHeapBytes", "Delegates", "PendingAsyncTasks", "ResolvedTypes", "OverloadCacheEntries"
            , "BoundCallCacheEntries", "QueuedCallbacks"]
        m := Map()
        for i, n in names
            m[n] := raw[i - 1]
        return m
    }

    ; ── CS.Same — are these two proxies the very same .NET object? (proxies themselves compare by AHK identity) ──
    static Same(a, b) {
        return _AhkSharpEngine.Boot().SameObject(a is _CSProxy ? a._obj : a, b is _CSProxy ? b._obj : b)
    }

    ; ── CS.Using — run fn(obj), then Dispose the object (even if fn throws) ──
    ;   CS.Using(CS.System.IO.StreamReader(path), (r) => MsgBox(r.ReadToEnd()))
    static Using(obj, fn) {
        try
            return fn(obj)
        finally
            try obj.Dispose()
    }

    ; ── CS.Bool — pass a real .NET bool (AHK true/false are the integers 1/0 and pick int overloads) ──
    ;   sb.Append(CS.Bool(true))   → "True"      sb.Append(true) → "1"
    static Bool(value) {
        return ComValue(0xB, value ? -1 : 0)
    }

    ; helper functions that can never clash with a .NET member of the same name
    static ToAHK(proxy) => proxy._hToAHK()
    static ToBuffer(proxy) => proxy._hToBuffer()

    ; ── CS.Explain — how an overload is chosen ────────────────────────────
    ;   MsgBox CS.Explain(CS.System.Math, "Abs", -2.5)      ; or a proxy: CS.Explain(sb, "Append", "x")
    static Explain(target, method, args*) {
        bridge := _AhkSharpEngine.Boot()
        try {
            if (target is _CSProxy)
                return bridge.ExplainMember(target._obj, method, _PackArgs(args))
            return bridge.ExplainStatic((target is _CSType) ? target._typeName : target, method, _PackArgs(args))
        } catch as e
            throw _CSError(e, "CS.Explain")
    }

    ; ── CS.Members / CS.Types — what can I call? ──────────────────────────
    ;   MsgBox CS.Members(CS.System.Math)                 ; one line per member: "static double Abs(double value)" ...
    ;   MsgBox CS.Members(sb, "app")                      ; an object, filtered by name
    ;   MsgBox CS.Types("System.IO")                      ; types (and child namespaces) in a namespace
    static Members(target, filter := "") {
        bridge := _AhkSharpEngine.Boot()
        try {
            if (target is _CSType)
                target := target._typeName
            else if (target is _CSProxy)
                target := target._obj
            else if (target is _CSNamespace)
                return CS.Types(_JoinDot(target._segments), filter)
            return bridge.Describe(target, filter)
        } catch as e
            throw _CSError(e, "CS.Members")
    }

    static Types(namespaceName, filter := "") {
        bridge := _AhkSharpEngine.Boot()
        if (namespaceName is _CSNamespace)
            namespaceName := _JoinDot(namespaceName._segments)
        try
            return bridge.TypesIn(namespaceName, filter)
        catch as e
            throw _CSError(e, "CS.Types")
    }

    ; ── CS.Declare — editor autocomplete ──────────────────────────────────
    ;   CS.Declare("System.IO", "System.Text.StringBuilder", CS.System.Math)     ; run once (or from a tiny script), then reopen the file
    ; writes lib\ahk#.d.ahk next to ahk#.ahk: a declaration file the AutoHotkey v2 language server (thqby's VS Code extension)
    ; loads automatically, so CS.System.Text.StringBuilder(), sb.Append(...), CS.System.Math.Abs(...) get completion, hover and
    ; signature help. A namespace declares every public type in it; calling Declare again adds to what is already there.
    ; Returns the file's path. The file is never executed.
    static Declare(specs*) {
        bridge := _AhkSharpEngine.Boot()
        path := RegExReplace(A_LineFile, "\\[^\\]+$", "") "\ahk#.d.ahk"
        all := [], seen := Map()
        if FileExist(path) {
            first := ""
            try first := StrSplit(FileRead(path, "UTF-8"), "`n", "`r")[1]
            if (SubStr(first, 1, 8) == ";@specs ")
                for s in StrSplit(SubStr(first, 9), ";")
                    if (s != "" && !seen.Has(s))
                        seen[s] := 1, all.Push(s)
        }
        for s in specs {
            if (s is _CSType)
                s := s._typeName
            else if (s is _CSNamespace)
                s := _JoinDot(s._segments)
            if (s != "" && !seen.Has(s))
                seen[s] := 1, all.Push(s)
        }
        joined := ""
        for s in all
            joined .= (joined == "" ? "" : ";") s
        try
            text := bridge.Declarations(joined)
        catch as e
            throw _CSError(e, "CS.Declare")
        f := FileOpen(path, "w", "UTF-8-RAW")
        f.Write(";@specs " joined "`n" text)
        f.Close()
        return path
    }

    ; ── CS.Wrap — write an AHK class that mirrors a .NET type (real parameter names, overloads as comments)
    ;   CS.Wrap("System.Math", A_ScriptDir "\Math.ahk")     ; then  #Include Math.ahk  →  Math.Abs(x)
    static Wrap(typeName, outPath := "", className := "") {
        bridge := _AhkSharpEngine.Boot()
        try
            src := bridge.GenerateWrapper((typeName is _CSType) ? typeName._typeName : typeName, className)
        catch as e
            throw _CSError(e, "CS.Wrap")
        if (outPath != "") {
            f := FileOpen(outPath, "w", "UTF-8")
            f.Write(src)
            f.Close()
        }
        return src
    }

    ; ── CS.CreateObject — Instantiate a .NET object from an assembly ────────
    static CreateObject(typeName, assemblyPath := "") {
        if (assemblyPath != "") {
            CS.LoadAssembly(assemblyPath)
        }
        return CS(typeName)()
    }
}

;; ── _CSNamespace — Phantom Namespace Builder ─────────────────────────────────
;; Accumulates path segments until the dotted path names a real .NET type; at that
;; point the chain switches to _CSType (which owns static calls / properties /
;; construction). So CS.System.Math.Pow(5, 3) is:
;;   CS.System            → _CSNamespace(["System"])
;;   ....Math             → _CSType("System.Math")      (bridge.HasType says it's a type)
;;   ....Pow(5, 3)        → _CSType.__Call → InvokeStatic
;; Because types are resolved up front, a .NET exception thrown inside a call is
; reported as-is instead of being mistaken for "type not found".

class _CSNamespace {
    static _types := Map()      ; lower-cased dotted path → _CSType (positive cache only)
    static _roots := Map()      ; CS.System, CS.Microsoft ... → shared namespace objects
    static _gen := 0            ; bumped when new assemblies appear, invalidating cached namespace children

    __New(segments) {
        this.DefineProp("_segments", { Value: segments })
        this.DefineProp("_kids", { Value: Map() })      ; child name → _CSType / _CSNamespace
        this.DefineProp("_kidsGen", { Get: (*) => kidsGen, Set: (_, v) => kidsGen := v })
        kidsGen := _CSNamespace._gen
    }

    static Root(name) {
        if this._roots.Has(name)
            return this._roots[name]
        return this._roots[name] := _CSNamespace([name])
    }

    ; Call after loading an assembly / compiling a module: cached "this is only a namespace" answers may be stale
    static Invalidate() {
        this._gen += 1
        this._roots.Clear()
    }

    ; Resolve a full segment path: a type if the bridge knows it, else a deeper namespace
    static Resolve(segments) {
        if (segments.Length >= 2) {
            path := _JoinDot(segments)
            key := StrLower(path)
            if this._types.Has(key)
                return this._types[key]
            if _AhkSharpEngine.Boot().HasType(path)
                return this._types[key] := _CSType(path)
        }
        return _CSNamespace(segments)
    }

    __Get(name, params) {
        if (name == "Async")
            return _CSAsyncNamespace(this._segments)
        ; ns.List[CS.System.Int32] — AHK passes the bracket contents as 'params'
        if (params.Length) {
            segs := this._segments.Clone()
            segs.Push(name)
            full := _JoinDot(segs)
            gen := _CSGenericType(full, params)
            if (gen == "")
                throw _CSUnresolved(full, true)
            return gen
        }

        ; Hot path: CS.System.Math.Abs(...) walks the same names every call — remember each hop
        if (this._kidsGen != _CSNamespace._gen) {
            this._kids.Clear()
            this._kidsGen := _CSNamespace._gen
        }
        kids := this._kids
        if kids.Has(name)
            return kids[name]
        segs := this._segments.Clone()
        segs.Push(name)
        return kids[name] := _CSNamespace.Resolve(segs)
    }

    ; Generic type builder: CS.System.Collections.Generic.List[CS.System.String]
    __Item[args*] {
        get {
            open := _JoinDot(this._segments)
            gen := _CSGenericType(open, args)
            if (gen == "")
                throw _CSUnresolved(open, true)
            return gen
        }
    }

    ; ns.Name(args) is a METHOD-style call on the namespace object, so:
    ;   CS.System.Text.StringBuilder()                         → constructor of a type
    ;   CS.System.Collections.Generic.List(CS.System.String)   → generic type builder
    __Call(name, args) {
        segs := this._segments.Clone()
        segs.Push(name)
        target := _CSNamespace.Resolve(segs)
        if (target is _CSType)
            return target(args*)
        full := _JoinDot(segs)
        gen := _CSGenericType(full, args)
        if (gen != "")
            return gen
        throw _CSUnresolved(full)
    }

    ; ns(args) — same, when the last segment was already consumed by __Get
    Call(args*) {
        open := _JoinDot(this._segments)
        gen := _CSGenericType(open, args)
        if (gen != "")
            return gen
        throw _CSUnresolved(open)
    }

    ToString() {
        return "CSNamespace<" _JoinDot(this._segments) ">"
    }
}

_CSUnresolved(name, generic := false) {
    hint := ""
    if (!generic) {
        try {
            better := _AhkSharpEngine.Boot().SuggestPath(name)
            if (better != "")
                hint := " Did you mean '" better "'?"
        }
    }
    return Error("AHK# could not resolve '" name "' — no such .NET "
        . (generic ? "generic type" : "type, method or namespace") . "." . hint
        . " For types in other assemblies call CS.LoadAssembly(path) first.", -2)
}

; Builds "Ns.Name`N[arg1,arg2]" from CS types / type-name strings and checks it exists.
_CSGenericType(openName, args) {
    if (args.Length == 0)
        return ""
    names := ""
    for i, arg in args {
        if (arg is String)
            n := arg
        else if (IsObject(arg) && HasProp(arg, "_typeName"))
            n := arg._typeName
        else if (IsObject(arg) && HasProp(arg, "_segments"))
            n := _JoinDot(arg._segments)
        else
            return ""
        names .= (i > 1 ? "," : "") n
    }
    full := openName "``" args.Length "[" names "]"
    return _AhkSharpEngine.Boot().HasType(full) ? _CSType(full) : ""
}

;; ── _CSProxy — The Object Wrapper ────────────────────────────────────────────
;; Wraps a live CLR object reference for fluid dot-chaining.
;;
;; .NET ALWAYS WINS. AHK# adds a few helper members to every proxy (ToAHK, ToBuffer, FromBuffer, On, Off,
;; Is, Dispose, Await, Then, Catch, ToPromise, AutoDispose, Type, Raw, Members) but each one is only used
;; when the object has NO .NET member of that name — so a .NET class with its own `Type` property or
;; `On()` method behaves exactly as .NET defines it. The helpers are also available as functions that can
;; never clash: CS.ToAHK(x), CS.ToBuffer(x). Underscore members (_Invoke, _Explain) are AHK#'s own.

class _CSProxy {
    ; helper name → implementing method (case-insensitive)
    static _helpers := _CSProxy._MakeHelperMap()
    static _MakeHelperMap() {
        m := Map()
        m.CaseSense := false
        for name, impl in Map("ToAHK", "_hToAHK", "ToArray", "_hToAHK", "ToBuffer", "_hToBuffer", "FromBuffer", "_hFromBuffer"
            , "ToPromise", "_hToPromise", "Await", "_hAwait", "Then", "_hThen", "Catch", "_hCatch"
            , "Finally", "_hFinally", "Timeout", "_hTimeout"
            , "On", "_hOn", "Off", "_hOff", "Is", "_hIs", "Dispose", "_hDispose", "AutoDispose", "_hAutoDispose")
            m[name] := impl
        return m
    }

    ; property-style helpers
    static _props := _CSProxy._MakePropMap()
    static _MakePropMap() {
        m := Map()
        m.CaseSense := false
        m["Type"] := "_hType", m["Raw"] := "_hRaw", m["Members"] := "_hMembers"
        return m
    }

    __New(obj) {
        this.DefineProp("_obj", { Value: obj })
        this.DefineProp("_bridge", { Value: _AhkSharpEngine.Boot() })
    }

    ; Objects opted in with .AutoDispose() are disposed when the last AHK reference goes away
    __Delete() {
        if HasProp(this, "_auto")
            try this._bridge.DisposeObject(this._obj)
    }

    ; proxy.SomeMethod(args) → the .NET method (or an AHK# helper when .NET has no member of that name)
    __Call(name, args) {
        impl := _CSProxy._helpers.Get(name, "")
        if (impl != "" && !this._bridge.HasMember(this._obj, name))
            return this.%impl%(args*)
        return this._Invoke(name, args*)
    }

    ; Call the .NET method by name — bypasses the helper lookup
    _Invoke(name, args*) {
        b := this._bridge, o := this._obj
        trace := _CSConfig.Trace
        if (trace)
            t0 := _CSQpc()
        try {
            for a in args
                if (IsSet(a) && IsObject(a) && a is VarRef)
                    return _CSCallWithRefs(b, false, o, name, args, trace)
            switch args.Length {
                case 0: result := b.InvokeMember0(o, name)
                case 1: result := b.InvokeMember1(o, name, _ArgAt(args, 1))
                case 2: result := b.InvokeMember2(o, name, _ArgAt(args, 1), _ArgAt(args, 2))
                case 3: result := b.InvokeMember3(o, name, _ArgAt(args, 1), _ArgAt(args, 2), _ArgAt(args, 3))
                default: result := b.InvokeMember(o, name, _PackArgs(args))
            }
        } catch as e {
            if (trace)
                _CSTrace(trace, this._Describe() "." name, args, "ERROR " e.Message, t0)
            throw _CSError(e, this._Describe() "." name "()")
        }
        if (trace)
            _CSTrace(trace, this._Describe() "." name, args, result, t0)
        return _WrapResult(result)
    }

    ; Show how each .NET overload scores for these arguments (which one would be picked and why)
    _Explain(name, args*) {
        return this._bridge.ExplainMember(this._obj, name, _PackArgs(args))
    }

    _Describe() {
        try
            return this._bridge.GetTypeName(this._obj)
        return "object"
    }

    ; proxy.Property → the .NET property / field (or an AHK# property helper: Type, Raw, Members)
    __Get(name, params) {
        if (name == "Async")
            return _CSAsyncProxy(this._obj)
        if (name == "Ptr" || name == "_obj" || name == "_bridge")
            return
        impl := _CSProxy._props.Get(name, "")
        if (impl != "" && !this._bridge.HasMember(this._obj, name))
            return this.%impl%()
        try
            result := this._bridge.GetProperty(this._obj, name)
        catch as e
            throw _CSError(e, this._Describe() "." name)
        return _WrapResult(result)
    }

    ; proxy.Property := value → SetProperty
    __Set(name, params, value) {
        if (name == "_obj" || name == "_bridge" || name == "_auto")
            return
        try
            this._bridge.SetProperty(this._obj, name, _ToBridgeValue(value))
        catch as e
            throw _CSError(e, this._Describe() "." name)
    }

    ; proxy[index] → GetIndex;  matrix[row, col] / multi-parameter indexers → GetIndexMulti
    __Item[indices*] {
        get {
            try {
                if (indices.Length == 1)
                    result := this._bridge.GetIndex(this._obj, _ToBridgeValue(indices[1]))
                else
                    result := this._bridge.GetIndexMulti(this._obj, _PackArgs(indices))
            } catch as e
                throw _CSError(e, this._Describe() "[" _JoinDot(indices) "]")
            return _WrapResult(result)
        }
        set {
            try {
                if (indices.Length == 1)
                    this._bridge.SetIndex(this._obj, _ToBridgeValue(indices[1]), _ToBridgeValue(value))
                else
                    this._bridge.SetIndexMulti(this._obj, _PackArgs(indices), _ToBridgeValue(value))
            } catch as e
                throw _CSError(e, this._Describe() "[" _JoinDot(indices) "]")
        }
    }

    ; for item in proxy      → items
    ; for key, value in proxy → (key, value) for dictionaries, (index, value) for lists
    __Enum(n) {
        if (n == 2)
            return this._hToAHK().__Enum(2)
        ; Collections (List, array, HashSet, ...) are read in bulk and iterated natively;
        ; lazy sequences (LINQ, File.ReadLines, ...) are pulled one item at a time.
        if this._bridge.IsType(this._obj, "System.Collections.ICollection")
            return this._hToAHK().__Enum(1)
        enumerator := this._bridge.GetEnumerator(this._obj)
        return (&val) => (
            this._bridge.MoveNext(enumerator)
                ? (val := _WrapResult(this._bridge.GetCurrent(enumerator)), true)
            : false
        )
    }

    ; ── helpers (reached only when .NET has no member of that name) ────────────

    ; Convert a .NET collection into native AHK values:
    ;   array / List<T> / IEnumerable → Array (1-based)     Dictionary<K,V> → Map
    _hToAHK() {
        return _SafeArrayToAHK(this._bridge.ToSafeArray(this._obj))
    }

    ; Raw memory transfer for primitive arrays (byte[], int[], double[] ...): one memcpy each way.
    ;   data := CS.System.IO.File.ReadAllBytes(path).ToBuffer()      ; → AHK Buffer (read with NumGet / StrGet)
    _hToBuffer() {
        n := this._bridge.ByteLength(this._obj)
        buf := Buffer(n)
        if (n)
            this._bridge.CopyToPtr(this._obj, buf.Ptr, n)
        return buf
    }

    _hFromBuffer(buf, bytes := unset) {
        this._bridge.CopyFromPtr(this._obj, buf.Ptr, IsSet(bytes) ? bytes : buf.Size)
        return this
    }

    ; A method that returns a System.Threading.Tasks.Task (HttpClient.GetStringAsync, Task.Delay ...)
    ; can be awaited like any AHK# promise:
    ;   html := client.GetStringAsync(url).Await(10000)
    ;   client.GetStringAsync(url).Then((html) => ...).Catch((e) => ...)
    _hToPromise() {
        bridge := _AhkSharpEngine.Boot()
        try
            id := bridge.TaskToAsync(this._obj, _AhkSharpEngine._callbackHwnd, _AhkSharpEngine._WM_ASYNC)
        catch as e
            throw _CSError(e, "ToPromise")
        return _CSPromise(id)
    }

    _hAwait(timeoutMs := 0) {
        return this._hToPromise().Await(timeoutMs)
    }

    _hThen(onOk := "", onFail := "") {
        return this._hToPromise().Then(onOk, onFail)
    }

    _hCatch(callback) {
        return this._hToPromise().Catch(callback)
    }

    _hFinally(callback) {
        return this._hToPromise().Finally(callback)
    }

    ; task.Timeout(3000, cts): a promise that fails with a TimeoutError (and cancels cts) unless the task is done by then
    _hTimeout(ms, cancelSource := "") {
        return this._hToPromise().Timeout(ms, cancelSource)
    }

    ; ── Event subscription ────────────────────────────────────────────────
    ; proxy.On("Elapsed", (e, sender) => ...)
    ; The callback receives (eventArgs, sender) for standard EventHandler events and
    ; the delegate's own arguments otherwise; declare fewer parameters if you like.
    ; Events raised on other threads are queued and delivered on the AHK thread.
    _hOn(eventName, ahkFunc) {
        ref := CS.Delegate(ahkFunc)
        _AhkSharpEngine.Boot().SubscribeEvent(this._obj, eventName, ref.Id)
        _CSEventAdd(this, eventName, ref)
        return this
    }

    ; proxy.Off("Elapsed") removes every handler added with On for that event (no name = all events)
    _hOff(eventName := "") {
        _CSEventRemove(this, eventName)
        return this
    }

    _hIs(typeName) {
        return this._bridge.IsType(this._obj, typeName)
    }

    _hDispose() {
        this._bridge.DisposeObject(this._obj)
    }

    ; Dispose this object automatically when the last AHK reference to the proxy goes away.
    ; (Only call it on the ONE proxy that owns the object — a second proxy of the same object would
    ; find it disposed.)  For scoped use see CS.Using(obj, fn).
    _hAutoDispose() {
        this.DefineProp("_auto", { Value: true })
        return this
    }

    _hType() {
        return this._bridge.GetTypeName(this._obj)
    }

    _hRaw() {
        return this._obj
    }

    _hMembers() {
        return this._bridge.GetMembers(this._obj)
    }
}

;; ── _CSAsyncProxy — Async Wrapper ────────────────────────────────────────────

class _CSAsyncProxy {
    __New(obj) {
        this.DefineProp("_obj", { Value: obj })
        this.DefineProp("_bridge", { Value: _AhkSharpEngine.Boot() })
    }

    __Call(name, args) {
        hwnd := _AhkSharpEngine._callbackHwnd
        msgId := _AhkSharpEngine._WM_ASYNC
        taskId := this._bridge.BeginAsync(this._obj, name, _PackArgs(args), hwnd, msgId)
        return _CSPromise(taskId)
    }
}

;; ── _CSAsyncNamespace — Async Static Call Wrapper ────────────────────────────

class _CSAsyncNamespace {
    __New(segments) {
        this.DefineProp("_segments", { Value: segments })
    }

    __Get(name, params) {
        newSegments := this._segments.Clone()
        newSegments.Push(name)
        return _CSAsyncNamespace(newSegments)
    }

    __Call(name, args) {
        bridge := _AhkSharpEngine.Boot()
        typeName := _JoinDot(this._segments)
        hwnd := _AhkSharpEngine._callbackHwnd
        msgId := _AhkSharpEngine._WM_ASYNC
        taskId := bridge.BeginAsyncStatic(typeName, name, _PackArgs(args), hwnd, msgId)
        return _CSPromise(taskId)
    }

    Call(args*) {
        bridge := _AhkSharpEngine.Boot()
        segs := this._segments
        typeParts := []
        Loop segs.Length - 1
            typeParts.Push(segs[A_Index])
        typeName := _JoinDot(typeParts)
        methodName := segs[segs.Length]
        hwnd := _AhkSharpEngine._callbackHwnd
        msgId := _AhkSharpEngine._WM_ASYNC
        taskId := bridge.BeginAsyncStatic(typeName, methodName, _PackArgs(args), hwnd, msgId)
        return _CSPromise(taskId)
    }
}

;; ── _CSPromise — AHK Promise ─────────────────────────────────────────────────
;;   p := CS.System.Threading.Thread.Async.Sleep(500)            ; or any .NET Task:  task.ToPromise()
;;   p.Then((v) => v * 2).Then((v) => MsgBox(v)).Catch((e) => MsgBox(e.Message)).Finally(() => cleanup())
;;   value := p.Await(5000)                     ; block (message pump alive) up to 5 s, then throws TimeoutError
;;   p.Timeout(3000, cts)                       ; a promise that fails with TimeoutError (and cancels cts) if p is not done in 3 s
;;   CS.Promise.AwaitAll(p1, p2)                ; → Array of results          CS.Promise.All(p1, p2)   → a promise of that Array
;;   CS.Promise.AwaitAny(p1, p2)                ; the first to settle         CS.Promise.Race(p1, p2)  → a promise
;;   CS.Promise.Resolve(v) / Reject(err) / Delay(ms, value)
;; Then / Catch / Finally return a NEW promise, like JS: its value is what the callback returns (a promise is
;; adopted), a callback that throws rejects it, and a failure with no Catch flows down the chain. A .NET task that
;; failed and that nobody handles stays silent (p.Error / p.Await() report it); an error thrown by YOUR callback
;; that nothing ever observes is reported as an ordinary AHK error after 100 ms.
;; Errors keep their .NET identity: e.NetType / CS.ErrorIs(e, "IOException") work in Catch and around Await.

class _CSPromise {
    static _pending := Map()

    ; taskId 0 → a promise settled from AHK code (what Then / Catch / Finally / Timeout / All / Delay return)
    __New(taskId := 0) {
        ; Store state in closure-backed properties (writable, no prototype interference)
        _tid := taskId, _comp := false, _bad := false, _res := "", _err := "", _cbs := [], _seen := false
        this.DefineProp("_taskId", { Get: (*) => _tid })
        this.DefineProp("_complete", { Get: (*) => _comp, Set: (_, v) => _comp := v })
        this.DefineProp("_failed", { Get: (*) => _bad, Set: (_, v) => _bad := v })
        this.DefineProp("_result", { Get: (*) => _res, Set: (_, v) => _res := v })
        this.DefineProp("_errObj", { Get: (*) => _err, Set: (_, v) => _err := v })
        this.DefineProp("_observed", { Get: (*) => _seen, Set: (_, v) => _seen := v })
        this.DefineProp("_cbs", { Get: (*) => _cbs })
        if (taskId) {
            _CSPromise._pending[taskId] := this
            _CSPromise._StartSweeper()
        }
    }

    ; The completion message (WM_APP) is only a wake-up call: when hundreds arrive at once AutoHotkey can drop some
    ; (its thread limit), so while bridge tasks are pending a timer also asks the bridge which ones have finished.
    static _sweeping := false
    static _StartSweeper() {
        if _CSPromise._sweeping
            return
        _CSPromise._sweeping := true
        SetTimer(_CSPromise._SweepFn, 25)
    }

    static _SweepFn := ObjBindMethod(_CSPromise, "_Sweep")

    static _Sweep() {
        if (_CSPromise._pending.Count == 0) {
            SetTimer(_CSPromise._SweepFn, 0)
            _CSPromise._sweeping := false
            return
        }
        bridge := _AhkSharpEngine.Boot()
        ids := []
        for id in _CSPromise._pending
            ids.Push(id)
        for id in ids
            if (_CSPromise._pending.Has(id) && bridge.IsAsyncComplete(id))
                _CSPromise._pending[id]._TakeFromBridge()
    }

    ; ── settling ──────────────────────────────────────────────────────────
    ; The one place a promise becomes done: keep the outcome, forget the bridge slot, run the waiting callbacks.
    _Finish(ok, valueOrError) {
        if this._complete
            return
        if ok
            this._result := valueOrError
        else {
            this._failed := true
            this._errObj := valueOrError
        }
        this._complete := true
        if this._taskId
            this._Forget()
        waiting := this._cbs.Clone()
        this._cbs.Length := 0
        for entry in waiting
            this._Schedule(entry)
        if (!ok && HasProp(valueOrError, "AsyncCallback"))
            SetTimer(ObjBindMethod(this, "_ReportIfUnobserved"), -100)
    }

    _Schedule(entry) {
        SetTimer(ObjBindMethod(this, "_Deliver", entry), -1)
    }

    ; entry = [onOk, onFail, childPromise]
    _Deliver(entry) {
        onOk := entry[1], onFail := entry[2], child := entry[3]
        if !this._failed {
            if !IsObject(onOk)
                return child._Finish(true, this._result)
            handler := onOk, arg := this._result
        } else {
            if !IsObject(onFail)
                return child._Finish(false, this._errObj)
            handler := onFail, arg := this._errObj
        }
        try
            out := _CSCallFlex(handler, [arg])
        catch as e {
            ; rethrowing the very error we were handed is propagation, not a new bug in the callback
            return child._Finish(false, (IsObject(e) && e == arg) ? e : _CSFlagCallbackError(e))
        }
        child._Adopt(out ?? "")
    }

    ; a callback returned `out`: a promise is followed, anything else becomes the value
    _Adopt(out) {
        if (out is _CSProxy) {                           ; a .NET Task returned from a callback is awaited too
            try out := out._hToPromise()
        }
        if (out is _CSPromise) {
            out.Then((v) => this._Finish(true, v), (e) => this._Finish(false, e))
            return
        }
        this._Finish(true, out)
    }

    _ReportIfUnobserved() {
        if (!this._observed && this._failed)
            throw this._errObj
    }

    ; The bridge finished this task: take its value or its .NET exception. Idempotent.
    ; AHK may run an OnMessage handler between any two lines, and that handler consumes the bridge's result slot,
    ; so "is it resolved? / take the result" is one uninterruptible step (otherwise EndAsync can hit "Unknown task").
    _TakeFromBridge() {
        Critical "On"
        try {
            if this._complete
                return
            bridge := _AhkSharpEngine.Boot()
            tid := this._taskId
            text := bridge.GetAsyncError(tid)
            if (text != "" && text != 0) {
                err := Error(text)
                try
                    bridge.EndAsync(tid)                 ; frees the bridge slot and rethrows the .NET exception: keep its type
                catch as ex {
                    typed := _CSError(ex)
                    for name in ["NetType", "NetStack", "NetHResult", "NetBases"]
                        if HasProp(typed, name)
                            err.%name% := typed.%name%
                }
                err.AsyncTask := true
                this._Finish(false, err)
            } else {
                try
                    raw := bridge.EndAsync(tid)
                catch as ex {
                    err := _CSError(ex)
                    err.AsyncTask := true
                    this._Finish(false, err)
                    return
                }
                this._Finish(true, _WrapResult(raw))
            }
        } finally
            Critical "Off"
    }

    _Complete() {
        this._TakeFromBridge()
    }

    _Forget() {
        if _CSPromise._pending.Has(this._taskId)
            _CSPromise._pending.Delete(this._taskId)
    }

    ; ── consuming ─────────────────────────────────────────────────────────
    ; Block until complete, but keep the AHK message pump alive
    Await(timeoutMs := 0) {
        this._observed := true
        deadline := timeoutMs > 0 ? A_TickCount + timeoutMs : 0
        while !this._complete {
            if (this._taskId && _AhkSharpEngine.Boot().IsAsyncComplete(this._taskId)) {
                this._TakeFromBridge()
                break
            }
            if (deadline && A_TickCount > deadline)
                throw TimeoutError("Async operation did not finish within " timeoutMs " ms", -1)
            Sleep(1)
        }
        if !this._failed
            return this._result
        e := this._errObj
        if HasProp(e, "AsyncTask") {
            out := Error("Async operation failed: " e.Message, -1)
            for name in ["NetType", "NetStack", "NetHResult", "NetBases"]
                if HasProp(e, name)
                    out.%name% := e.%name%
            throw out
        }
        throw e
    }

    ; then((value) => next, (err) => recovered) → a new promise; callbacks run on the AHK thread, even if already complete
    Then(onOk := "", onFail := "") {
        this._observed := true
        child := _CSPromise()
        entry := [onOk, onFail, child]
        ; "already complete? else register" must be one uninterruptible step: a completion handler
        ; running between the check and the Push would lose the callback.
        Critical "On"
        try {
            if this._complete
                this._Schedule(entry)
            else
                this._cbs.Push(entry)
        } finally
            Critical "Off"
        return child
    }

    Catch(onFail) {
        return this.Then("", onFail)
    }

    ; runs fn() whatever happened, then passes the outcome on (unless fn itself throws)
    Finally(fn) {
        return this.Then((v) => _CSFinally(fn, v, true), (e) => _CSFinally(fn, e, false))
    }

    ; a promise that follows this one but fails with a TimeoutError after `ms`;
    ; pass a CancellationTokenSource proxy to have it cancelled at that moment
    Timeout(ms, cancelSource := "") {
        out := _CSPromise()
        timer := ObjBindMethod(this, "_TimedOut", out, ms, cancelSource)
        SetTimer(timer, -ms)
        this.Then((v) => (SetTimer(timer, 0), out._Finish(true, v)), (e) => (SetTimer(timer, 0), out._Finish(false, e)))
        return out
    }

    _TimedOut(out, ms, cancelSource) {
        if out._complete
            return
        if IsObject(cancelSource)
            try cancelSource.Cancel()
        out._Finish(false, TimeoutError("Async operation did not finish within " ms " ms"))
    }

    IsComplete {
        get {
            if this._complete
                return true
            if (this._taskId && _AhkSharpEngine.Boot().IsAsyncComplete(this._taskId)) {
                this._TakeFromBridge()
                return true
            }
            return false
        }
    }

    ; "" while running or on success, the error text if it failed
    Error {
        get {
            this._observed := true
            return (this.IsComplete && this._failed) ? this._errObj.Message : ""
        }
    }

    ; ── combinators ───────────────────────────────────────────────────────
    ; a promise for a value, a promise, or a .NET Task proxy
    static Resolve(value := "") {
        if (value is _CSPromise)
            return value
        if (value is _CSProxy) {
            try return value._hToPromise()
        }
        p := _CSPromise()
        p._Finish(true, value)
        return p
    }

    static Reject(err) {
        p := _CSPromise()
        p._Finish(false, IsObject(err) ? err : Error(String(err)))
        return p
    }

    ; resolves with `value` after `ms` (an AHK timer: nothing blocks)
    static Delay(ms, value := "") {
        p := _CSPromise()
        SetTimer(() => p._Finish(true, value), -Max(1, ms))
        return p
    }

    ; a promise of an Array with every result, in order; fails as soon as any input fails
    static All(promises*) {
        out := _CSPromise()
        if (promises.Length == 0) {
            out._Finish(true, [])
            return out
        }
        results := []
        results.Length := promises.Length
        state := { left: promises.Length }
        for i, p in promises
            _CSPromise._AllHook(out, results, state, i, _CSPromise.Resolve(p))
        return out
    }

    static _AllHook(out, results, state, i, p) {
        p.Then((v) => _CSPromise._AllSet(out, results, state, i, v), (e) => out._Finish(false, e))
    }

    static _AllSet(out, results, state, i, v) {
        results[i] := v
        if (--state.left == 0)
            out._Finish(true, results)
    }

    ; a promise that settles like the first input to settle
    static Race(promises*) {
        out := _CSPromise()
        for p in promises
            _CSPromise._RaceHook(out, _CSPromise.Resolve(p))
        return out
    }

    static _RaceHook(out, p) {
        p.Then((v) => out._Finish(true, v), (e) => out._Finish(false, e))
    }

    ; blocking forms: results in order / the first to settle (throws if that one failed)
    static AwaitAll(promises*) {
        return _CSPromise.All(promises*).Await()
    }

    static AwaitAny(promises*) {
        return _CSPromise.Race(promises*).Await()
    }
}

_CSFlagCallbackError(e) {
    if !IsObject(e)
        e := Error(String(e))
    if !HasProp(e, "AsyncCallback")
        try e.AsyncCallback := true
    return e
}

; body of Promise.Finally: run fn, then pass the value on / rethrow the error
_CSFinally(fn, value, ok) {
    _CSCallFlex(fn, [])
    if !ok
        throw value
    return value
}

;; ── _CSModule — Embedded C# Paradigm ─────────────────────────────────────────
;; Embed C# code directly in AHK classes. Compiles once, caches on disk.
;;
;; Properties:
;;   static CSharp := "..."           ; C# source code (required unless PrecompiledDLL set)
;;   static References := "..."       ; Semicolon-separated assembly references
;;   static CSVersion := ""           ; C# language version (e.g. "7.3") — requires Roslyn
;;   static PrecompiledDLL := ""      ; Path to precompiled DLL (skips compilation)

class _CSModule {
    static _assemblyId := ""
    static _className := ""
    static CSharp := ""
    static References := ""

    static __New() {
        ; ── Check for precompiled DLL first ──────────────────────────────
        if (this.HasOwnProp("PrecompiledDLL") && this.PrecompiledDLL != "") {
            try {
                bridge := _AhkSharpEngine.Boot()
                this._className := RegExReplace(this.Prototype.__Class, "\..*$", "")
                result := bridge.LoadPrecompiled(this.PrecompiledDLL)
                ; LoadPrecompiled returns "hash|ClassName" — use actual class name from DLL
                parts := StrSplit(result, "|")
                this._assemblyId := parts[1]
                if (parts.Length > 1 && parts[2] != "")
                    this._className := parts[2]
                return
            } catch as err {
                throw Error("Failed to load precompiled DLL: " this.PrecompiledDLL "`n" err.Message)
            }
        }

        if (this.CSharp == "")
            return

        bridge := _AhkSharpEngine.Boot()

        ; Determine class name — use the AHK class name
        this._className := RegExReplace(this.Prototype.__Class, "\..*$", "")

        ; Wrap user code if it doesn't contain a class declaration
        code := this._WrapSource(this.CSharp)

        ; ── C# version targeting ─────────────────────────────────────────
        langVer := ""
        try langVer := this.CSVersion

        ; ── Compile with rich error handling ──────────────────────────────
        try {
            if (langVer != "")
                this._assemblyId := bridge.CompileModuleVersioned(code, this.References, langVer)
            else
                this._assemblyId := bridge.CompileModule(code, this.References)
            _CSNamespace.Invalidate()       ; referenced assemblies may have added namespaces
        } catch as compileErr {
            ; Interactive: show the diagnosis window. Headless: set CS.Config.ShowErrorGui := false.
            if (_CSConfig.ShowErrorGui)
                _CSModule._ShowCompileError(this._className, compileErr.Message, code, langVer, this)
            ; Never continue with a dead module — fail where the problem is
            throw Error("CSModule '" this._className "' failed to compile:`n" _CSError(compileErr).Message, -1)
        }
    }

    ; Add the class wrapper / default usings when the source is just members
    static _WrapSource(code) {
        if !RegExMatch(code, "im)^\s*(?:(?:public|internal|static|sealed|abstract|partial|unsafe)\s+)*class\s+\w+") {
            ; Extract any 'using' directives from user code first
            usings := "using System; using System.Linq; using System.Collections.Generic;`n"
            while RegExMatch(code, "im)^\s*using\s+[\w.]+\s*;", &m) {
                usings .= Trim(m[0]) "`n"
                code := StrReplace(code, m[0], "", , &_, 1)
            }
            code := usings . "public class " this._className " {`n" code "`n}"
        } else if !RegExMatch(code, "i)\busing\s+System\b") {
            code := "using System; using System.Linq; using System.Collections.Generic;`n" code
        }
        return code
    }

    ; ── Hot reload ────────────────────────────────────────────────────────
    ; Recompile the module from new C# source. The old code keeps running if the new source
    ; does not compile (the error is thrown). Instance state of the module starts fresh.
    ;   MyMod.Reload(FileRead("MyMod.cs", "UTF-8"))
    static Reload(csharpSource) {
        if (this._className == "")
            this._className := RegExReplace(this.Prototype.__Class, "\..*$", "")
        code := this._WrapSource(csharpSource)
        langVer := ""
        try langVer := this.CSVersion
        bridge := _AhkSharpEngine.Boot()
        try {
            if (langVer != "")
                id := bridge.CompileModuleVersioned(code, this.References, langVer)
            else
                id := bridge.CompileModule(code, this.References)
        } catch as e
            throw _CSError(e, "CSModule '" this._className "' reload failed")
        this._assemblyId := id
        this.CSharp := csharpSource
        _CSNamespace.Invalidate()
    }

    ; Watch a .cs file and Reload() the module whenever it changes.
    ;   MyMod.Watch("MyMod.cs", (ok, message) => ToolTip(ok ? "reloaded" : message))
    ; Returns the timer function — SetTimer(fn, 0) stops watching.
    static Watch(path, onReload := "", intervalMs := 500) {
        ; Compare CONTENT, not timestamps: AHK file times have 1-second resolution, so two saves
        ; within a second would look identical. (A .cs file is small; reading it twice a second is free.)
        last := FileRead(path, "UTF-8")
        cls := this
        tick(*) {
            try
                now := FileRead(path, "UTF-8")
            catch
                return
            if (now == last)
                return
            last := now
            ok := true, msg := ""
            try
                cls.Reload(now)
            catch as e
                ok := false, msg := e.Message
            if (onReload)
                _CSCallFlex(onReload, [ok, msg])
        }
        SetTimer(tick, intervalMs)
        return tick
    }

    ; ── Rich Compilation Error Reporter ───────────────────────────────────
    static _ShowCompileError(className, errMsg, generatedCode, langVer, modClass) {
        ; Build diagnostic report
        lines := StrSplit(generatedCode, "`n")
        lineCount := lines.Length

        ; Format source preview (first 30 lines with line numbers)
        srcPreview := ""
        previewLines := Min(lineCount, 30)
        Loop previewLines {
            ln := Format("{:3d}", A_Index) ": " lines[A_Index]
            srcPreview .= ln "`r`n"
        }
        if (lineCount > 30)
            srcPreview .= "    ... (" (lineCount - 30) " more lines)`r`n"

        ; Detect common issues and build advice
        advice := ""

        ; C# 6.0+ null-conditional ?.
        if InStr(errMsg, "Unexpected character") || InStr(errMsg, "Invalid expression term '.'") {
            if RegExMatch(generatedCode, "\w+\?\.\w+")
                advice .= ">>> LIKELY FIX: Your C# code uses '?.' (null-conditional operator)`r`n"
                    . "   This requires C# 6.0+, but AHK# defaults to C# 4.0.`r`n"
                    . "   Replace:  obj?.Method()  ->  obj != null ? obj.Method() : null`r`n"
                    . "   Or add:   static CSVersion := '6.0' to your class`r`n`r`n"
        }

        ; C# 6.0+ string interpolation $""
        if InStr(generatedCode, "$" Chr(34)) {
            advice .= '>>> LIKELY FIX: Your C# code uses $"..." (string interpolation)`r`n'
                . "   This requires C# 6.0+. AHK# defaults to C# 4.0.`r`n"
                . '   Replace:  $"Hello {name}"  ->  string.Format("Hello {0}", name)`r`n'
                . "   Or add:   static CSVersion := '6.0' to your class`r`n`r`n"
        }

        ; C# 7.0+ pattern matching: is Type varName
        if RegExMatch(generatedCode, "\bis\s+\w+\s+\w+\s*[\){]") {
            advice .= ">>> LIKELY FIX: Your C# code uses 'is Type varName' (C# 7.0 pattern matching)`r`n"
                . "   AHK# defaults to C# 4.0.`r`n"
                . "   Replace:  if (x is string s) { ... }`r`n"
                . "   With:     if (x is string) { var s = (string)x; ... }`r`n"
                . "   Or add:   static CSVersion := '7.0' to your class`r`n`r`n"
        }

        ; Unexpected characters (encoding issues)
        if InStr(errMsg, "Unexpected character") {
            advice .= ">>> CHECK: Unexpected characters in C# source.`r`n"
                . "   Common causes:`r`n"
                . "   - Special chars in double-quoted AHK strings (use single-quoted '(...)')`r`n"
                . "   - Save your .ahk file as UTF-8 with BOM`r`n"
                . "   - Use Chr() for special characters`r`n`r`n"
        }

        ; Namespace/member errors (missing class wrapper)
        if InStr(errMsg, "namespace cannot directly contain") {
            advice .= ">>> LIKELY FIX: Code not properly wrapped in a class.`r`n"
                . "   Check that CSharp only contains method/field definitions,`r`n"
                . "   not bare statements. Or wrap in 'public class X { ... }'`r`n`r`n"
        }

        ; Missing references
        if InStr(errMsg, "could not be found") || InStr(errMsg, "are you missing") {
            advice .= ">>> LIKELY FIX: Missing assembly reference.`r`n"
                . "   Add:  static References := 'AssemblyName.dll'`r`n"
                . "   For NuGet packages:  static References := CS.NuGet.Require('Package')`r`n`r`n"
        }

        ; General fallback advice
        if (advice == "")
            advice := ">>> Check the C# source below for syntax errors.`r`n"
                . "   AHK# uses C# 4.0 by default (built-in csc.exe).`r`n"
                . "   For modern C# syntax, add:  static CSVersion := '7.3'`r`n`r`n"

        ; Build the error GUI
        refStr := ""
        try refStr := modClass.References

        g := Gui("+AlwaysOnTop -MinimizeBox +Resize", "AHK# — Compilation Error")
        g.SetFont("s10", "Segoe UI")
        g.BackColor := "0x1e1e2e"
        g.SetFont("cF38BA8")
        g.Add("Text", "x15 y10 w560", Chr(0x2717) " CSModule compilation failed: " className)

        g.SetFont("s9 cCDD6F4", "Segoe UI")
        g.Add("Text", "x15 y35 w560", "C# Version: " (langVer != "" ? langVer : "4.0 (default)")
            . "  |  Refs: " (refStr != "" ? SubStr(refStr, 1, 60) : "(none)"))

        ; Compiler Errors
        g.SetFont("s9 cF38BA8", "Cascadia Mono")
        g.Add("Text", "x15 y58 w560", Chr(0x2500) Chr(0x2500) " Compiler Errors " Chr(0x2500) Chr(0x2500))
        g.SetFont("s8 cFAB387", "Cascadia Mono")
        g.Add("Edit", "x15 y78 w560 h100 Multi ReadOnly Background0x181825 cFAB387", errMsg)

        ; Advice
        g.SetFont("s9 cA6E3A1", "Cascadia Mono")
        g.Add("Text", "x15 y184 w560", Chr(0x2500) Chr(0x2500) " Diagnosis & Fix Suggestions " Chr(0x2500) Chr(0x2500))
        g.SetFont("s8 cA6E3A1", "Cascadia Mono")
        g.Add("Edit", "x15 y204 w560 h80 Multi ReadOnly Background0x181825 cA6E3A1", advice)

        ; Source Preview
        g.SetFont("s9 c89B4FA", "Cascadia Mono")
        g.Add("Text", "x15 y290 w560", Chr(0x2500) Chr(0x2500) " Generated C# Source (first 30 lines) " Chr(0x2500) Chr(0x2500))
        g.SetFont("s8 c6C7086", "Cascadia Mono")
        g.Add("Edit", "x15 y310 w560 h170 Multi ReadOnly Background0x181825 c6C7086", srcPreview)

        ; Buttons
        g.SetFont("s10", "Segoe UI")
        btnCopy := g.Add("Button", "x15 y490 w140 h30", "Copy Error Report")
        report := "AHK# Compile Error`nClass: " className "`n`n" errMsg "`n`nAdvice:`n" advice "`n`nSource:`n" srcPreview
        btnCopy.OnEvent("Click", (*) => (A_Clipboard := report, ToolTip("Copied!"), SetTimer(() => ToolTip(), -1500)))
        btnOk := g.Add("Button", "x430 y490 w145 h30 Default", "Continue")
        btnOk.OnEvent("Click", (*) => g.Destroy())

        g.Show("w590 h530")
        WinWaitClose(g.Hwnd)
    }

    static __Call(name, args) {
        if (this._assemblyId == "")
            throw Error("_CSModule not compiled — set static CSharp property")

        bridge := _AhkSharpEngine.Boot()
        try
            result := bridge.InvokeModule(this._assemblyId, this._className, name, _PackArgs(args))
        catch as e
            throw _CSError(e)
        return _WrapResult(result)
    }

    static __Get(name, params) {
        ; .Async returns a proxy that dispatches calls via ThreadPool
        if (name == "Async")
            return _CSModuleAsync(this)
        if (this._assemblyId == "")
            throw Error("_CSModule '" this.Prototype.__Class "' is not compiled — no member '" name "'", -1)
        bridge := _AhkSharpEngine.Boot()
        try
            result := bridge.ModuleGet(this._assemblyId, this._className, name)
        catch as e
            throw _CSError(e, this._className "." name)
        return _WrapResult(result)
    }

    ; ── Precompile — Export compiled DLL for distribution ─────────────────
    ; Usage: MyModule.Precompile(A_ScriptDir "\lib\MyModule.dll")
    static Precompile(outputPath) {
        if (this._assemblyId == "")
            throw Error("Module not compiled yet — cannot precompile")
        bridge := _AhkSharpEngine.Boot()
        bridge.CopyModuleDLL(this._assemblyId, outputPath)
    }
}

;; ── _CSModuleAsync — Async wrapper for CSModule ──────────────────────────────

class _CSModuleAsync {
    __New(moduleClass) {
        this.DefineProp("_mod", { Value: moduleClass })
    }

    __Call(name, args) {
        mod := this._mod
        if (mod._assemblyId == "")
            throw Error("_CSModule not compiled")

        bridge := _AhkSharpEngine.Boot()
        hwnd := _AhkSharpEngine._callbackHwnd
        msgId := _AhkSharpEngine._WM_ASYNC

        ; Compile a wrapper that calls the module method, then dispatch it async
        ; We use BeginAsyncStatic with the compiled module's class name
        taskId := bridge.BeginAsyncModule(mod._assemblyId, mod._className, name, _PackArgs(args), hwnd, msgId)
        return _CSPromise(taskId)
    }
}

;; ── _CSFast — Hardware-Parallel Polyfills ────────────────────────────────────
;; CS.Fast.Map([1,2,3], "x * 2")               → [2, 4, 6]      (all cores, order preserved)
;; CS.Fast.Filter(arr, "x % 2 == 0")           → Array
;; CS.Fast.Reduce(arr, "acc + x", 0)           → value           (sequential)
;; 'x' / 'acc' are dynamic C# values; results are AHK Arrays (1-based).

class _CSFast {
    static Map(arr, lambdaBody, refs := "") {
        bridge := _AhkSharpEngine.Boot()
        try
            raw := bridge.FastMap(_ToBridgeValue(arr), lambdaBody, refs)
        catch as e
            throw _CSError(e, "CS.Fast.Map")
        return _SafeArrayToAHK(raw)
    }

    static Filter(arr, lambdaBody, refs := "") {
        bridge := _AhkSharpEngine.Boot()
        try
            raw := bridge.FastFilter(_ToBridgeValue(arr), lambdaBody, refs)
        catch as e
            throw _CSError(e, "CS.Fast.Filter")
        return _SafeArrayToAHK(raw)
    }

    static Reduce(arr, lambdaBody, initial := 0, refs := "") {
        bridge := _AhkSharpEngine.Boot()
        try
            raw := bridge.FastReduce(_ToBridgeValue(arr), lambdaBody, initial, refs)
        catch as e
            throw _CSError(e, "CS.Fast.Reduce")
        return _WrapResult(raw)
    }
}

;; ── _CSType — Direct Type Reference ──────────────────────────────────────────
;; A resolved .NET type: static methods, static properties, constructors.

class _CSType {
    __New(typeName) {
        this.DefineProp("_typeName", { Value: typeName })
        this.DefineProp("_bridge", { Value: _AhkSharpEngine.Boot() })
    }

    __Call(name, args) {
        b := this._bridge
        ; static events:  CS.System.Console.On("CancelKeyPress", (e, sender) => ...)  /  .Off("CancelKeyPress")
        ; (a .NET static member of the same name always wins)
        if ((name = "On" || name = "Off") && !b.HasStaticMember(this._typeName, name)) {
            if (name = "On") {
                ref := CS.Delegate(args[2])
                b.SubscribeStaticEvent(this._typeName, args[1], ref.Id)
                _CSEventAdd(this, args[1], ref)
            } else
                _CSEventRemove(this, args.Length ? args[1] : "")
            return this
        }
        trace := _CSConfig.Trace
        if (trace)
            t0 := _CSQpc()
        try {
            ; out / ref parameters: Int32.TryParse("12", &n)
            for a in args
                if (IsSet(a) && IsObject(a) && a is VarRef)
                    return _CSCallWithRefs(b, true, this._typeName, name, args, trace)
            ; 0–3 arguments go straight over COM as separate parameters (no SafeArray to build)
            switch args.Length {
                case 0: result := b.InvokeStatic0(this._typeName, name)
                case 1: result := b.InvokeStatic1(this._typeName, name, _ArgAt(args, 1))
                case 2: result := b.InvokeStatic2(this._typeName, name, _ArgAt(args, 1), _ArgAt(args, 2))
                case 3: result := b.InvokeStatic3(this._typeName, name, _ArgAt(args, 1), _ArgAt(args, 2), _ArgAt(args, 3))
                default: result := b.InvokeStatic(this._typeName, name, _PackArgs(args))
            }
        } catch as e {
            if (trace)
                _CSTrace(trace, this._typeName "." name, args, "ERROR " e.Message, t0)
            throw _CSError(e, this._typeName "." name "()")
        }
        if (trace)
            _CSTrace(trace, this._typeName "." name, args, result, t0)
        return _WrapResult(result)
    }

    __Get(name, params) {
        if (name == "Async")
            return _CSAsyncNamespace(StrSplit(this._typeName, "."))
        try
            result := this._bridge.GetStaticProperty(this._typeName, name)
        catch as e
            throw _CSError(e, this._typeName "." name)
        return _WrapResult(result)
    }

    __Set(name, params, value) {
        try
            this._bridge.SetStaticProperty(this._typeName, name, _ToBridgeValue(value))
        catch as e
            throw _CSError(e, this._typeName "." name)
    }

    Call(args*) {
        try
            result := this._bridge.CreateInstance(this._typeName, _PackArgs(args))
        catch as e
            throw _CSError(e, "new " this._typeName "()")
        return _CSProxy(result)
    }
}

;; ── _CSNuGet — NuGet Package Manager ─────────────────────────────────────────
;; Download, extract, and cache NuGet packages from nuget.org (dependencies included).
;; Packages are stored in %LocalAppData%\AhkSharp\Packages\{id}\{version}\
;;
;; Usage:
;;   CS.NuGet.Install("Newtonsoft.Json", "13.0.3")    ; download + cache (throws on failure)
;;   refs := CS.NuGet.Require("Newtonsoft.Json")      ; install if needed, return refs
;;   CS.NuGet.IsInstalled("Newtonsoft.Json", "13.0.3")
;; Set CS.Config.NuGetGui := false (or pass showGui := false) for headless scripts.

class _CSNuGet {
    ; Install a package. Returns the install directory; throws Error on failure.
    static Install(packageId, version := "", showGui := unset) {
        bridge := _AhkSharpEngine.Boot()
        useGui := IsSet(showGui) ? showGui : _CSConfig.NuGetGui

        pg := statusText := ""
        if (useGui) {
            pg := Gui("+AlwaysOnTop -MinimizeBox", "AHK# — NuGet")
            pg.SetFont("s10", "Segoe UI")
            pg.BackColor := "0x1e1e2e"
            pg.SetFont("cCDD6F4")
            pg.Add("Text", "x15 y10 w270", "📦 Installing: " packageId)
            statusText := pg.Add("Text", "x15 y35 w270 h20 cA6ADC8", "Resolving version...")
            pg.Show("w300 h65 NoActivate")
        }

        try {
            bridge.NuGetSetPolicy(_CSConfig.VerifyNuGet ? 1 : 0, _CSConfig.NuGetStrict ? 1 : 0)
            if (version == "") {
                if (statusText)
                    statusText.Value := "Resolving latest version..."
                version := bridge.NuGetResolveVersion(packageId)
            }
            if (statusText)
                statusText.Value := "Downloading " packageId " " version "..."
            result := bridge.NuGetInstall(packageId, version)
        } catch as e {
            if (pg)
                pg.Destroy()
            throw _CSError(e, "NuGet install of '" packageId (version != "" ? " " version : "") "' failed")
        }

        if (pg) {
            statusText.Value := "✓ Installed!"
            Sleep(300)
            pg.Destroy()
        }
        _CSNamespace.Invalidate()
        return result
    }

    ; Install if needed and return reference paths (for static References)
    static Require(packageId, version := "") {
        bridge := _AhkSharpEngine.Boot()
        try {
            if (version == "")
                version := bridge.NuGetResolveVersion(packageId)
            if !bridge.NuGetIsInstalled(packageId, version)
                this.Install(packageId, version)
            refs := bridge.NuGetGetRefs(packageId, version)
        } catch as e {
            throw _CSError(e, "NuGet.Require('" packageId "')")
        }
        if (refs == "")
            throw Error("NuGet package '" packageId " " version "' contains no assemblies usable from .NET Framework.", -1)
        return refs
    }

    ; Search nuget.org. Packages this runtime cannot load (only net5.0+ / netstandard2.1 builds) are left out, and one whose newest
    ; release is too new is listed with the newest release that works:
    ;   for p in CS.NuGet.Search("json", 10)
    ;       MsgBox p["Id"] " " p["Version"] " — " p["Description"]
    ; Each result is a Map: Id, Version (what Require would install), Latest, Downloads, Description.
    ; includeIncompatible := true shows everything nuget.org returns.
    static Search(query, take := 20, includeIncompatible := false) {
        bridge := _AhkSharpEngine.Boot()
        try
            text := bridge.NuGetSearch(query, take, includeIncompatible ? 1 : 0)
        catch as e
            throw _CSError(e, "NuGet.Search('" query "')")
        results := []
        if (text == "")
            return results
        for line in StrSplit(text, "`n") {
            f := StrSplit(line, "|", , 5)
            results.Push(Map("Id", f[1], "Version", f[2], "Latest", f[3], "Downloads", Integer(f[4]), "Description", f.Length >= 5 ? f[5] : ""))
        }
        return results
    }

    ; Check if a package is cached
    static IsInstalled(packageId, version := "") {
        bridge := _AhkSharpEngine.Boot()
        return bridge.NuGetIsInstalled(packageId, version)
    }

    ; Uninstall a package
    static Uninstall(packageId, version := "") {
        bridge := _AhkSharpEngine.Boot()
        return bridge.NuGetUninstall(packageId, version)
    }

    ; Remove a package (alias to Uninstall)
    static Remove(packageId, version := "") {
        return this.Uninstall(packageId, version)
    }
}

;; ── _CSDelegate — .NET events → AHK callbacks ───────────────────────────────
;; Enables passing AHK functions as C# event handlers. Events may fire on any
;; thread; each one is queued and delivered on the AHK main thread via PostMessage.
;;
;; Usage:
;;   watcher := CS.System.IO.FileSystemWatcher("C:\Folder", "*.txt")
;;   watcher.On("Created", (e) => MsgBox("New file: " e.FullPath))
;;   watcher.EnableRaisingEvents := true

class _CSDelegate {
    static _WM_DELEGATE := 0x8002  ; WM_APP+2
    static _initialized := false

    static _Init() {
        if this._initialized
            return
        this._initialized := true
        OnMessage(this._WM_DELEGATE, ObjBindMethod(this, "_OnCallback"))
    }

    static Wrap(ahkFunc) {
        this._Init()
        bridge := _AhkSharpEngine.Boot()
        hwnd := _AhkSharpEngine._callbackHwnd
        id := bridge.RegisterDelegate(_CSEventCallback(ahkFunc), hwnd, this._WM_DELEGATE)
        return _CSDelegateRef(id)
    }

    ; One message = one queued event. _CSEventCallback reports handler errors itself.
    static _OnCallback(wParam, lParam, msg, hwnd) {
        if (hwnd != _AhkSharpEngine._callbackHwnd)     ; another window's WM_APP+2 (see _OnPump)
            return
        try _AhkSharpEngine.Boot().InvokeDelegate(wParam)
        return 0
    }
}

class _CSDelegateRef {
    __New(id) {
        this.DefineProp("_id", { Value: id })
    }
    Id => this._id

    Unregister() {
        bridge := _AhkSharpEngine.Boot()
        bridge.UnregisterDelegate(this._id)
    }
}

; The object the bridge calls back for an event: wraps event objects as proxies and
; lets the user's function declare fewer parameters than the event supplies.
class _CSEventCallback {
    __New(fn) {
        this.DefineProp("_fn", { Value: fn })
    }

    Call(args*) {
        for i, a in args
            args[i] := _WrapResult(a)
        try
            _CSCallFlex(this._fn, args)
        catch as e
            SetTimer(_CSRethrow.Bind(e), -1)    ; surface through AHK's normal error handling
    }
}

; The object the bridge calls when .NET invokes an AHK function synchronously
; (list.Where(fn), list.Sort(fn), ...). Only legal on the AHK thread.
class _CSCallback {
    __New(fn) {
        this.DefineProp("_fn", { Value: fn })
    }

    Call(args*) {
        for i, a in args
            args[i] := _WrapResult(a)
        r := _CSCallFlex(this._fn, args)
        if !IsSet(r)
            return ""
        return (r is _CSProxy) ? r._obj : r
    }
}

;; ── Utility Functions ───────────────────────────────────────────────────────

_JoinDot(arr) {
    result := ""
    for i, seg in arr
        result .= (i > 1 ? "." : "") . seg
    return result
}

; Turns a .NET-side exception (arrives as a COM error) into a clean AHK Error.
; The bridge reports "(0x80131509)`n`n<message>`nSource:`t<assembly>".
_CSError(e, context := "") {
    msg := e.Message
    msg := RegExReplace(msg, "^\(0x[0-9A-Fa-f]+\)\s*", "")
    msg := RegExReplace(msg, "\s*Source:\s*\S+\s*$", "")
    msg := Trim(msg, " `t`r`n")
    err := Error((context != "" ? context ": " : "") msg, -2)

    ; Attach the .NET exception's details when the bridge recorded the very exception this error carries:
    ;   e.NetType "System.IO.FileNotFoundException", e.NetBases ["System.IO.IOException", ...],
    ;   e.NetStack (throw-site frames), e.NetHResult — test with CS.ErrorIs(e, "System.IO.IOException")
    try {
        info := _AhkSharpEngine._bridge.LastErrorInfo()
        first := StrSplit(Trim(info[4], "`r`n"), "`n", "`r")[1]
        if (info[0] != "" && first != "" && InStr(e.Message, SubStr(first, 1, 80))) {
            err.NetType := info[0]
            err.NetStack := info[1]
            err.NetHResult := info[2]
            err.NetBases := StrSplit(info[3], "|")
        }
    }
    return err
}

; does this .NET type name (full or short) match `want`?
_CSTypeMatches(full, want) {
    return StrLower(full) == StrLower(want) || StrLower(SubStr(full, -StrLen(want) - 1)) == "." StrLower(want)
}

; Buffer → VT_UI1 SafeArray (.NET byte[]) with a single memcpy
_BufferToByteArray(buf, size) {
    arr := ComObjArray(0x11, size)
    if (size > 0) {
        DllCall("oleaut32\SafeArrayAccessData", "Ptr", ComObjValue(arr), "Ptr*", &pData := 0, "HRESULT")
        DllCall("RtlMoveMemory", "Ptr", pData, "Ptr", buf, "UPtr", size)
        DllCall("oleaut32\SafeArrayUnaccessData", "Ptr", ComObjValue(arr), "HRESULT")
    }
    return arr
}

; ── event handler bookkeeping (shared by proxies and static types) ──────────
_CSEventAdd(owner, eventName, ref) {
    if !HasProp(owner, "_events")
        owner.DefineProp("_events", { Value: Map() })
    key := StrLower(eventName)
    if !owner._events.Has(key)
        owner._events[key] := []
    owner._events[key].Push(ref)
}

_CSEventRemove(owner, eventName := "") {
    if !HasProp(owner, "_events")
        return
    if (eventName == "") {
        for , refs in owner._events
            for ref in refs
                ref.Unregister()
        owner._events.Clear()
    } else if owner._events.Has(key := StrLower(eventName)) {
        for ref in owner._events[key]
            ref.Unregister()
        owner._events.Delete(key)
    }
}

; ── out / ref parameters ────────────────────────────────────────────────────
; Int32.TryParse("12", &n): the bridge gets VT_NULL (or the variable's current value for ref
; parameters), calls the method, and returns [result, arg0-after, arg1-after, ...].
_CSRefIsSet(&v) => IsSet(v)
_CSRefGet(&v) => v
_CSRefSet(&v, value) {
    v := value
}

_CSCallWithRefs(bridge, isStatic, target, name, args, trace) {
    packed := ComObjArray(0xC, args.Length)
    refs := []
    for i, a in args {
        if (IsSet(a) && IsObject(a) && a is VarRef) {
            refs.Push(i)
            packed[i - 1] := _CSRefIsSet(a) ? _ToBridgeValue(_CSRefGet(a)) : ComValue(1, 0)
        } else
            packed[i - 1] := _ArgAt(args, i)
    }
    try
        res := isStatic ? bridge.InvokeStaticRef(target, name, packed) : bridge.InvokeMemberRef(target, name, packed)
    catch as e
        throw _CSError(e, (isStatic ? target : "object") "." name "()")
    for i in refs
        _CSRefSet(args[i], _SafeArrayItem(res[i]))
    return _WrapResult(res[0])
}

; ── tracing (CS.Config.Trace) ───────────────────────────────────────────────
_CSQpc() {
    DllCall("QueryPerformanceCounter", "Int64*", &c := 0)
    return c
}

_CSTrace(trace, what, args, result, t0) {
    static freq := (DllCall("QueryPerformanceFrequency", "Int64*", &f := 0), f)
    shown := ""
    for a in args {
        s := IsSet(a) ? (IsObject(a) ? "<" Type(a) ">" : String(a)) : "?"
        shown .= (A_Index > 1 ? ", " : "") (StrLen(s) > 40 ? SubStr(s, 1, 37) "..." : s)
    }
    r := IsObject(result) ? "<" Type(result) ">" : String(result)
    trace(Format("{}({}) => {}  [{:.1f} us]", what, shown, StrLen(r) > 60 ? SubStr(r, 1, 57) "..." : r, (_CSQpc() - t0) * 1000000 / freq))
}

; Leading arguments that were actually supplied — drops trailing unset optionals.
; Used by generated wrappers (CS.Wrap): f(a, b?, c?) → forwards only what the caller passed.
_CSArgs(args*) {
    out := []
    Loop args.Length {
        if !args.Has(A_Index)
            break
        out.Push(args[A_Index])
    }
    return out
}

; VT_UI1 SafeArray (.NET byte[] by value) → AHK Buffer with a single memcpy
_ByteArrayToBuffer(sa) {
    if !(sa is ComObjArray)
        return Buffer(0)
    n := sa.MaxIndex(1) - sa.MinIndex(1) + 1
    buf := Buffer(Max(n, 0))
    if (n > 0) {
        DllCall("oleaut32\SafeArrayAccessData", "Ptr", ComObjValue(sa), "Ptr*", &pData := 0, "HRESULT")
        DllCall("RtlMoveMemory", "Ptr", buf, "Ptr", pData, "UPtr", n)
        DllCall("oleaut32\SafeArrayUnaccessData", "Ptr", ComObjValue(sa), "HRESULT")
    }
    return buf
}

; Call fn with at most as many arguments as it declares (AHK errors on extra ones)
_CSCallFlex(fn, args) {
    if (HasProp(fn, "MaxParams") && !fn.IsVariadic && args.Length > fn.MaxParams)
        args.Length := fn.MaxParams
    return fn(args*)
}

_CSRethrow(e) {
    throw e
}

; Run cb(arg) on the next message-loop turn (each call gets its own arg — safe inside loops)
_CSDefer(cb, arg) {
    SetTimer(() => _CSCallFlex(cb, [arg]), -1)
}

; ── AHK value → bridge value ────────────────────────────────────────────────
;   number / string   as is                    Array  → object[] (nested ok)
;   _CSProxy          the raw CLR object       Map    → object[,] rows → Dictionary
;   _CSType           System.Type              Buffer → byte[]
;   function object   → delegate when a .NET parameter expects one (sync, AHK thread only)
_PackArgs(args) {
    if !IsObject(args) || args.Length == 0
        return ""

    packed := ComObjArray(0xC, args.Length)  ; VT_VARIANT SafeArray
    i := 0
    for val in args {
        v := val ?? ""
        packed[i++] := IsObject(v) ? _ToBridgeValue(v) : v     ; numbers / strings need no conversion
    }
    return packed
}

; one call argument, ready for a COM parameter (unset → "")
_ArgAt(args, i) {
    v := args.Has(i) ? args[i] : ""
    return IsObject(v) ? _ToBridgeValue(v) : v
}

_ToBridgeValue(val) {
    if !IsObject(val)
        return val
    if (val is _CSProxy)
        return val._obj
    if (val is _CSType)
        return _AhkSharpEngine.Boot().TypeOf(val._typeName)
    if (val is ComValue)
        return val
    if (val is Array)
        return _ArrayToBridge(val)
    if (val is Map) {
        arr := ComObjArray(0xC, val.Count, 2)
        row := 0
        for k, v in val {
            arr[row, 0] := _ToBridgeValue(k)
            arr[row, 1] := _ToBridgeValue(v ?? "")
            row++
        }
        return arr
    }
    if (val is Buffer)
        return _BufferToByteArray(val, val.Size)
    if HasMethod(val, "Call")
        return _CSCallback(val)
    return val
}

; ── AHK Array → SafeArray, without a COM call per element ───────────────────
;   all Integers → long[]   numbers → double[]   all Strings → string[] (one join + one split)
;   anything else → object[] (VARIANT per element, nested values converted recursively)
; The number/string paths fill a raw Buffer with NumPut and hand it to COM in ONE memcpy.
_ArrayToBridge(arr) {
    n := arr.Length
    if (n == 0)
        return ComObjArray(0xC, 0)

    allInt := true, allNum := true, allStr := true
    for v in arr {
        if !IsSet(v) {
            allInt := allNum := allStr := false
            break
        }
        if (v is Integer) {
            allStr := false
        } else if (v is Float) {
            allInt := allStr := false
        } else if (v is String) {
            allInt := allNum := false
        } else {
            allInt := allNum := allStr := false
            break
        }
    }

    if (allInt || allNum) {
        buf := Buffer(n * 8)
        type := allInt ? "Int64" : "Double"
        off := 0
        for v in arr {
            NumPut(type, v, buf, off)
            off += 8
        }
        sa := ComObjArray(allInt ? 0x14 : 5, n)      ; VT_I8 / VT_R8
        _CopyIntoSafeArray(sa, buf, n * 8)
        return sa
    }

    if (allStr) {
        lens := Buffer(n * 8)
        joined := ""
        off := 0
        for v in arr {
            NumPut("Int64", StrLen(v), lens, off)
            off += 8
            joined .= v
        }
        sa := ComObjArray(0x14, n)
        _CopyIntoSafeArray(sa, lens, n * 8)
        return _AhkSharpEngine.Boot().SplitStrings(joined, sa)
    }

    out := ComObjArray(0xC, n)
    for i, v in arr
        out[i - 1] := _ToBridgeValue(v ?? "")
    return out
}

_CopyIntoSafeArray(sa, buf, bytes) {
    DllCall("oleaut32\SafeArrayAccessData", "Ptr", ComObjValue(sa), "Ptr*", &pData := 0, "HRESULT")
    DllCall("RtlMoveMemory", "Ptr", pData, "Ptr", buf, "UPtr", bytes)
    DllCall("oleaut32\SafeArrayUnaccessData", "Ptr", ComObjValue(sa), "HRESULT")
}

; ── bridge value → AHK value ────────────────────────────────────────────────
_WrapResult(result) {
    if !IsObject(result) {
        ; nested type reference from GetStaticProperty
        if (result is String && SubStr(result, 1, 9) == "__type__:")
            return _CSType(SubStr(result, 10))
        return result
    }
    return _CSProxy(result)
}

; SafeArray from the bridge → native AHK Array (1-D) or Map (2-D key/value rows)
_SafeArrayToAHK(raw) {
    if !(raw is ComObjArray)
        return _WrapResult(raw)

    dims := 1
    try {
        raw.MaxIndex(2)
        dims := 2
    }

    lo := raw.MinIndex(1), hi := raw.MaxIndex(1)
    if (dims == 2) {
        m := Map()
        Loop hi - lo + 1 {
            i := lo + A_Index - 1
            m[_WrapResult(raw[i, 0])] := _SafeArrayItem(raw[i, 1])
        }
        return m
    }

    a := []
    n := hi - lo + 1
    if (n <= 0)
        return a
    a.Capacity := n

    ; Numbers, strings and VARIANT cells are read straight out of the SafeArray's memory
    ; (NumGet / StrGet) — no COM call per element.
    static numType := Map(16, "Char", 17, "UChar", 2, "Short", 18, "UShort", 3, "Int", 22, "Int"
        , 19, "UInt", 23, "UInt", 20, "Int64", 4, "Float", 5, "Double")
    static numSize := Map(16, 1, 17, 1, 2, 2, 18, 2, 3, 4, 22, 4, 19, 4, 23, 4, 20, 8, 4, 4, 5, 8)
    vt := ComObjType(raw) & 0xFFF

    if (numType.Has(vt) || vt == 8 || vt == 12) {
        DllCall("oleaut32\SafeArrayAccessData", "Ptr", ComObjValue(raw), "Ptr*", &pData := 0, "HRESULT")
        try {
            if numType.Has(vt) {
                t := numType[vt], sz := numSize[vt]
                off := 0
                Loop n {
                    a.Push(NumGet(pData, off, t))
                    off += sz
                }
            } else if (vt == 8) {                        ; BSTR[]
                off := 0
                Loop n {
                    p := NumGet(pData, off, "Ptr")
                    a.Push(p ? StrGet(p, NumGet(p, -4, "UInt") // 2, "UTF-16") : "")
                    off += A_PtrSize
                }
            } else {                                     ; VARIANT[]  (24 bytes each on x64, 16 on x86: cbElements says)
                stride := NumGet(ComObjValue(raw), 4, "UInt")
                Loop n {
                    p := pData + (A_Index - 1) * stride
                    switch NumGet(p, 0, "UShort") {
                        case 0, 1: a.Push("")
                        case 2: a.Push(NumGet(p, 8, "Short"))
                        case 3, 22: a.Push(NumGet(p, 8, "Int"))
                        case 4: a.Push(NumGet(p, 8, "Float"))
                        case 5: a.Push(NumGet(p, 8, "Double"))
                        case 8:
                            b := NumGet(p, 8, "Ptr")
                            a.Push(b ? StrGet(b, NumGet(b, -4, "UInt") // 2, "UTF-16") : "")
                        case 11: a.Push(NumGet(p, 8, "Short") ? 1 : 0)
                        case 17: a.Push(NumGet(p, 8, "UChar"))
                        case 18: a.Push(NumGet(p, 8, "UShort"))
                        case 19, 23: a.Push(NumGet(p, 8, "UInt"))
                        case 20: a.Push(NumGet(p, 8, "Int64"))
                        default: a.Push(_SafeArrayItem(raw[lo + A_Index - 1]))   ; objects, nested arrays
                    }
                }
            }
        } finally {
            DllCall("oleaut32\SafeArrayUnaccessData", "Ptr", ComObjValue(raw), "HRESULT")
        }
        return a
    }

    Loop n
        a.Push(_SafeArrayItem(raw[lo + A_Index - 1]))
    return a
}

_SafeArrayItem(v) {
    return (v is ComObjArray) ? _SafeArrayToAHK(v) : _WrapResult(v)
}

;; ── Public Aliases ──────────────────────────────────────────────────────────
;; These let user code use clean names like CSModule, CSProxy, etc.

CSProxy := _CSProxy
CSModule := _CSModule
CSPromise := _CSPromise
CSFast := _CSFast
CSType := _CSType
CSNamespace := _CSNamespace
CSNuGet := _CSNuGet
CSConfig := _CSConfig
CSDelegate := _CSDelegate
AHKSharp := CS
