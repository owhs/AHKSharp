// ═══════════════════════════════════════════════════════════════════════════════
// AHK# Overload Binder
// ═══════════════════════════════════════════════════════════════════════════════
// Picks the best overload for a call made from AutoHotkey, where every value
// arrives as Int32 / Int64 / Double / String / object[] / object[,] / typed
// arrays / COM object.
//
//   • Two phases: every candidate is SCORED (cheap, never throws, allocates
//     nothing per element); only the winner has its arguments converted.
//   • Lowest total cost wins (exact type = 0). Lossy conversions are rejected
//     (Math.Abs(-2.5) can never bind to Abs(int)).
//   • params arrays, optional parameters and generic methods (LINQ) work.
//   • AHK Array (object[] / long[] / double[]) → T[] / List<T> / IEnumerable<T>
//   • AHK Map   (object[,]) → Dictionary<K,V> / IDictionary
//   • AHK function objects (COM IDispatch) → any delegate type — invoked
//     synchronously on the AHK thread only.
//
// Written in C# 4.0 syntax (csc v4.0.30319).
// ═══════════════════════════════════════════════════════════════════════════════

using System;
using System.Collections;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.ComponentModel;
using System.Globalization;
using System.Linq;
using System.Linq.Expressions;
using System.Reflection;
using System.Text;
using System.Threading;

internal sealed class BoundCall
{
    public MethodBase Method;
    public object[] Args;
    public int Cost;
}

internal static class OverloadBinder
{
    // ── Candidate lookup (cached, allocation-free key) ────────────────────

    private struct MemberKey : IEquatable<MemberKey>
    {
        public Type Type; public string Name; public int Kind;   // 0 instance, 1 static, 2 ctor
        public bool Equals(MemberKey o) { return Type == o.Type && Kind == o.Kind && string.Equals(Name, o.Name, StringComparison.Ordinal); }
        public override bool Equals(object o) { return o is MemberKey && Equals((MemberKey)o); }
        public override int GetHashCode() { return (Type.GetHashCode() * 31 + Kind) * 31 + (Name == null ? 0 : Name.GetHashCode()); }
    }

    private static readonly ConcurrentDictionary<MemberKey, MethodBase[]> _methodCache =
        new ConcurrentDictionary<MemberKey, MethodBase[]>();

    public static MethodBase[] GetMethods(Type t, string name, bool isStatic)
    {
        MemberKey key = new MemberKey { Type = t, Name = name, Kind = isStatic ? 1 : 0 };
        MethodBase[] cached;
        if (_methodCache.TryGetValue(key, out cached)) return cached;

        BindingFlags f = BindingFlags.Public
            | (isStatic ? (BindingFlags.Static | BindingFlags.FlattenHierarchy) : BindingFlags.Instance);
        List<MethodBase> exact = new List<MethodBase>();
        List<MethodBase> loose = new List<MethodBase>();
        foreach (MethodInfo m in t.GetMethods(f))
        {
            if (string.Equals(m.Name, name, StringComparison.Ordinal)) exact.Add(m);
            else if (string.Equals(m.Name, name, StringComparison.OrdinalIgnoreCase)) loose.Add(m);
        }
        // AHK is case-insensitive: fall back to a case-insensitive match
        MethodBase[] result = (exact.Count > 0 ? exact : loose).ToArray();
        _methodCache[key] = result;
        return result;
    }

    public static MethodBase[] GetConstructors(Type t)
    {
        MemberKey key = new MemberKey { Type = t, Name = null, Kind = 2 };
        MethodBase[] cached;
        if (_methodCache.TryGetValue(key, out cached)) return cached;
        MethodBase[] result = t.GetConstructors(BindingFlags.Public | BindingFlags.Instance).Cast<MethodBase>().ToArray();
        _methodCache[key] = result;
        return result;
    }

    // ── Binding ───────────────────────────────────────────────────────────

    // Set by any scoring step whose outcome depends on the argument VALUE (parsing a string, range
    // checks, "" meaning null, array contents). When it stays false the winner depends on the argument
    // TYPES alone and is cached, so repeated calls skip scoring entirely.
    [ThreadStatic] private static bool _valueDependent;

    private sealed class CachedBind
    {
        public MethodBase[] Candidates;
        public Type[] Types;
        public MethodBase Method;
    }

    private static readonly ConcurrentDictionary<int, CachedBind> _bindCache =
        new ConcurrentDictionary<int, CachedBind>();

    public static int[] CacheSizes { get { return new[] { _methodCache.Count, _bindCache.Count }; } }

    private static int SignatureHash(MethodBase[] cands, object[] args)
    {
        int h = System.Runtime.CompilerServices.RuntimeHelpers.GetHashCode(cands);
        for (int i = 0; i < args.Length; i++)
            h = h * 31 + (args[i] == null ? 7 : args[i].GetType().GetHashCode());
        return h;
    }

    private static bool SignatureMatches(CachedBind e, MethodBase[] cands, object[] args)
    {
        if (!object.ReferenceEquals(e.Candidates, cands) || e.Types.Length != args.Length) return false;
        for (int i = 0; i < args.Length; i++)
            if (e.Types[i] != (args[i] == null ? typeof(void) : args[i].GetType())) return false;
        return true;
    }

    public static BoundCall Bind(IEnumerable<MethodBase> candidates, object[] args)
    {
        MethodBase[] cachable = candidates as MethodBase[];
        int hash = 0;
        if (cachable != null)
        {
            hash = SignatureHash(cachable, args);
            CachedBind hit;
            if (_bindCache.TryGetValue(hash, out hit) && SignatureMatches(hit, cachable, args))
            {
                BoundCall fast = TryBind(hit.Method, args, true);
                if (fast != null) return fast;
            }
        }

        // Phase 1: score every candidate (no conversions built, no exceptions)
        _valueDependent = false;
        BoundCall best = null;
        foreach (MethodBase mb in candidates)
        {
            BoundCall b = TryBind(mb, args, false);
            if (b != null && (best == null || b.Cost < best.Cost))
                best = b;
        }
        if (best == null) return null;

        // Cacheable when the winner is chosen by TYPES alone: it used no value-dependent scoring itself and
        // its cost (< 6) is below the cheapest possible value-dependent conversion, so no value can beat it.
        _valueDependent = false;
        TryBind(best.Method, args, false);
        bool typeOnly = !_valueDependent && best.Cost < 6;
        // Phase 2: convert the arguments for the winner only
        BoundCall final = TryBind(best.Method, args, true);
        if (final == null)
            throw new InvalidCastException("Arguments (" + DescribeArgs(args) + ") could not be converted for "
                + best.Method.DeclaringType.Name + "." + best.Method.Name);

        if (cachable != null && typeOnly)
        {
            Type[] types = new Type[args.Length];
            for (int i = 0; i < args.Length; i++) types[i] = args[i] == null ? typeof(void) : args[i].GetType();
            _bindCache[hash] = new CachedBind { Candidates = cachable, Types = types, Method = best.Method };
        }
        return final;
    }

    private static BoundCall TryBind(MethodBase mb, object[] args, bool make)
    {
        MethodInfo mi = mb as MethodInfo;
        if (mi != null && mi.IsGenericMethodDefinition)
        {
            mi = InferGeneric(mi, args);
            if (mi == null) return null;
            mb = mi;
        }

        ParameterInfo[] ps = mb.GetParameters();
        BoundCall best = null;
        object[] conv;
        int cost;

        if (TryBindNormal(ps, args, make, out conv, out cost))
            best = new BoundCall { Method = mb, Args = conv, Cost = cost };

        if (ps.Length > 0 && IsParams(ps[ps.Length - 1]) && args.Length >= ps.Length - 1)
        {
            if (TryBindExpanded(ps, args, make, out conv, out cost))
            {
                cost += 25;
                if (best == null || cost < best.Cost)
                    best = new BoundCall { Method = mb, Args = conv, Cost = cost };
            }
        }

        // Variadic-style calls into a trailing object / object[] parameter:
        //   Json.Build("k1", "v1", "k2", "v2")  →  Build(object pairs)   (extra arguments are packed)
        if (best == null && ps.Length > 0 && args.Length > ps.Length
            && (ps[ps.Length - 1].ParameterType == typeof(object) || ps[ps.Length - 1].ParameterType == typeof(object[])))
        {
            if (TryBindPacked(ps, args, make, out conv, out cost))
                best = new BoundCall { Method = mb, Args = conv, Cost = cost + 40 };
        }
        return best;
    }

    private static bool TryBindPacked(ParameterInfo[] ps, object[] args, bool make, out object[] conv, out int cost)
    {
        conv = null; cost = 0;
        int fixedCount = ps.Length - 1;
        object[] result = make ? new object[ps.Length] : null;
        for (int i = 0; i < fixedCount; i++)
        {
            object c;
            int k = CoerceCore(args[i], ps[i].ParameterType, make, out c);
            if (k < 0) return false;
            if (make) result[i] = c;
            cost += k;
        }
        if (make)
        {
            object[] packed = new object[args.Length - fixedCount];
            Array.Copy(args, fixedCount, packed, 0, packed.Length);
            result[fixedCount] = packed;
        }
        conv = result;
        return true;
    }

    private static bool IsParams(ParameterInfo p)
    {
        return p.ParameterType.IsArray && p.IsDefined(typeof(ParamArrayAttribute), false);
    }

    private static object DefaultFor(ParameterInfo p)
    {
        Type pt = p.ParameterType;
        if (pt.IsByRef) pt = pt.GetElementType();
        object d = p.DefaultValue;
        if (d == Missing.Value) return Type.Missing;
        if (d == null || d == DBNull.Value)
            return pt.IsValueType ? Activator.CreateInstance(pt) : null;
        return d;
    }

    private static bool TryBindNormal(ParameterInfo[] ps, object[] args, bool make, out object[] conv, out int cost)
    {
        conv = null; cost = 0;
        if (args.Length > ps.Length) return false;
        object[] result = make ? new object[ps.Length] : null;
        for (int i = 0; i < ps.Length; i++)
        {
            Type pt = ps[i].ParameterType;
            if (i < args.Length)
            {
                object c;
                int k = CoerceCore(args[i], pt, make, out c);
                if (k < 0) return false;
                if (make) result[i] = c;
                cost += k;
            }
            else if (ps[i].IsOptional)
            {
                if (make) result[i] = DefaultFor(ps[i]);
                cost += 2;
            }
            else if (pt.IsByRef && ps[i].IsOut)
            {
                cost += 3;   // out parameter — reflection supplies default(T)
            }
            else return false;
        }
        conv = result;
        return true;
    }

    private static bool TryBindExpanded(ParameterInfo[] ps, object[] args, bool make, out object[] conv, out int cost)
    {
        conv = null; cost = 0;
        int fixedCount = ps.Length - 1;
        Type elem = ps[fixedCount].ParameterType.GetElementType();
        object[] result = make ? new object[ps.Length] : null;
        for (int i = 0; i < fixedCount; i++)
        {
            object c;
            int k = CoerceCore(args[i], ps[i].ParameterType, make, out c);
            if (k < 0) return false;
            if (make) result[i] = c;
            cost += k;
        }
        int extra = args.Length - fixedCount;
        Array pack = make ? Array.CreateInstance(elem, extra) : null;
        for (int j = 0; j < extra; j++)
        {
            object c;
            int k = CoerceCore(args[fixedCount + j], elem, make, out c);
            if (k < 0) return false;
            if (make) pack.SetValue(c, j);
            cost += k;
        }
        if (make) result[fixedCount] = pack;
        conv = result;
        return true;
    }

    // ── Generic method inference (LINQ etc.) ──────────────────────────────

    private static MethodInfo InferGeneric(MethodInfo def, object[] args)
    {
        Type[] gargs = def.GetGenericArguments();
        Dictionary<Type, Type> map = new Dictionary<Type, Type>();
        ParameterInfo[] ps = def.GetParameters();
        bool anyCallable = false;

        for (int i = 0; i < ps.Length && i < args.Length; i++)
        {
            if (args[i] == null) continue;
            Type at = args[i].GetType();
            if (at.IsCOMObject) anyCallable = true;
            Unify(ps[i].ParameterType, at, map);
        }

        Type[] resolved = new Type[gargs.Length];
        for (int i = 0; i < gargs.Length; i++)
        {
            Type r;
            if (map.TryGetValue(gargs[i], out r)) resolved[i] = r;
            else if (anyCallable) resolved[i] = typeof(object);   // e.g. Select<TSource,TResult>: TResult from an AHK callback
            else return null;
        }
        try { return def.MakeGenericMethod(resolved); }
        catch (ArgumentException) { return null; }
    }

    private static void Unify(Type p, Type a, Dictionary<Type, Type> map)
    {
        if (p.IsByRef) p = p.GetElementType();
        if (p.IsGenericParameter)
        {
            if (!map.ContainsKey(p)) map[p] = a;
            return;
        }
        if (p.IsArray)
        {
            if (a.IsArray) Unify(p.GetElementType(), a.GetElementType(), map);
            return;
        }
        if (p.IsGenericType && p.ContainsGenericParameters)
        {
            Type pdef = p.GetGenericTypeDefinition();
            Type match = FindGenericMatch(a, pdef);
            if (match == null) return;
            Type[] pa = p.GetGenericArguments();
            Type[] ma = match.GetGenericArguments();
            for (int i = 0; i < pa.Length && i < ma.Length; i++)
                Unify(pa[i], ma[i], map);
        }
    }

    private static Type FindGenericMatch(Type a, Type genericDef)
    {
        if (a.IsGenericType && a.GetGenericTypeDefinition() == genericDef) return a;
        foreach (Type itf in a.GetInterfaces())
            if (itf.IsGenericType && itf.GetGenericTypeDefinition() == genericDef) return itf;
        for (Type b = a.BaseType; b != null; b = b.BaseType)
            if (b.IsGenericType && b.GetGenericTypeDefinition() == genericDef) return b;
        return null;
    }

    // ── Argument coercion / cost model ────────────────────────────────────
    // Returns a cost >= 0 when arg can be passed to 'to', or -1 when it cannot.
    // make == false: score only (no conversion is built, nothing throws).
    // make == true : conv receives the value to pass.

    public static int Coerce(object arg, Type to, out object conv)
    {
        return CoerceCore(arg, to, true, out conv);
    }

    private static readonly string[] AhkDateFormats = { "yyyyMMddHHmmss", "yyyyMMddHHmm", "yyyyMMddHH", "yyyyMMdd", "yyyyMM", "yyyy" };

    private static readonly ConcurrentDictionary<Type, HashSet<string>> _enumNames =
        new ConcurrentDictionary<Type, HashSet<string>>();
    private static readonly ConcurrentDictionary<Type, TypeConverter> _converters =
        new ConcurrentDictionary<Type, TypeConverter>();

    private static bool EnumNameOk(Type enumType, string s)
    {
        HashSet<string> names = _enumNames.GetOrAdd(enumType, delegate(Type t)
        {
            return new HashSet<string>(Enum.GetNames(t), StringComparer.OrdinalIgnoreCase);
        });
        foreach (string part in s.Split(','))       // flags: "Read, Write"
        {
            string p = part.Trim();
            long dummy;
            if (!names.Contains(p) && !long.TryParse(p, NumberStyles.Integer, CultureInfo.InvariantCulture, out dummy))
                return false;
        }
        return s.Trim().Length > 0;
    }

    private static TypeConverter ConverterFor(Type t)
    {
        return _converters.GetOrAdd(t, delegate(Type x) { return TypeDescriptor.GetConverter(x); });
    }

    private static int CoerceCore(object arg, Type to, bool make, out object conv)
    {
        conv = arg;
        bool byRef = to.IsByRef;
        if (byRef) to = to.GetElementType();

        // AHK passes VT_NULL (DBNull) for an &var argument: an out/ref slot the callee fills in
        if (arg is DBNull)
        {
            if (byRef)
            {
                if (make) conv = (to.IsValueType && Nullable.GetUnderlyingType(to) == null) ? Activator.CreateInstance(to) : null;
                return 0;
            }
            arg = null;
            conv = null;
        }

        int extra = 0;
        Type underlying = Nullable.GetUnderlyingType(to);
        if (underlying != null)
        {
            if (arg == null) { conv = null; return 1; }
            to = underlying;
            extra = 1;
        }

        if (arg == null)
        {
            if (!to.IsValueType) return 1 + extra;
            if (make) conv = Activator.CreateInstance(to);
            return 25;
        }

        Type at = arg.GetType();
        if (at == to) return extra;

        string s = arg as string;

        if (to == typeof(object))
        {
            if (make) conv = NormalizeForObject(arg);
            return 12 + extra;
        }
        if (to.IsAssignableFrom(at)) return 1 + extra;

        if (s != null) _valueDependent = true;   // every branch below inspects the string

        // AHK has no null: "" means null for reference parameters
        if (s != null && s.Length == 0 && !to.IsValueType && to != typeof(string))
        {
            conv = null;
            return 10;
        }

        if (IsNumeric(at) && IsNumeric(to))
            return NumericCost(arg, at, to, make, out conv, extra);

        if (to == typeof(IntPtr) && IsIntegral(at)) { if (make) conv = new IntPtr(Convert.ToInt64(arg)); return 6 + extra; }
        if (to == typeof(UIntPtr) && IsIntegral(at)) { if (make) conv = new UIntPtr(Convert.ToUInt64(arg)); return 6 + extra; }

        if (to.IsEnum)
        {
            if (s != null)
            {
                if (!EnumNameOk(to, s)) return -1;
                if (make) conv = Enum.Parse(to, s, true);
                return 5 + extra;
            }
            if (IsIntegral(at))
            {
                if (make) conv = Enum.ToObject(to, arg);
                return 4 + extra;
            }
            return -1;
        }

        if (to == typeof(string))
        {
            if (arg is IConvertible)
            {
                if (make) conv = Convert.ToString(arg, CultureInfo.InvariantCulture);
                return 30 + extra;
            }
            return -1;
        }

        if (to == typeof(bool))
        {
            _valueDependent = true;
            if (IsIntegral(at) || at == typeof(double))
            {
                double d = Convert.ToDouble(arg, CultureInfo.InvariantCulture);
                if (d == 0 || d == 1) { if (make) conv = d == 1; return 6 + extra; }
                return -1;
            }
            bool b;
            if (s != null && bool.TryParse(s, out b)) { if (make) conv = b; return 15 + extra; }
            return -1;
        }

        if (to == typeof(char))
        {
            _valueDependent = true;
            if (s != null && s.Length == 1) { if (make) conv = s[0]; return 8 + extra; }
            if (IsIntegral(at))
            {
                long v = Convert.ToInt64(arg);
                if (v >= 0 && v <= char.MaxValue) { if (make) conv = (char)v; return 9 + extra; }
            }
            return -1;
        }

        if (s != null)
        {
            if (IsNumeric(to))
            {
                object parsed;
                if (!TryParseNumber(s, to, out parsed)) return -1;
                if (make) conv = parsed;
                return 15 + extra;
            }
            if (to == typeof(DateTime))
            {
                // AHK timestamps: YYYY, YYYYMM, YYYYMMDD, YYYYMMDDHH24, YYYYMMDDHH24MI, YYYYMMDDHH24MISS (A_Now)
                DateTime dt;
                if (DateTime.TryParseExact(s, AhkDateFormats, CultureInfo.InvariantCulture, DateTimeStyles.None, out dt))
                {
                    if (make) conv = dt;
                    return 12 + extra;
                }
            }
            if (to == typeof(Type))
            {
                Type rt = TypeResolver.Resolve(s);
                if (rt == null) return -1;
                if (make) conv = rt;
                return 16;
            }
            TypeConverter tc = ConverterFor(to);
            if (tc != null && tc.CanConvertFrom(typeof(string)))
            {
                if (make) conv = tc.ConvertFromInvariantString(s);   // may throw: reported as the call error
                return 16 + extra;
            }
            return -1;
        }

        // Arrays from AHK: object[] (mixed), long[] / double[] (bulk-packed numbers), string[] ...
        IList list = arg as IList;
        if (list != null && at.IsArray && at.GetArrayRank() == 1)
        {
            _valueDependent = true;
            return CoerceArray(list, to, make, out conv, extra);
        }

        object[,] od = arg as object[,];
        if (od != null) { _valueDependent = true; return CoerceDict(od, to, make, out conv, extra); }

        if (at.IsCOMObject && typeof(Delegate).IsAssignableFrom(to))
        {
            if (!make) return 5 + extra;
            Delegate d = AhkCallback.MakeDelegate(to, arg);
            if (d == null) return -1;
            conv = d;
            return 5 + extra;
        }

        return -1;
    }

    // Values passed to a plain 'object' parameter: AHK Map → Dictionary so that
    // serializers and generic APIs see something sensible.
    private static object NormalizeForObject(object arg)
    {
        object[,] od = arg as object[,];
        if (od != null) return ToDictionary(od);

        object[] oa = arg as object[];
        if (oa != null)
        {
            bool needs = false;
            for (int i = 0; i < oa.Length; i++)
                if (oa[i] is object[,] || oa[i] is object[]) { needs = true; break; }
            if (!needs) return oa;
            object[] copy = new object[oa.Length];
            for (int i = 0; i < oa.Length; i++) copy[i] = NormalizeForObject(oa[i]);
            return copy;
        }
        return arg;
    }

    public static object ToDictionary(object[,] src)
    {
        int n = src.GetLength(0);
        int l0 = src.GetLowerBound(0), l1 = src.GetLowerBound(1);
        bool allStrings = true;
        for (int i = 0; i < n; i++)
            if (!(src[l0 + i, l1] is string)) { allStrings = false; break; }

        if (allStrings)
        {
            Dictionary<string, object> d = new Dictionary<string, object>();
            for (int i = 0; i < n; i++)
                d[(string)src[l0 + i, l1]] = NormalizeForObject(src[l0 + i, l1 + 1]);
            return d;
        }
        Dictionary<object, object> d2 = new Dictionary<object, object>();
        for (int i = 0; i < n; i++)
            d2[src[l0 + i, l1]] = NormalizeForObject(src[l0 + i, l1 + 1]);
        return d2;
    }

    // How many elements of a big array the scoring phase looks at (materialisation converts them all)
    private const int ScoreSample = 16;

    private static int CoerceArray(IList src, Type to, bool make, out object conv, int extra)
    {
        conv = null;
        Type elem = null;
        if (to.IsArray && to.GetArrayRank() == 1)
            elem = to.GetElementType();
        else if (to.IsGenericType)
        {
            Type[] ga = to.GetGenericArguments();
            if (ga.Length == 1 && to.IsAssignableFrom(typeof(List<>).MakeGenericType(ga[0])))
                elem = ga[0];
        }
        if (elem == null) return -1;

        int n = src.Count;
        int worst = 0;
        if (!make)
        {
            int m = Math.Min(n, ScoreSample);
            for (int i = 0; i < m; i++)
            {
                object c;
                int k = CoerceCore(src[i], elem, false, out c);
                if (k < 0) return -1;
                if (k > worst) worst = k;
            }
            return 10 + worst + extra;
        }

        Array arr = to.IsArray ? Array.CreateInstance(elem, n) : null;
        IList list = arr != null ? null : (IList)Activator.CreateInstance(typeof(List<>).MakeGenericType(elem));
        for (int i = 0; i < n; i++)
        {
            object c;
            int k = CoerceCore(src[i], elem, true, out c);
            if (k < 0)
                throw new InvalidCastException("Array element " + i + " (" + (src[i] == null ? "null" : src[i].GetType().Name)
                    + ") cannot be converted to " + elem.Name);
            if (arr != null) arr.SetValue(c, i); else list.Add(c);
        }
        conv = arr != null ? (object)arr : list;
        return 10 + worst + extra;
    }

    private static int CoerceDict(object[,] src, Type to, bool make, out object conv, int extra)
    {
        conv = null;
        Type kt = typeof(object), vt = typeof(object);
        IDictionary dict = null;
        if (to.IsGenericType && to.GetGenericArguments().Length == 2)
        {
            Type[] ga = to.GetGenericArguments();
            Type dt = typeof(Dictionary<,>).MakeGenericType(ga);
            if (!to.IsAssignableFrom(dt)) return -1;
            kt = ga[0]; vt = ga[1];
            if (make) dict = (IDictionary)Activator.CreateInstance(dt);
        }
        else if (to == typeof(IDictionary) || to == typeof(Hashtable))
        {
            if (make) dict = new Hashtable();
        }
        else
            return -1;

        int n = src.GetLength(0);
        int l0 = src.GetLowerBound(0), l1 = src.GetLowerBound(1);
        int limit = make ? n : Math.Min(n, ScoreSample);
        int worst = 0;
        for (int i = 0; i < limit; i++)
        {
            object k, v;
            int ck = CoerceCore(src[l0 + i, l1], kt, make, out k);
            int cv = CoerceCore(src[l0 + i, l1 + 1], vt, make, out v);
            if (ck < 0 || cv < 0) return -1;
            worst = Math.Max(worst, Math.Max(ck, cv));
            if (make) dict[k] = v;
        }
        conv = dict;
        return 12 + worst + extra;
    }

    // ── Numeric conversions ───────────────────────────────────────────────

    private static bool IsNumeric(Type t)
    {
        if (t.IsEnum) return false;
        switch (Type.GetTypeCode(t))
        {
            case TypeCode.Byte: case TypeCode.SByte: case TypeCode.Int16: case TypeCode.UInt16:
            case TypeCode.Int32: case TypeCode.UInt32: case TypeCode.Int64: case TypeCode.UInt64:
            case TypeCode.Single: case TypeCode.Double: case TypeCode.Decimal:
                return true;
        }
        return false;
    }

    private static bool IsIntegral(Type t)
    {
        if (t.IsEnum) return false;
        switch (Type.GetTypeCode(t))
        {
            case TypeCode.Byte: case TypeCode.SByte: case TypeCode.Int16: case TypeCode.UInt16:
            case TypeCode.Int32: case TypeCode.UInt32: case TypeCode.Int64: case TypeCode.UInt64:
                return true;
        }
        return false;
    }

    private static readonly Dictionary<TypeCode, TypeCode[]> _implicit = new Dictionary<TypeCode, TypeCode[]>
    {
        { TypeCode.SByte,  new[] { TypeCode.Int16, TypeCode.Int32, TypeCode.Int64, TypeCode.Single, TypeCode.Double, TypeCode.Decimal } },
        { TypeCode.Byte,   new[] { TypeCode.Int16, TypeCode.UInt16, TypeCode.Int32, TypeCode.UInt32, TypeCode.Int64, TypeCode.UInt64, TypeCode.Single, TypeCode.Double, TypeCode.Decimal } },
        { TypeCode.Int16,  new[] { TypeCode.Int32, TypeCode.Int64, TypeCode.Single, TypeCode.Double, TypeCode.Decimal } },
        { TypeCode.UInt16, new[] { TypeCode.Int32, TypeCode.UInt32, TypeCode.Int64, TypeCode.UInt64, TypeCode.Single, TypeCode.Double, TypeCode.Decimal } },
        { TypeCode.Int32,  new[] { TypeCode.Int64, TypeCode.Single, TypeCode.Double, TypeCode.Decimal } },
        { TypeCode.UInt32, new[] { TypeCode.Int64, TypeCode.UInt64, TypeCode.Single, TypeCode.Double, TypeCode.Decimal } },
        { TypeCode.Int64,  new[] { TypeCode.Single, TypeCode.Double, TypeCode.Decimal } },
        { TypeCode.UInt64, new[] { TypeCode.Single, TypeCode.Double, TypeCode.Decimal } },
        { TypeCode.Single, new[] { TypeCode.Double } }
    };

    private static bool IntegralRange(TypeCode tc, out double min, out double max)
    {
        switch (tc)
        {
            case TypeCode.Byte:   min = byte.MinValue;   max = byte.MaxValue;   return true;
            case TypeCode.SByte:  min = sbyte.MinValue;  max = sbyte.MaxValue;  return true;
            case TypeCode.Int16:  min = short.MinValue;  max = short.MaxValue;  return true;
            case TypeCode.UInt16: min = ushort.MinValue; max = ushort.MaxValue; return true;
            case TypeCode.Int32:  min = int.MinValue;    max = int.MaxValue;    return true;
            case TypeCode.UInt32: min = uint.MinValue;   max = uint.MaxValue;   return true;
            case TypeCode.Int64:  min = long.MinValue;   max = long.MaxValue;   return true;
            case TypeCode.UInt64: min = 0;               max = ulong.MaxValue;  return true;
        }
        min = max = 0;
        return false;
    }

    // Does this numeric value fit the integral target without loss? (no exceptions)
    private static bool FitsIntegral(object arg, TypeCode target)
    {
        double lo, hi;
        if (!IntegralRange(target, out lo, out hi)) return false;
        double d = Convert.ToDouble(arg, CultureInfo.InvariantCulture);
        if (double.IsNaN(d) || double.IsInfinity(d) || d != Math.Floor(d)) return false;   // never truncate silently
        return d >= lo && d <= hi;
    }

    private static bool TryParseNumber(string s, Type to, out object result)
    {
        result = null;
        TypeCode tc = Type.GetTypeCode(to);
        CultureInfo inv = CultureInfo.InvariantCulture;
        switch (tc)
        {
            case TypeCode.Decimal:
                decimal m;
                if (!decimal.TryParse(s, NumberStyles.Float, inv, out m)) return false;
                result = m; return true;
            case TypeCode.Double:
                double d;
                if (!double.TryParse(s, NumberStyles.Float, inv, out d)) return false;
                result = d; return true;
            case TypeCode.Single:
                double f;
                if (!double.TryParse(s, NumberStyles.Float, inv, out f)) return false;
                result = (float)f; return true;
        }
        long l;
        if (!long.TryParse(s, NumberStyles.Integer, inv, out l)) return false;
        double lo, hi;
        if (!IntegralRange(tc, out lo, out hi) || l < lo || l > hi) return false;
        result = Convert.ChangeType(l, to, inv);
        return true;
    }

    private static int NumericCost(object arg, Type from, Type to, bool make, out object conv, int extra)
    {
        conv = arg;
        TypeCode fc = Type.GetTypeCode(from), tc = Type.GetTypeCode(to);

        TypeCode[] widen;
        if (_implicit.TryGetValue(fc, out widen))
        {
            int idx = Array.IndexOf(widen, tc);
            if (idx >= 0)
            {
                if (make) conv = Convert.ChangeType(arg, to, CultureInfo.InvariantCulture);
                return 1 + idx + extra;
            }
        }

        _valueDependent = true;   // narrowing / float→int: depends on the value
        bool fromFloat = fc == TypeCode.Double || fc == TypeCode.Single;
        if (fromFloat && IsIntegral(to))
        {
            if (!FitsIntegral(arg, tc)) return -1;
            if (make) conv = Convert.ChangeType(Convert.ToDouble(arg, CultureInfo.InvariantCulture), to, CultureInfo.InvariantCulture);
            return 9 + extra;
        }
        if (fc == TypeCode.Double && tc == TypeCode.Single)
        {
            if (make) conv = (float)(double)arg;
            return 8 + extra;
        }
        if (fromFloat && tc == TypeCode.Decimal)
        {
            double d = Convert.ToDouble(arg, CultureInfo.InvariantCulture);
            if (Math.Abs(d) > 7.9e28 || double.IsNaN(d)) return -1;
            if (make) conv = Convert.ToDecimal(d);
            return 6 + extra;
        }
        // integral narrowing / sign change: allowed only if the value fits
        if (IsIntegral(to) && IsIntegral(from))
        {
            if (!FitsIntegral(arg, tc)) return -1;
            if (make) conv = Convert.ChangeType(arg, to, CultureInfo.InvariantCulture);
            return 8 + extra;
        }
        // decimal → anything else
        try
        {
            if (make) conv = Convert.ChangeType(arg, to, CultureInfo.InvariantCulture);
            return 10 + extra;
        }
        catch (OverflowException) { return -1; }
        catch (InvalidCastException) { return -1; }
    }

    // ── Explain (CS.Explain): show how every overload scores for a call ────

    public static string Explain(string what, MethodBase[] candidates, object[] args)
    {
        StringBuilder sb = new StringBuilder();
        sb.Append(what).Append("(").Append(DescribeArgs(args)).Append(")");
        if (candidates.Length == 0) return sb.Append("\n  no such method").ToString();

        int bestCost = int.MaxValue;
        MethodBase bestM = null;
        int[] costs = new int[candidates.Length];
        for (int i = 0; i < candidates.Length; i++)
        {
            BoundCall b = TryBind(candidates[i], args, false);
            costs[i] = b == null ? -1 : b.Cost;
            if (b != null && b.Cost < bestCost) { bestCost = b.Cost; bestM = candidates[i]; }
        }
        for (int i = 0; i < candidates.Length; i++)
        {
            sb.Append("\n  ").Append(candidates[i] == bestM ? "=> " : "   ")
              .Append(costs[i] < 0 ? "rejected  " : ("cost " + costs[i].ToString().PadLeft(3) + "  "))
              .Append(Signature(candidates[i]));
        }
        if (bestM == null) sb.Append("\n  (no overload accepts these arguments)");
        return sb.ToString();
    }

    private static string Signature(MethodBase m)
    {
        StringBuilder sb = new StringBuilder();
        MethodInfo mi = m as MethodInfo;
        if (mi != null) sb.Append(mi.ReturnType.Name).Append(" ");
        sb.Append(m.Name).Append("(");
        ParameterInfo[] ps = m.GetParameters();
        for (int i = 0; i < ps.Length; i++)
        {
            if (i > 0) sb.Append(", ");
            sb.Append(ps[i].ParameterType.Name).Append(" ").Append(ps[i].Name);
        }
        return sb.Append(")").ToString();
    }

    // ── Error text ────────────────────────────────────────────────────────

    public static string DescribeArgs(object[] args)
    {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < args.Length; i++)
        {
            if (i > 0) sb.Append(", ");
            sb.Append(args[i] == null ? "null" : args[i].GetType().Name);
        }
        return sb.ToString();
    }

    public static string DescribeCandidates(IEnumerable<MethodBase> candidates)
    {
        StringBuilder sb = new StringBuilder();
        int n = 0;
        foreach (MethodBase m in candidates)
        {
            if (n++ >= 8) { sb.Append("\n    ..."); break; }
            sb.Append("\n    ").Append(m.Name).Append("(");
            ParameterInfo[] ps = m.GetParameters();
            for (int i = 0; i < ps.Length; i++)
            {
                if (i > 0) sb.Append(", ");
                sb.Append(ps[i].ParameterType.Name).Append(" ").Append(ps[i].Name);
            }
            sb.Append(")");
        }
        return sb.ToString();
    }
}
