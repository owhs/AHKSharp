// ═══════════════════════════════════════════════════════════════════════════════
// AHK# Bridge — Discovery: "what can I call on this?" (CS.Members / CS.Types)
// (part of ahk#.bridge.dll; exposed through AhkSharpBridge.Describe / TypesIn)
// ═══════════════════════════════════════════════════════════════════════════════

using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Text;

internal static class Discovery
{
    private static readonly Dictionary<Type, string> _keywords = new Dictionary<Type, string> {
        { typeof(void), "void" }, { typeof(bool), "bool" }, { typeof(byte), "byte" }, { typeof(sbyte), "sbyte" },
        { typeof(short), "short" }, { typeof(ushort), "ushort" }, { typeof(int), "int" }, { typeof(uint), "uint" },
        { typeof(long), "long" }, { typeof(ulong), "ulong" }, { typeof(float), "float" }, { typeof(double), "double" },
        { typeof(decimal), "decimal" }, { typeof(char), "char" }, { typeof(string), "string" }, { typeof(object), "object" }
    };

    public static string TypeName(Type t)
    {
        string k;
        if (_keywords.TryGetValue(t, out k)) return k;
        if (t.IsByRef) return "ref " + TypeName(t.GetElementType());
        if (t.IsArray) return TypeName(t.GetElementType()) + "[" + new string(',', t.GetArrayRank() - 1) + "]";
        if (t.IsGenericParameter) return t.Name;
        if (t.IsGenericType)
        {
            Type[] args = t.GetGenericArguments();
            Type under = Nullable.GetUnderlyingType(t);
            if (under != null) return TypeName(under) + "?";
            string n = t.Name;
            int tick = n.IndexOf('`');
            if (tick > 0) n = n.Substring(0, tick);
            return n + "<" + string.Join(", ", args.Select(a => TypeName(a)).ToArray()) + ">";
        }
        return t.Name;
    }

    private static string Params(ParameterInfo[] ps)
    {
        return string.Join(", ", ps.Select(p =>
        {
            string s = TypeName(p.ParameterType) + " " + p.Name;
            if (p.IsOptional) s += " = " + (p.DefaultValue == null || p.DefaultValue == DBNull.Value ? "null" : p.DefaultValue.ToString());
            if (p.GetCustomAttributes(typeof(ParamArrayAttribute), false).Length > 0) s = "params " + s;
            return s;
        }).ToArray());
    }

    // One line per public member: "static double Abs(double value)", "int Length { get; set; }", ...
    public static string Describe(Type t, string filter)
    {
        List<KeyValuePair<string, string>> rows = new List<KeyValuePair<string, string>>();
        foreach (MemberInfo m in t.GetMembers(BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static | BindingFlags.FlattenHierarchy))
        {
            string line = null;
            MethodBase mb = m as MethodBase;
            if (m is ConstructorInfo)
                line = "new " + TypeName(t) + "(" + Params(((ConstructorInfo)m).GetParameters()) + ")";
            else if (m is MethodInfo)
            {
                MethodInfo mi = (MethodInfo)m;
                if (mi.IsSpecialName) continue;
                string gen = mi.IsGenericMethodDefinition
                    ? "<" + string.Join(", ", mi.GetGenericArguments().Select(a => a.Name).ToArray()) + ">" : "";
                line = (mi.IsStatic ? "static " : "") + TypeName(mi.ReturnType) + " " + mi.Name + gen + "(" + Params(mi.GetParameters()) + ")";
            }
            else if (m is PropertyInfo)
            {
                PropertyInfo pi = (PropertyInfo)m;
                ParameterInfo[] idx = pi.GetIndexParameters();
                MethodInfo g = pi.GetGetMethod(), s = pi.GetSetMethod();
                bool isStatic = (g ?? s).IsStatic;
                string acc = (g != null && s != null) ? "get; set;" : (g != null ? "get;" : "set;");
                string nm = idx.Length > 0 ? "this[" + Params(idx) + "]" : pi.Name;
                line = (isStatic ? "static " : "") + TypeName(pi.PropertyType) + " " + nm + " { " + acc + " }";
            }
            else if (m is FieldInfo)
            {
                FieldInfo fi = (FieldInfo)m;
                line = (fi.IsStatic ? (fi.IsLiteral ? "const " : "static ") : "") + TypeName(fi.FieldType) + " " + fi.Name;
            }
            else if (m is EventInfo)
            {
                EventInfo ei = (EventInfo)m;
                MethodInfo add = ei.GetAddMethod();
                line = (add != null && add.IsStatic ? "static " : "") + "event " + TypeName(ei.EventHandlerType) + " " + ei.Name;
            }
            else if (m.MemberType == MemberTypes.NestedType)
                line = "type " + m.Name;
            if (line == null) continue;
            if (!string.IsNullOrEmpty(filter) && m.Name.IndexOf(filter, StringComparison.OrdinalIgnoreCase) < 0) continue;
            rows.Add(new KeyValuePair<string, string>(m is ConstructorInfo ? "" : m.Name, line));
        }
        return string.Join("\n", rows.Distinct()
            .OrderBy(r => r.Key, StringComparer.OrdinalIgnoreCase).ThenBy(r => r.Value, StringComparer.Ordinal)
            .Select(r => r.Value).ToArray());
    }

    // Names directly under a namespace: its own types and its child namespaces.
    private static List<string> ChildNames(string ns)
    {
        string prefix = ns.Length > 0 ? ns + "." : "";
        HashSet<string> names = new HashSet<string>(StringComparer.Ordinal);
        foreach (Assembly asm in TypeResolver.AllAssemblies())
        {
            Type[] types;
            try { types = asm.GetExportedTypes(); }
            catch { continue; }
            foreach (Type t in types)
            {
                string tn = t.Namespace;
                if (tn == null || t.IsNested) continue;
                if (tn == ns) names.Add(t.Name);
                else if (tn.StartsWith(prefix, StringComparison.Ordinal))
                {
                    string sub = tn.Substring(prefix.Length);
                    int dot = sub.IndexOf('.');
                    names.Add(dot > 0 ? sub.Substring(0, dot) : sub);
                }
            }
        }
        return names.ToList();
    }

    // "System.Tex.StringBuilder" → "System.Text.StringBuilder": corrects the first segment that does not exist.
    public static string SuggestPath(string dotted)
    {
        if (string.IsNullOrEmpty(dotted)) return "";
        string[] parts = dotted.Split('.');
        string ns = "";
        TypeResolver.EnsureCommonAssemblies(dotted);
        for (int i = 0; i < parts.Length; i++)
        {
            List<string> children = ChildNames(ns);
            string seg = parts[i];
            string exact = children.FirstOrDefault(c => string.Equals(c, seg, StringComparison.OrdinalIgnoreCase));
            if (exact != null)
            {
                parts[i] = exact;
                if (TypeResolver.Resolve(ns.Length > 0 ? ns + "." + exact : exact) != null)
                    return i == parts.Length - 1 && exact == seg ? "" : string.Join(".", parts);   // reached a type: the rest are members
                ns = ns.Length > 0 ? ns + "." + exact : exact;
                continue;
            }
            int limit = seg.Length <= 4 ? 1 : Math.Max(2, seg.Length / 3);
            string best = children.Select(c => new { Name = c, D = MemberHints.Distance(seg, c) })
                .Where(x => x.D <= limit).OrderBy(x => x.D).ThenBy(x => x.Name, StringComparer.Ordinal)
                .Select(x => x.Name).FirstOrDefault();
            if (best == null) return "";
            parts[i] = best;
            return string.Join(".", parts);
        }
        return "";
    }

    // Public types directly in namespace `ns` (plus "Sub.*" lines for child namespaces), from the loaded assemblies.
    public static string TypesIn(string ns, string filter)
    {
        TypeResolver.EnsureCommonAssemblies(ns);
        string prefix = ns.Length > 0 ? ns + "." : "";
        SortedDictionary<string, string> found = new SortedDictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (Assembly asm in TypeResolver.AllAssemblies())
        {
            Type[] types;
            try { types = asm.GetExportedTypes(); }
            catch { continue; }
            foreach (Type t in types)
            {
                string tn = t.Namespace;
                if (tn == null || t.IsNested) continue;
                if (tn == ns)
                    found[t.Name] = t.FullName + (t.IsInterface ? "  (interface)" : t.IsEnum ? "  (enum)" : t.IsValueType ? "  (struct)" : t.IsAbstract && t.IsSealed ? "  (static class)" : "");
                else if (tn.StartsWith(prefix, StringComparison.Ordinal))
                {
                    string sub = tn.Substring(prefix.Length);
                    int dot = sub.IndexOf('.');
                    if (dot > 0) sub = sub.Substring(0, dot);
                    found[sub + "."] = prefix + sub + ".*";
                }
            }
        }
        IEnumerable<string> lines = found.Where(kv => string.IsNullOrEmpty(filter)
            || kv.Key.IndexOf(filter, StringComparison.OrdinalIgnoreCase) >= 0).Select(kv => kv.Value);
        return string.Join("\n", lines.ToArray());
    }
}
