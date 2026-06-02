using System;
using System.Windows.Forms;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Net;
using System.Diagnostics;

private static readonly string _cacheDir = Path.Combine(
    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
    "AhkSharp", "CompileCache");

private static readonly string _pkgDir = Path.Combine(
    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
    "AhkSharp", "Packages");

// ── WinForms UI Generators ───────────────────────────────────────
public static SplitContainer _marshSplit;
public static TextBox _marshInput;
public static TreeView _marshTree;

public static long CreateMarshallingUI() {
    _marshSplit = new SplitContainer();
    _marshSplit.Dock = DockStyle.Fill;
    _marshSplit.SplitterDistance = 520;
    _marshSplit.BackColor = Color.FromArgb(51, 51, 51);
    
    _marshInput = new TextBox();
    _marshInput.Multiline = true;
    _marshInput.ScrollBars = ScrollBars.Both;
    _marshInput.Dock = DockStyle.Fill;
    _marshInput.BackColor = Color.FromArgb(18, 18, 31);
    _marshInput.ForeColor = Color.FromArgb(212, 212, 232);
    _marshInput.Font = new Font("Consolas", 10);
    _marshInput.Text = "[1, 2, \"three\"]";
    _marshInput.BorderStyle = BorderStyle.None;
    
    _marshTree = new TreeView();
    _marshTree.Dock = DockStyle.Fill;
    _marshTree.BackColor = Color.FromArgb(13, 13, 24);
    _marshTree.ForeColor = Color.FromArgb(74, 222, 128);
    _marshTree.Font = new Font("Consolas", 10);
    _marshTree.BorderStyle = BorderStyle.None;
    
    _marshSplit.Panel1.Controls.Add(_marshInput);
    _marshSplit.Panel2.Controls.Add(_marshTree);
    
    return _marshSplit.Handle.ToInt64();
}

public static string GetMarshallingInput() { return _marshInput.Text; }
public static void SetMarshallingInput(string text) { _marshInput.Text = text; }

public static void PopulateMarshallingTree(object obj) {
    _marshTree.Nodes.Clear();
    var root = _marshTree.Nodes.Add("Root");
    BuildTreeNode(root, obj, 0);
    root.ExpandAll();
}

public static void SetMarshallingError(string msg) {
    _marshTree.Nodes.Clear();
    _marshTree.Nodes.Add(msg).ForeColor = Color.Red;
}

private static void BuildTreeNode(TreeNode parent, object obj, int depth) {
    if (depth > 5) { parent.Nodes.Add("... max depth"); return; }
    if (obj == null) { parent.Text += " : null"; return; }
    
    Type t = obj.GetType();
    parent.Text += " (" + t.Name + ")";
    
    if (t.IsCOMObject) {
        try {
            object lenObj = t.InvokeMember("Length", BindingFlags.GetProperty, null, obj, null);
            int len = Convert.ToInt32(lenObj);
            for (int i = 1; i <= len; i++) {
                object item = null;
                try { item = t.InvokeMember("Item", BindingFlags.GetProperty, null, obj, new object[] { i }); } catch {}
                var child = parent.Nodes.Add("[" + i + "]");
                BuildTreeNode(child, item, depth + 1);
            }
            return;
        } catch {}
        try {
            object count = t.InvokeMember("Count", BindingFlags.GetProperty, null, obj, null);
            parent.Nodes.Add("Count: " + count);
        } catch {}
    } else if (obj is IEnumerable && !(obj is string)) {
        IEnumerable enumerable = (IEnumerable)obj;
        int i = 0;
        foreach (var item in enumerable) {
            var child = parent.Nodes.Add("[" + i++ + "]");
            BuildTreeNode(child, item, depth + 1);
        }
    } else {
        parent.Text += " = " + obj.ToString();
    }
}

public static SplitContainer _overSplit;
public static TextBox _overInput;
public static TextBox _overResult;

public static long CreateOverloadsUI() {
    _overSplit = new SplitContainer();
    _overSplit.Dock = DockStyle.Fill;
    _overSplit.SplitterDistance = 520;
    _overSplit.BackColor = Color.FromArgb(51, 51, 51);
    
    _overInput = new TextBox();
    _overInput.Multiline = true;
    _overInput.ScrollBars = ScrollBars.Both;
    _overInput.Dock = DockStyle.Fill;
    _overInput.BackColor = Color.FromArgb(18, 18, 31);
    _overInput.ForeColor = Color.FromArgb(212, 212, 232);
    _overInput.Font = new Font("Consolas", 10);
    _overInput.Text = "[\"123\", 16]";
    _overInput.BorderStyle = BorderStyle.None;
    
    _overResult = new TextBox();
    _overResult.Multiline = true;
    _overResult.ScrollBars = ScrollBars.Both;
    _overResult.Dock = DockStyle.Fill;
    _overResult.BackColor = Color.FromArgb(13, 13, 24);
    _overResult.ForeColor = Color.FromArgb(74, 222, 128);
    _overResult.Font = new Font("Consolas", 10);
    _overResult.BorderStyle = BorderStyle.None;
    
    _overSplit.Panel1.Controls.Add(_overInput);
    _overSplit.Panel2.Controls.Add(_overResult);
    
    return _overSplit.Handle.ToInt64();
}

public static string GetOverloadsArgs() { return _overInput.Text; }
public static void SetOverloadsResult(string msg) { _overResult.Text = msg; }

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
        var parms = string.Join(", ", ci.GetParameters().Select(p => ShortName(p.ParameterType) + " " + p.Name));
        sb.AppendLine("Constructor|" + t.Name + "|(" + parms + ")|" + (ci.IsStatic ? "Static" : "Instance"));
    }
    foreach (var mi in t.GetMethods(flags).Where(m => !m.IsSpecialName).OrderBy(m => m.Name)) {
        var parms = string.Join(", ", mi.GetParameters().Select(p => ShortName(p.ParameterType) + " " + p.Name));
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

public static string GenerateSnippet(string typeName, string memberName, string memberType) {
    Type t = null;
    foreach (var asm in AppDomain.CurrentDomain.GetAssemblies()) {
        try { t = asm.GetType(typeName, false, true); if (t != null) break; } catch { }
    }
    if (t == null) return "; Type not found";
    string ns = t.FullName;

    if (memberType == "Constructor") {
        var ci = t.GetConstructors().FirstOrDefault();
        if (ci == null) return "; No constructor";
        var parms = string.Join(", ", ci.GetParameters().Select(p => p.Name));
        return "obj := CS." + ns + "(" + parms + ")";
    }
    if (memberType == "Method") {
        var mi = t.GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static)
            .FirstOrDefault(m => m.Name == memberName && !m.IsSpecialName);
        if (mi == null) return "; Method not found";
        var parms = string.Join(", ", mi.GetParameters().Select(p => p.Name));
        return mi.IsStatic
            ? "result := CS." + ns + "." + memberName + "(" + parms + ")"
            : "result := obj." + memberName + "(" + parms + ")";
    }
    if (memberType == "Property") {
        var pi = t.GetProperty(memberName, BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static);
        if (pi == null) return "; Property not found";
        return IsStaticP(pi)
            ? "value := CS." + ns + "." + memberName
            : "value := obj." + memberName;
    }
    return "; " + memberType + ": " + memberName;
}

// ── Cache Manager ────────────────────────────────────────────────
public static string ScanCache() {
    if (!Directory.Exists(_cacheDir)) return "";
    var sb = new StringBuilder();
    foreach (var dll in Directory.GetFiles(_cacheDir, "*.dll")) {
        var fi = new FileInfo(dll);
        string hash = Path.GetFileNameWithoutExtension(dll);
        string classes = "";
        try {
            var bytes = File.ReadAllBytes(dll);
            var asm = Assembly.Load(bytes);
            var types = asm.GetExportedTypes();
            classes = types.Length > 0
                ? string.Join(", ", types.Select(x => x.Name))
                : "(no exported types)";
        } catch {
            classes = "(unable to inspect)";
        }
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

        // Get exported classes
        string classes = "";
        try {
            var types = asm.GetExportedTypes();
            classes = types.Length > 0
                ? string.Join(", ", types.Select(x => x.Name))
                : "(none)";
        } catch {
            classes = "(unable to inspect)";
        }

        sb.AppendLine(n.Name + "|" + n.Version + "|" + sizeStr + "|" + classes + "|" + loc);
    }
    return sb.ToString().TrimEnd();
}

public static int CleanUnusedCache() {
    if (!Directory.Exists(_cacheDir)) return 0;
    
    var loadedNames = new HashSet<string>(
        AppDomain.CurrentDomain.GetAssemblies().Select(a => a.GetName().Name),
        StringComparer.OrdinalIgnoreCase
    );
    
    int deleted = 0;
    foreach (var dll in Directory.GetFiles(_cacheDir, "*.dll")) {
        try {
            string hash = Path.GetFileNameWithoutExtension(dll);
            if (!loadedNames.Contains(hash)) {
                string csFile = Path.Combine(_cacheDir, hash + ".cs");
                if (File.Exists(dll)) File.Delete(dll);
                if (File.Exists(csFile)) File.Delete(csFile);
                deleted++;
            }
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

// ── Marshalling Inspector ────────────────────────────────────────
public static string InspectType(object obj) {
    if (obj == null) return "null";
    var sb = new StringBuilder();
    InspectInternal(obj, sb, 0);
    return sb.ToString().TrimEnd();
}

private static void InspectInternal(object obj, StringBuilder sb, int depth) {
    string indent = new string(' ', depth * 4);
    if (obj == null) {
        sb.AppendLine(indent + "null");
        return;
    }
    Type t = obj.GetType();
    sb.AppendLine(indent + "Type: " + t.FullName);
    if (t.IsArray) {
        Array arr = (Array)obj;
        sb.AppendLine(indent + "Array Length: " + arr.Length);
        int limit = Math.Min(arr.Length, 10);
        for (int i = 0; i < limit; i++) {
            sb.AppendLine(indent + "  [" + i + "]:");
            InspectInternal(arr.GetValue(i), sb, depth + 1);
        }
        if (arr.Length > 10) sb.AppendLine(indent + "  ... (" + (arr.Length - 10) + " more items)");
    } else if (obj is IDictionary) {
        IDictionary dict = (IDictionary)obj;
        sb.AppendLine(indent + "Dictionary Count: " + dict.Count);
        int count = 0;
        foreach (DictionaryEntry kv in dict) {
            if (count++ >= 10) { sb.AppendLine(indent + "  ... more items"); break; }
            sb.AppendLine(indent + "  Key:");
            InspectInternal(kv.Key, sb, depth + 1);
            sb.AppendLine(indent + "  Value:");
            InspectInternal(kv.Value, sb, depth + 1);
        }
    } else if (t.IsCOMObject) {
        sb.AppendLine(indent + "COM Object Detected (IDispatch)");
        try {
            object count = t.InvokeMember("Count", BindingFlags.GetProperty, null, obj, null);
            sb.AppendLine(indent + "  Count: " + count);
        } catch { }
        try {
            object lengthObj = t.InvokeMember("Length", BindingFlags.GetProperty, null, obj, null);
            sb.AppendLine(indent + "  Length: " + lengthObj);
            try {
                int len = Convert.ToInt32(lengthObj);
                int limit = Math.Min(len, 10);
                for (int i = 1; i <= limit; i++) {
                    try {
                        object item = t.InvokeMember("Item", BindingFlags.GetProperty, null, obj, new object[] { i });
                        sb.AppendLine(indent + "  [" + i + "]: " + (item != null ? item.ToString() : "null"));
                    } catch {}
                }
                if (len > 10) sb.AppendLine(indent + "  ... (" + (len - 10) + " more items)");
            } catch {}
        } catch { }
    } else if (t.IsPrimitive || t == typeof(string)) {
        sb.AppendLine(indent + "Value: " + obj.ToString());
    } else {
        sb.AppendLine(indent + "ToString: " + obj.ToString());
    }
}

// ── Overload Predictor ───────────────────────────────────────────
public static string PredictOverload(string typeName, string methodName, object[] args) {
    Type t = ResolveType(typeName);
    if (t == null) return "ERROR:Type not found: " + typeName;

    if (args == null) args = new object[0];

    Type bridgeType = null;
    foreach (var asm in AppDomain.CurrentDomain.GetAssemblies()) {
        if (asm.GetName().Name == "ahk#.bridge") {
            bridgeType = asm.GetType("AhkSharpBridge");
            break;
        }
    }
    if (bridgeType == null) return "ERROR:AhkSharpBridge not found in AppDomain.";

    MethodInfo resolveMethod = bridgeType.GetMethod("ResolveMethod", BindingFlags.NonPublic | BindingFlags.Static);
    if (resolveMethod == null) return "ERROR:ResolveMethod not found in AhkSharpBridge.";

    BindingFlags flags = BindingFlags.Static | BindingFlags.Instance | BindingFlags.Public | BindingFlags.FlattenHierarchy;
    
    try {
        MethodInfo mi = (MethodInfo)resolveMethod.Invoke(null, new object[] { t, methodName, args, flags });
        if (mi == null) return "No matching overload found for the given arguments.";

        var parms = string.Join(", ", mi.GetParameters().Select(p => ShortName(p.ParameterType) + " " + p.Name));
        return "Selected Overload:\n" + ShortName(mi.ReturnType) + " " + mi.Name + "(" + parms + ")";
    } catch (Exception ex) {
        return "ERROR:" + (ex.InnerException != null ? ex.InnerException.Message : ex.Message);
    }
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

public static string GetUiaTree(long hwnd) {
    if (hwnd == 0) return "ERROR: Invalid HWND";
    try {
        var winEl = System.Windows.Automation.AutomationElement.FromHandle((IntPtr)hwnd);
        if (winEl == null) return "ERROR: Failed to get AutomationElement";
        
        var sb = new StringBuilder();
        BuildTreeString(winEl, sb, 0);
        return sb.ToString();
    } catch (Exception ex) {
        return "ERROR: " + ex.Message;
    }
}

private static void BuildTreeString(System.Windows.Automation.AutomationElement el, StringBuilder sb, int depth) {
    if (depth > 30) return; // Prevent stack overflow and extremely deep scans
    
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
        
        var children = el.FindAll(System.Windows.Automation.TreeScope.Children, System.Windows.Automation.Condition.TrueCondition);
        foreach (System.Windows.Automation.AutomationElement child in children) {
            BuildTreeString(child, sb, depth + 1);
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
