// ═══════════════════════════════════════════════════════════════════════════════
// AHK# Bridge — FastParallel: CS.Fast.Map / Filter / Reduce
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
// Fast Parallel — CS.Fast.Map / Filter / Reduce
// ─────────────────────────────────────────────────────────────────────────────
// The lambda body is compiled ONCE into a delegate (no per-element reflection).
// 'x' (and 'acc' for Reduce) are typed dynamic, so "x * 2" and "acc + x" just work.
// AHK integers are widened to Int64 first so sums don't overflow at 2^31.
// Map and Filter run on all cores (order preserved); Reduce is sequential because
// an arbitrary combine function is not associative.

internal static class FastParallel
{
    private static readonly ConcurrentDictionary<string, Delegate> _compiled =
        new ConcurrentDictionary<string, Delegate>();

    private static T Compile<T>(string method, string signature, string lambdaBody, string references) where T : class
    {
        string key = method + "|" + lambdaBody + "|" + references;
        return (T)(object)_compiled.GetOrAdd(key, delegate(string k)
        {
            string code = "using System; using System.Linq; using System.Collections.Generic;\n"
                + "public static class __FastLambda {\n"
                + "    public static " + signature + " { return " + lambdaBody + "; }\n}";
            string id = RuntimeCompiler.CompileModule(code, references ?? "");
            Type t = RuntimeCompiler.FindModuleType(id, "__FastLambda");
            return Delegate.CreateDelegate(typeof(T), t.GetMethod(method));
        });
    }

    private static object Widen(object v)
    {
        if (v is int) return (long)(int)v;
        if (v is short) return (long)(short)v;
        if (v is ushort) return (long)(ushort)v;
        if (v is byte) return (long)(byte)v;
        if (v is sbyte) return (long)(sbyte)v;
        if (v is uint) return (long)(uint)v;
        return v;
    }

    private static object[] WidenAll(object[] input)
    {
        object[] r = new object[input.Length];
        for (int i = 0; i < input.Length; i++) r[i] = Widen(input[i]);
        return r;
    }

    private static Exception Unwrap(AggregateException ae)
    {
        Exception inner = ae.Flatten().InnerExceptions[0];
        return inner;
    }

    public static object Map(object[] input, string lambdaBody, string references)
    {
        Func<object, object> f = Compile<Func<object, object>>("Apply", "object Apply(dynamic x)", lambdaBody, references);
        try
        {
            return WidenAll(input).AsParallel().AsOrdered()
                .Select(x => MarshalEngine.PackResult(f(x)))
                .ToArray();
        }
        catch (AggregateException ae) { throw Unwrap(ae); }
    }

    public static object Filter(object[] input, string lambdaBody, string references)
    {
        Func<object, bool> f = Compile<Func<object, bool>>("Test", "bool Test(dynamic x)", lambdaBody, references);
        try
        {
            return WidenAll(input).AsParallel().AsOrdered()
                .Where(x => f(x))
                .Select(x => MarshalEngine.PackResult(x))
                .ToArray();
        }
        catch (AggregateException ae) { throw Unwrap(ae); }
    }

    public static object Reduce(object[] input, string lambdaBody, object initial, string references)
    {
        Func<object, object, object> f = Compile<Func<object, object, object>>(
            "Combine", "object Combine(dynamic acc, dynamic x)", lambdaBody, references);
        object acc = Widen(initial);
        foreach (object x in WidenAll(input))
            acc = f(acc, x);
        return MarshalEngine.PackResult(acc);
    }
}

