// ═══════════════════════════════════════════════════════════════════════════════
// AHK# Bridge — MemberHints: "did you mean ...?" for misspelled members
// (part of ahk#.bridge.dll; used by the error paths in AhkSharpBridge.cs / DelegateBridge.cs)
// ═══════════════════════════════════════════════════════════════════════════════

using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;

internal static class MemberHints
{
    // Public member names of `t` (static or instance side), de-duplicated, without compiler noise.
    private static List<string> Names(Type t, bool isStatic, bool events)
    {
        BindingFlags f = BindingFlags.Public | BindingFlags.FlattenHierarchy
            | (isStatic ? BindingFlags.Static : BindingFlags.Instance);
        HashSet<string> set = new HashSet<string>(StringComparer.Ordinal);
        try
        {
            foreach (MemberInfo m in t.GetMembers(f))
            {
                if (events ? m.MemberType != MemberTypes.Event
                           : (m.MemberType == MemberTypes.Constructor || m.MemberType == MemberTypes.Event
                              || m.MemberType == MemberTypes.TypeInfo))
                    continue;
                MethodBase mb = m as MethodBase;
                if (mb != null && mb.IsSpecialName) continue;      // get_X / set_X / op_Addition ...
                set.Add(m.Name);
            }
            if (!events && isStatic)
                foreach (Type n in t.GetNestedTypes(BindingFlags.Public))
                    set.Add(n.Name);
        }
        catch { }
        return set.ToList();
    }

    // "  Did you mean: Abs?"  (empty when nothing is close enough)
    public static string Suggest(Type t, string name, bool isStatic, bool events)
    {
        if (t == null || string.IsNullOrEmpty(name)) return "";
        int limit = name.Length <= 4 ? 1 : Math.Max(2, name.Length / 3);
        var ranked = Names(t, isStatic, events)
            .Select(n => new { Name = n, Score = Distance(name, n) })
            .Where(x => x.Score <= limit)
            .OrderBy(x => x.Score).ThenBy(x => x.Name, StringComparer.Ordinal)
            .Take(3).Select(x => x.Name).ToList();
        if (ranked.Count == 0)
        {
            // the member may exist on the other side (instance member used statically, or the reverse)
            string other = Names(t, !isStatic, events).FirstOrDefault(n => string.Equals(n, name, StringComparison.OrdinalIgnoreCase));
            if (other != null)
                return " '" + other + "' is " + (isStatic ? "an instance" : "a static") + " member: call it on "
                    + (isStatic ? "an object" : "the type") + ".";
            return "";
        }
        return " Did you mean: " + string.Join(", ", ranked.ToArray()) + "?";
    }

    // Case-insensitive Levenshtein distance; a transposed adjacent pair counts as one edit.
    internal static int Distance(string a, string b)
    {
        a = a.ToLowerInvariant(); b = b.ToLowerInvariant();
        if (a == b) return 0;
        int[,] d = new int[a.Length + 1, b.Length + 1];
        for (int i = 0; i <= a.Length; i++) d[i, 0] = i;
        for (int j = 0; j <= b.Length; j++) d[0, j] = j;
        for (int i = 1; i <= a.Length; i++)
            for (int j = 1; j <= b.Length; j++)
            {
                int cost = a[i - 1] == b[j - 1] ? 0 : 1;
                int v = Math.Min(Math.Min(d[i - 1, j] + 1, d[i, j - 1] + 1), d[i - 1, j - 1] + cost);
                if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1])
                    v = Math.Min(v, d[i - 2, j - 2] + 1);
                d[i, j] = v;
            }
        return d[a.Length, b.Length];
    }

    public static Exception Missing(Type t, string name, bool isStatic)
    {
        return new MissingMemberException("Member '" + t.FullName + "." + name + "' not found."
            + Suggest(t, name, isStatic, false));
    }
}
