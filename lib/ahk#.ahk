;; ═══════════════════════════════════════════════════════════════════════════════
;; AHK#
;; Bridges the entire .NET CLR into AutoHotkey v2 through a fluid, native syntax.
;;
;; Version: 1.0.0
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
;; ═══════════════════════════════════════════════════════════════════════════════

#Requires AutoHotkey v2.0

;; ── Version Constants ───────────────────────────────────────────────────────
AHK_SHARP_VERSION := "1.0.0"
AHK_SHARP_CLR := "v4.0.30319"

;; ── Global Bridge Bootstrap ─────────────────────────────────────────────────

class _AhkSharpEngine {
    static _bridge := ""
    static _clrStarted := false
    static _dllPath := ""
    static _appDomain := ""
    static _callbackHwnd := 0
    static _WM_ASYNC := 0x8001  ; WM_APP+1

    static Boot() {
        if (this._clrStarted)
            return this._bridge

        ; Locate the bridge DLL relative to this script
        scriptDir := RegExReplace(A_LineFile, "\\[^\\]+$", "")
        this._dllPath := scriptDir "\ahk#.bridge.dll"

        if !FileExist(this._dllPath) {
            ; Try to compile it
            buildScript := scriptDir "\build.ps1"
            if FileExist(buildScript)
                RunWait('powershell -ExecutionPolicy Bypass -File "' buildScript '"', "", "Hide")
            if !FileExist(this._dllPath)
                throw Error("AHK# bridge DLL not found: " this._dllPath "`nRun lib\build.ps1 first.")
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

        ; Read bridge DLL as raw bytes
        fileObj := FileOpen(this._dllPath, "r")
        fileSize := fileObj.Length
        rawBuf := Buffer(fileSize)
        fileObj.Pos := 0
        fileObj.RawRead(rawBuf, fileSize)
        fileObj.Close()

        ; Build COM byte array (VT_UI1 SafeArray)
        bytes := ComObjArray(0x11, fileSize)
        Loop fileSize
            bytes[A_Index - 1] := NumGet(rawBuf, A_Index - 1, "UChar")

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
            fileObj := FileOpen(assemblyPath, "r")
            fileSize := fileObj.Length
            rawBuf := Buffer(fileSize)
            fileObj.Pos := 0
            fileObj.RawRead(rawBuf, fileSize)
            fileObj.Close()

            bytes := ComObjArray(0x11, fileSize)
            Loop fileSize
                bytes[A_Index - 1] := NumGet(rawBuf, A_Index - 1, "UChar")

            static nullObj := ComValue(13, 0)
            loadArgs := ComObjArray(0xC, 1)
            loadArgs[0] := bytes
            return this._asmType.InvokeMember_3("Load", 0x158, nullObj, nullObj, loadArgs)
        }

        throw Error("Assembly not found: " assemblyPath)
    }

    static _SetupAsyncReceiver() {
        ; Create a hidden window to receive async completion messages
        static receiver := Gui()
        this._callbackHwnd := receiver.Hwnd
        callback := ObjBindMethod(this, "_OnAsyncComplete")
        OnMessage(this._WM_ASYNC, callback)
    }

    static _OnAsyncComplete(wParam, lParam, msg, hwnd) {
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

class CS {
    ; CS.System → CSNamespace(["System"])
    ; CS.Fast → _CSFast parallel engine
    ; CS.NuGet → _CSNuGet package manager
    static __Get(name, params) {
        if (name == "Fast")
            return _CSFast
        if (name == "NuGet")
            return _CSNuGet
        return _CSNamespace([name])
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
        return _WrapResult(bridge.EvalExpression(expression, refs))
    }

    ; ── CS.Import — Namespace aliasing for cleaner code ───────────────────
    ; Usage: IO := CS.Import("System.IO")
    ;        IO.File.WriteAllText("test.txt", "Hello")
    static Import(namespaceName) {
        segments := StrSplit(namespaceName, ".")
        return _CSNamespace(segments)
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
        bridge.LoadAssembly(assemblyPath)
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
;; Accumulates path segments. __Call handles terminal method invocations,
;; __Get handles property access / further namespace building,
;; Call handles direct invocation CSNamespace(["System", "Text", "StringBuilder"])()

class _CSNamespace {
    __New(segments) {
        this.DefineProp("_segments", { Value: segments })
    }

    ; obj.SomeMethod(args) → this is the critical path that was missing
    ; CS.System.Math.Pow(5, 3):
    ;   CS.__Get("System") → _CSNamespace(["System"])
    ;   ._CSNamespace.__Get("Math") → _CSNamespace(["System", "Math"])
    ;   ._CSNamespace.__Call("Pow", [5, 3]) → InvokeStatic("System.Math", "Pow", args)
    __Call(name, args) {
        bridge := _AhkSharpEngine.Boot()

        ; Build type from all current segments, method = name
        typeName := _JoinDot(this._segments)
        methodName := name

        ; Try static method invocation
        try {
            result := bridge.InvokeStatic(typeName, methodName, _PackArgs(args))
            return _WrapResult(result)
        }

        ; Maybe the last segment is part of the type name, not the namespace
        ; e.g. CS.System.Text.RegularExpressions.Regex.Match(...)
        ; where _segments = ["System", "Text", "RegularExpressions", "Regex"]
        ; and name = "Match"
        ; Already tried above. Try constructor if name looks like a type.
        try {
            fullName := typeName "." methodName
            result := bridge.CreateInstance(fullName, _PackArgs(args))
            return _CSProxy(result)
        }

        ; Maybe it's a generic type builder (e.g. CS.System.Collections.Generic.List(CS.System.String))
        if (args.Length > 0) {
            isGeneric := true
            genArgs := ""
            for i, arg in args {
                genArgs .= (i > 1 ? "," : "")
                if (arg is String)
                    genArgs .= arg
                else if (IsObject(arg) && HasProp(arg, "_typeName"))
                    genArgs .= arg._typeName
                else if (IsObject(arg) && HasProp(arg, "_segments"))
                    genArgs .= _JoinDot(arg._segments)
                else
                    isGeneric := false
            }
            if (isGeneric) {
                genFullName := typeName "." methodName "``" args.Length "[" genArgs "]"
                return _CSType(genFullName)
            }
        }

        throw Error("AHK# could not resolve: " typeName "." methodName)
    }

    ; Generic Type Builder: CS.System.Collections.Generic.List[CS.System.String]
    __Item[args*] {
        get {
            typeName := _JoinDot(this._segments)
            genArgs := ""
            for i, arg in args {
                genArgs .= (i > 1 ? "," : "")
                if (arg is String)
                    genArgs .= arg
                else if (IsObject(arg) && HasProp(arg, "_typeName"))
                    genArgs .= arg._typeName
                else if (IsObject(arg) && HasProp(arg, "_segments"))
                    genArgs .= _JoinDot(arg._segments)
            }
            fullName := typeName "``" args.Length "[" genArgs "]"
            return _CSType(fullName)
        }
    }


    ; obj.Prop → try to resolve as static property, else extend namespace
    __Get(name, params) {
        if (name == "Async")
            return _CSAsyncNamespace(this._segments)

        ; If we have at least 2 segments, the current segments might be a type name
        ; and 'name' might be a static property. Try resolving eagerly.
        ; e.g., _CSNamespace(["System", "Environment"]).__Get("MachineName")
        ;   → try GetStaticProperty("System.Environment", "MachineName")
        if (this._segments.Length >= 2) {
            try {
                bridge := _AhkSharpEngine.Boot()
                typeName := _JoinDot(this._segments)
                result := bridge.GetStaticProperty(typeName, name)
                return _WrapResult(result)
            }
        }

        ; Fall back to extending the namespace chain
        newSegments := this._segments.Clone()
        newSegments.Push(name)
        return _CSNamespace(newSegments)
    }

    ; obj() → constructor invocation
    ; CS.System.Text.StringBuilder() → Call() on _CSNamespace(["System","Text","StringBuilder"])
    Call(args*) {
        bridge := _AhkSharpEngine.Boot()
        fullName := _JoinDot(this._segments)

        ; Try constructor first
        try {
            result := bridge.CreateInstance(fullName, _PackArgs(args))
            return _CSProxy(result)
        }

        ; If constructor fails, maybe it's a generic type builder (e.g. CS.System.Collections.Generic.List(CS.System.String))
        if (args.Length > 0) {
            isGeneric := true
            genArgs := ""
            for i, arg in args {
                genArgs .= (i > 1 ? "," : "")
                if (arg is String)
                    genArgs .= arg
                else if (IsObject(arg) && HasProp(arg, "_typeName"))
                    genArgs .= arg._typeName
                else if (IsObject(arg) && HasProp(arg, "_segments"))
                    genArgs .= _JoinDot(arg._segments)
                else
                    isGeneric := false
            }
            if (isGeneric) {
                genFullName := fullName "``" args.Length "[" genArgs "]"
                return _CSType(genFullName)
            }
        }

        ; Maybe it's a static method with no specific method name
        ; (e.g., calling a delegate-like type)
        if (this._segments.Length >= 2) {
            segs := this._segments
            typeParts := []
            Loop segs.Length - 1
                typeParts.Push(segs[A_Index])
            typeName := _JoinDot(typeParts)
            methodName := segs[segs.Length]

            try {
                result := bridge.InvokeStatic(typeName, methodName, _PackArgs(args))
                return _WrapResult(result)
            }
        }

        ; Static property get (no-arg)
        if (args.Length == 0 && this._segments.Length >= 2) {
            segs := this._segments
            typeParts := []
            Loop segs.Length - 1
                typeParts.Push(segs[A_Index])
            typeName := _JoinDot(typeParts)
            propName := segs[segs.Length]

            try {
                result := bridge.GetStaticProperty(typeName, propName)
                return _WrapResult(result)
            }
        }

        throw Error("AHK# could not resolve: " fullName)
    }

    ToString() {
        ; Try to resolve as a static property value
        bridge := _AhkSharpEngine.Boot()
        segs := this._segments
        if (segs.Length >= 2) {
            typeParts := []
            Loop segs.Length - 1
                typeParts.Push(segs[A_Index])
            typeName := _JoinDot(typeParts)
            propName := segs[segs.Length]
            try {
                result := bridge.GetStaticProperty(typeName, propName)
                return String(result)
            }
        }
        return "CSNamespace<" _JoinDot(this._segments) ">"
    }
}

;; ── _CSProxy — The Object Wrapper ────────────────────────────────────────────
;; Wraps a live CLR object reference for fluid dot-chaining.

class _CSProxy {
    __New(obj) {
        this.DefineProp("_obj", { Value: obj })
        this.DefineProp("_bridge", { Value: _AhkSharpEngine.Boot() })
    }

    ; proxy.SomeMethod(args) → InvokeMember
    __Call(name, args) {
        try {
            result := this._bridge.InvokeMember(this._obj, name, _PackArgs(args))
            return _WrapResult(result)
        } catch as e {
            throw Error("AHK# method call failed: " name "`n" e.Message)
        }
    }

    ; proxy.Property → GetProperty
    __Get(name, params) {
        if (name == "Async")
            return _CSAsyncProxy(this._obj)
        if (name == "Ptr" || name == "_obj" || name == "_bridge")
            return
        try {
            result := this._bridge.GetProperty(this._obj, name)
            return _WrapResult(result)
        } catch as e {
            throw Error("AHK# property get failed: " name "`n" e.Message)
        }
    }

    ; proxy.Property := value → SetProperty
    __Set(name, params, value) {
        if (name == "_obj" || name == "_bridge")
            return
        rawVal := (value is _CSProxy) ? value._obj : value
        try {
            this._bridge.SetProperty(this._obj, name, rawVal)
        } catch as e {
            throw Error("AHK# property set failed: " name "`n" e.Message)
        }
    }

    ; proxy[index] → GetIndex
    __Item[index] {
        get {
            result := this._bridge.GetIndex(this._obj, index)
            return _WrapResult(result)
        }
        set {
            rawVal := (value is _CSProxy) ? value._obj : value
            this._bridge.SetIndex(this._obj, index, rawVal)
        }
    }

    ; for value in proxy → enumeration
    __Enum(n) {
        enumerator := this._bridge.GetEnumerator(this._obj)
        return (&val) => (
            this._bridge.MoveNext(enumerator)
                ? (val := _WrapResult(this._bridge.GetCurrent(enumerator)), true)
            : false
        )
    }

    ; Disposal
    Dispose() {
        this._bridge.DisposeObject(this._obj)
    }

    ; String representation
    ToString() {
        try {
            return this._bridge.ObjectToString(this._obj)
        } catch {
            ; Fallback for value types that don't survive COM round-trip
            try {
                result := this._bridge.InvokeMember(this._obj, "ToString", "")
                return (result is String) ? result : String(result)
            }
            return "CSProxy<" Type(this._obj) ">"
        }
    }

    ; Type introspection
    Type {
        get => this._bridge.GetTypeName(this._obj)
    }

    ; Raw CLR object reference (for passing back to bridge)
    Raw {
        get => this._obj
    }

    ; Membership check
    Is(typeName) {
        return this._bridge.IsType(this._obj, typeName)
    }

    ; Get all member names (for debugging / autocomplete)
    Members {
        get => this._bridge.GetMembers(this._obj)
    }

    ; Convert collection to native AHK array
    ToArray() {
        return this._bridge.InvokeMember(this._obj, "ToArray", "")
    }

    ; ── Event subscription via delegate bridge ────────────────────────────
    ; Usage: proxy.On("EventName", (args) => MsgBox(args))
    On(eventName, ahkFunc) {
        delegateRef := CS.Delegate(ahkFunc)
        bridge := _AhkSharpEngine.Boot()
        bridge.SubscribeEvent(this._obj, eventName, delegateRef.Id)
        return this
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

class _CSPromise {
    static _pending := Map()

    __New(taskId) {
        ; Store state in closure-backed properties (writable, no prototype interference)
        _tid := taskId, _comp := 0, _res := "", _err := "", _then := "", _catch := ""
        this.DefineProp("_taskId", { Get: (*) => _tid })
        this.DefineProp("_complete", { Get: (*) => _comp, Set: (_, v) => _comp := v })
        this.DefineProp("_result", { Get: (*) => _res, Set: (_, v) => _res := v })
        this.DefineProp("_error", { Get: (*) => _err, Set: (_, v) => _err := v })
        this.DefineProp("_thenCb", { Get: (*) => _then, Set: (_, v) => _then := v })
        this.DefineProp("_catchCb", { Get: (*) => _catch, Set: (_, v) => _catch := v })
        _CSPromise._pending[taskId] := this
    }

    ; Block until complete, but keep AHK message pump alive
    Await() {
        bridge := _AhkSharpEngine.Boot()

        ; Wait for completion — _Complete() fires via PostMessage during Sleep.
        while !this._complete {
            if bridge.IsAsyncComplete(this._taskId)
                break
            Sleep(1)
        }

        ; If _Complete already resolved (via WM_APP), return cached result
        if (this._complete) {
            if (this._error != "")
                throw Error("Async operation failed:`n" this._error)
            return _WrapResult(this._result)
        }

        ; Fallback: bridge says complete but WM_APP hasn't fired yet
        err := bridge.GetAsyncError(this._taskId)
        if (err != "" && err != 0) {
            if _CSPromise._pending.Has(this._taskId)
                _CSPromise._pending.Delete(this._taskId)
            throw Error("Async operation failed:`n" err)
        }

        result := bridge.EndAsync(this._taskId)
        if _CSPromise._pending.Has(this._taskId)
            _CSPromise._pending.Delete(this._taskId)
        return _WrapResult(result)
    }

    Then(callback) {
        this._thenCb := callback
        return this
    }

    Catch(callback) {
        this._catchCb := callback
        return this
    }

    _Complete() {
        bridge := _AhkSharpEngine.Boot()

        err := bridge.GetAsyncError(this._taskId)
        if (err != "" && err != 0) {
            this._error := err
            this._complete := true
            if (this._catchCb != "") {
                cb := this._catchCb
                SetTimer(() => cb.Call(Error(err)), -1)
            }
        } else {
            try {
                this._result := bridge.EndAsync(this._taskId)
                this._complete := true
                if (this._thenCb != "") {
                    cb := this._thenCb, r := this._result
                    SetTimer(() => cb.Call(_WrapResult(r)), -1)
                }
            } catch as e {
                this._error := e.Message
                this._complete := true
                if (this._catchCb != "") {
                    cb := this._catchCb
                    SetTimer(() => cb.Call(e), -1)
                }
            }
        }

        _CSPromise._pending.Delete(this._taskId)
    }

    IsComplete {
        get {
            if this._complete
                return true
            bridge := _AhkSharpEngine.Boot()
            return bridge.IsAsyncComplete(this._taskId)
        }
    }
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
        code := this.CSharp
        if !RegExMatch(code, "i)\bclass\s+\w+") {
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

        ; ── C# version targeting ─────────────────────────────────────────
        langVer := ""
        try langVer := this.CSVersion

        ; ── Compile with rich error handling ──────────────────────────────
        try {
            if (langVer != "")
                this._assemblyId := bridge.CompileModuleVersioned(code, this.References, langVer)
            else
                this._assemblyId := bridge.CompileModule(code, this.References)
        } catch as compileErr {
            _CSModule._ShowCompileError(this._className, compileErr.Message, code, langVer, this)
        }
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
        result := bridge.InvokeModule(this._assemblyId, this._className, name, _PackArgs(args))
        return _WrapResult(result)
    }

    static __Get(name, params) {
        ; .Async returns a proxy that dispatches calls via ThreadPool
        if (name == "Async")
            return _CSModuleAsync(this)
        if (this._assemblyId == "")
            return
        bridge := _AhkSharpEngine.Boot()
        try {
            result := bridge.InvokeModule(this._assemblyId, this._className, "get_" name, "")
            return _WrapResult(result)
        }
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

class _CSFast {
    static Map(arr, lambdaBody, refs := "") {
        bridge := _AhkSharpEngine.Boot()
        return bridge.FastMap(_PackArgs(arr), lambdaBody, refs)
    }

    static Filter(arr, lambdaBody, refs := "") {
        bridge := _AhkSharpEngine.Boot()
        return bridge.FastFilter(_PackArgs(arr), lambdaBody, refs)
    }

    static Reduce(arr, lambdaBody, initial := 0, refs := "") {
        bridge := _AhkSharpEngine.Boot()
        return bridge.FastReduce(_PackArgs(arr), lambdaBody, initial, refs)
    }
}

;; ── _CSType — Direct Type Reference ──────────────────────────────────────────

class _CSType {
    __New(typeName) {
        this.DefineProp("_typeName", { Value: typeName })
        this.DefineProp("_bridge", { Value: _AhkSharpEngine.Boot() })
    }

    __Call(name, args) {
        result := this._bridge.InvokeStatic(this._typeName, name, _PackArgs(args))
        return _WrapResult(result)
    }

    __Get(name, params) {
        result := this._bridge.GetStaticProperty(this._typeName, name)
        return _WrapResult(result)
    }

    __Set(name, params, value) {
        rawVal := (value is _CSProxy) ? value._obj : value
        this._bridge.SetStaticProperty(this._typeName, name, rawVal)
    }

    Call(args*) {
        result := this._bridge.CreateInstance(this._typeName, _PackArgs(args))
        return _CSProxy(result)
    }
}

;; ── _CSNuGet — NuGet Package Manager ─────────────────────────────────────────
;; Download, extract, and cache NuGet packages from nuget.org.
;; Packages are stored in %LocalAppData%\AhkSharp\Packages\{id}\{version}\
;;
;; Usage:
;;   CS.NuGet.Install("Newtonsoft.Json", "13.0.3")    ; download + cache
;;   refs := CS.NuGet.Require("Newtonsoft.Json")      ; install if needed, return refs
;;   installed := CS.NuGet.IsInstalled("Newtonsoft.Json", "13.0.3")

class _CSNuGet {
    ; Install a package (shows progress GUI)
    static Install(packageId, version := "") {
        bridge := _AhkSharpEngine.Boot()

        ; Show progress GUI
        pg := Gui("+AlwaysOnTop -MinimizeBox", "AHK# — NuGet")
        pg.SetFont("s10", "Segoe UI")
        pg.BackColor := "0x1e1e2e"
        pg.SetFont("cCDD6F4")
        pg.Add("Text", "x15 y10 w270", "📦 Installing: " packageId)
        statusText := pg.Add("Text", "x15 y35 w270 h20 cA6ADC8", "Resolving version...")
        pg.Show("w300 h65 NoActivate")

        try {
            if (version == "") {
                statusText.Value := "Resolving latest version..."
                version := bridge.NuGetResolveVersion(packageId)
            }
            statusText.Value := "Downloading " packageId " " version "..."
            result := bridge.NuGetInstall(packageId, version)
            statusText.Value := "✓ Installed!"
            Sleep(500)
        } catch as e {
            statusText.Value := "✗ Error: " e.Message
            Sleep(2000)
        }

        pg.Destroy()
        return result ?? ""
    }

    ; Install if needed and return reference paths (for static References)
    static Require(packageId, version := "") {
        bridge := _AhkSharpEngine.Boot()
        if (version == "")
            version := bridge.NuGetResolveVersion(packageId)
        if !bridge.NuGetIsInstalled(packageId, version)
            this.Install(packageId, version)
        return bridge.NuGetGetRefs(packageId, version)
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

;; ── _CSDelegate — AHK Function → C# Event Bridge ────────────────────────────
;; Enables passing AHK functions as C# event handlers.
;; Uses PostMessage to safely invoke callbacks on the AHK main thread.
;;
;; Usage:
;;   watcher := CS.System.IO.FileSystemWatcher("C:\\Folder", "*.txt")
;;   watcher.On("Created", (args) => MsgBox("New file: " args))
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
        id := bridge.RegisterDelegate(ahkFunc, hwnd, this._WM_DELEGATE)
        return _CSDelegateRef(id)
    }

    static _OnCallback(wParam, lParam, msg, hwnd) {
        delegateId := wParam
        bridge := _AhkSharpEngine.Boot()
        try bridge.InvokeDelegate(delegateId)
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

;; ── Utility Functions ───────────────────────────────────────────────────────

_JoinDot(arr) {
    result := ""
    for i, seg in arr
        result .= (i > 1 ? "." : "") . seg
    return result
}

_PackArgs(args) {
    if !IsObject(args) || args.Length == 0
        return ""

    ; Convert _CSProxy objects to raw CLR references
    packed := ComObjArray(0xC, args.Length)  ; VT_VARIANT SafeArray
    for i, val in args {
        if (val is _CSProxy)
            packed[i - 1] := val._obj
        else
            packed[i - 1] := val ?? ""
    }
    return packed
}

_WrapResult(result) {
    ; null / empty
    if (result == "" || result == 0 && !IsNumber(result))
        return result

    ; Primitives pass through
    if IsNumber(result) || (result is String)
        return result

    ; Nested type reference
    if (result is String) && RegExMatch(result, "^__type__:(.+)$", &m)
        return _CSType(m[1])

    ; COM objects / CLR objects → wrap in _CSProxy
    if IsObject(result)
        return _CSProxy(result)

    return result
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
CSDelegate := _CSDelegate
AHKSharp := CS