// ═══════════════════════════════════════════════════════════════════════════════
// AHK# Bridge — RuntimeCompiler: CSModule compilation, cache and module invocation
// (part of ahk#.bridge.dll; see AhkSharpBridge.cs for the COM entry point)
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

        // Compile to a private temp file and move it into place afterwards, so two AHK
        // processes compiling the same module never load a half-written DLL.
        string tmpDll = Path.Combine(_cacheDir, hash + "." + Guid.NewGuid().ToString("N") + ".tmp");

        CSharpCodeProvider provider = new CSharpCodeProvider();
        CompilerParameters cp = new CompilerParameters();
        cp.GenerateInMemory = false;
        cp.OutputAssembly = tmpDll;
        cp.ReferencedAssemblies.Add("System.dll");
        cp.ReferencedAssemblies.Add("System.Core.dll");
        cp.ReferencedAssemblies.Add("Microsoft.CSharp.dll");
        cp.ReferencedAssemblies.Add("System.Data.dll");
        cp.ReferencedAssemblies.Add("System.Xml.dll");
        string winRt = Path.Combine(System.Runtime.InteropServices.RuntimeEnvironment.GetRuntimeDirectory(),
            "System.Runtime.WindowsRuntime.dll");
        if (File.Exists(winRt))
            cp.ReferencedAssemblies.Add(winRt);

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
            try { File.Delete(tmpDll); } catch { }
            StringBuilder sb = new StringBuilder("Compilation failed:\n");
            foreach (CompilerError err in cr.Errors)
            {
                if (!err.IsWarning)
                    sb.AppendLine(string.Format("  Line {0}: {1}", err.Line, err.ErrorText));
            }
            throw new InvalidOperationException(sb.ToString());
        }

        try { File.Move(tmpDll, cachedDll); }
        catch (IOException) { try { File.Delete(tmpDll); } catch { } }   // another process won the race

        _cache[hash] = Assembly.LoadFrom(cachedDll);
        return hash;
    }

    // ── Module invocation (cached type lookup, overload-aware) ─────────────

    private static readonly ConcurrentDictionary<string, Type> _typeCache =
        new ConcurrentDictionary<string, Type>(StringComparer.Ordinal);

    private static readonly ConcurrentDictionary<Type, object> _instances =
        new ConcurrentDictionary<Type, object>();

    internal static Type FindModuleType(string assemblyId, string className)
    {
        return _typeCache.GetOrAdd(assemblyId + "|" + className, delegate(string key)
        {
            Assembly asm;
            if (!_cache.TryGetValue(assemblyId, out asm))
            {
                string cachedDll = Path.Combine(_cacheDir, assemblyId + ".dll");
                if (!File.Exists(cachedDll))
                    throw new InvalidOperationException("Assembly not found: " + assemblyId);
                asm = Assembly.LoadFrom(cachedDll);
                _cache[assemblyId] = asm;
            }

            foreach (Type exported in asm.GetExportedTypes())
                if (exported.Name == className || exported.FullName == className)
                    return exported;

            throw new TypeLoadException("Class not found in compiled assembly: " + className);
        });
    }

    public static object InvokeModule(string assemblyId, string className, string methodName, object[] args)
    {
        Type t = FindModuleType(assemblyId, className);

        object target = null;
        MethodBase[] candidates = OverloadBinder.GetMethods(t, methodName, true);
        BoundCall call = OverloadBinder.Bind(candidates, args);
        if (call == null)
        {
            candidates = OverloadBinder.GetMethods(t, methodName, false);
            call = OverloadBinder.Bind(candidates, args);
            if (call != null)
                target = _instances.GetOrAdd(t, delegate(Type type) { return Activator.CreateInstance(type); });
        }

        if (call == null)
        {
            MethodBase[] all = OverloadBinder.GetMethods(t, methodName, true)
                .Concat(OverloadBinder.GetMethods(t, methodName, false)).ToArray();
            if (all.Length == 0)
                throw new MissingMethodException("Method '" + className + "." + methodName + "' not found.");
            throw new MissingMethodException("No overload of " + className + "." + methodName
                + " accepts (" + OverloadBinder.DescribeArgs(args) + "). Candidates:"
                + OverloadBinder.DescribeCandidates(all));
        }

        try
        {
            return MarshalEngine.PackResult(call.Method.Invoke(target, call.Args));
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

    /// <summary>Reads a static (or singleton-instance) property/field of a compiled module.</summary>
    public static object GetMember(string assemblyId, string className, string name)
    {
        Type t = FindModuleType(assemblyId, className);
        foreach (BindingFlags ci in new[] { BindingFlags.Default, BindingFlags.IgnoreCase })
        {
            BindingFlags sf = BindingFlags.Public | BindingFlags.Static | BindingFlags.FlattenHierarchy | ci;
            BindingFlags inst = BindingFlags.Public | BindingFlags.Instance | ci;

            PropertyInfo pi = t.GetProperty(name, sf);
            if (pi != null) return MarshalEngine.PackResult(pi.GetValue(null, null));
            FieldInfo fi = t.GetField(name, sf);
            if (fi != null) return MarshalEngine.PackResult(fi.GetValue(null));

            pi = t.GetProperty(name, inst);
            if (pi != null)
                return MarshalEngine.PackResult(pi.GetValue(_instances.GetOrAdd(t, delegate(Type x) { return Activator.CreateInstance(x); }), null));
            fi = t.GetField(name, inst);
            if (fi != null)
                return MarshalEngine.PackResult(fi.GetValue(_instances.GetOrAdd(t, delegate(Type x) { return Activator.CreateInstance(x); })));
        }
        throw new MissingMemberException(className, name);
    }

    /// <summary>Public accessor for the compile cache directory path.</summary>
    public static string CacheDir { get { return _cacheDir; } }

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

        // C# 9 records and `init` accessors need a marker type that only newer frameworks ship: supply it.
        double langNum;
        bool newLang = string.Equals(langVersion, "latest", StringComparison.OrdinalIgnoreCase) || string.Equals(langVersion, "preview", StringComparison.OrdinalIgnoreCase)
            || (double.TryParse(langVersion, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out langNum) && langNum >= 9);
        if (newLang && !fullCode.Contains("IsExternalInit")
            && System.Text.RegularExpressions.Regex.IsMatch(fullCode, @"\binit\s*;|\binit\s*\{|\brecord\b"))
            fullCode += "\nnamespace System.Runtime.CompilerServices { internal static class IsExternalInit { } }\n";

        // Ensure Roslyn compiler is available
        if (!System.Text.RegularExpressions.Regex.IsMatch(langVersion, @"^[A-Za-z0-9.]{1,12}$"))
            throw new ArgumentException("Invalid C# language version: " + langVersion + " (use e.g. \"6.0\", \"10.0\", \"12.0\", \"latest\")");
        string roslynDir = NuGetManager.EnsureRoslyn(langVersion);
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

        string tmpDll = Path.Combine(_cacheDir, hash + "." + Guid.NewGuid().ToString("N") + ".tmp");
        string args = string.Format(
            "/nologo /target:library /optimize+ /langversion:{0} /out:\"{1}\" /lib:\"{2}\" {3} \"{4}\"",
            langVersion, tmpDll, fxDir, refArgs, srcFile);

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
                try { File.Delete(tmpDll); } catch { }
                throw new InvalidOperationException(
                    "Roslyn compilation failed (C# " + langVersion + "):\n" + stdout + "\n" + stderr);
            }
        }

        try { File.Move(tmpDll, cachedDll); }
        catch (IOException) { try { File.Delete(tmpDll); } catch { } }   // another process won the race

        Assembly compiled = Assembly.LoadFrom(cachedDll);
        _cache[hash] = compiled;
        return hash;
    }
}

