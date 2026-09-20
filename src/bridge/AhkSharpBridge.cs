// ═══════════════════════════════════════════════════════════════════════════════
// AHK# Bridge
// ═══════════════════════════════════════════════════════════════════════════════
//
// Compiled via csc.exe (C# 4.0, .NET Framework v4.0.30319) into ahk#.bridge.dll
// Loaded into AutoHotkey v2 via CLR hosting (mscoree.dll) — zero COM registration.
//
// ── Why .NET Framework v4.0.30319 (C# 4.0 / CLR 4)? ─────────────────────────
//   This is the widest natively-compatible runtime on Windows:
//     • Windows 7 SP1+  — .NET 4.0 included via Windows Update
//     • Windows 8/8.1   — .NET 4.5 pre-installed (runs 4.0 code)
//     • Windows 10/11   — .NET 4.8 pre-installed (runs 4.0 code)
//   Result: ZERO dependency installs on any supported Windows version.
//   The bridge DLL runs at full native CLR speed — not interpreted.
//
// ── Architecture ─────────────────────────────────────────────────────────────
//   AHK Process → mscoree.dll (CLR host) → AppDomain → AhkSharpBridge (COM)
//   AHK calls bridge methods via IDispatch (COM automation interface).
//   Bridge uses reflection to invoke .NET types, methods, and properties.
//
// ── Components ───────────────────────────────────────────────────────────────
//   AhkSharpBridge   : COM-visible entry point — all AHK ↔ .NET routing
//   TypeResolver     : Fully-qualified name → System.Type (cached, scanned)
//   MarshalEngine    : CLR ↔ COM SafeArray auto-marshalling
//   RuntimeCompiler  : CSharpCodeProvider for _CSModule embedded C# paradigm
//   AsyncRouter      : ThreadPool dispatch → AHK Promise via PostMessage
//   NuGetManager     : Download, extract, cache NuGet packages from nuget.org
//   DelegateBridge   : AHK function → C# delegate/event subscription
//
// ── C# Version Support ──────────────────────────────────────────────────────
//   Default compiler: csc.exe v4.0.30319 (C# 4.0 syntax)
//   With CSVersion:   Roslyn compiler via Microsoft.CodeDom.Providers
//                     (auto-downloaded from NuGet on first use)
//                     Supports C# 5.0 → 7.3 on .NET Framework 4.8
//                     C# 8.0 partially supported (some runtime features unavailable)
//
// ═══════════════════════════════════════════════════════════════════════════════

using System;
using System.CodeDom.Compiler;
using System.Collections;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Linq.Expressions;
using System.Net;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Runtime.ExceptionServices;
using Microsoft.CSharp;

[assembly: AssemblyVersion("2.0.0.0")]
[assembly: AssemblyFileVersion("2.0.0.0")]
[assembly: AssemblyTitle("AHK# Bridge")]
[assembly: AssemblyDescription(".NET CLR ↔ AutoHotkey v2")]

// ─────────────────────────────────────────────────────────────────────────────
// COM-Visible Entry Point
// ─────────────────────────────────────────────────────────────────────────────

[ComVisible(true)]
[ClassInterface(ClassInterfaceType.AutoDual)]
[Guid("A7B3C1D2-E4F5-6789-ABCD-EF0123456789")]
[ProgId("AhkSharp.Bridge")]
public class AhkSharpBridge
{
    // Singleton — AHK holds a single reference via CLR hosting
    private static AhkSharpBridge _instance;
    public static AhkSharpBridge Instance
    {
        get { return _instance ?? (_instance = new AhkSharpBridge()); }
    }

    public AhkSharpBridge()
    {
        // The bridge is created on the AHK main thread; AHK callbacks are only legal there.
        AhkCallback.Init();
        ErrorInfo.Install();

        // The AHK host has no app.config, so the CLR falls back to legacy defaults (SSL3/TLS1.0) and
        // every https:// call from AHK (WebClient, HttpWebRequest, ...) fails. Enable TLS 1.2 (and 1.3
        // where the framework knows it) for the whole process.
        try { ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls | (SecurityProtocolType)768 | (SecurityProtocolType)3072; } catch { }
        try { ServicePointManager.SecurityProtocol |= (SecurityProtocolType)12288; } catch { }    }

    // ── Diagnostic ─────────────────────────────────────────────────────────
    /// <summary>Returns version string for connectivity test.</summary>
    public string Ping() { return "AHK# Bridge v1.0 OK"; }

    /// <summary>Reads a static property/field of a compiled CSModule (throws if it doesn't exist).</summary>
    public object ModuleGet(string assemblyId, string className, string name)
    {
        return RuntimeCompiler.GetMember(assemblyId, className, name);
    }

    // ── Diagnostics (CS.Stats) ─────────────────────────────────────────────
    /// <summary>Internal counters: [managedHeapBytes, registeredDelegates, pendingAsyncTasks, resolvedTypes, overloadCacheEntries, boundCallCacheEntries, queuedCallbacks].</summary>
    public object Stats()
    {
        return new object[] {
            GC.GetTotalMemory(false), DelegateBridge.Count, AsyncRouter.PendingCount,
            TypeResolver.CachedCount, OverloadBinder.CacheSizes[0], OverloadBinder.CacheSizes[1], AhkCallback.QueuedCount };
    }

    // ── Multi-index access: matrix[1, 2], indexers with several parameters ──
    public object GetIndexMulti(object target, object indices)
    {
        target = MarshalEngine.Unbox(target);
        object[] idx = MarshalEngine.UnpackArgs(indices);
        Array arr = target as Array;
        if (arr != null && arr.Rank == idx.Length)
        {
            int[] ints = new int[idx.Length];
            for (int i = 0; i < idx.Length; i++) ints[i] = Convert.ToInt32(idx[i]);
            return MarshalEngine.PackResult(arr.GetValue(ints));
        }
        PropertyInfo indexer = FindIndexer(target.GetType(), idx.Length);
        object[] converted = ConvertIndices(indexer, idx);
        return MarshalEngine.PackResult(indexer.GetValue(target, converted));
    }

    public void SetIndexMulti(object target, object indices, object value)
    {
        target = MarshalEngine.Unbox(target);
        object[] idx = MarshalEngine.UnpackArgs(indices);
        Array arr = target as Array;
        if (arr != null && arr.Rank == idx.Length)
        {
            int[] ints = new int[idx.Length];
            for (int i = 0; i < idx.Length; i++) ints[i] = Convert.ToInt32(idx[i]);
            arr.SetValue(CoerceValue(arr.GetType().GetElementType(), MarshalEngine.Unbox(value)), ints);
            return;
        }
        PropertyInfo indexer = FindIndexer(target.GetType(), idx.Length);
        indexer.SetValue(target, CoerceValue(indexer.PropertyType, MarshalEngine.Unbox(value)), ConvertIndices(indexer, idx));
    }

    private static PropertyInfo FindIndexer(Type t, int paramCount)
    {
        foreach (PropertyInfo p in t.GetProperties(BindingFlags.Public | BindingFlags.Instance))
            if (p.GetIndexParameters().Length == paramCount) return p;
        throw new InvalidOperationException("Type " + t.FullName + " has no indexer taking " + paramCount + " index(es).");
    }

    private static object[] ConvertIndices(PropertyInfo indexer, object[] idx)
    {
        ParameterInfo[] ps = indexer.GetIndexParameters();
        object[] r = new object[idx.Length];
        for (int i = 0; i < idx.Length; i++) r[i] = CoerceValue(ps[i].ParameterType, idx[i]);
        return r;
    }

    // ── Explicit generic type arguments: Enumerable.Empty<int>(), Activator.CreateInstance<T>() ──
    public object InvokeGeneric(string typeName, string methodName, object typeArgs, object args)
    {
        Type t = TypeResolver.Resolve(typeName);
        if (t == null) throw new TypeLoadException("Type not found: " + typeName);
        return InvokeGenericCore(t, null, methodName, typeArgs, args);
    }

    public object InvokeGenericMember(object target, string methodName, object typeArgs, object args)
    {
        target = MarshalEngine.Unbox(target);
        return InvokeGenericCore(target.GetType(), target, methodName, typeArgs, args);
    }

    private object InvokeGenericCore(Type t, object target, string methodName, object typeArgs, object args)
    {
        object[] rawTypes = MarshalEngine.UnpackArgs(typeArgs);
        Type[] ta = new Type[rawTypes.Length];
        for (int i = 0; i < ta.Length; i++)
        {
            ta[i] = rawTypes[i] as Type ?? TypeResolver.Resolve(Convert.ToString(rawTypes[i]));
            if (ta[i] == null) throw new TypeLoadException("Type not found: " + rawTypes[i]);
        }
        BindingFlags flags = BindingFlags.Public | (target == null ? (BindingFlags.Static | BindingFlags.FlattenHierarchy) : BindingFlags.Instance);
        List<MethodBase> closed = new List<MethodBase>();
        foreach (MethodInfo m in t.GetMethods(flags))
        {
            if (!string.Equals(m.Name, methodName, StringComparison.OrdinalIgnoreCase) || !m.IsGenericMethodDefinition) continue;
            if (m.GetGenericArguments().Length != ta.Length) continue;
            try { closed.Add(m.MakeGenericMethod(ta)); } catch (ArgumentException) { }   // constraint not satisfied
        }
        object[] a = MarshalEngine.UnpackArgs(args);
        BoundCall call = OverloadBinder.Bind(closed, a);
        if (call == null)
            throw new MissingMethodException("No generic overload of " + t.FullName + "." + methodName + "<" + string.Join(", ", ta.Select(x => x.Name).ToArray())
                + "> accepts (" + OverloadBinder.DescribeArgs(a) + ").");
        return InvokeBound(call, target);
    }

    // ── CS.Run: a multi-statement C# body (must `return` a value, or falls off the end → null) ──
    public object RunStatements(string body, string references)
    {
        string code = "using System; using System.Linq; using System.Collections.Generic; using System.IO; using System.Text; using System.Text.RegularExpressions;\n"
            + "public class __Run { public static object Run() {\n" + body + "\nreturn null; } }";
        string id = RuntimeCompiler.CompileModule(code, references ?? "");
        return RuntimeCompiler.InvokeModule(id, "__Run", "Run", new object[0]);
    }

    // ── Static events (Console.CancelKeyPress, SystemEvents.DisplaySettingsChanged ...) ──
    public void SubscribeStaticEvent(string typeName, string eventName, int delegateId)
    {
        Type t = TypeResolver.Resolve(typeName);
        if (t == null) throw new TypeLoadException("Type not found: " + typeName);
        DelegateBridge.SubscribeStatic(t, eventName, delegateId);
    }

    public bool HasStaticMember(string typeName, string name)
    {
        Type t = TypeResolver.Resolve(typeName);
        return t != null && t.GetMember(name, BindingFlags.Public | BindingFlags.Static | BindingFlags.IgnoreCase).Length > 0;
    }

    // ── Typed errors ───────────────────────────────────────────────────────
    /// <summary>[type, stack, hresult, base types ('|'-joined), message] of the exception that last propagated to AHK.</summary>
    public object LastErrorInfo() { return ErrorInfo.Describe(); }

    // ── Object helpers ─────────────────────────────────────────────────────
    /// <summary>True if both arguments are the same .NET object (reference identity).</summary>
    public bool SameObject(object a, object b)
    {
        return object.ReferenceEquals(MarshalEngine.Unbox(a), MarshalEngine.Unbox(b));
    }

    /// <summary>Does the object's type have a public instance member with this name? (cached; case-insensitive)</summary>
    public bool HasMember(object target, string name)
    {
        return MemberCache.Has(MarshalEngine.Unbox(target).GetType(), name);
    }

    // ── out / ref parameters ───────────────────────────────────────────────
    // AHK passes VT_NULL for an &var argument. The reply is object[]: [0] = the return value,
    // [i + 1] = the value of argument i after the call (AHK stores it back into the VarRef).
    public object InvokeStaticRef(string typeName, string methodName, object args)
    {
        Type t = TypeResolver.Resolve(typeName);
        if (t == null) throw new TypeLoadException("Type not found: " + typeName);
        object[] a = MarshalEngine.UnpackArgs(args);
        MethodBase[] candidates = OverloadBinder.GetMethods(t, methodName, true);
        BoundCall call = OverloadBinder.Bind(candidates, a);
        if (call == null) throw NoOverload(t, methodName, a, candidates, "static");
        return InvokeBoundRef(call, null, a.Length);
    }

    public object InvokeMemberRef(object target, string memberName, object args)
    {
        if (target == null) throw new ArgumentNullException("target");
        object[] a = MarshalEngine.UnpackArgs(args);
        target = MarshalEngine.Unbox(target);
        Type t = target.GetType();
        MethodBase[] candidates = OverloadBinder.GetMethods(t, memberName, false);
        BoundCall call = OverloadBinder.Bind(candidates, a);
        if (call == null) throw NoOverload(t, memberName, a, candidates, "instance");
        return InvokeBoundRef(call, target, a.Length);
    }

    private static object[] InvokeBoundRef(BoundCall call, object target, int argCount)
    {
        try
        {
            object r = call.Method.Invoke(target, call.Args);
            object[] reply = new object[argCount + 1];
            reply[0] = IsStruct(r) ? new ValueBox(r) : MarshalEngine.PackResult(r);
            for (int i = 0; i < argCount && i < call.Args.Length; i++)
                reply[i + 1] = MarshalEngine.PackResult(call.Args[i]);
            return reply;
        }
        catch (TargetInvocationException ex)
        {
            throw AhkSharpBridge.FlattenAggregate(ex.InnerException ?? ex);
        }
    }

    // ── Task → promise ─────────────────────────────────────────────────────
    public int TaskToAsync(object task, long ahkHwnd, int callbackMsg)
    {
        Task t = MarshalEngine.Unbox(task) as Task;
        if (t == null) throw new ArgumentException("Not a System.Threading.Tasks.Task: " + (task == null ? "null" : task.GetType().FullName));
        return AsyncRouter.FromTask(t, (IntPtr)ahkHwnd, callbackMsg);
    }

    // ── AHK callbacks from worker threads ──────────────────────────────────
    public void SetAhkWindow(long hwnd, int msg) { AhkCallback.SetWindow((IntPtr)hwnd, msg); }
    public int PumpCallbacks() { return AhkCallback.Pump(); }
    public void SetCallbackTimeout(int milliseconds) { AhkCallback.TimeoutMs = milliseconds; }

    // ── CS.Implement ───────────────────────────────────────────────────────
    public object Implement(object typeArg, object handlerPairs)
    {
        Type t = typeArg as Type ?? TypeResolver.Resolve(Convert.ToString(typeArg));
        if (t == null) throw new TypeLoadException("Type not found: " + typeArg);
        if (!t.IsInterface && !typeof(MarshalByRefObject).IsAssignableFrom(t))
            throw new ArgumentException("CS.Implement needs an interface (or a class deriving MarshalByRefObject): " + t.FullName);
        AhkInterfaceProxy proxy = new AhkInterfaceProxy(t, handlerPairs as object[,]);
        return new ValueBox(proxy.GetTransparentProxy());
    }

    // ── CS.Explain / CS.Wrap ───────────────────────────────────────────────
    public string ExplainStatic(string typeName, string methodName, object args)
    {
        Type t = TypeResolver.Resolve(typeName);
        if (t == null) throw new TypeLoadException("Type not found: " + typeName);
        return OverloadBinder.Explain(t.FullName + "." + methodName, OverloadBinder.GetMethods(t, methodName, true), MarshalEngine.UnpackArgs(args));
    }

    public string ExplainMember(object target, string memberName, object args)
    {
        target = MarshalEngine.Unbox(target);
        Type t = target.GetType();
        return OverloadBinder.Explain(t.FullName + "." + memberName, OverloadBinder.GetMethods(t, memberName, false), MarshalEngine.UnpackArgs(args));
    }

    public string GenerateWrapper(string typeName, string ahkClassName)
    {
        Type t = TypeResolver.Resolve(typeName);
        if (t == null) throw new TypeLoadException("Type not found: " + typeName);
        string cls = string.IsNullOrEmpty(ahkClassName) ? new string(t.Name.Select(c => char.IsLetterOrDigit(c) || c == '_' ? c : '_').ToArray()) : ahkClassName;
        return WrapperGenerator.Generate(t, cls, "CS(\"" + t.FullName + "\")");
    }

    // ── Errors ────────────────────────────────────────────────────────────
    private static Exception NoOverload(Type t, string name, object[] args, MethodBase[] candidates, string kind)
    {
        if (candidates.Length == 0)
            return new MissingMethodException("'" + t.FullName + "' has no " + kind + " method '" + name + "'."
                + MemberHints.Suggest(t, name, kind == "static", false));
        return new MissingMethodException("No overload of " + t.FullName + "." + name
            + " accepts (" + OverloadBinder.DescribeArgs(args) + "). Candidates:"
            + OverloadBinder.DescribeCandidates(candidates));
    }

    // Task.Wait()/Result wrap the real error in an AggregateException: show the real one
    internal static Exception FlattenAggregate(Exception ex)
    {
        while (ex is AggregateException && ((AggregateException)ex).InnerExceptions.Count == 1)
            ex = ((AggregateException)ex).InnerExceptions[0];
        return ex;
    }
    private static bool IsStruct(object o)
    {
        if (o == null) return false;
        Type t = o.GetType();
        return t.IsValueType && !t.IsPrimitive && !t.IsEnum;
    }

    private static object InvokeBound(BoundCall call, object target, bool boxStructs = false)
    {
        try
        {
            object r = call.Method.Invoke(target, call.Args);
            if (boxStructs && IsStruct(r)) return new ValueBox(r);
            return MarshalEngine.PackResult(r);
        }
        catch (TargetInvocationException ex)
        {
            throw AhkSharpBridge.FlattenAggregate(ex.InnerException ?? ex);
        }
    }

    // ── Static Method Invocation ──────────────────────────────────────────
    // CS.System.Math.Pow(5, 3) routes here
    // Fixed-arity entry points: small calls skip building a SafeArray on the AHK side
    public object InvokeStatic0(string typeName, string methodName) { return InvokeStaticCore(typeName, methodName, new object[0]); }
    public object InvokeStatic1(string typeName, string methodName, object a) { return InvokeStaticCore(typeName, methodName, MarshalEngine.UnboxAll(new object[] { a })); }
    public object InvokeStatic2(string typeName, string methodName, object a, object b) { return InvokeStaticCore(typeName, methodName, MarshalEngine.UnboxAll(new object[] { a, b })); }
    public object InvokeStatic3(string typeName, string methodName, object a, object b, object c) { return InvokeStaticCore(typeName, methodName, MarshalEngine.UnboxAll(new object[] { a, b, c })); }

    public object InvokeMember0(object target, string memberName) { return InvokeMemberCore(target, memberName, new object[0]); }
    public object InvokeMember1(object target, string memberName, object a) { return InvokeMemberCore(target, memberName, MarshalEngine.UnboxAll(new object[] { a })); }
    public object InvokeMember2(object target, string memberName, object a, object b) { return InvokeMemberCore(target, memberName, MarshalEngine.UnboxAll(new object[] { a, b })); }
    public object InvokeMember3(object target, string memberName, object a, object b, object c) { return InvokeMemberCore(target, memberName, MarshalEngine.UnboxAll(new object[] { a, b, c })); }

    public object InvokeStatic(string typeName, string methodName, object args)
    {
        return InvokeStaticCore(typeName, methodName, MarshalEngine.UnpackArgs(args));
    }

    private object InvokeStaticCore(string typeName, string methodName, object[] a)
    {
        Type t = TypeResolver.Resolve(typeName);
        if (t == null)
            throw new TypeLoadException("Type not found: " + typeName);

        // Enum parsing helper: Type.__enum("Name")
        if (methodName == "__enum" && t.IsEnum)
            return Enum.Parse(t, Convert.ToString(a[0]), true);

        MethodBase[] candidates = OverloadBinder.GetMethods(t, methodName, true);
        BoundCall call = OverloadBinder.Bind(candidates, a);
        if (call == null)
            throw NoOverload(t, methodName, a, candidates, "static");
        return InvokeBound(call, null);
    }

    // ── Object Construction ───────────────────────────────────────────────
    // CS.System.Text.StringBuilder() routes here
    public object CreateInstance(string typeName, object args)
    {
        Type t = TypeResolver.Resolve(typeName);
        if (t == null)
            throw new TypeLoadException("Type not found: " + typeName);

        object[] a = MarshalEngine.UnpackArgs(args);

        MethodBase[] candidates = OverloadBinder.GetConstructors(t);
        BoundCall call = OverloadBinder.Bind(candidates, a);
        if (call == null)
        {
            if (a.Length == 0)
            {
                object dflt = Activator.CreateInstance(t);   // value types / non-public default ctor errors surface here
                return IsStruct(dflt) ? new ValueBox(dflt) : dflt;
            }
            throw new MissingMethodException("No constructor of " + t.FullName + " accepts ("
                + OverloadBinder.DescribeArgs(a) + "). Candidates:" + OverloadBinder.DescribeCandidates(candidates));
        }
        try
        {
            object created = ((ConstructorInfo)call.Method).Invoke(call.Args);
            return IsStruct(created) ? new ValueBox(created) : created;
        }
        catch (TargetInvocationException ex)
        {
            throw AhkSharpBridge.FlattenAggregate(ex.InnerException ?? ex);
        }
    }

    // ── Instance Method Invocation ────────────────────────────────────────
    public object InvokeMember(object target, string memberName, object args)
    {
        return InvokeMemberCore(target, memberName, MarshalEngine.UnpackArgs(args));
    }

    private object InvokeMemberCore(object target, string memberName, object[] a)
    {
        if (target == null)
            throw new ArgumentNullException("target");
        bool boxedTarget = target is ValueBox;
        target = MarshalEngine.Unbox(target);
        Type t = target.GetType();

        MethodBase[] candidates = OverloadBinder.GetMethods(t, memberName, false);
        BoundCall call = OverloadBinder.Bind(candidates, a);
        if (call != null)
            return InvokeBound(call, target, boxedTarget);

        // LINQ extension methods (System.Linq.Enumerable) on any IEnumerable
        if (target is IEnumerable)
        {
            object[] ext = new object[a.Length + 1];
            ext[0] = target;
            Array.Copy(a, 0, ext, 1, a.Length);
            MethodBase[] extCandidates = OverloadBinder.GetMethods(typeof(Enumerable), memberName, true);
            BoundCall extCall = OverloadBinder.Bind(extCandidates, ext);
            if (extCall != null)
                return InvokeBound(extCall, null);
        }

        throw NoOverload(t, memberName, a, candidates, "instance");
    }

    // ── Property Get ──────────────────────────────────────────────────────
    private static PropertyInfo FindProperty(Type t, string name, BindingFlags flags)
    {
        PropertyInfo pi = null;
        try { pi = t.GetProperty(name, flags); } catch (AmbiguousMatchException) { }
        if (pi == null)
        {
            try { pi = t.GetProperty(name, flags | BindingFlags.IgnoreCase); } catch (AmbiguousMatchException) { }
        }
        return pi;
    }

    private static FieldInfo FindField(Type t, string name, BindingFlags flags)
    {
        FieldInfo fi = t.GetField(name, flags);
        if (fi == null) fi = t.GetField(name, flags | BindingFlags.IgnoreCase);
        return fi;
    }

    public object GetProperty(object target, string propertyName)
    {
        if (target == null) throw new ArgumentNullException("target");
        target = MarshalEngine.Unbox(target);
        Type t = target.GetType();
        const BindingFlags F = BindingFlags.Instance | BindingFlags.Public | BindingFlags.FlattenHierarchy;

        PropertyInfo pi = FindProperty(t, propertyName, F);
        if (pi != null)
            return MarshalEngine.PackResult(pi.GetValue(target, null));

        FieldInfo fi = FindField(t, propertyName, F);
        if (fi != null)
            return MarshalEngine.PackResult(fi.GetValue(target));

        throw MemberHints.Missing(t, propertyName, false);
    }

    // ── Static Property Get ───────────────────────────────────────────────
    public object GetStaticProperty(string typeName, string propertyName)
    {
        Type t = TypeResolver.Resolve(typeName);
        if (t == null) throw new TypeLoadException("Type not found: " + typeName);
        const BindingFlags F = BindingFlags.Static | BindingFlags.Public | BindingFlags.FlattenHierarchy;

        PropertyInfo pi = FindProperty(t, propertyName, F);
        if (pi != null)
            return MarshalEngine.PackResult(pi.GetValue(null, null));

        FieldInfo fi = FindField(t, propertyName, F);
        if (fi != null)
            return MarshalEngine.PackResult(fi.GetValue(null));

        // Could be a nested type
        Type nested = t.GetNestedType(propertyName, BindingFlags.Public | BindingFlags.IgnoreCase);
        if (nested != null)
            return "__type__:" + nested.FullName;

        throw MemberHints.Missing(t, propertyName, true);
    }

    // ── Property Set ──────────────────────────────────────────────────────
    public void SetProperty(object target, string propertyName, object value)
    {
        if (target == null) throw new ArgumentNullException("target");
        target = MarshalEngine.Unbox(target);
        Type t = target.GetType();
        const BindingFlags F = BindingFlags.Instance | BindingFlags.Public | BindingFlags.FlattenHierarchy;

        PropertyInfo pi = FindProperty(t, propertyName, F);
        if (pi != null)
        {
            pi.SetValue(target, CoerceValue(pi.PropertyType, value), null);
            return;
        }

        FieldInfo fi = FindField(t, propertyName, F);
        if (fi != null)
        {
            fi.SetValue(target, CoerceValue(fi.FieldType, value));
            return;
        }

        throw MemberHints.Missing(t, propertyName, false);
    }

    // ── Static Property Set ───────────────────────────────────────────────
    public void SetStaticProperty(string typeName, string propertyName, object value)
    {
        Type t = TypeResolver.Resolve(typeName);
        if (t == null) throw new TypeLoadException("Type not found: " + typeName);
        const BindingFlags F = BindingFlags.Static | BindingFlags.Public | BindingFlags.FlattenHierarchy;

        PropertyInfo pi = FindProperty(t, propertyName, F);
        if (pi != null)
        {
            pi.SetValue(null, CoerceValue(pi.PropertyType, value), null);
            return;
        }

        FieldInfo fi = FindField(t, propertyName, F);
        if (fi != null)
        {
            fi.SetValue(null, CoerceValue(fi.FieldType, value));
            return;
        }

        throw MemberHints.Missing(t, propertyName, true);
    }

    // ── Indexer Access ────────────────────────────────────────────────────
    // Finds the generic argument types of IDictionary<K,V> / IList<T> so that AHK
    // Int32/Int64/Double keys and values are converted to what the collection expects.
    private static Type[] GenericArgsOf(Type t, Type genericDef)
    {
        foreach (Type itf in t.GetInterfaces())
            if (itf.IsGenericType && itf.GetGenericTypeDefinition() == genericDef)
                return itf.GetGenericArguments();
        return null;
    }

    public object GetIndex(object target, object index)
    {
        if (target == null) throw new ArgumentNullException("target");
        target = MarshalEngine.Unbox(target);
        Type t = target.GetType();

        if (target is Array)
            return MarshalEngine.PackResult(((Array)target).GetValue(Convert.ToInt32(index)));

        if (target is IList)
            return MarshalEngine.PackResult(((IList)target)[Convert.ToInt32(index)]);

        if (target is IDictionary)
        {
            Type[] kv = GenericArgsOf(t, typeof(IDictionary<,>));
            object key = kv != null ? CoerceValue(kv[0], index) : index;
            return MarshalEngine.PackResult(((IDictionary)target)[key]);
        }

        // Default indexer
        PropertyInfo indexer = t.GetProperty("Item", BindingFlags.Instance | BindingFlags.Public);
        if (indexer != null)
        {
            ParameterInfo[] ps = indexer.GetIndexParameters();
            object idx = CoerceValue(ps[0].ParameterType, index);
            return MarshalEngine.PackResult(indexer.GetValue(target, new[] { idx }));
        }

        throw new InvalidOperationException("Type " + t.FullName + " does not support indexing");
    }

    public void SetIndex(object target, object index, object value)
    {
        if (target == null) throw new ArgumentNullException("target");
        target = MarshalEngine.Unbox(target);
        Type t = target.GetType();

        if (target is Array)
        {
            ((Array)target).SetValue(CoerceValue(t.GetElementType(), value), Convert.ToInt32(index));
            return;
        }
        if (target is IList)
        {
            Type[] ga = GenericArgsOf(t, typeof(IList<>));
            ((IList)target)[Convert.ToInt32(index)] = ga != null ? CoerceValue(ga[0], value) : value;
            return;
        }
        if (target is IDictionary)
        {
            Type[] kv = GenericArgsOf(t, typeof(IDictionary<,>));
            object key = kv != null ? CoerceValue(kv[0], index) : index;
            object val = kv != null ? CoerceValue(kv[1], value) : value;
            ((IDictionary)target)[key] = val;
            return;
        }

        PropertyInfo indexer = t.GetProperty("Item", BindingFlags.Instance | BindingFlags.Public);
        if (indexer != null)
        {
            ParameterInfo[] ps = indexer.GetIndexParameters();
            indexer.SetValue(target, CoerceValue(indexer.PropertyType, value), new[] { CoerceValue(ps[0].ParameterType, index) });
            return;
        }

        throw new InvalidOperationException("Type " + t.FullName + " does not support index assignment");
    }

    // ── Enumeration Support ───────────────────────────────────────────────
    // Enumerators are handed to AHK inside a class: List<T>.GetEnumerator() and friends return
    // STRUCT enumerators, which cannot cross COM ("The parameter is incorrect").
    [ComVisible(true)]
    public class EnumHandle { internal IEnumerator E; }

    public object GetEnumerator(object target)
    {
        target = MarshalEngine.Unbox(target);
        if (target is IEnumerable)
            return new EnumHandle { E = ((IEnumerable)target).GetEnumerator() };
        throw new InvalidOperationException("Object does not implement IEnumerable");
    }

    public bool MoveNext(object enumerator)
    {
        return ((EnumHandle)enumerator).E.MoveNext();
    }

    public object GetCurrent(object enumerator)
    {
        return MarshalEngine.PackResult(((EnumHandle)enumerator).E.Current);
    }

    // ── Type helpers used by the AHK side ─────────────────────────────────
    /// <summary>True if the dotted name resolves to a .NET type (used to tell types from namespaces).</summary>
    public bool HasType(string typeName)
    {
        return TypeResolver.Resolve(typeName) != null;
    }

    /// <summary>Returns the System.Type object for a type name.</summary>
    public object TypeOf(string typeName)
    {
        Type t = TypeResolver.Resolve(typeName);
        if (t == null) throw new TypeLoadException("Type not found: " + typeName);
        return t;
    }

    /// <summary>
    /// Bulk string transfer from AHK: one concatenated string plus the length of each piece
    /// (an Int64 SafeArray) → string[]. One COM call instead of one per element.
    /// </summary>
    public object SplitStrings(string joined, object lengths)
    {
        Array lens = (Array)lengths;
        string[] result = new string[lens.Length];
        int pos = 0;
        for (int i = 0; i < result.Length; i++)
        {
            int n = Convert.ToInt32(lens.GetValue(i));
            result[i] = joined.Substring(pos, n);
            pos += n;
        }
        return result;
    }

    // ── Raw memory transfer (no per-element marshalling at all) ────────────
    [DllImport("kernel32.dll", EntryPoint = "RtlMoveMemory")]
    private static extern void MoveMemory(IntPtr dest, IntPtr src, UIntPtr count);

    private static Array PrimitiveArray(object array)
    {
        Array a = MarshalEngine.Unbox(array) as Array;
        if (a == null || a.Rank != 1 || !a.GetType().GetElementType().IsPrimitive)
            throw new ArgumentException("Only one-dimensional arrays of primitive types (byte[], int[], double[] ...) can be copied to or from memory.");
        return a;
    }

    /// <summary>Size in bytes of a primitive array's contents.</summary>
    public long ByteLength(object array)
    {
        return System.Buffer.ByteLength(PrimitiveArray(array));
    }

    /// <summary>Copies a primitive array into unmanaged memory (e.g. an AHK Buffer) with a single memcpy.</summary>
    public long CopyToPtr(object array, long destPtr, long capacityBytes)
    {
        Array a = PrimitiveArray(array);
        int bytes = System.Buffer.ByteLength(a);
        if (bytes > capacityBytes)
            throw new ArgumentException("Destination holds " + capacityBytes + " bytes but the array needs " + bytes + ".");
        GCHandle h = GCHandle.Alloc(a, GCHandleType.Pinned);
        try { MoveMemory((IntPtr)destPtr, h.AddrOfPinnedObject(), (UIntPtr)(uint)bytes); }
        finally { h.Free(); }
        return bytes;
    }

    /// <summary>Fills a primitive array from unmanaged memory with a single memcpy.</summary>
    public long CopyFromPtr(object array, long srcPtr, long bytes)
    {
        Array a = PrimitiveArray(array);
        int cap = System.Buffer.ByteLength(a);
        if (bytes > cap)
            throw new ArgumentException("The array holds " + cap + " bytes but " + bytes + " were supplied.");
        GCHandle h = GCHandle.Alloc(a, GCHandleType.Pinned);
        try { MoveMemory(h.AddrOfPinnedObject(), (IntPtr)srcPtr, (UIntPtr)(uint)bytes); }
        finally { h.Free(); }
        return bytes;
    }

    /// <summary>Converts a collection/dictionary into a SafeArray (typed array, object[] or object[,]) for AHK.</summary>
    public object ToSafeArray(object target)
    {
        target = MarshalEngine.Unbox(target);
        return MarshalEngine.ToSafeArray(target);
    }

    // ── Reflection Introspection ──────────────────────────────────────────
    public string GetMembers(object target)
    {
        target = MarshalEngine.Unbox(target);
        Type t = (target is string) ? TypeResolver.Resolve((string)target) : target.GetType();
        if (t == null) return "";

        StringBuilder sb = new StringBuilder();
        foreach (MemberInfo mi in t.GetMembers(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static))
        {
            if (sb.Length > 0) sb.Append("|");
            sb.Append(mi.MemberType.ToString()[0]);
            sb.Append(":");
            sb.Append(mi.Name);
        }
        return sb.ToString();
    }

    /// <summary>Human-readable member list (one per line) of a type, given a type name or an object; optional name filter.</summary>
    public string Describe(object target, string filter)
    {
        target = MarshalEngine.Unbox(target);
        Type t = (target is string) ? TypeResolver.Resolve((string)target) : (target == null ? null : target.GetType());
        if (t == null) throw new TypeLoadException("Type not found: " + target);
        return Discovery.Describe(t, filter);
    }

    /// <summary>Editor declarations (.d.ahk text) for the types / namespaces named one per line.</summary>
    public string Declarations(string specs)
    {
        return global::Declarations.Generate((specs ?? "").Split(new char[] { '\n', '\r', ';' }, StringSplitOptions.RemoveEmptyEntries));
    }

    /// <summary>Corrects the first misspelled segment of a dotted type path ("" when there is no close match).</summary>
    public string SuggestPath(string dotted)
    {
        string s = Discovery.SuggestPath(dotted);
        return string.Equals(s, dotted, StringComparison.Ordinal) ? "" : s;
    }

    /// <summary>Public types (and child namespaces) directly inside a namespace, one per line.</summary>
    public string TypesIn(string ns, string filter)
    {
        return Discovery.TypesIn(ns ?? "", filter);
    }

    public string GetTypeName(object target)
    {
        target = MarshalEngine.Unbox(target);
        return target == null ? "null" : target.GetType().FullName;
    }

    public bool IsType(object target, string typeName)
    {
        target = MarshalEngine.Unbox(target);
        if (target == null) return false;
        Type t = TypeResolver.Resolve(typeName);
        return t != null && t.IsInstanceOfType(target);
    }

    // ── Assembly Loading ──────────────────────────────────────────────────
    public void LoadAssembly(string pathOrName)
    {
        TypeResolver.LoadAssembly(pathOrName);
    }

    // ── Dispose Support ───────────────────────────────────────────────────
    public void DisposeObject(object target)
    {
        target = MarshalEngine.Unbox(target);
        if (target is IDisposable)
        {
            ((IDisposable)target).Dispose();
            return;
        }
        // classes with a plain public Dispose() that do not implement IDisposable
        MethodInfo dispose = target == null ? null : target.GetType().GetMethod("Dispose", Type.EmptyTypes);
        if (dispose != null && !dispose.IsStatic)
            dispose.Invoke(target, null);
    }

    public string CompileModule(string csCode, string references)
    {
        // Returns assembly ID (hash) for cached reuse
        return RuntimeCompiler.CompileModule(csCode, references);
    }

    public object InvokeModule(string assemblyId, string className, string methodName, object args)
    {
        object[] a = MarshalEngine.UnpackArgs(args);
        return RuntimeCompiler.InvokeModule(assemblyId, className, methodName, a);
    }

    // ── Async Router ──────────────────────────────────────────────────────
    public int BeginAsync(object target, string methodName, object args, long ahkHwnd, int callbackMsg)
    {
        return AsyncRouter.Begin(target, methodName, MarshalEngine.UnpackArgs(args), (IntPtr)ahkHwnd, callbackMsg);
    }

    public int BeginAsyncStatic(string typeName, string methodName, object args, long ahkHwnd, int callbackMsg)
    {
        return AsyncRouter.BeginStatic(typeName, methodName, MarshalEngine.UnpackArgs(args), (IntPtr)ahkHwnd, callbackMsg);
    }

    public object EndAsync(int taskId)
    {
        return AsyncRouter.End(taskId);
    }

    public bool IsAsyncComplete(int taskId)
    {
        return AsyncRouter.IsComplete(taskId);
    }

    public string GetAsyncError(int taskId)
    {
        return AsyncRouter.GetError(taskId);
    }

    // ── Fast Parallel Operations ──────────────────────────────────────────
    public object FastMap(object inputArray, string lambdaBody, string references)
    {
        return FastParallel.Map(MarshalEngine.UnpackArgs(inputArray), lambdaBody, references);
    }

    public int BeginAsyncModule(string assemblyId, string className, string methodName, object args, long ahkHwnd, int callbackMsg)
    {
        return AsyncRouter.BeginModule(assemblyId, className, methodName, MarshalEngine.UnpackArgs(args), (IntPtr)ahkHwnd, callbackMsg);
    }

    public object FastFilter(object inputArray, string lambdaBody, string references)
    {
        return FastParallel.Filter(MarshalEngine.UnpackArgs(inputArray), lambdaBody, references);
    }

    public object FastReduce(object inputArray, string lambdaBody, object initial, string references)
    {
        return FastParallel.Reduce(MarshalEngine.UnpackArgs(inputArray), lambdaBody, initial, references);
    }

    // ── CS.Eval — One-liner expression evaluator ──────────────────────────
    /// <summary>
    /// Compiles and evaluates a single C# expression. Result is cached by expression hash.
    /// Usage from AHK: CS.Eval("Math.Sqrt(144) + Math.PI")
    /// </summary>
    public object EvalExpression(string expression, string references)
    {
        string code = "using System; using System.Linq; using System.Collections.Generic; "
            + "using System.IO; using System.Text; using System.Text.RegularExpressions;\n"
            + "public class __Eval { public static object Run() { return " + expression + "; } }";
        string id = RuntimeCompiler.CompileModule(code, references ?? "");
        return RuntimeCompiler.InvokeModule(id, "__Eval", "Run", new object[0]);
    }

    // ── Garbage Collection & Memory ───────────────────────────────────────
    /// <summary>Forces a full GC cycle and waits for finalizers.</summary>
    public void ForceGC()
    {
        GC.Collect(GC.MaxGeneration, GCCollectionMode.Forced);
        GC.WaitForPendingFinalizers();
        GC.Collect();
    }

    /// <summary>Returns current managed heap size in bytes.</summary>
    public long GetMemoryUsage()
    {
        return GC.GetTotalMemory(false);
    }

    // ── NuGet Package Manager ─────────────────────────────────────────────
    /// <summary>Downloads and extracts a NuGet package. Returns install path.</summary>
    public string NuGetInstall(string packageId, string version)
    {
        return NuGetManager.Install(packageId, version);
    }

    /// <summary>Returns semicolon-separated DLL paths for a cached package.</summary>
    public string NuGetGetRefs(string packageId, string version)
    {
        return NuGetManager.GetReferences(packageId, version);
    }

    /// <summary>Checks if a package version is already cached locally.</summary>
    public bool NuGetIsInstalled(string packageId, string version)
    {
        return NuGetManager.IsInstalled(packageId, version);
    }

    /// <summary>Resolves the latest stable version of a package from nuget.org.</summary>
    public string NuGetResolveVersion(string packageId)
    {
        return NuGetManager.ResolveLatestVersion(packageId);
    }

    /// <summary>Checks a .nupkg against nuget.org's published SHA-512: "verified sha512", "mismatch: ...", "unverifiable: ...".</summary>
    public string NuGetVerify(string packageId, string version, string nupkgPath)
    {
        return NuGetManager.Verify(packageId, version, nupkgPath);
    }

    /// <summary>verify: check every download; strict: fail when a hash cannot be fetched.</summary>
    public void NuGetSetPolicy(bool verify, bool strict)
    {
        NuGetManager.VerifyDownloads = verify;
        NuGetManager.StrictVerification = strict;
    }

    /// <summary>Returns a status message about the current NuGet operation.</summary>
    public string NuGetStatus()
    {
        return NuGetManager.LastStatus;
    }

    /// <summary>Searches nuget.org; lines "id|usableVersion|latestVersion|downloads|description".</summary>
    public string NuGetSearch(string query, int take, bool includeIncompatible)
    {
        return NuGetManager.Search(query, take, includeIncompatible);
    }

    /// <summary>Uninstalls and removes a NuGet package directory.</summary>
    public bool NuGetUninstall(string packageId, string version)
    {
        return NuGetManager.Uninstall(packageId, version);
    }

    // ── Delegate Bridge — AHK Function → C# Event ────────────────────────
    /// <summary>Registers an AHK IDispatch callable for use as a C# callback.</summary>
    public int RegisterDelegate(object ahkCallable, long ahkHwnd, int callbackMsg)
    {
        return DelegateBridge.Register(ahkCallable, (IntPtr)ahkHwnd, callbackMsg);
    }

    /// <summary>Subscribes a registered delegate to a .NET event on a target object.</summary>
    public void SubscribeEvent(object target, string eventName, int delegateId)
    {
        DelegateBridge.Subscribe(target, eventName, delegateId);
    }

    /// <summary>Called from AHK main thread to execute a queued delegate callback.</summary>
    public object InvokeDelegate(int delegateId)
    {
        return DelegateBridge.InvokeQueued(delegateId);
    }

    /// <summary>Unregisters a delegate and removes its event subscription.</summary>
    public void UnregisterDelegate(int delegateId)
    {
        DelegateBridge.Unregister(delegateId);
    }

    // ── Cross-Module & Precompile ─────────────────────────────────────────
    /// <summary>Returns the file path of a compiled module's cached DLL.</summary>
    public string GetModulePath(string assemblyId)
    {
        return RuntimeCompiler.GetModulePath(assemblyId);
    }

    /// <summary>Copies a compiled module DLL to an output path for distribution.</summary>
    public void CopyModuleDLL(string assemblyId, string outputPath)
    {
        string srcPath = RuntimeCompiler.GetModulePath(assemblyId);
        if (!File.Exists(srcPath))
            throw new FileNotFoundException("Compiled module not found: " + assemblyId);
        string dir = Path.GetDirectoryName(outputPath);
        if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
            Directory.CreateDirectory(dir);
        File.Copy(srcPath, outputPath, true);
    }

    /// <summary>Loads a precompiled DLL and registers it as a module.</summary>
    public string LoadPrecompiled(string dllPath)
    {
        return RuntimeCompiler.LoadPrecompiled(dllPath);
    }

    /// <summary>Compiles a CSModule with optional C# language version targeting.</summary>
    public string CompileModuleVersioned(string csCode, string references, string langVersion)
    {
        if (string.IsNullOrEmpty(langVersion))
            return RuntimeCompiler.CompileModule(csCode, references);
        return RuntimeCompiler.CompileModuleVersioned(csCode, references, langVersion);
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    internal static object CoerceValue(Type targetType, object value)
    {
        object converted;
        if (OverloadBinder.Coerce(value, targetType, out converted) < 0)
            throw new InvalidCastException("Cannot convert "
                + (value == null ? "null" : value.GetType().Name) + " to " + targetType.Name);
        return converted;
    }
}

