#Include harness.ahk

; A .NET class whose members collide with AHK# helper names (Type, On, Dispose ...)
class Thing extends _CSModule {
    static CSharp := "
    (
        public class Inner {
            public string Type { get { return `"dotnet-type`"; } }
            public string On(string e) { return `"on:`" + e; }
            public string Await(int n) { return `"await:`" + n; }
            public bool Disposed;
            public void Dispose() { Disposed = true; }
        }
        public class Thing {
            public static object Last;
            public static object Make() { Last = new Inner(); return Last; }
            public static object LastObject() { return Last; }
            public static bool LastDisposed() { return ((Inner)Last).Disposed; }
        }
    )"
}

; ── .NET members always win over AHK# helpers ─────────────────────────────────
Test("a .NET property named Type beats the AHK# Type helper", () => Eq(Thing.Make().Type, "dotnet-type"))
Test("a .NET method named On beats the AHK# On helper", () => Eq(Thing.Make().On("z"), "on:z"))
Test("a .NET method named Await beats the AHK# Await helper", () => Eq(Thing.Make().Await(3), "await:3"))
Test("Dispose reaches the .NET Dispose", () => (o := Thing.Make(), o.Dispose(), Eq(o.Disposed, 1)))
Test("helpers still work when .NET has no such member", () => (
    L := CS.System.Collections.Generic.List(CS.System.Int32)(), L.Add(7),
    Eq(L.ToAHK()[1], 7), Has(L.Type, "System.Collections.Generic.List"),
    Eq(L.Is("System.Collections.IEnumerable"), 1)))
Test("CS.ToAHK / CS.ToBuffer never clash", () => (
    L := CS.System.Collections.Generic.List(CS.System.Int32)(), L.Add(1), Eq(CS.ToAHK(L)[1], 1),
    Eq(CS.ToBuffer(CS.System.Text.Encoding.ASCII.GetBytes("AB")).Size, 2)))
Test("_Invoke forces the .NET call", () => Eq(Thing.Make()._Invoke("On", "q"), "on:q"))

; ── identity and lifetime ─────────────────────────────────────────────────────
Test("CS.Same: two proxies of one object", () => (a := Thing.Make(), b := Thing.LastObject(), IsTrue(CS.Same(a, b), "same object"), IsTrue(a != b, "distinct AHK proxies")))
Test("CS.Same: different objects", () => IsTrue(!CS.Same(Thing.Make(), Thing.Make()), "different"))
Test("CS.Using disposes even when the function throws", () => (
    o := Thing.Make(), Throws(() => CS.Using(o, _boom), "inner"), Eq(o.Disposed, 1)))
Test("CS.Using returns the function's value and disposes", () => (
    r := CS.Using(Thing.Make(), (x) => 5), Eq(r, 5), IsTrue(Thing.LastDisposed(), "disposed")))
Test("AutoDispose disposes when the last AHK reference goes away", () => _autoDispose())

_boom(x) {
    throw Error("inner")
}

_autoDispose() {
    x := Thing.Make().AutoDispose()
    IsTrue(!Thing.LastDisposed(), "not disposed while referenced")
    x := ""
    IsTrue(Thing.LastDisposed(), "disposed after the proxy was released")
}

; ── typed .NET exceptions on AHK errors ───────────────────────────────────────
Test("e.NetType is the .NET exception type", () => (
    e := _catch(() => CS.System.Int32.Parse("abc")), Eq(e.NetType, "System.FormatException")))
Test("CS.ErrorIs matches the type, short names and base classes", () => (
    e := _catch(() => CS.System.IO.File.ReadAllText("C:\definitely\not\here.txt")),
    IsTrue(CS.ErrorIs(e, "System.IO.DirectoryNotFoundException"), "exact"),
    IsTrue(CS.ErrorIs(e, "DirectoryNotFoundException"), "short name"),
    IsTrue(CS.ErrorIs(e, "IOException"), "base class"),
    IsTrue(CS.ErrorIs(e, "SystemException"), "further base"),
    IsTrue(!CS.ErrorIs(e, "FormatException"), "unrelated")))
Test("e.NetStack carries .NET frames", () => (
    e := _catch(() => CS.System.Int32.Parse("abc")), Has(e.NetStack, "System.Number")))
Test("e.NetHResult is the .NET HRESULT", () => (
    e := _catch(() => CS.System.Int32.Parse("abc")), IsTrue(e.NetHResult != 0, "hresult")))
Test("AHK-side errors carry no .NET details", () => (
    e := _catch(() => CS.System.Math.Powwww(1)), IsTrue(!CS.ErrorIs(e, "FormatException"), "no stale type from the previous call")))
Test("a failed promise exposes the .NET type through its message", () => Throws(() => CS.System.Int32.Async.Parse("abc").Await(), "FormatException"))

_catch(fn) {
    try
        fn()
    catch as e
        return e
    throw Error("expected an error", -2)
}

; ── bool and DateTime ─────────────────────────────────────────────────────────
Test("AHK true is the integer 1", () => (sb := CS.System.Text.StringBuilder(), sb.Append(true), Eq(sb.ToString(), "1")))
Test("CS.Bool passes a real .NET bool", () => (sb := CS.System.Text.StringBuilder(), sb.Append(CS.Bool(true)), Eq(sb.ToString(), "True")))
Test("DateTime results are AHK timestamps", () => Eq(CS.System.DateTime.Parse("2020-05-17 13:45:09"), "20200517134509"))
Test("AHK timestamps convert to DateTime parameters", () => Eq(CS.System.DateTime.Compare("20200101", "20210101"), -1))
Test("date-only timestamps work too", () => Eq(CS.System.DateTime.DaysInMonth(2024, 2), 29))
Test("FormatTime accepts a DateTime result", () => Eq(FormatTime(CS.System.DateTime.Parse("2020-05-17 13:45:09"), "yyyy-MM-dd HH:mm"), "2020-05-17 13:45"))

RunTests()
