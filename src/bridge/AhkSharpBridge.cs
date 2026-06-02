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
using System.Net;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using Microsoft.CSharp;

[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]
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

    // ── Diagnostic ─────────────────────────────────────────────────────────
    /// <summary>Returns version string for connectivity test.</summary>
    public string Ping() { return "AHK# Bridge v1.0 OK"; }

    // ── Static Method Invocation ──────────────────────────────────────────
    // CS.System.Math.Pow(5, 3) routes here
    public object InvokeStatic(string typeName, string methodName, object args)
    {
        try
        {
            Type t = TypeResolver.Resolve(typeName);
            if (t == null)
                throw new TypeLoadException("Type not found: " + typeName);

            object[] a = MarshalEngine.UnpackArgs(args);

            // Handle enum parsing: if methodName == "__enum" treat args[0] as enum value name
            if (methodName == "__enum" && t.IsEnum)
                return Enum.Parse(t, Convert.ToString(a[0]), true);

            // Find method with best parameter match
            MethodInfo mi = ResolveMethod(t, methodName, a, BindingFlags.Static | BindingFlags.Public | BindingFlags.FlattenHierarchy);
            if (mi == null)
                throw new MissingMethodException(typeName, methodName);

            object result = mi.Invoke(null, CoerceArgs(mi.GetParameters(), a));
            return MarshalEngine.PackResult(result);
        }
        catch (TargetInvocationException ex)
        {
            throw ex.InnerException ?? ex;
        }
    }

    // ── Object Construction ───────────────────────────────────────────────
    // CS.System.Text.StringBuilder() routes here
    public object CreateInstance(string typeName, object args)
    {
        try
        {
            Type t = TypeResolver.Resolve(typeName);
            if (t == null)
                throw new TypeLoadException("Type not found: " + typeName);

            object[] a = MarshalEngine.UnpackArgs(args);

            if (a.Length == 0)
                return Activator.CreateInstance(t);

            // Find best constructor match
            ConstructorInfo[] ctors = t.GetConstructors(BindingFlags.Public | BindingFlags.Instance);
            foreach (ConstructorInfo ci in ctors)
            {
                ParameterInfo[] ps = ci.GetParameters();
                if (ps.Length == a.Length)
                {
                    try
                    {
                        return ci.Invoke(CoerceArgs(ps, a));
                    }
                    catch { continue; }
                }
            }

            // Fallback — let Activator try
            return Activator.CreateInstance(t, a);
        }
        catch (TargetInvocationException ex)
        {
            throw ex.InnerException ?? ex;
        }
    }

    // ── Instance Method Invocation ────────────────────────────────────────
    public object InvokeMember(object target, string memberName, object args)
    {
        try
        {
            if (target == null)
                throw new ArgumentNullException("target");

            object[] a = MarshalEngine.UnpackArgs(args);
            Type t = target.GetType();

            MethodInfo mi = ResolveMethod(t, memberName, a,
                BindingFlags.Instance | BindingFlags.Public | BindingFlags.FlattenHierarchy);

            if (mi == null)
            {
                // Try extension methods on common LINQ types
                mi = ResolveLINQExtension(t, memberName, a);
            }

            if (mi == null)
                throw new MissingMethodException(t.FullName, memberName);

            if (mi.IsStatic)
            {
                // Extension method — prepend target to args
                object[] extArgs = new object[a.Length + 1];
                extArgs[0] = target;
                Array.Copy(a, 0, extArgs, 1, a.Length);
                object result = mi.Invoke(null, extArgs);
                return MarshalEngine.PackResult(result);
            }
            else
            {
                object result = mi.Invoke(target, CoerceArgs(mi.GetParameters(), a));
                return MarshalEngine.PackResult(result);
            }
        }
        catch (TargetInvocationException ex)
        {
            throw ex.InnerException ?? ex;
        }
    }

    // ── Property Get ──────────────────────────────────────────────────────
    public object GetProperty(object target, string propertyName)
    {
        if (target == null) throw new ArgumentNullException("target");
        Type t = target.GetType();

        PropertyInfo pi = t.GetProperty(propertyName,
            BindingFlags.Instance | BindingFlags.Public | BindingFlags.FlattenHierarchy);
        if (pi != null)
            return MarshalEngine.PackResult(pi.GetValue(target, null));

        FieldInfo fi = t.GetField(propertyName,
            BindingFlags.Instance | BindingFlags.Public | BindingFlags.FlattenHierarchy);
        if (fi != null)
            return MarshalEngine.PackResult(fi.GetValue(target));

        throw new MissingMemberException(t.FullName, propertyName);
    }

    // ── Static Property Get ───────────────────────────────────────────────
    public object GetStaticProperty(string typeName, string propertyName)
    {
        Type t = TypeResolver.Resolve(typeName);
        if (t == null) throw new TypeLoadException("Type not found: " + typeName);

        PropertyInfo pi = t.GetProperty(propertyName,
            BindingFlags.Static | BindingFlags.Public | BindingFlags.FlattenHierarchy);
        if (pi != null)
            return MarshalEngine.PackResult(pi.GetValue(null, null));

        FieldInfo fi = t.GetField(propertyName,
            BindingFlags.Static | BindingFlags.Public | BindingFlags.FlattenHierarchy);
        if (fi != null)
            return MarshalEngine.PackResult(fi.GetValue(null));

        // Could be a nested type
        Type nested = t.GetNestedType(propertyName, BindingFlags.Public);
        if (nested != null)
            return "__type__:" + nested.FullName;

        throw new MissingMemberException(typeName, propertyName);
    }

    // ── Property Set ──────────────────────────────────────────────────────
    public void SetProperty(object target, string propertyName, object value)
    {
        if (target == null) throw new ArgumentNullException("target");
        Type t = target.GetType();

        PropertyInfo pi = t.GetProperty(propertyName,
            BindingFlags.Instance | BindingFlags.Public | BindingFlags.FlattenHierarchy);
        if (pi != null)
        {
            pi.SetValue(target, CoerceValue(pi.PropertyType, value), null);
            return;
        }

        FieldInfo fi = t.GetField(propertyName,
            BindingFlags.Instance | BindingFlags.Public | BindingFlags.FlattenHierarchy);
        if (fi != null)
        {
            fi.SetValue(target, CoerceValue(fi.FieldType, value));
            return;
        }

        throw new MissingMemberException(t.FullName, propertyName);
    }

    // ── Static Property Set ───────────────────────────────────────────────
    public void SetStaticProperty(string typeName, string propertyName, object value)
    {
        Type t = TypeResolver.Resolve(typeName);
        if (t == null) throw new TypeLoadException("Type not found: " + typeName);

        PropertyInfo pi = t.GetProperty(propertyName,
            BindingFlags.Static | BindingFlags.Public | BindingFlags.FlattenHierarchy);
        if (pi != null)
        {
            pi.SetValue(null, CoerceValue(pi.PropertyType, value), null);
            return;
        }

        FieldInfo fi = t.GetField(propertyName,
            BindingFlags.Static | BindingFlags.Public | BindingFlags.FlattenHierarchy);
        if (fi != null)
        {
            fi.SetValue(null, CoerceValue(fi.FieldType, value));
            return;
        }

        throw new MissingMemberException(typeName, propertyName);
    }

    // ── Indexer Access ────────────────────────────────────────────────────
    public object GetIndex(object target, object index)
    {
        if (target == null) throw new ArgumentNullException("target");
        Type t = target.GetType();

        // Array types
        if (target is Array)
            return MarshalEngine.PackResult(((Array)target).GetValue(Convert.ToInt32(index)));

        // IList
        if (target is IList)
            return MarshalEngine.PackResult(((IList)target)[Convert.ToInt32(index)]);

        // IDictionary
        if (target is IDictionary)
            return MarshalEngine.PackResult(((IDictionary)target)[index]);

        // Default indexer
        PropertyInfo indexer = t.GetProperty("Item",
            BindingFlags.Instance | BindingFlags.Public);
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
        Type t = target.GetType();

        if (target is IList)
        {
            ((IList)target)[Convert.ToInt32(index)] = value;
            return;
        }
        if (target is IDictionary)
        {
            ((IDictionary)target)[index] = value;
            return;
        }

        PropertyInfo indexer = t.GetProperty("Item",
            BindingFlags.Instance | BindingFlags.Public);
        if (indexer != null)
        {
            ParameterInfo[] ps = indexer.GetIndexParameters();
            indexer.SetValue(target, value, new[] { CoerceValue(ps[0].ParameterType, index) });
            return;
        }

        throw new InvalidOperationException("Type " + t.FullName + " does not support index assignment");
    }

    // ── Enumeration Support ───────────────────────────────────────────────
    public object GetEnumerator(object target)
    {
        if (target is IEnumerable)
            return ((IEnumerable)target).GetEnumerator();
        throw new InvalidOperationException("Object does not implement IEnumerable");
    }

    public bool MoveNext(object enumerator)
    {
        return ((IEnumerator)enumerator).MoveNext();
    }

    public object GetCurrent(object enumerator)
    {
        return MarshalEngine.PackResult(((IEnumerator)enumerator).Current);
    }

    // ── Reflection Introspection ──────────────────────────────────────────
    public string GetMembers(object target)
    {
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

    public string GetTypeName(object target)
    {
        return target == null ? "null" : target.GetType().FullName;
    }

    public bool IsType(object target, string typeName)
    {
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
        if (target is IDisposable)
            ((IDisposable)target).Dispose();
    }

    // ── ToString ──────────────────────────────────────────────────────────
    public string ObjectToString(object target)
    {
        return target == null ? "" : target.ToString();
    }

    // ── Runtime Compilation (CSModule) ─────────────────────────────────────
    public object CompileAndInvoke(string csCode, string className, string methodName, object args, string references)
    {
        return RuntimeCompiler.CompileAndInvoke(csCode, className, methodName, MarshalEngine.UnpackArgs(args), references);
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

    /// <summary>Removes a compiled module from the in-memory cache.</summary>
    public void UnloadModule(string assemblyId)
    {
        RuntimeCompiler.UnloadModule(assemblyId);
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

    /// <summary>Returns a status message about the current NuGet operation.</summary>
    public string NuGetStatus()
    {
        return NuGetManager.LastStatus;
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

    /// <summary>Gets the serialized args from the last delegate invocation.</summary>
    public object GetDelegateArgs(int delegateId)
    {
        return DelegateBridge.GetLastArgs(delegateId);
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

    private static MethodInfo ResolveMethod(Type type, string name, object[] args, BindingFlags flags)
    {
        MethodInfo[] methods = type.GetMethods(flags).Where(m => m.Name == name).ToArray();

        // Exact parameter count match first
        foreach (MethodInfo m in methods)
        {
            ParameterInfo[] ps = m.GetParameters();
            if (ps.Length == args.Length)
            {
                bool match = true;
                for (int i = 0; i < ps.Length; i++)
                {
                    if (args[i] != null && !CanCoerce(args[i].GetType(), ps[i].ParameterType))
                    { match = false; break; }
                }
                if (match) return m;
            }
        }

        // Relaxed match — just count
        foreach (MethodInfo m in methods)
        {
            if (m.GetParameters().Length == args.Length)
                return m;
        }

        // params[] match
        foreach (MethodInfo m in methods)
        {
            ParameterInfo[] ps = m.GetParameters();
            if (ps.Length > 0 && ps.Last().GetCustomAttributes(typeof(ParamArrayAttribute), false).Length > 0)
            {
                if (args.Length >= ps.Length - 1)
                    return m;
            }
        }

        return methods.Length > 0 ? methods[0] : null;
    }

    private static MethodInfo ResolveLINQExtension(Type targetType, string methodName, object[] args)
    {
        // Search System.Linq.Enumerable for extension methods
        Type enumerable = typeof(System.Linq.Enumerable);
        foreach (MethodInfo m in enumerable.GetMethods(BindingFlags.Static | BindingFlags.Public))
        {
            if (m.Name == methodName)
                return m;
        }
        return null;
    }

    private static bool CanCoerce(Type from, Type to)
    {
        if (to.IsAssignableFrom(from)) return true;
        if (to.IsPrimitive && from.IsPrimitive) return true;
        if (to == typeof(string)) return true;
        if (to == typeof(object)) return true;
        return false;
    }

    internal static object[] CoerceArgs(ParameterInfo[] parameters, object[] args)
    {
        if (parameters.Length == 0) return new object[0];
        if (args == null) args = new object[0];

        object[] result = new object[parameters.Length];

        // If more args than params, pack excess into last param as object[]
        // This enables variadic-style calls: Build("k1","v1","k2","v2") → Build(object pairs)
        if (args.Length > parameters.Length && parameters.Length > 0)
        {
            var lastParam = parameters[parameters.Length - 1];
            bool isParams = lastParam.GetCustomAttributes(typeof(ParamArrayAttribute), false).Length > 0;
            bool isObjOrArr = lastParam.ParameterType == typeof(object)
                           || lastParam.ParameterType == typeof(object[]);

            if (isParams || isObjOrArr)
            {
                // Fill preceding params normally
                for (int i = 0; i < parameters.Length - 1; i++)
                {
                    if (i < args.Length)
                        result[i] = CoerceValue(parameters[i].ParameterType, args[i]);
                    else if (parameters[i].HasDefaultValue)
                        result[i] = parameters[i].DefaultValue;
                    else
                        result[i] = parameters[i].ParameterType.IsValueType
                            ? Activator.CreateInstance(parameters[i].ParameterType) : null;
                }

                // Pack remaining args into the last parameter
                int startIdx = parameters.Length - 1;
                int extraCount = args.Length - startIdx;
                object[] packed = new object[extraCount];
                for (int j = 0; j < extraCount; j++)
                    packed[j] = args[startIdx + j];

                result[parameters.Length - 1] = lastParam.ParameterType == typeof(object)
                    ? (object)packed : packed;
                return result;
            }
        }

        // Standard case: 1:1 param mapping
        for (int i = 0; i < parameters.Length; i++)
        {
            if (i < args.Length)
                result[i] = CoerceValue(parameters[i].ParameterType, args[i]);
            else if (parameters[i].HasDefaultValue)
                result[i] = parameters[i].DefaultValue;
            else
                result[i] = parameters[i].ParameterType.IsValueType
                    ? Activator.CreateInstance(parameters[i].ParameterType) : null;
        }
        return result;
    }

    internal static object CoerceValue(Type targetType, object value)
    {
        if (value == null)
            return targetType.IsValueType ? Activator.CreateInstance(targetType) : null;
        if (targetType.IsInstanceOfType(value))
            return value;
        if (targetType.IsEnum)
            return Enum.Parse(targetType, Convert.ToString(value), true);

        try { return Convert.ChangeType(value, targetType, CultureInfo.InvariantCulture); }
        catch { return value; }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Type Resolver — FQN to System.Type with assembly scanning + caching
// ─────────────────────────────────────────────────────────────────────────────

internal static class TypeResolver
{
    private static readonly Dictionary<string, Type> _cache = new Dictionary<string, Type>(StringComparer.OrdinalIgnoreCase);
    private static readonly List<Assembly> _extraAssemblies = new List<Assembly>();
    private static bool _scanned = false;

    public static Type Resolve(string name)
    {
        if (string.IsNullOrEmpty(name)) return null;

        Type cached;
        lock (_cache)
        {
            if (_cache.TryGetValue(name, out cached))
                return cached;
        }

        // 1. Direct type lookup
        Type t = Type.GetType(name, false, true);

        // 2. Search loaded assemblies
        if (t == null)
        {
            foreach (Assembly asm in AppDomain.CurrentDomain.GetAssemblies())
            {
                t = asm.GetType(name, false, true);
                if (t != null) break;
            }
        }

        // 3. Search extra loaded assemblies
        if (t == null)
        {
            lock (_extraAssemblies)
            {
                foreach (Assembly asm in _extraAssemblies)
                {
                    t = asm.GetType(name, false, true);
                    if (t != null) break;
                }
            }
        }

        // 4. Try common assembly-qualified names
        if (t == null)
        {
            string[] commonAssemblies = {
                "mscorlib", "System", "System.Core", "System.Data",
                "System.Drawing", "System.Windows.Forms", "System.Xml",
                "System.Xml.Linq", "System.Net.Http",
                "WindowsBase", "PresentationCore", "PresentationFramework",
                "UIAutomationClient", "UIAutomationTypes"
            };

            foreach (string asmName in commonAssemblies)
            {
                try
                {
                    Assembly asm = Assembly.Load(asmName);
                    t = asm.GetType(name, false, true);
                    if (t != null) break;
                }
                catch { }
            }
        }

        // 5. Brute-force scan all types (first time only)
        if (t == null && !_scanned)
        {
            _scanned = true;
            foreach (Assembly asm in AppDomain.CurrentDomain.GetAssemblies())
            {
                try
                {
                    foreach (Type exported in asm.GetExportedTypes())
                    {
                        if (exported.FullName != null)
                        {
                            lock (_cache)
                            {
                                _cache[exported.FullName] = exported;
                                // Also cache by short name if unambiguous
                                if (!_cache.ContainsKey(exported.Name))
                                    _cache[exported.Name] = exported;
                            }
                        }
                    }
                }
                catch { }
            }

            lock (_cache)
            {
                if (_cache.TryGetValue(name, out t))
                    return t;
            }
        }

        if (t != null)
        {
            lock (_cache) { _cache[name] = t; }
        }

        return t;
    }

    public static void LoadAssembly(string pathOrName)
    {
        Assembly asm;
        if (File.Exists(pathOrName))
            asm = Assembly.LoadFrom(pathOrName);
        else
            asm = Assembly.Load(pathOrName);

        lock (_extraAssemblies)
        {
            _extraAssemblies.Add(asm);
        }

        // Invalidate brute-force scan flag so new assembly gets scanned
        _scanned = false;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Marshal Engine — CLR ↔ SafeArray/COM auto-marshalling
// ─────────────────────────────────────────────────────────────────────────────

internal static class MarshalEngine
{
    /// <summary>
    /// Unpacks COM VARIANT/SafeArray args from AHK into a flat object[].
    /// AHK passes params as either a single value, a SafeArray, or null.
    /// </summary>
    public static object[] UnpackArgs(object args)
    {
        if (args == null || args is DBNull)
            return new object[0];

        // AHK passes "" for no arguments
        string s = args as string;
        if (s != null && s.Length == 0)
            return new object[0];

        // If it's already an array, use it directly
        if (args is object[])
            return (object[])args;

        // SafeArray from AHK (arrives as System.Array wrapped in object)
        if (args is Array)
        {
            Array arr = (Array)args;
            object[] result = new object[arr.Length];
            for (int i = 0; i < arr.Length; i++)
                result[i] = arr.GetValue(i);
            return result;
        }

        // Single value — wrap in array
        return new object[] { args };
    }

    /// <summary>
    /// Packs a CLR return value for COM consumption by AHK.
    /// Primitive types pass through. Collections become SafeArrays.
    /// Complex objects pass through as COM references (wrapped by CSProxy on AHK side).
    /// </summary>
    public static object PackResult(object value)
    {
        if (value == null) return null;

        Type t = value.GetType();

        // Primitives and strings pass through
        if (t.IsPrimitive || value is string || value is decimal || value is DateTime)
            return value;

        // Byte arrays pass through for binary data
        if (value is byte[])
            return value;

        // Arrays → pass through (AHK can handle SafeArrays)
        if (value is Array)
            return value;

        // Value types without IDispatch (Guid, TimeSpan, etc.) can't survive
        // COM round-trips — convert to string for safe AHK consumption
        if (t.IsValueType)
            return value.ToString();

        // For complex objects: pass the object reference directly.
        // AHK's CSProxy wrapper will handle member access via InvokeMember/GetProperty.
        return value;
    }

    /// <summary>
    /// Deep-converts a CLR collection to a SafeArray for AHK native unwrapping.
    /// Called explicitly by user when they want AHK-native arrays.
    /// </summary>
    public static object ToSafeArray(object clrObject)
    {
        if (clrObject == null) return null;

        // List<T> → object[]
        if (clrObject is IList)
        {
            IList list = (IList)clrObject;
            object[] result = new object[list.Count];
            for (int i = 0; i < list.Count; i++)
                result[i] = PackResult(list[i]);
            return result;
        }

        // Dictionary<K,V> → 2D SafeArray [key, value] pairs
        if (clrObject is IDictionary)
        {
            IDictionary dict = (IDictionary)clrObject;
            object[,] result = new object[dict.Count, 2];
            int row = 0;
            foreach (DictionaryEntry entry in dict)
            {
                result[row, 0] = PackResult(entry.Key);
                result[row, 1] = PackResult(entry.Value);
                row++;
            }
            return result;
        }

        // IEnumerable → object[]
        if (clrObject is IEnumerable)
        {
            var items = new List<object>();
            foreach (object item in (IEnumerable)clrObject)
                items.Add(PackResult(item));
            return items.ToArray();
        }

        return clrObject;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Runtime Compiler — CSharpCodeProvider for CSModule + dynamic compilation
// ─────────────────────────────────────────────────────────────────────────────

internal static class RuntimeCompiler
{
    private static readonly ConcurrentDictionary<string, Assembly> _cache =
        new ConcurrentDictionary<string, Assembly>(StringComparer.Ordinal);

    private static readonly string _cacheDir;

    private static readonly ConcurrentDictionary<string, string> _resolvedPaths =
        new ConcurrentDictionary<string, string>(StringComparer.OrdinalIgnoreCase);

    static RuntimeCompiler()
    {
        _cacheDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "AhkSharp", "CompileCache");
        if (!Directory.Exists(_cacheDir))
            Directory.CreateDirectory(_cacheDir);

        AppDomain.CurrentDomain.AssemblyResolve += CurrentDomain_AssemblyResolve;
    }

    private static Assembly CurrentDomain_AssemblyResolve(object sender, ResolveEventArgs args)
    {
        AssemblyName asmName = new AssemblyName(args.Name);
        string shortName = asmName.Name;

        string path;
        if (_resolvedPaths.TryGetValue(shortName, out path))
        {
            if (File.Exists(path))
            {
                try { return Assembly.LoadFrom(path); }
                catch { }
            }
        }
        return null;
    }

    private static string ComputeHash(string source)
    {
        using (SHA256 sha = SHA256.Create())
        {
            byte[] hash = sha.ComputeHash(Encoding.UTF8.GetBytes(source));
            return BitConverter.ToString(hash).Replace("-", "").Substring(0, 16);
        }
    }

    private static void RegisterResolvedPaths(string references)
    {
        if (string.IsNullOrEmpty(references))
            return;

        foreach (string r in references.Split(';'))
        {
            string trimmed = r.Trim();
            if (!string.IsNullOrEmpty(trimmed))
            {
                if (File.Exists(trimmed))
                {
                    try
                    {
                        string sName = Path.GetFileNameWithoutExtension(trimmed);
                        _resolvedPaths[sName] = trimmed;
                        Assembly.LoadFrom(trimmed);
                    }
                    catch { }
                }
            }
        }
    }

    public static string CompileModule(string csCode, string references)
    {
        string hash = ComputeHash(csCode + "|" + references);

        if (_cache.ContainsKey(hash))
            return hash;

        // Ensure all references (especially NuGet packages) are registered and pre-loaded even if loading from cache
        RegisterResolvedPaths(references);

        // Wrap user code in a namespace if not already namespaced
        string fullCode = csCode;
        if (!csCode.Contains("namespace ") && !csCode.Contains("class "))
        {
            fullCode = "using System; using System.Linq; using System.Collections.Generic;\n" + csCode;
        }
        else if (!csCode.Contains("using System"))
        {
            fullCode = "using System; using System.Linq; using System.Collections.Generic;\n" + csCode;
        }

        // Check disk cache
        string cachedDll = Path.Combine(_cacheDir, hash + ".dll");
        if (File.Exists(cachedDll))
        {
            Assembly asm = Assembly.LoadFrom(cachedDll);
            _cache[hash] = asm;
            return hash;
        }

        // Compile
        CSharpCodeProvider provider = new CSharpCodeProvider();
        CompilerParameters cp = new CompilerParameters();
        cp.GenerateInMemory = false;
        cp.OutputAssembly = cachedDll;
        cp.ReferencedAssemblies.Add("System.dll");
        cp.ReferencedAssemblies.Add("System.Core.dll");
        cp.ReferencedAssemblies.Add("Microsoft.CSharp.dll");
        cp.ReferencedAssemblies.Add("System.Data.dll");
        cp.ReferencedAssemblies.Add("System.Xml.dll");
        cp.ReferencedAssemblies.Add(@"C:\Windows\Microsoft.NET\Framework64\v4.0.30319\System.Runtime.WindowsRuntime.dll");

        if (!string.IsNullOrEmpty(references))
        {
            foreach (string r in references.Split(';'))
            {
                string trimmed = r.Trim();
                if (!string.IsNullOrEmpty(trimmed))
                {
                    cp.ReferencedAssemblies.Add(trimmed);

                    // Pre-load non-GAC assemblies so they're available at runtime
                    if (File.Exists(trimmed))
                    {
                        try
                        {
                            string sName = Path.GetFileNameWithoutExtension(trimmed);
                            _resolvedPaths[sName] = trimmed;
                            Assembly.LoadFrom(trimmed);
                        }
                        catch { /* ignore load failures — compiler will report */ }
                    }
                }
            }
        }

        CompilerResults cr = provider.CompileAssemblyFromSource(cp, fullCode);
        if (cr.Errors.HasErrors)
        {
            StringBuilder sb = new StringBuilder("Compilation failed:\n");
            foreach (CompilerError err in cr.Errors)
            {
                if (!err.IsWarning)
                    sb.AppendLine(string.Format("  Line {0}: {1}", err.Line, err.ErrorText));
            }
            throw new InvalidOperationException(sb.ToString());
        }

        _cache[hash] = cr.CompiledAssembly;
        return hash;
    }

    public static object InvokeModule(string assemblyId, string className, string methodName, object[] args)
    {
        Assembly asm;
        if (!_cache.TryGetValue(assemblyId, out asm))
        {
            string cachedDll = Path.Combine(_cacheDir, assemblyId + ".dll");
            if (File.Exists(cachedDll))
            {
                asm = Assembly.LoadFrom(cachedDll);
                _cache[assemblyId] = asm;
            }
            else
            {
                throw new InvalidOperationException("Assembly not found: " + assemblyId);
            }
        }

        Type t = null;
        foreach (Type exported in asm.GetExportedTypes())
        {
            if (exported.Name == className || exported.FullName == className)
            { t = exported; break; }
        }
        if (t == null)
            throw new TypeLoadException("Class not found in compiled assembly: " + className);

        MethodInfo mi = t.GetMethod(methodName,
            BindingFlags.Public | BindingFlags.Static | BindingFlags.Instance);
        if (mi == null)
            throw new MissingMethodException(className, methodName);

        try
        {
            if (mi.IsStatic)
            {
                return MarshalEngine.PackResult(
                    mi.Invoke(null, AhkSharpBridge.CoerceArgs(mi.GetParameters(), args)));
            }
            else
            {
                object instance = Activator.CreateInstance(t);
                return MarshalEngine.PackResult(
                    mi.Invoke(instance, AhkSharpBridge.CoerceArgs(mi.GetParameters(), args)));
            }
        }
        catch (System.Reflection.TargetInvocationException tie)
        {
            // Unwrap TargetInvocationException to surface the real error
            string innerMsg = tie.InnerException != null
                ? tie.InnerException.GetType().Name + ": " + tie.InnerException.Message
                : tie.Message;
            throw new InvalidOperationException(
                className + "." + methodName + "() failed: " + innerMsg,
                tie.InnerException ?? tie);
        }
    }

    public static object CompileAndInvoke(string csCode, string className, string methodName, object[] args, string references)
    {
        string id = CompileModule(csCode, references);
        return InvokeModule(id, className, methodName, args);
    }

    /// <summary>Public accessor for the compile cache directory path.</summary>
    public static string CacheDir { get { return _cacheDir; } }

    /// <summary>Removes a module from the in-memory cache (DLL stays on disk until process exit).</summary>
    public static void UnloadModule(string assemblyId)
    {
        Assembly removed;
        _cache.TryRemove(assemblyId, out removed);
        // Note: The assembly itself cannot be unloaded from the AppDomain.
        // This only removes it from our lookup cache so it won't be invoked.
        // The disk-cached DLL remains for future reloads.
    }

    /// <summary>Returns the full path to a compiled module's DLL on disk.</summary>
    public static string GetModulePath(string assemblyId)
    {
        return Path.Combine(_cacheDir, assemblyId + ".dll");
    }

    /// <summary>Loads a precompiled DLL and registers it in the module cache.
    /// Returns "hash|ClassName" so AHK can use the actual class name.</summary>
    public static string LoadPrecompiled(string dllPath)
    {
        if (!File.Exists(dllPath))
            throw new FileNotFoundException("Precompiled DLL not found: " + dllPath);

        // Hash the file content for a stable cache key
        byte[] fileBytes = File.ReadAllBytes(dllPath);
        string hash;
        using (SHA256 sha = SHA256.Create())
        {
            hash = BitConverter.ToString(sha.ComputeHash(fileBytes)).Replace("-", "").Substring(0, 16);
        }

        if (!_cache.ContainsKey(hash))
        {
            Assembly asm = Assembly.LoadFrom(dllPath);
            _cache[hash] = asm;
        }

        // Find the first public non-abstract class and return it with the hash
        Assembly loaded = _cache[hash];
        string className = "";
        foreach (Type exported in loaded.GetExportedTypes())
        {
            if (exported.IsClass && !exported.IsAbstract)
            { className = exported.Name; break; }
        }
        return hash + "|" + className;
    }

    /// <summary>
    /// Compiles with a specific C# language version via Roslyn.
    /// Requires Microsoft.CodeDom.Providers.DotNetCompilerPlatform (auto-installed via NuGet).
    /// </summary>
    public static string CompileModuleVersioned(string csCode, string references, string langVersion)
    {
        string hash = ComputeHash(csCode + "|" + references + "|v" + langVersion);

        if (_cache.ContainsKey(hash))
            return hash;

        // Ensure all references (especially NuGet packages) are registered and pre-loaded even if loading from cache
        RegisterResolvedPaths(references);

        // Wrap user code
        string fullCode = csCode;
        if (!csCode.Contains("namespace ") && !csCode.Contains("class "))
            fullCode = "using System; using System.Linq; using System.Collections.Generic;\n" + csCode;
        else if (!csCode.Contains("using System"))
            fullCode = "using System; using System.Linq; using System.Collections.Generic;\n" + csCode;

        // Check disk cache
        string cachedDll = Path.Combine(_cacheDir, hash + ".dll");
        if (File.Exists(cachedDll))
        {
            Assembly asm = Assembly.LoadFrom(cachedDll);
            _cache[hash] = asm;
            return hash;
        }

        // Ensure Roslyn compiler is available
        string roslynDir = NuGetManager.EnsureRoslyn();
        string roslynCsc = Path.Combine(roslynDir, "csc.exe");
        if (!File.Exists(roslynCsc))
            throw new InvalidOperationException("Roslyn csc.exe not found at: " + roslynCsc
                + "\nCannot compile with C# " + langVersion);

        // Compile using Roslyn csc.exe directly via Process
        // Write source to temp file
        string srcFile = Path.Combine(_cacheDir, hash + ".cs");
        File.WriteAllText(srcFile, fullCode, Encoding.UTF8);

        // Build reference list
        var refList = new List<string> {
            "System.dll", "System.Core.dll", "Microsoft.CSharp.dll",
            "System.Data.dll", "System.Xml.dll"
        };
        if (!string.IsNullOrEmpty(references))
        {
            foreach (string r in references.Split(';'))
            {
                string trimmed = r.Trim();
                if (!string.IsNullOrEmpty(trimmed))
                {
                    refList.Add(trimmed);
                    if (File.Exists(trimmed))
                    {
                        try
                        {
                            string sName = Path.GetFileNameWithoutExtension(trimmed);
                            _resolvedPaths[sName] = trimmed;
                        }
                        catch { }
                    }
                }
            }
        }

        string refArgs = string.Join(" ", refList.Select(r => "/reference:\"" + r + "\""));
        string fxDir = Path.GetDirectoryName(typeof(object).Assembly.Location);

        string args = string.Format(
            "/nologo /target:library /optimize+ /langversion:{0} /out:\"{1}\" /lib:\"{2}\" {3} \"{4}\"",
            langVersion, cachedDll, fxDir, refArgs, srcFile);

        var psi = new System.Diagnostics.ProcessStartInfo
        {
            FileName = roslynCsc,
            Arguments = args,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };

        using (var proc = System.Diagnostics.Process.Start(psi))
        {
            string stdout = proc.StandardOutput.ReadToEnd();
            string stderr = proc.StandardError.ReadToEnd();
            proc.WaitForExit();

            // Cleanup temp source
            try { File.Delete(srcFile); } catch { }

            if (proc.ExitCode != 0)
            {
                throw new InvalidOperationException(
                    "Roslyn compilation failed (C# " + langVersion + "):\n" + stdout + "\n" + stderr);
            }
        }

        Assembly compiled = Assembly.LoadFrom(cachedDll);
        _cache[hash] = compiled;
        return hash;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Async Router — ThreadPool dispatch → AHK Promise via PostMessage
// ─────────────────────────────────────────────────────────────────────────────

internal static class AsyncRouter
{
    [DllImport("user32.dll")]
    private static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    private static int _nextId = 0;

    private class TaskResult
    {
        public object Value;
        public Exception Error;
        public volatile bool Complete;
    }

    private static readonly ConcurrentDictionary<int, TaskResult> _tasks =
        new ConcurrentDictionary<int, TaskResult>();

    public static int Begin(object target, string methodName, object[] args, IntPtr ahkHwnd, int callbackMsg)
    {
        int id = Interlocked.Increment(ref _nextId);
        var result = new TaskResult();
        _tasks[id] = result;

        ThreadPool.QueueUserWorkItem(_ =>
        {
            try
            {
                object r = AhkSharpBridge.Instance.InvokeMember(target, methodName, args);
                result.Value = r;
            }
            catch (Exception ex)
            {
                result.Error = ex;
            }
            finally
            {
                result.Complete = true;
                if (ahkHwnd != IntPtr.Zero)
                    PostMessage(ahkHwnd, (uint)callbackMsg, (IntPtr)id, IntPtr.Zero);
            }
        });

        return id;
    }

    public static int BeginStatic(string typeName, string methodName, object[] args, IntPtr ahkHwnd, int callbackMsg)
    {
        int id = Interlocked.Increment(ref _nextId);
        var result = new TaskResult();
        _tasks[id] = result;

        ThreadPool.QueueUserWorkItem(_ =>
        {
            try
            {
                object r = AhkSharpBridge.Instance.InvokeStatic(typeName, methodName, args);
                result.Value = r;
            }
            catch (Exception ex)
            {
                result.Error = ex;
            }
            finally
            {
                result.Complete = true;
                if (ahkHwnd != IntPtr.Zero)
                    PostMessage(ahkHwnd, (uint)callbackMsg, (IntPtr)id, IntPtr.Zero);
            }
        });

        return id;
    }

    public static int BeginModule(string assemblyId, string className, string methodName, object[] args, IntPtr ahkHwnd, int callbackMsg)
    {
        int id = Interlocked.Increment(ref _nextId);
        var result = new TaskResult();
        _tasks[id] = result;

        ThreadPool.QueueUserWorkItem(_ =>
        {
            try
            {
                object r = RuntimeCompiler.InvokeModule(assemblyId, className, methodName, args);
                result.Value = r;
            }
            catch (Exception ex)
            {
                result.Error = ex;
            }
            finally
            {
                result.Complete = true;
                if (ahkHwnd != IntPtr.Zero)
                    PostMessage(ahkHwnd, (uint)callbackMsg, (IntPtr)id, IntPtr.Zero);
            }
        });

        return id;
    }

    public static object End(int taskId)
    {
        TaskResult r;
        if (!_tasks.TryGetValue(taskId, out r))
            throw new InvalidOperationException("Unknown task: " + taskId);

        // Spin-wait with message pumping (short wait, AHK pumps its own loop)
        while (!r.Complete)
            Thread.Sleep(1);

        TaskResult removed;
        _tasks.TryRemove(taskId, out removed);

        if (r.Error != null)
            throw r.Error;

        return MarshalEngine.PackResult(r.Value);
    }

    public static bool IsComplete(int taskId)
    {
        TaskResult r;
        return _tasks.TryGetValue(taskId, out r) && r.Complete;
    }

    public static string GetError(int taskId)
    {
        TaskResult r;
        if (_tasks.TryGetValue(taskId, out r) && r.Error != null)
            return r.Error.ToString();
        return null;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fast Parallel — CS.Fast.Map / Filter / Reduce via AsParallel()
// ─────────────────────────────────────────────────────────────────────────────

internal static class FastParallel
{
    public static object Map(object[] input, string lambdaBody, string references)
    {
        // Compile a class with a static method wrapping the lambda
        string code = string.Format(@"
using System; using System.Linq; using System.Collections.Generic;
public static class __FastLambda {{
    public static object Apply(object x) {{ return {0}; }}
}}", lambdaBody);

        string id = RuntimeCompiler.CompileModule(code, references ?? "");

        // Invoke in parallel
        object[] results = input
            .AsParallel()
            .AsOrdered()
            .Select(x => RuntimeCompiler.InvokeModule(id, "__FastLambda", "Apply", new[] { x }))
            .ToArray();

        return results;
    }

    public static object Filter(object[] input, string lambdaBody, string references)
    {
        string code = string.Format(@"
using System; using System.Linq; using System.Collections.Generic;
public static class __FastLambda {{
    public static bool Test(object x) {{ return {0}; }}
}}", lambdaBody);

        string id = RuntimeCompiler.CompileModule(code, references ?? "");

        object[] results = input
            .AsParallel()
            .AsOrdered()
            .Where(x => (bool)RuntimeCompiler.InvokeModule(id, "__FastLambda", "Test", new[] { x }))
            .ToArray();

        return results;
    }

    public static object Reduce(object[] input, string lambdaBody, object initial, string references)
    {
        string code = string.Format(@"
using System; using System.Linq; using System.Collections.Generic;
public static class __FastLambda {{
    public static object Combine(object acc, object x) {{ return {0}; }}
}}", lambdaBody);

        string id = RuntimeCompiler.CompileModule(code, references ?? "");

        object result = input.Aggregate(initial,
            (acc, x) => RuntimeCompiler.InvokeModule(id, "__FastLambda", "Combine", new[] { acc, x }));

        return MarshalEngine.PackResult(result);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// NuGet Package Manager — Download, extract, cache packages from nuget.org
// ─────────────────────────────────────────────────────────────────────────────
// .nupkg files are ZIP archives. DLLs live in lib/{framework}/ folders.
// We prefer: net48 → net472 → net462 → net45 → netstandard2.0 → netstandard1.x
// Cache dir: %LocalAppData%\AhkSharp\Packages\{id}\{version}\

internal static class NuGetManager
{
    private static readonly string _packagesDir;
    private static string _lastStatus = "";

    public static string LastStatus { get { return _lastStatus; } }

    static NuGetManager()
    {
        _packagesDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "AhkSharp", "Packages");
        if (!Directory.Exists(_packagesDir))
            Directory.CreateDirectory(_packagesDir);

        // Force TLS 1.2 for NuGet API
        ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072;
    }

    /// <summary>
    /// Downloads and extracts a NuGet package. Returns the package install directory.
    /// If version is empty, resolves the latest stable version.
    /// </summary>
    public static string Install(string packageId, string version)
    {
        if (string.IsNullOrEmpty(version))
            version = ResolveLatestVersion(packageId);

        string pkgDir = Path.Combine(_packagesDir, packageId.ToLowerInvariant(), version);
        string libDir = Path.Combine(pkgDir, "lib");

        // Already installed?
        if (Directory.Exists(libDir) && Directory.GetFiles(libDir, "*.dll", SearchOption.AllDirectories).Length > 0)
        {
            _lastStatus = "Already installed: " + packageId + " " + version;
            return pkgDir;
        }

        // Download the .nupkg
        _lastStatus = "Downloading " + packageId + " " + version + "...";
        string nupkgUrl = string.Format(
            "https://api.nuget.org/v3-flatcontainer/{0}/{1}/{0}.{1}.nupkg",
            packageId.ToLowerInvariant(), version);

        string nupkgPath = Path.Combine(pkgDir, packageId + "." + version + ".nupkg");
        if (!Directory.Exists(pkgDir))
            Directory.CreateDirectory(pkgDir);

        using (var client = new WebClient())
        {
            client.Headers.Add("User-Agent", "AHK-Sharp/2.0");
            client.DownloadFile(nupkgUrl, nupkgPath);
        }

        // Extract
        _lastStatus = "Extracting " + packageId + "...";
        string extractDir = Path.Combine(pkgDir, "_extract");
        if (Directory.Exists(extractDir))
            Directory.Delete(extractDir, true);

        ZipFile.ExtractToDirectory(nupkgPath, extractDir);

        // Find best framework target
        string extractLib = Path.Combine(extractDir, "lib");
        if (Directory.Exists(extractLib))
        {
            string bestFx = FindBestFramework(extractLib);
            if (bestFx != null)
            {
                if (!Directory.Exists(libDir))
                    Directory.CreateDirectory(libDir);

                foreach (string file in Directory.GetFiles(bestFx))
                {
                    string dest = Path.Combine(libDir, Path.GetFileName(file));
                    File.Copy(file, dest, true);
                }
            }
        }

        // Also copy any native runtimes (for packages like SQLitePCLRaw)
        string runtimesDir = Path.Combine(extractDir, "runtimes");
        if (Directory.Exists(runtimesDir))
        {
            string destRuntimes = Path.Combine(pkgDir, "runtimes");
            CopyDirectory(runtimesDir, destRuntimes);
        }

        // Also check for tools (some packages like Roslyn put csc.exe in tools/)
        string toolsDir = Path.Combine(extractDir, "tools");
        if (Directory.Exists(toolsDir))
        {
            string destTools = Path.Combine(pkgDir, "tools");
            CopyDirectory(toolsDir, destTools);
        }

        // Cleanup
        try { Directory.Delete(extractDir, true); } catch { }
        try { File.Delete(nupkgPath); } catch { }

        _lastStatus = "Installed: " + packageId + " " + version;
        return pkgDir;
    }

    /// <summary>Returns semicolon-separated paths to all DLLs for a package.</summary>
    public static string GetReferences(string packageId, string version)
    {
        if (string.IsNullOrEmpty(version))
            version = ResolveLatestVersion(packageId);

        string libDir = Path.Combine(_packagesDir, packageId.ToLowerInvariant(), version, "lib");
        if (!Directory.Exists(libDir))
            return "";

        string[] dlls = Directory.GetFiles(libDir, "*.dll", SearchOption.TopDirectoryOnly);
        return string.Join(";", dlls);
    }

    /// <summary>Checks if a package is already cached.</summary>
    public static bool IsInstalled(string packageId, string version)
    {
        if (string.IsNullOrEmpty(version))
        {
            // Check if any version exists
            string pkgRoot = Path.Combine(_packagesDir, packageId.ToLowerInvariant());
            return Directory.Exists(pkgRoot) && Directory.GetDirectories(pkgRoot).Length > 0;
        }

        string libDir = Path.Combine(_packagesDir, packageId.ToLowerInvariant(), version, "lib");
        return Directory.Exists(libDir) && Directory.GetFiles(libDir, "*.dll", SearchOption.AllDirectories).Length > 0;
    }

    /// <summary>Uninstalls and removes a NuGet package directory.</summary>
    public static bool Uninstall(string packageId, string version)
    {
        if (string.IsNullOrEmpty(packageId))
            return false;

        string pkgDir = Path.Combine(_packagesDir, packageId.ToLowerInvariant());
        if (!Directory.Exists(pkgDir))
        {
            _lastStatus = "Package " + packageId + " not found.";
            return false;
        }

        try
        {
            if (string.IsNullOrEmpty(version) || version == "*" || version.ToLowerInvariant() == "all")
            {
                Directory.Delete(pkgDir, true);
                _lastStatus = "Successfully removed package: " + packageId;
                return true;
            }
            else
            {
                string verDir = Path.Combine(pkgDir, version);
                if (Directory.Exists(verDir))
                {
                    Directory.Delete(verDir, true);

                    // If no other versions remain, delete parent package folder
                    if (Directory.GetDirectories(pkgDir).Length == 0 && Directory.GetFiles(pkgDir).Length == 0)
                    {
                        Directory.Delete(pkgDir, true);
                    }

                    _lastStatus = "Successfully removed " + packageId + " " + version;
                    return true;
                }
                else
                {
                    _lastStatus = "Version " + version + " of " + packageId + " not found.";
                    return false;
                }
            }
        }
        catch (Exception ex)
        {
            _lastStatus = "Failed to uninstall " + packageId + ": " + ex.Message;
            return false;
        }
    }

    /// <summary>Resolves the latest stable version via NuGet v3 API.</summary>
    public static string ResolveLatestVersion(string packageId)
    {
        _lastStatus = "Resolving latest version of " + packageId + "...";
        string url = string.Format(
            "https://api.nuget.org/v3-flatcontainer/{0}/index.json",
            packageId.ToLowerInvariant());

        string json;
        using (var client = new WebClient())
        {
            client.Headers.Add("User-Agent", "AHK-Sharp/2.0");
            json = client.DownloadString(url);
        }

        // Simple JSON parsing — extract last version from "versions": ["..."]
        int idx = json.LastIndexOf("\"");
        if (idx < 2) throw new InvalidOperationException("Could not resolve version for: " + packageId);

        int start = json.LastIndexOf("\"", idx - 1) + 1;
        string version = json.Substring(start, idx - start);

        // Try to find the latest non-preview version
        int versionsStart = json.IndexOf("[");
        int versionsEnd = json.IndexOf("]");
        if (versionsStart >= 0 && versionsEnd > versionsStart)
        {
            string versionsBlock = json.Substring(versionsStart + 1, versionsEnd - versionsStart - 1);
            string[] versions = versionsBlock.Split(',');
            string latestStable = null;
            foreach (string v in versions)
            {
                string clean = v.Trim().Trim('"');
                if (!string.IsNullOrEmpty(clean) && !clean.Contains("-"))
                    latestStable = clean;
            }
            if (latestStable != null)
                version = latestStable;
        }

        return version;
    }

    /// <summary>
    /// Ensures the Roslyn compiler is available. Downloads if needed.
    /// Returns the directory containing csc.exe.
    /// </summary>
    public static string EnsureRoslyn()
    {
        // Check if we already have it
        string roslynPkgId = "microsoft.net.compilers";
        string roslynVersion = "4.0.1"; // Last version supporting .NET Framework 4.x

        string toolsDir = Path.Combine(_packagesDir, roslynPkgId, roslynVersion, "tools");
        if (Directory.Exists(toolsDir))
        {
            string existingCsc = Path.Combine(toolsDir, "csc.exe");
            if (File.Exists(existingCsc))
                return toolsDir;
        }

        // Install via NuGet
        _lastStatus = "Installing Roslyn compiler (one-time setup)...";
        Install(roslynPkgId, roslynVersion);

        // The Roslyn compiler package puts csc.exe in tools/
        if (Directory.Exists(toolsDir) && File.Exists(Path.Combine(toolsDir, "csc.exe")))
            return toolsDir;

        throw new InvalidOperationException(
            "Failed to install Roslyn compiler. Check network connection.");
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    /// <summary>Selects the best .NET Framework target folder from lib/ subfolders.</summary>
    private static string FindBestFramework(string libPath)
    {
        // Priority order: prefer full framework, then netstandard
        string[] priorities = {
            "net48", "net472", "net471", "net47",
            "net462", "net461", "net46",
            "net452", "net451", "net45",
            "net40", "net403", "net40-client",
            "net35",
            "netstandard2.1", "netstandard2.0",
            "netstandard1.6", "netstandard1.3", "netstandard1.0"
        };

        string[] dirs = Directory.GetDirectories(libPath);

        foreach (string pref in priorities)
        {
            foreach (string dir in dirs)
            {
                string dirName = Path.GetFileName(dir).ToLowerInvariant();
                if (dirName == pref || dirName.StartsWith(pref + "-"))
                {
                    if (Directory.GetFiles(dir, "*.dll").Length > 0)
                        return dir;
                }
            }
        }

        // Fallback: any directory with DLLs
        foreach (string dir in dirs)
        {
            if (Directory.GetFiles(dir, "*.dll").Length > 0)
                return dir;
        }

        return null;
    }

    private static void CopyDirectory(string src, string dest)
    {
        if (!Directory.Exists(dest))
            Directory.CreateDirectory(dest);

        foreach (string file in Directory.GetFiles(src))
            File.Copy(file, Path.Combine(dest, Path.GetFileName(file)), true);

        foreach (string dir in Directory.GetDirectories(src))
            CopyDirectory(dir, Path.Combine(dest, Path.GetFileName(dir)));
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Delegate Bridge — AHK Function → C# Event Subscription
// ─────────────────────────────────────────────────────────────────────────────
// AHK v2 objects natively implement IDispatch. Function objects have a Call()
// method. We store a reference to the AHK callable, and when the C# event fires
// (from any thread), we PostMessage to the AHK main thread to invoke it safely.
//
// Threading model:
//   C# event fires (any thread) → PostMessage(WM_APP+2) → AHK pump → InvokeQueued()
//   This keeps AHK single-threaded while allowing C# events from ThreadPool/IO threads.

internal static class DelegateBridge
{
    [DllImport("user32.dll")]
    private static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    private static int _nextId = 0;

    private class DelegateEntry
    {
        public object Callable;     // AHK IDispatch object with .Call() method
        public IntPtr Hwnd;         // AHK hidden window for PostMessage
        public int Msg;             // WM_APP+2
        public object LastArgs;     // Queued args from last event fire
        public Delegate Subscription; // The actual .NET delegate subscribed to the event
        public object Target;       // The .NET object we subscribed to
        public string EventName;    // The event name
    }

    private static readonly ConcurrentDictionary<int, DelegateEntry> _delegates =
        new ConcurrentDictionary<int, DelegateEntry>();

    /// <summary>Registers an AHK callable for use as a C# callback.</summary>
    public static int Register(object ahkCallable, IntPtr ahkHwnd, int callbackMsg)
    {
        int id = Interlocked.Increment(ref _nextId);
        _delegates[id] = new DelegateEntry
        {
            Callable = ahkCallable,
            Hwnd = ahkHwnd,
            Msg = callbackMsg
        };
        return id;
    }

    /// <summary>Subscribes a registered delegate to a .NET event.</summary>
    public static void Subscribe(object target, string eventName, int delegateId)
    {
        DelegateEntry entry;
        if (!_delegates.TryGetValue(delegateId, out entry))
            throw new InvalidOperationException("Delegate not registered: " + delegateId);

        Type targetType = target.GetType();
        var eventInfo = targetType.GetEvent(eventName);
        if (eventInfo == null)
            throw new MissingMemberException(targetType.FullName, eventName);

        entry.Target = target;
        entry.EventName = eventName;

        // Create a generic handler that captures the delegate ID
        // and posts to the AHK message pump when the event fires
        int capturedId = delegateId;
        Type handlerType = eventInfo.EventHandlerType;
        ParameterInfo[] handlerParams = handlerType.GetMethod("Invoke").GetParameters();

        // Build a dynamic handler using EventHandler or EventHandler<T>
        // For simplicity, we create an Action-based wrapper
        EventHandler genericHandler = (sender, args) =>
        {
            // Store event args for retrieval by AHK
            DelegateEntry e;
            if (_delegates.TryGetValue(capturedId, out e))
            {
                // Serialize event args to a simple string for safe cross-thread access
                string argStr = "";
                if (args != null)
                {
                    try { argStr = args.ToString(); }
                    catch { argStr = args.GetType().Name; }
                }
                e.LastArgs = argStr;

                // Post message to AHK main thread
                if (e.Hwnd != IntPtr.Zero)
                    PostMessage(e.Hwnd, (uint)e.Msg, (IntPtr)capturedId, IntPtr.Zero);
            }
        };

        // Convert our EventHandler to the specific delegate type required
        Delegate handler;
        if (handlerType == typeof(EventHandler))
        {
            handler = genericHandler;
        }
        else
        {
            // For EventHandler<T> or custom delegate types, create a wrapper
            handler = Delegate.CreateDelegate(handlerType,
                genericHandler.Target, genericHandler.Method, false);

            // If direct creation fails, use a lambda wrapper
            if (handler == null)
            {
                // Fallback: create a dynamic method that calls our handler
                handler = CreateDynamicHandler(handlerType, capturedId);
            }
        }

        entry.Subscription = handler;
        eventInfo.AddEventHandler(target, handler);
    }

    /// <summary>Called from AHK main thread to retrieve and invoke a queued callback.</summary>
    public static object InvokeQueued(int delegateId)
    {
        DelegateEntry entry;
        if (!_delegates.TryGetValue(delegateId, out entry))
            return null;

        // Invoke the AHK callable via IDispatch
        try
        {
            dynamic callable = entry.Callable;
            object args = entry.LastArgs ?? "";
            return callable.Call(args);
        }
        catch
        {
            return null;
        }
    }

    /// <summary>Returns the last event args for a delegate.</summary>
    public static object GetLastArgs(int delegateId)
    {
        DelegateEntry entry;
        if (_delegates.TryGetValue(delegateId, out entry))
            return MarshalEngine.PackResult(entry.LastArgs);
        return null;
    }

    /// <summary>Unregisters a delegate and removes its event subscription.</summary>
    public static void Unregister(int delegateId)
    {
        DelegateEntry entry;
        if (_delegates.TryRemove(delegateId, out entry))
        {
            // Remove event subscription
            if (entry.Target != null && entry.EventName != null && entry.Subscription != null)
            {
                try
                {
                    var eventInfo = entry.Target.GetType().GetEvent(entry.EventName);
                    if (eventInfo != null)
                        eventInfo.RemoveEventHandler(entry.Target, entry.Subscription);
                }
                catch { }
            }
        }
    }

    /// <summary>Creates a dynamic delegate for custom event handler types.</summary>
    private static Delegate CreateDynamicHandler(Type delegateType, int delegateId)
    {
        MethodInfo invokeMethod = delegateType.GetMethod("Invoke");
        ParameterInfo[] parms = invokeMethod.GetParameters();

        // Create an EventHandler wrapper that ignores extra type-specific args
        EventHandler wrapper = (sender, args) =>
        {
            DelegateEntry entry;
            if (_delegates.TryGetValue(delegateId, out entry))
            {
                string argStr = "";
                if (args != null)
                {
                    try { argStr = args.ToString(); }
                    catch { argStr = args.GetType().Name; }
                }
                entry.LastArgs = argStr;

                if (entry.Hwnd != IntPtr.Zero)
                    PostMessage(entry.Hwnd, (uint)entry.Msg, (IntPtr)delegateId, IntPtr.Zero);
            }
        };

        // For 2-param delegates (sender, EventArgs), try direct cast
        if (parms.Length == 2)
        {
            try
            {
                return Delegate.CreateDelegate(delegateType, wrapper.Target, wrapper.Method);
            }
            catch { }
        }

        // Last resort: return as EventHandler and let the caller handle type mismatch
        return wrapper;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// CLR Host Entry Point — called by AHK via DllCall into mscoree.dll
// ─────────────────────────────────────────────────────────────────────────────

public static class AhkSharpEntry
{
    /// <summary>
    /// Entry point called by ICLRRuntimeHost.ExecuteInDefaultAppDomain().
    /// Creates the bridge singleton, obtains its IDispatch pointer, and stores
    /// it in the AHKSHARP_PTR environment variable so AHK can retrieve it.
    /// Returns 0 on success.
    /// </summary>
    public static int Initialize(string args)
    {
        try
        {
            // Force singleton creation
            AhkSharpBridge bridge = AhkSharpBridge.Instance;

            // Get the IDispatch pointer for this COM-visible object
            IntPtr pDispatch = Marshal.GetIDispatchForObject(bridge);

            // Store pointer as string in environment variable
            // AHK reads this back and wraps it as ComValue(VT_DISPATCH)
            Environment.SetEnvironmentVariable("AHKSHARP_PTR",
                pDispatch.ToInt64().ToString());

            // Pre-load commonly used assemblies for faster first-call
            try { Assembly.Load("System.Core"); } catch { }
            try { Assembly.Load("System.Drawing"); } catch { }
            try { Assembly.Load("System.Windows.Forms"); } catch { }

            return 0;
        }
        catch (Exception ex)
        {
            // Store error for debugging
            Environment.SetEnvironmentVariable("AHKSHARP_ERR", ex.ToString());
            return -1;
        }
    }
}
