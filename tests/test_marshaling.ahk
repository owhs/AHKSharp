#Include harness.ahk

; ── AHK → .NET ────────────────────────────────────────────────────────────────
Test("Integer array → long[] (bulk)", () => Eq(CS.System.Linq.Enumerable.Sum([1, 2, 3, 4]), 10))
Test("Float array → double[] (bulk)", () => Near(CS.System.Linq.Enumerable.Sum([1.5, 2.5, 3]), 7))
Test("empty Array", () => Eq(CS.System.Linq.Enumerable.Count([]), 0))
Test("String array round trip (one join + one split)", () => Eq(CS.System.String.Join("|", ["a", "bb", "", "dddd"]), "a|bb||dddd"))
Test("Unicode strings survive", () => (
    u := CS.System.String.Join("|", ["héllo", "日本"]), Eq(StrLen(u), 8), Eq(Ord(SubStr(u, 7, 1)), 26085)))
Test("mixed array → object[]", () => Eq(CS.System.String.Join("|", ["a", 2, 3.5]), "a|2|3.5"))
Test("nested arrays", () => Eq(CS.System.Linq.Enumerable.Count([[1, 2], [3]]), 2))
Test("Array → List<int> constructor", () => Eq(CS.System.Collections.Generic.List(CS.System.Int32)([4, 5, 6]).Count, 3))
Test("64-bit integers stay 64-bit", () => Eq(CS.System.Linq.Enumerable.Sum([9000000000, 1]), 9000000001))
Test("Map → Dictionary<string,int> parameter", () => (
    D := CS.System.Collections.Generic.Dictionary(CS.System.String, CS.System.Int32)(Map("x", 1, "y", 2)),
    Eq(D.Count, 2), Eq(D["y"], 2)))
Test("Buffer → byte[]", () => (
    b := Buffer(4, 0), NumPut("UInt", 0x64636261, b), Eq(CS.System.Text.Encoding.ASCII.GetString(b), "abcd")))

; ── .NET → AHK ────────────────────────────────────────────────────────────────
Test("List<int>.ToAHK() is a 1-based Array", () => (
    a := _list(CS.System.Int32, 3, 6, 9).ToAHK(), Eq(a.Length, 3), Eq(a[1], 3), Eq(a[3], 9)))
Test("List<double>.ToAHK()", () => (
    a := _list(CS.System.Double, 1.25, 2.5).ToAHK(), Near(a[1], 1.25), Near(a[2], 2.5)))
Test("List<string>.ToAHK() incl. empty + unicode", () => (
    a := _list(CS.System.String, "x", "", "日本").ToAHK(), Eq(a.Length, 3), Eq(a[2], ""), Eq(Ord(a[3]), 26085)))
Test("List<object> keeps mixed types (24-byte VARIANT cells)", () => (
    a := _list(CS.System.Object, "s", 5, 2.5).ToAHK(), Eq(a[1], "s"), Eq(a[2], 5), Near(a[3], 2.5)))
Test("byte[].ToAHK()", () => (
    a := CS.System.Text.Encoding.ASCII.GetBytes("ABC").ToAHK(), Eq(a[1], 65), Eq(a[3], 67)))
Test("lazy LINQ sequence ToAHK()", () => Eq(CS.System.Linq.Enumerable.Range(1, 5).ToAHK().Length, 5))
Test("Dictionary.ToAHK() is a Map", () => (
    D := CS.System.Collections.Generic.Dictionary(CS.System.String, CS.System.Int32)(),
    D.Add("a", 1), m := D.ToAHK(), Eq(Type(m), "Map"), Eq(m["a"], 1)))

; ── iteration ─────────────────────────────────────────────────────────────────
Test("for x in List<string>", () => Eq(_join(_list(CS.System.String, "Apple", "Banana")), "Apple;Banana;"))
Test("for i, x in List<string>", () => Eq(_pairs(_list(CS.System.String, "a", "b")), "1=a;2=b;"))
Test("for x in a lazy sequence", () => Eq(_join(CS.System.Linq.Enumerable.Range(1, 3)), "1;2;3;"))
Test("for k, v in Dictionary", () => (
    D := CS.System.Collections.Generic.Dictionary(CS.System.String, CS.System.Int32)(),
    D.Add("a", 1), Eq(_pairs(D), "a=1;")))

; ── arrays are REFERENCES ─────────────────────────────────────────────────────
Test("arr[i] := v changes the real .NET array", () => (
    a := CS.System.Array.CreateInstance(CS.System.Int32, 3), a[1] := 42, Eq(a.ToAHK()[2], 42)))
Test("Array.Sort sorts in place", () => (
    a := CS.System.Array.CreateInstance(CS.System.Int32, 3), a[0] := 9, a[1] := 2, a[2] := 5,
    CS.System.Array.Sort(a), Eq(a.ToAHK()[1], 2), Eq(a.ToAHK()[3], 9)))

; ── raw memory ────────────────────────────────────────────────────────────────
Test("ToBuffer: byte[] → Buffer (one memcpy)", () => (
    buf := CS.System.Text.Encoding.UTF8.GetBytes("héllo").ToBuffer(), Eq(buf.Size, 6), Eq(StrGet(buf, buf.Size, "UTF-8"), "héllo")))
Test("ToBuffer: int[] → Buffer", () => (
    ints := CS.System.Linq.Enumerable.ToArray(CS.System.Linq.Enumerable.Range(10, 5)), b := ints.ToBuffer(),
    Eq(b.Size, 20), Eq(NumGet(b, 0, "Int"), 10), Eq(NumGet(b, 16, "Int"), 14)))
Test("FromBuffer fills the .NET array in place", () => (
    t := CS.System.Array.CreateInstance(CS.System.Byte, 4), src := Buffer(4), NumPut("UInt", 0x04030201, src),
    t.FromBuffer(src), Eq(t.ToAHK()[1], 1), Eq(t.ToAHK()[4], 4)))
Test("IntPtr parameter takes buf.Ptr (zero copy)", () => (
    b := Buffer(8, 0), StrPut("hi", b, "UTF-16"),
    Eq(CS.System.Runtime.InteropServices.Marshal.PtrToStringUni(b.Ptr), "hi")))

; ── structs & object identity ─────────────────────────────────────────────────
Test("DateTime(...) stays an object", () => Eq(CS.System.DateTime(2020, 5, 17).ToString("yyyy-MM-dd"), "2020-05-17"))
Test("TimeSpan(...).TotalSeconds", () => Near(CS.System.TimeSpan(0, 0, 90).TotalSeconds, 90))
Test("proxy.ToString(fmt) calls the .NET overload", () => Eq(CS.System.DateTime(2021, 1, 2).ToString("dd/MM/yyyy"), "02/01/2021"))
Test("_Invoke reaches a name AHK# shadows", () => Eq(CS.System.Text.StringBuilder("hi")._Invoke("ToString"), "hi"))

_list(type, vals*) {
    L := CS.System.Collections.Generic.List(type)()
    for v in vals
        L.Add(v)
    return L
}

_pairs(seq) {
    s := ""
    for k, v in seq
        s .= k "=" v ";"
    return s
}

_join(seq) {
    s := ""
    for x in seq
        s .= x ";"
    return s
}

RunTests()
