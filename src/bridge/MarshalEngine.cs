// ═══════════════════════════════════════════════════════════════════════════════
// AHK# Bridge — MarshalEngine: CLR ↔ SafeArray/COM value conversion
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
// Marshal Engine — CLR ↔ SafeArray/COM auto-marshalling
// ─────────────────────────────────────────────────────────────────────────────

internal static class MarshalEngine
{
    /// <summary>
    /// Unpacks COM VARIANT/SafeArray args from AHK into a flat object[].
    /// AHK passes params as either a single value, a SafeArray, or null.
    /// </summary>
    public static object Unbox(object o)
    {
        ValueBox b = o as ValueBox;
        return b != null ? b.Value : o;
    }

    public static object[] UnboxAll(object[] r)
    {
        for (int i = 0; i < r.Length; i++)
            if (r[i] is ValueBox) r[i] = ((ValueBox)r[i]).Value;
        return r;
    }

    public static object[] UnpackArgs(object args)
    {
        object[] r = UnpackArgsRaw(args);
        for (int i = 0; i < r.Length; i++)
            if (r[i] is ValueBox) r[i] = ((ValueBox)r[i]).Value;
        return r;
    }

    private static object[] UnpackArgsRaw(object args)
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

        // AHK integers are signed 64-bit: UInt64 beyond Int64.MaxValue becomes a digit string,
        // pointers become plain integers, chars become 1-char strings.
        if (value is ulong)
        {
            ulong u = (ulong)value;
            return u > long.MaxValue ? (object)u.ToString(CultureInfo.InvariantCulture) : (object)(long)u;
        }
        if (value is uint) return (long)(uint)value;
        if (value is IntPtr) return ((IntPtr)value).ToInt64();
        if (value is UIntPtr) return (long)((UIntPtr)value).ToUInt64();
        if (value is char) return value.ToString();

        // decimal has no AHK equivalent: keep full precision as a numeric string
        if (value is decimal)
            return ((decimal)value).ToString(CultureInfo.InvariantCulture);

        // Primitives and strings pass through
        if (value is DateTime)   // AHK timestamp (YYYYMMDDHH24MISS): locale-independent, works with FormatTime / DateAdd
            return ((DateTime)value).ToString("yyyyMMddHHmmss", CultureInfo.InvariantCulture);

        if (t.IsPrimitive || value is string)
            return value;

        // Arrays stay REFERENCES (a SafeArray would be a by-value copy: arr[i] := v and FromBuffer
        // would change a throwaway copy, and every round trip would cost O(n)). AHK reads them with
        // ToAHK() / ToBuffer() / arr[i] / for-in; passing the proxy back hands .NET the same array.
        if (value is Array)
            return new ValueBox(value);

        // Value types without IDispatch (Guid, TimeSpan, etc.) can't survive
        // COM round-trips — convert to string for safe AHK consumption
        // Enums, Guid, TimeSpan and DateTimeOffset become strings AHK can pass straight back (parsed by the binder).
        // Any OTHER struct (CancellationToken, Point, Rectangle, Color, KeyValuePair ...) stays a real object behind a
        // ValueBox, so it can be passed back to .NET and its members read: cts.Token, Task.Delay(500, cts.Token).
        if (t.IsEnum || value is Guid || value is TimeSpan || value is DateTimeOffset)
            return value.ToString();
        if (t.IsValueType)
            return new ValueBox(value);

        // For complex objects: pass the object reference directly.
        // AHK's CSProxy wrapper will handle member access via InvokeMember/GetProperty.
        return value;
    }

    // Element types that marshal as a flat SafeArray AHK can read with NumGet/StrGet
    // (no UInt64/decimal/char/bool: AHK has no matching native type).
    private static bool IsBulkType(Type t)
    {
        if (t.IsEnum) return false;
        switch (Type.GetTypeCode(t))
        {
            case TypeCode.Byte: case TypeCode.SByte: case TypeCode.Int16: case TypeCode.UInt16:
            case TypeCode.Int32: case TypeCode.UInt32: case TypeCode.Int64:
            case TypeCode.Single: case TypeCode.Double: case TypeCode.String:
                return true;
        }
        return false;
    }

    private static Type SequenceElementType(Type t)
    {
        if (t.IsGenericType && t.GetGenericTypeDefinition() == typeof(IEnumerable<>))
            return t.GetGenericArguments()[0];
        foreach (Type itf in t.GetInterfaces())
            if (itf.IsGenericType && itf.GetGenericTypeDefinition() == typeof(IEnumerable<>))
                return itf.GetGenericArguments()[0];
        return null;
    }

    /// <summary>
    /// Deep-converts a CLR collection to a SafeArray for AHK native unwrapping.
    /// Called explicitly by user when they want AHK-native arrays.
    /// </summary>
    public static object ToSafeArray(object clrObject)
    {
        if (clrObject == null) return null;

        // strings enumerate as chars and byte[] is binary data: leave both alone
        if (clrObject is string || clrObject is byte[]) return clrObject;

        // Homogeneous numbers / strings travel as ONE typed SafeArray (int[], double[], string[] ...)
        // which AHK reads straight out of memory — no per-element COM calls, no boxing.
        Array direct = clrObject as Array;
        if (direct != null && direct.Rank == 1 && IsBulkType(direct.GetType().GetElementType()))
            return direct;
        if (!(clrObject is IDictionary))
        {
            Type elemT = SequenceElementType(clrObject.GetType());
            if (elemT != null && IsBulkType(elemT))
            {
                ICollection col = clrObject as ICollection;
                if (col != null)
                {
                    Array typed = Array.CreateInstance(elemT, col.Count);
                    col.CopyTo(typed, 0);
                    return typed;
                }
                return typeof(Enumerable).GetMethod("ToArray").MakeGenericMethod(elemT)
                    .Invoke(null, new object[] { clrObject });
            }
        }

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

