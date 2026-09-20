// ═══════════════════════════════════════════════════════════════════════════════
// AHK# Bridge — TypeResolver: dotted names → System.Type (cached, generics, misses)
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
// Type Resolver — FQN to System.Type with assembly scanning + caching
// ─────────────────────────────────────────────────────────────────────────────

internal static class TypeResolver
{
    private static readonly Dictionary<string, Type> _cache = new Dictionary<string, Type>(StringComparer.OrdinalIgnoreCase);
    private static readonly List<Assembly> _extraAssemblies = new List<Assembly>();
    private static bool _scanned = false;

    public static int CachedCount { get { lock (_cache) { return _cache.Count; } } }

    // Names that failed to resolve. Namespace hops like "System.IO" are looked up as types
    // by the AHK side, so misses must be cheap. Cleared whenever an assembly is loaded.
    private static readonly HashSet<string> _misses = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

    static TypeResolver()
    {
        AppDomain.CurrentDomain.AssemblyLoad += delegate { lock (_cache) { _misses.Clear(); } };
    }

    public static Type Resolve(string name)
    {
        if (string.IsNullOrEmpty(name)) return null;

        lock (_cache)
        {
            Type cached;
            if (_cache.TryGetValue(name, out cached))
                return cached;
            if (_misses.Contains(name))
                return null;
        }

        Type found = ResolveCore(name);

        lock (_cache)
        {
            if (found != null) _cache[name] = found;
            else _misses.Add(name);
        }
        return found;
    }

    /// <summary>
    /// Builds a closed generic type from "Ns.List`1[Ns.Foo]" / "Ns.Dictionary`2[System.String,Ns.Foo]"
    /// where the type arguments may live in any loaded assembly.
    /// </summary>
    private static Type ResolveGeneric(string name)
    {
        int open = name.IndexOf('[');
        if (open <= 0 || !name.EndsWith("]") || name.IndexOf('`') < 0 || name.IndexOf('`') > open)
            return null;

        Type def = Resolve(name.Substring(0, open));
        if (def == null || !def.IsGenericTypeDefinition) return null;

        string inner = name.Substring(open + 1, name.Length - open - 2);
        List<Type> args = new List<Type>();
        int depth = 0, start = 0;
        for (int i = 0; i <= inner.Length; i++)
        {
            char c = i < inner.Length ? inner[i] : ',';
            if (c == '[') depth++;
            else if (c == ']') depth--;
            else if (c == ',' && depth == 0)
            {
                string part = inner.Substring(start, i - start).Trim();
                start = i + 1;
                if (part.Length == 0) continue;
                if (part[0] == '[' && part[part.Length - 1] == ']')
                    part = part.Substring(1, part.Length - 2);
                Type at = Resolve(part);
                if (at == null) return null;
                args.Add(at);
            }
        }
        if (args.Count != def.GetGenericArguments().Length) return null;
        try { return def.MakeGenericType(args.ToArray()); }
        catch (ArgumentException) { return null; }
    }

    private static Type ResolveCore(string name)
    {
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

        // 3b. Closed generic with type arguments from any assembly
        if (t == null && name.IndexOf('`') > 0 && name.IndexOf('[') > 0)
            t = ResolveGeneric(name);

        // 4. Try common assembly-qualified names
        if (t == null)
        {
            string[] commonAssemblies = {
                "mscorlib", "System", "System.Core", "System.Data",
                "System.Drawing", "System.Windows.Forms", "System.Xml",
                "System.Xml.Linq", "System.Net.Http, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a",
                "WindowsBase", "PresentationCore", "PresentationFramework",
                "UIAutomationClient", "UIAutomationTypes"
            };

            // The WPF / UIA assemblies are heavy: only load them for names that can live there.
            bool wpfName = name.StartsWith("System.Windows.", StringComparison.OrdinalIgnoreCase)
                        && !name.StartsWith("System.Windows.Forms", StringComparison.OrdinalIgnoreCase)
                        || name.StartsWith("System.IO.Packaging", StringComparison.OrdinalIgnoreCase)
                        || name.StartsWith("System.Windows.Automation", StringComparison.OrdinalIgnoreCase);

            foreach (string asmName in commonAssemblies)
            {
                if (!wpfName && (asmName == "WindowsBase" || asmName.StartsWith("Presentation") || asmName.StartsWith("UIAutomation")))
                    continue;
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

        return t;
    }

    // Every assembly type lookups can reach: the loaded ones plus those added with LoadAssembly.
    public static List<Assembly> AllAssemblies()
    {
        List<Assembly> all = new List<Assembly>(AppDomain.CurrentDomain.GetAssemblies());
        lock (_extraAssemblies)
        {
            foreach (Assembly a in _extraAssemblies)
                if (!all.Contains(a)) all.Add(a);
        }
        return all;
    }

    // Namespace listings should see the framework assemblies even if nothing has touched them yet.
    public static void EnsureCommonAssemblies(string ns)
    {
        string[] names = { "System", "System.Core", "System.Data", "System.Drawing", "System.Windows.Forms",
            "System.Xml", "System.Xml.Linq", "System.Net.Http, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a" };
        foreach (string n in names)
            try { Assembly.Load(n); } catch { }
        if (ns.StartsWith("System.Windows", StringComparison.OrdinalIgnoreCase) && !ns.StartsWith("System.Windows.Forms", StringComparison.OrdinalIgnoreCase))
            foreach (string n in new string[] { "WindowsBase", "PresentationCore", "PresentationFramework" })
                try { Assembly.Load(n); } catch { }
    }

    public static void LoadAssembly(string pathOrName)
    {
        Assembly asm;
        if (File.Exists(pathOrName))
            asm = Assembly.LoadFrom(pathOrName);
        else
        {
            try { asm = Assembly.Load(pathOrName); }
            catch (FileNotFoundException)
            {
                // Some framework assemblies (System.Net.Http, System.Web.Extensions ...) refuse a partial name
#pragma warning disable 618
                asm = Assembly.LoadWithPartialName(pathOrName);
#pragma warning restore 618
                if (asm == null) throw;
            }
        }

        lock (_extraAssemblies)
        {
            _extraAssemblies.Add(asm);
        }

        // Invalidate brute-force scan flag so new assembly gets scanned
        _scanned = false;
    }
}

