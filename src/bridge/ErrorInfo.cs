// ═══════════════════════════════════════════════════════════════════════════════
// AHK# Bridge — ErrorInfo + MemberCache: typed exceptions and member lookup for AHK
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
// Error recorder — remembers the .NET exception that propagated to AHK, so the AHK
// side can expose its type, base types and stack trace (e.NetType, e.NetStack ...)
// ─────────────────────────────────────────────────────────────────────────────

internal static class ErrorInfo
{
    private static bool _installed;
    private static Exception _last;
    private static string _lastStack = "";

    public static void Install()
    {
        if (_installed) return;
        _installed = true;
        AppDomain.CurrentDomain.FirstChanceException += delegate(object sender, FirstChanceExceptionEventArgs e)
        {
            // Only exceptions raised on the AHK thread matter; the last one before control returns is the one AHK sees.
            if (Thread.CurrentThread.ManagedThreadId != AhkCallback.AhkThreadId) return;
            Exception ex = Unwrap(e.Exception);
            if (!object.ReferenceEquals(ex, _last))
            {
                _last = ex;
                try { _lastStack = new System.Diagnostics.StackTrace(1, true).ToString(); }   // frames at the real throw site
                catch { _lastStack = ""; }
            }
        };
    }

    private static Exception Unwrap(Exception ex)
    {
        while (ex != null && ex.InnerException != null && (ex is TargetInvocationException || (ex is AggregateException && ((AggregateException)ex).InnerExceptions.Count == 1)))
            ex = ex.InnerException;
        return ex;
    }

    public static object[] Describe()
    {
        Exception ex = _last;
        if (ex == null) return new object[] { "", "", 0, "", "" };
        StringBuilder bases = new StringBuilder();
        for (Type b = ex.GetType().BaseType; b != null && b != typeof(object); b = b.BaseType)
        {
            if (bases.Length > 0) bases.Append('|');
            bases.Append(b.FullName);
        }
        int hr = 0;
        try { hr = Marshal.GetHRForException(ex); } catch { }
        string stack = string.IsNullOrEmpty(ex.StackTrace) ? _lastStack : ex.StackTrace + "\n--- at the throw site:\n" + _lastStack;
        return new object[] { ex.GetType().FullName, stack ?? "", hr, bases.ToString(), ex.Message ?? "" };
    }
}

/// <summary>Cached "does this type have a public instance member called X" (case-insensitive).</summary>
internal static class MemberCache
{
    private struct Key : IEquatable<Key>
    {
        public Type T; public string Name;
        public bool Equals(Key o) { return T == o.T && string.Equals(Name, o.Name, StringComparison.OrdinalIgnoreCase); }
        public override bool Equals(object o) { return o is Key && Equals((Key)o); }
        public override int GetHashCode() { return T.GetHashCode() * 31 + StringComparer.OrdinalIgnoreCase.GetHashCode(Name ?? ""); }
    }

    private static readonly ConcurrentDictionary<Key, bool> _cache = new ConcurrentDictionary<Key, bool>();

    public static bool Has(Type t, string name)
    {
        Key k = new Key { T = t, Name = name };
        bool r;
        if (_cache.TryGetValue(k, out r)) return r;
        r = t.GetMember(name, BindingFlags.Public | BindingFlags.Instance | BindingFlags.IgnoreCase).Length > 0;
        _cache[k] = r;
        return r;
    }
}

