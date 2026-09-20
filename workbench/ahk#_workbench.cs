using System;
using System.IO;
using System.Reflection;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Net;
using System.Diagnostics;

// NOTE: _CSModule wraps this file inside a generated WBHelper type and compiles it as C# 4/5.
// Keep it free of nested type declarations and of C# 6+ syntax (no ?. / interpolated strings / nameof).

private static readonly string _cacheDir = Path.Combine(
    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
    "AhkSharp", "CompileCache");

private static readonly string _pkgDir = Path.Combine(
    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
    "AhkSharp", "Packages");

// ── Type Explorer ────────────────────────────────────────────────
public static Type ResolveType(string typeName) {
    Type t = null;
    foreach (var asm in AppDomain.CurrentDomain.GetAssemblies()) {
        try { t = asm.GetType(typeName, false, true); if (t != null) break; } catch { }
    }
    if (t == null) t = Type.GetType(typeName, false, true);
    
    if (t == null) {
        int lastDot = typeName.LastIndexOf('.');
        if (lastDot > 0) {
            string ns = typeName.Substring(0, lastDot);
            try {
                #pragma warning disable 618
                var asm = Assembly.LoadWithPartialName(ns);
                #pragma warning restore 618
                if (asm != null) t = asm.GetType(typeName, false, true);
            } catch { }
        }
    }
    
    if (t == null) {
        string[] common = new[] { "System.Net.Http", "System.Xml.Linq", "System.Xml", "System.Drawing" };
        foreach (var c in common) {
            try {
                #pragma warning disable 618
                var asm = Assembly.LoadWithPartialName(c);
                #pragma warning restore 618
                if (asm != null) { t = asm.GetType(typeName, false, true); if (t != null) break; }
            } catch { }
        }
    }
    return t;
}

public static string ExploreType(string typeName, bool includeInherited) {
    Type t = ResolveType(typeName);
    var sb = new StringBuilder();

    if (t == null) {
        var matches = new List<Type>();
        foreach (var asm in AppDomain.CurrentDomain.GetAssemblies()) {
            if (asm.IsDynamic) continue;
            try {
                foreach (var type in asm.GetExportedTypes()) {
                    if (type.FullName.StartsWith(typeName + ".", StringComparison.OrdinalIgnoreCase) || 
                        type.Name.IndexOf(typeName, StringComparison.OrdinalIgnoreCase) >= 0 ||
                        type.FullName.IndexOf(typeName, StringComparison.OrdinalIgnoreCase) >= 0) {
                        matches.Add(type);
                    }
                }
            } catch { }
        }
        
        if (matches.Count == 0) return "ERROR:Type not found: " + typeName;
        
        foreach (var mt in matches.OrderBy(x => x.FullName).Take(2000)) {
            string kind = mt.IsInterface ? "Interface" : mt.IsEnum ? "Enum" : mt.IsValueType ? "Struct" : typeof(Delegate).IsAssignableFrom(mt) ? "Delegate" : "Class";
            sb.AppendLine(kind + "|" + mt.Name + "|" + mt.FullName + "|" + mt.Assembly.GetName().Name);
        }
        return sb.ToString().TrimEnd();
    }

    sb.AppendLine("Assembly|" + t.Assembly.GetName().Name + "|" + (t.Assembly.IsDynamic ? "Dynamic" : t.Assembly.Location) + "|");

    var flags = BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static;
    if (!includeInherited) flags |= BindingFlags.DeclaredOnly;

    foreach (var ci in t.GetConstructors(flags)) {
        var parms = ParamList(ci.GetParameters());
        sb.AppendLine("Constructor|" + t.Name + "|(" + parms + ")|" + (ci.IsStatic ? "Static" : "Instance"));
    }
    foreach (var mi in t.GetMethods(flags).Where(m => !m.IsSpecialName).OrderBy(m => m.Name)) {
        var parms = ParamList(mi.GetParameters());
        sb.AppendLine("Method|" + mi.Name + "|(" + parms + ") -> " + ShortName(mi.ReturnType) + "|" + (mi.IsStatic ? "Static" : "Instance"));
    }
    foreach (var pi in t.GetProperties(flags).OrderBy(p => p.Name)) {
        string access = (pi.CanRead ? "get" : "") + (pi.CanRead && pi.CanWrite ? "/" : "") + (pi.CanWrite ? "set" : "");
        sb.AppendLine("Property|" + pi.Name + "|" + ShortName(pi.PropertyType) + " {" + access + "}|" + (IsStaticP(pi) ? "Static" : "Instance"));
    }
    foreach (var fi in t.GetFields(flags).OrderBy(f => f.Name)) {
        sb.AppendLine("Field|" + fi.Name + "|" + ShortName(fi.FieldType) + "|" + (fi.IsStatic ? "Static" : "Instance"));
    }
    foreach (var ei in t.GetEvents(flags).OrderBy(e => e.Name)) {
        sb.AppendLine("Event|" + ei.Name + "|" + ShortName(ei.EventHandlerType) + "|");
    }
    return sb.Length > 0 ? sb.ToString().TrimEnd() : "No public members found.";
}

private static string ShortName(Type t) {
    if (t == null) return "void";
    if (t == typeof(void)) return "void";
    if (t == typeof(string)) return "String";
    if (t == typeof(int)) return "Int32";
    if (t == typeof(long)) return "Int64";
    if (t == typeof(double)) return "Double";
    if (t == typeof(float)) return "Single";
    if (t == typeof(bool)) return "Boolean";
    if (t == typeof(object)) return "Object";
    if (t.IsGenericType) {
        string baseName = t.Name.Split(new char[]{(char)96})[0];
        return baseName + "<" + string.Join(",", t.GetGenericArguments().Select(a => ShortName(a))) + ">";
    }
    if (t.IsArray) return ShortName(t.GetElementType()) + "[]";
    return t.Name;
}

private static bool IsStaticP(PropertyInfo pi) {
    var g = pi.GetGetMethod(false); if (g != null) return g.IsStatic;
    var s = pi.GetSetMethod(false); if (s != null) return s.IsStatic;
    return false;
}

private static string ParamList(ParameterInfo[] ps) {
    return string.Join(", ", ps.Select(p => ShortName(p.ParameterType) + " " + p.Name));
}

private static string ArgNames(ParameterInfo[] ps) {
    return string.Join(", ", ps.Select(p => p.Name));
}

private static string NormSig(string s) {
    if (s == null) return "";
    return new string(s.Where(c => !char.IsWhiteSpace(c)).ToArray());
}

// AHK# expression that refers to a type. Nested and generic types cannot be written as a
// dotted CS.Namespace.Type path, so they use CS("Full.Name") (with the backtick doubled for AHK).
private static string SnippetTypeRef(Type t) {
    string full = t.FullName ?? t.Name;
    if (t.IsNested || t.IsGenericType)
        return "CS(\"" + full.Replace("`", "``") + "\")";
    return "CS." + full;
}

public static string GenerateSnippet(string typeName, string memberName, string memberType, string signature) {
    Type t = ResolveType(typeName);
    if (t == null) return "; Type not found";
    string tref = SnippetTypeRef(t);
    string note = t.IsGenericTypeDefinition
        ? "; NOTE: open generic type - it must be closed with type arguments before use.\n"
        : "";
    BindingFlags all = BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static | BindingFlags.FlattenHierarchy;
    string want = NormSig(signature);

    if (memberType == "Constructor") {
        var ctors = t.GetConstructors(BindingFlags.Public | BindingFlags.Instance);
        ConstructorInfo ci = null;
        foreach (var c in ctors) {
            if (NormSig("(" + ParamList(c.GetParameters()) + ")") == want) { ci = c; break; }
        }
        if (ci == null) ci = ctors.FirstOrDefault();
        if (ci == null) return note + "; No public constructor";
        return note + "obj := " + tref + "(" + ArgNames(ci.GetParameters()) + ")";
    }
    if (memberType == "Method") {
        var cands = t.GetMethods(all).Where(m => m.Name == memberName && !m.IsSpecialName).ToList();
        MethodInfo mi = null;
        foreach (var m in cands) {
            string s = "(" + ParamList(m.GetParameters()) + ") -> " + ShortName(m.ReturnType);
            if (NormSig(s) == want) { mi = m; break; }
        }
        if (mi == null) mi = cands.FirstOrDefault();
        if (mi == null) return "; Method not found";
        string args = ArgNames(mi.GetParameters());
        return note + (mi.IsStatic
            ? "result := " + tref + "." + memberName + "(" + args + ")"
            : "result := obj." + memberName + "(" + args + ")");
    }
    if (memberType == "Property") {
        var pi = t.GetProperties(all).FirstOrDefault(p => p.Name == memberName);
        if (pi == null) return "; Property not found";
        string target = IsStaticP(pi) ? tref : "obj";
        string sb = note + "value := " + target + "." + memberName;
        if (pi.CanWrite) sb += "\n" + target + "." + memberName + " := value";
        return sb;
    }
    if (memberType == "Field") {
        var fi = t.GetFields(all).FirstOrDefault(f => f.Name == memberName);
        if (fi == null) return "; Field not found";
        return note + "value := " + (fi.IsStatic ? tref : "obj") + "." + memberName;
    }
    if (memberType == "Event") {
        return note + "obj.On(\"" + memberName + "\", (e) => MsgBox(\"" + memberName + " fired\"))";
    }
    return "; " + memberType + ": " + memberName;
}

// ── Cache Manager ────────────────────────────────────────────────
// Exported type names of a compiled cache DLL, computed once per file version and remembered.
private static readonly Dictionary<string, string> _scanCache = new Dictionary<string, string>();
private static readonly Dictionary<Assembly, string> _typeNameCache = new Dictionary<Assembly, string>();

private static string ExportedTypeNames(Assembly a) {
    try {
        var types = a.GetExportedTypes();
        return types.Length > 0
            ? string.Join(", ", types.Select(x => x.Name))
            : "(no exported types)";
    } catch (ReflectionTypeLoadException rtle) {
        var names = rtle.Types.Where(x => x != null && x.IsPublic).Select(x => x.Name).ToArray();
        return names.Length > 0 ? string.Join(", ", names) : "(unable to inspect)";
    } catch {
        return "(unable to inspect)";
    }
}

private static string ExportedTypeNamesCached(Assembly a) {
    if (a.IsDynamic) return "(dynamic)";
    string s;
    if (_typeNameCache.TryGetValue(a, out s)) return s;
    s = ExportedTypeNames(a);
    _typeNameCache[a] = s;
    return s;
}

// Never loads the DLL into the executable context and never locks the file:
//   1. an assembly that is already loaded from that path is reused as-is,
//   2. otherwise the bytes are loaded reflection-only (metadata only, no code runs),
//   3. the result is cached per file (path + length + timestamp), so a refresh costs nothing.
private static string DescribeCachedDll(string dll, FileInfo fi) {
    string key = dll + "|" + fi.Length + "|" + fi.LastWriteTimeUtc.Ticks;
    string cached;
    if (_scanCache.TryGetValue(key, out cached)) return cached;

    string classes = "(unable to inspect)";
    bool done = false;
    foreach (var a in AppDomain.CurrentDomain.GetAssemblies()) {
        if (a.IsDynamic) continue;
        string loc = null;
        try { loc = a.Location; } catch { }
        if (!string.IsNullOrEmpty(loc) && string.Equals(loc, dll, StringComparison.OrdinalIgnoreCase)) {
            classes = ExportedTypeNames(a);
            done = true;
            break;
        }
    }

    if (!done) {
        ResolveEventHandler resolver = (s, e) => {
            try { return Assembly.ReflectionOnlyLoad(e.Name); } catch { return null; }
        };
        AppDomain.CurrentDomain.ReflectionOnlyAssemblyResolve += resolver;
        try {
            var asm = Assembly.ReflectionOnlyLoad(File.ReadAllBytes(dll));
            classes = ExportedTypeNames(asm);
        } catch {
            classes = "(unable to inspect)";
        } finally {
            AppDomain.CurrentDomain.ReflectionOnlyAssemblyResolve -= resolver;
        }
    }

    _scanCache[key] = classes;
    return classes;
}

public static string ScanCache() {
    if (!Directory.Exists(_cacheDir)) return "";
    var sb = new StringBuilder();
    foreach (var dll in Directory.GetFiles(_cacheDir, "*.dll")) {
        var fi = new FileInfo(dll);
        string hash = Path.GetFileNameWithoutExtension(dll);
        string classes = DescribeCachedDll(dll, fi);
        string sizeKB = (fi.Length / 1024.0).ToString("F1") + " KB";
        string created = fi.CreationTime.ToString("yyyy-MM-dd HH:mm");
        sb.AppendLine(hash + "|" + sizeKB + "|" + created + "|" + classes);
    }
    return sb.ToString().TrimEnd();
}

public static string GetCacheStats() {
    if (!Directory.Exists(_cacheDir)) return "0|0 B|" + _cacheDir;
    var files = Directory.GetFiles(_cacheDir, "*.dll");
    long total = files.Sum(f => new FileInfo(f).Length);
    string size = total < 1048576
        ? (total / 1024.0).ToString("F1") + " KB"
        : (total / 1048576.0).ToString("F2") + " MB";
    return files.Length + "|" + size + "|" + _cacheDir;
}

public static bool DeleteCacheEntry(string hash) {
    try {
        string p1 = Path.Combine(_cacheDir, hash + ".dll");
        string p2 = Path.Combine(_cacheDir, hash + ".cs");
        if (File.Exists(p1)) File.Delete(p1);
        if (File.Exists(p2)) File.Delete(p2);
        return true;
    } catch { return false; }
}

public static int ClearAllCache() {
    if (!Directory.Exists(_cacheDir)) return 0;
    int count = 0;
    foreach (var f in Directory.GetFiles(_cacheDir)) {
        try { File.Delete(f); count++; } catch { }
    }
    return count;
}

// ── CLR Diagnostics ──────────────────────────────────────────────
public static string ListAssemblies() {
    var sb = new StringBuilder();
    foreach (var asm in AppDomain.CurrentDomain.GetAssemblies().OrderBy(a => a.GetName().Name)) {
        var n = asm.GetName();
        string loc = "";
        try { loc = asm.Location; } catch { }
        if (string.IsNullOrEmpty(loc)) loc = "(in-memory)";

        // Get file size
        string sizeStr = "N/A";
        try {
            if (!string.IsNullOrEmpty(loc) && File.Exists(loc)) {
                long sz = new FileInfo(loc).Length;
                sizeStr = sz < 1048576
                    ? (sz / 1024.0).ToString("F1") + " KB"
                    : (sz / 1048576.0).ToString("F2") + " MB";
            } else if (loc == "(in-memory)") {
                sizeStr = asm.IsDynamic ? "Dynamic" : "In-Memory";
            }
        } catch { }

        // Exported classes (cached per assembly - loaded assemblies never change)
        string classes = ExportedTypeNamesCached(asm);

        sb.AppendLine(n.Name + "|" + n.Version + "|" + sizeStr + "|" + classes + "|" + loc);
    }
    return sb.ToString().TrimEnd();
}

// Cached DLLs whose assembly is not loaded in this process. Only ever removed by an explicit user action.
private static List<string> UnusedCacheDlls() {
    var result = new List<string>();
    if (!Directory.Exists(_cacheDir)) return result;

    var loadedNames = new HashSet<string>(
        AppDomain.CurrentDomain.GetAssemblies().Select(a => a.GetName().Name),
        StringComparer.OrdinalIgnoreCase
    );

    foreach (var dll in Directory.GetFiles(_cacheDir, "*.dll")) {
        if (!loadedNames.Contains(Path.GetFileNameWithoutExtension(dll)))
            result.Add(dll);
    }
    return result;
}

public static int CountUnusedCache() {
    return UnusedCacheDlls().Count;
}

public static int CleanUnusedCache() {
    int deleted = 0;
    foreach (var dll in UnusedCacheDlls()) {
        try {
            string csFile = Path.Combine(_cacheDir, Path.GetFileNameWithoutExtension(dll) + ".cs");
            File.Delete(dll);
            if (File.Exists(csFile)) File.Delete(csFile);
            deleted++;
        } catch { }
    }
    return deleted;
}

public static string GetMemoryInfo() {
    long heap = GC.GetTotalMemory(false);
    string hs = heap < 1048576
        ? (heap / 1024.0).ToString("F1") + " KB"
        : (heap / 1048576.0).ToString("F2") + " MB";
    return hs + "|" + GC.CollectionCount(0) + "|" + GC.CollectionCount(1) + "|"
        + GC.CollectionCount(2) + "|" + AppDomain.CurrentDomain.GetAssemblies().Length + "|" + heap;
}

// ── NuGet Search ─────────────────────────────────────────────────
public static string SearchNuGet(string query) {
    try {
        ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072;
        string url = "https://azuresearch-usnc.nuget.org/query?q="
            + Uri.EscapeDataString(query) + "&take=25&prerelease=false";
        using (var c = new WebClient()) {
            c.Headers.Add("User-Agent", "AHK-Sharp/2.0");
            return ParseNuGetJson(c.DownloadString(url));
        }
    } catch (Exception ex) { return "ERROR:" + ex.Message; }
}

private static string ParseNuGetJson(string json) {
    var sb = new StringBuilder();
    int pos = 0;
    while (true) {
        int idIdx = json.IndexOf("\"id\":", pos);
        if (idIdx < 0) break;
        string id = JStr(json, idIdx + 5);
        int verIdx = json.IndexOf("\"version\":", idIdx);
        string ver = verIdx > 0 && verIdx < idIdx + 3000 ? JStr(json, verIdx + 10) : "?";
        int descIdx = json.IndexOf("\"description\":", idIdx);
        string desc = descIdx > 0 && descIdx < idIdx + 3000 ? JStr(json, descIdx + 14) : "";
        if (desc.Length > 100) desc = desc.Substring(0, 100) + "...";
        desc = desc.Replace("\n", " ").Replace("\r", " ").Replace("|", "/");
        int dlIdx = json.IndexOf("\"totalDownloads\":", idIdx);
        string dl = "0";
        if (dlIdx > 0 && dlIdx < idIdx + 3000) {
            int ns = dlIdx + 17;
            int ne = json.IndexOfAny(new[]{',','}'}, ns);
            if (ne > ns) dl = json.Substring(ns, ne - ns).Trim();
        }
        sb.AppendLine(id + "|" + ver + "|" + dl + "|" + desc);
        int next = json.IndexOf("\"@type\":", idIdx + 10);
        pos = next > 0 ? next : idIdx + 200;
        if (pos >= json.Length) break;
    }
    return sb.ToString().TrimEnd();
}

private static string JStr(string json, int after) {
    int qs = json.IndexOf('"', after); if (qs < 0) return "";
    int qe = qs + 1;
    while (qe < json.Length) { if (json[qe] == '"' && json[qe-1] != '\\') break; qe++; }
    return qe < json.Length ? json.Substring(qs + 1, qe - qs - 1) : "";
}

public static string ListInstalledPkgs() {
    if (!Directory.Exists(_pkgDir)) return "";
    var sb = new StringBuilder();
    foreach (var pd in Directory.GetDirectories(_pkgDir)) {
        string name = Path.GetFileName(pd);
        foreach (var vd in Directory.GetDirectories(pd)) {
            string ver = Path.GetFileName(vd);
            string libDir = Path.Combine(vd, "lib");
            long sz = 0; int dc = 0;
            if (Directory.Exists(libDir)) {
                var dlls = Directory.GetFiles(libDir, "*.dll");
                dc = dlls.Length; sz = dlls.Sum(f => new FileInfo(f).Length);
            }
            string ss = sz < 1048576 ? (sz/1024.0).ToString("F1")+" KB" : (sz/1048576.0).ToString("F2")+" MB";
            sb.AppendLine(name + "|" + ver + "|" + dc + " DLLs|" + ss);
        }
    }
    return sb.ToString().TrimEnd();
}

public static string GetPackageDlls(string name, string ver) {
    string libDir = Path.Combine(_pkgDir, name, ver, "lib");
    if (!Directory.Exists(libDir)) return "";
    var dlls = Directory.GetFiles(libDir, "*.dll", SearchOption.AllDirectories);
    return string.Join(";", dlls);
}

// ── Overload Predictor ───────────────────────────────────────────
private static bool CanCoerceArg(Type fromType, Type toType) {
    if (toType.IsAssignableFrom(fromType)) return true;
    if (toType.IsPrimitive && fromType.IsPrimitive) return true;
    if (toType == typeof(string) || toType == typeof(object)) return true;
    return false;
}

private static string MethodSig(MethodInfo m) {
    return ShortName(m.ReturnType) + " " + m.Name + "(" + ParamList(m.GetParameters()) + ")";
}

// Self-contained overload prediction. It follows the same tiers the AHK# bridge uses when it binds a
// call (exact count + coercible types, then count only, then params[], then the first overload) but
// does not reflect into the bridge's private members, so it cannot break when the bridge changes.
// Treat the answer as a prediction: the bridge remains the authority at call time.
public static string PredictOverload(string typeName, string methodName, object[] args) {
    Type t = ResolveType(typeName);
    if (t == null) return "ERROR:Type not found: " + typeName;
    if (args == null) args = new object[0];

    BindingFlags flags = BindingFlags.Static | BindingFlags.Instance | BindingFlags.Public | BindingFlags.FlattenHierarchy;
    MethodInfo[] methods = t.GetMethods(flags).Where(x => x.Name == methodName).ToArray();
    if (methods.Length == 0) return "ERROR:No public method '" + methodName + "' on " + t.FullName;

    MethodInfo pick = null;
    string rule = "";

    foreach (MethodInfo m in methods) {
        ParameterInfo[] ps = m.GetParameters();
        if (ps.Length != args.Length) continue;
        bool ok = true;
        for (int i = 0; i < ps.Length; i++) {
            if (args[i] != null && !CanCoerceArg(args[i].GetType(), ps[i].ParameterType)) { ok = false; break; }
        }
        if (ok) { pick = m; rule = "parameter count and argument types match"; break; }
    }
    if (pick == null) {
        foreach (MethodInfo m in methods) {
            if (m.GetParameters().Length == args.Length) {
                pick = m; rule = "parameter count matches (argument types are coerced at call time)"; break;
            }
        }
    }
    if (pick == null) {
        foreach (MethodInfo m in methods) {
            ParameterInfo[] ps = m.GetParameters();
            if (ps.Length > 0 && ps[ps.Length - 1].GetCustomAttributes(typeof(ParamArrayAttribute), false).Length > 0
                && args.Length >= ps.Length - 1) {
                pick = m; rule = "params[] overload accepts the extra arguments"; break;
            }
        }
    }
    if (pick == null) { pick = methods[0]; rule = "nothing fits - falling back to the first overload"; }

    var sb = new StringBuilder();
    sb.Append("Selected Overload:\n").Append(MethodSig(pick)).Append("\n");
    sb.Append("Rule: ").Append(rule).Append("\n");
    sb.Append("Arguments: [").Append(string.Join(", ", args.Select(a => a == null ? "null" : a.GetType().Name))).Append("]\n");
    sb.Append("\nAll overloads (").Append(methods.Length).Append("):\n");
    foreach (MethodInfo m in methods)
        sb.Append(m == pick ? "  * " : "    ").Append(MethodSig(m)).Append("\n");
    return sb.ToString().TrimEnd();
}

// ── Visual Wrapper Auto-Generator ────────────────────────────────
public static string GetAssemblyTypes(string pathOrName) {
    Assembly targetAsm = null;
    string targetClassToCheck = null;

    if (File.Exists(pathOrName)) {
        try { targetAsm = Assembly.LoadFrom(pathOrName); } catch { return "ERROR:Failed to load assembly."; }
    } else {
        // 1. Direct match by assembly name
        foreach (var asm in AppDomain.CurrentDomain.GetAssemblies()) {
            if (asm.GetName().Name.Equals(pathOrName, StringComparison.OrdinalIgnoreCase)) {
                targetAsm = asm; break;
            }
        }

        // 2. If not found, check if it's a full type name (e.g. System.IO.File)
        if (targetAsm == null) {
            foreach (var asm in AppDomain.CurrentDomain.GetAssemblies()) {
                try {
                    var t = asm.GetType(pathOrName, false, true);
                    if (t != null) {
                        targetAsm = asm;
                        targetClassToCheck = t.FullName;
                        break;
                    }
                } catch { }
            }
        }

        // 3. Fallback to LoadWithPartialName
        if (targetAsm == null) {
            #pragma warning disable 618
            try { targetAsm = Assembly.LoadWithPartialName(pathOrName); } catch { }
            #pragma warning restore 618
        }

        // 4. If still not found, check if they typed a namespace (e.g. System.IO) and find any loaded assembly that has types in it
        if (targetAsm == null) {
            foreach (var asm in AppDomain.CurrentDomain.GetAssemblies()) {
                try {
                    bool hasNamespace = asm.GetExportedTypes().Any(x => x.Namespace != null && x.Namespace.Equals(pathOrName, StringComparison.OrdinalIgnoreCase));
                    if (hasNamespace) {
                        targetAsm = asm;
                        break;
                    }
                } catch { }
            }
        }
    }

    if (targetAsm == null) return "ERROR:Assembly not found.";

    var sb = new StringBuilder();
    // Return the resolved assembly name on the first line if it was redirected!
    sb.AppendLine("RESOLVED_ASM|" + targetAsm.GetName().Name + "|" + (targetClassToCheck ?? ""));

    foreach (Type t in targetAsm.GetExportedTypes().OrderBy(x => x.Namespace).ThenBy(x => x.Name)) {
        if (t.IsEnum || t.IsInterface || typeof(Delegate).IsAssignableFrom(t)) continue;
        
        var sm = t.GetMethods(BindingFlags.Public | BindingFlags.Static | BindingFlags.DeclaredOnly).Where(m => !m.IsSpecialName).Select(m => m.Name).Distinct();
        var im = t.GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly).Where(m => !m.IsSpecialName).Select(m => m.Name).Distinct();
        
        string sMethods = string.Join(",", sm);
        string iMethods = string.Join(",", im);
        
        if (sMethods.Length > 0 || iMethods.Length > 0) {
            sb.AppendLine(t.FullName + "|" + sMethods + "|" + iMethods);
        }
    }
    return sb.ToString().TrimEnd();
}

// Hard limits so a huge window (browser, IDE) cannot freeze the workbench: the walk stops at
// UiaMaxNodes elements or UiaMaxMillis milliseconds and the result is flagged with a #TRUNCATED line.
private const int UiaMaxNodes = 4000;
private const int UiaMaxMillis = 8000;

public static string GetUiaTree(long hwnd) {
    if (hwnd == 0) return "ERROR: Invalid HWND";
    try {
        var winEl = System.Windows.Automation.AutomationElement.FromHandle((IntPtr)hwnd);
        if (winEl == null) return "ERROR: Failed to get AutomationElement";

        var sb = new StringBuilder();
        var sw = Stopwatch.StartNew();
        int count = 0;
        bool truncated = false;
        BuildTreeString(winEl, sb, 0, sw, ref count, ref truncated);
        if (truncated)
            sb.AppendLine("#TRUNCATED|" + count + "|" + sw.ElapsedMilliseconds);
        return sb.ToString();
    } catch (Exception ex) {
        return "ERROR: " + ex.Message;
    }
}

private static void BuildTreeString(System.Windows.Automation.AutomationElement el, StringBuilder sb, int depth,
                                    Stopwatch sw, ref int count, ref bool truncated) {
    if (depth > 30) return; // Prevent stack overflow and extremely deep scans
    if (count >= UiaMaxNodes || sw.ElapsedMilliseconds > UiaMaxMillis) { truncated = true; return; }

    try {
        string name = el.Current.Name ?? "";
        string type = el.Current.ControlType.ProgrammaticName.Replace("ControlType.", "");
        string id = el.Current.AutomationId ?? "";
        string className = el.Current.ClassName ?? "";

        name = name.Replace("|", " ").Replace("\r", " ").Replace("\n", " ");
        id = id.Replace("|", " ").Replace("\r", " ").Replace("\n", " ");
        className = className.Replace("|", " ").Replace("\r", " ").Replace("\n", " ");

        string rectStr = "";
        try {
            var rect = el.Current.BoundingRectangle;
            rectStr = string.Format("{0},{1},{2},{3}", (int)rect.X, (int)rect.Y, (int)rect.Width, (int)rect.Height);
        } catch {
            rectStr = "0,0,0,0";
        }

        sb.AppendLine(string.Format("{0}|{1}|{2}|{3}|{4}|{5}", depth, name, type, id, className, rectStr));
        count++;

        var children = el.FindAll(System.Windows.Automation.TreeScope.Children, System.Windows.Automation.Condition.TrueCondition);
        foreach (System.Windows.Automation.AutomationElement child in children) {
            if (truncated) break;
            BuildTreeString(child, sb, depth + 1, sw, ref count, ref truncated);
        }
    } catch {}
}


public static string GetUiaElementAtPoint(int x, int y) {
    try {
        var pt = new System.Windows.Point(x, y);
        var el = System.Windows.Automation.AutomationElement.FromPoint(pt);
        if (el == null) return "";
        
        string name = el.Current.Name ?? "";
        string type = el.Current.ControlType.ProgrammaticName.Replace("ControlType.", "");
        string id = el.Current.AutomationId ?? "";
        string className = el.Current.ClassName ?? "";
        
        name = name.Replace("|", " ").Replace("\r", " ").Replace("\n", " ");
        id = id.Replace("|", " ").Replace("\r", " ").Replace("\n", " ");
        className = className.Replace("|", " ").Replace("\r", " ").Replace("\n", " ");
        
        string rectStr = "";
        try {
            var rect = el.Current.BoundingRectangle;
            rectStr = string.Format("{0},{1},{2},{3}", (int)rect.X, (int)rect.Y, (int)rect.Width, (int)rect.Height);
        } catch {
            rectStr = "0,0,0,0";
        }
        
        return string.Format("{0}|{1}|{2}|{3}|{4}", name, type, id, className, rectStr);
    } catch {
        return "";
    }
}
