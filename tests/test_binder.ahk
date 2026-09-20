#Include harness.ahk
#Include ..\ext\ahk#.http.ahk      ; Json (for the packing test)

; ── overload resolution: exact type wins, never a lossy conversion ────────────
Test("Math.Abs keeps the fraction", () => Eq(CS.System.Math.Abs(-2.5), 2.5))
Test("Math.Max(3.7, 2) is 3.7", () => Near(CS.System.Math.Max(3.7, 2), 3.7))
Test("Math.Min(2.5, 10) is 2.5", () => Near(CS.System.Math.Min(2.5, 10), 2.5))
Test("Math.Sign(-0.4) is -1", () => Eq(CS.System.Math.Sign(-0.4), -1))
Test("Math.Abs(-3000000000) uses the long overload", () => Eq(CS.System.Math.Abs(-3000000000), 3000000000))
Test("Math.Max(9000000000, 5)", () => Eq(CS.System.Math.Max(9000000000, 5), 9000000000))
Test("Convert.ToString(255, 16) reaches the static method", () => Eq(CS.System.Convert.ToString(255, 16), "ff"))
Test("UInt64.MaxValue is a digit string", () => Eq(CS.System.UInt64.MaxValue, "18446744073709551615"))

; ── params, optional, packing ─────────────────────────────────────────────────
Test("params array: String.Join(',', 'a', 'b', 'c')", () => Eq(CS.System.String.Join(",", "a", "b", "c"), "a,b,c"))
Test("Path.Combine with 3 parts", () => Eq(CS.System.IO.Path.Combine("C:\a", "b", "c"), "C:\a\b\c"))
Test("String.Format with boxed ints", () => Eq(CS.System.String.Format("{0}-{1}", 1, 2), "1-2"))
Test("optional parameter: Uri(string).Host", () => Eq(CS.System.Uri("http://a.b/c?d=1").Host, "a.b"))
Test("extra args pack into a trailing object parameter", () => IsTrue(InStr(Json.Build("k1", "v1", "k2", 2), '"k2":2'), "Json.Build"))

; ── strings parse to what the parameter wants ─────────────────────────────────
Test("enum from string", () => Eq(CS.System.Enum.Parse(CS.System.DayOfWeek, "Friday"), "Friday"))
Test("Guid from string", () => Eq(CS.System.Guid.Parse("d3b07384-d9a4-4b8a-8a6d-3f2f5a1c9e11"), "d3b07384-d9a4-4b8a-8a6d-3f2f5a1c9e11"))
Test("case-insensitive member names", () => Near(CS.system.math.pow(2, 10), 1024))

; ── errors surface with the real .NET message ─────────────────────────────────
Test("missing file → the real FileNotFound text", () => Throws(() => CS.System.IO.File.ReadAllText("C:\definitely\not\here.txt"), "Could not find"))
Test("Int32.Parse('abc') throws FormatException text", () => Throws(() => CS.System.Int32.Parse("abc"), "not in a correct format"))
Test("unknown static method names the type", () => Throws(() => CS.System.Math.Powwww(2, 3), "no static method 'Powwww'"))
Test("a misspelled static method suggests the real one", () => Throws(() => CS.System.Math.Abss(1), "Did you mean: Abs"))
Test("a misspelled property suggests the real one", () => Throws(() => CS.System.Text.StringBuilder().Lenght, "Did you mean: Length"))
Test("a misspelled static property suggests the real one", () => Throws(() => CS.System.Math.PIE, "Did you mean: PI"))
Test("a misspelled event suggests the real one", () => Throws(() => CS.System.Console.On("CancelKeyPres", (*) => 1), "Did you mean: CancelKeyPress"))
Test("an instance member used on the type says so", () => Throws(() => CS.System.String.Length, "instance member"))
Test("a misspelled namespace suggests the real one", () => Throws(() => CS.System.Tex.StringBuilder(), "Did you mean 'System.Text.StringBuilder'"))
Test("a misspelled type suggests the real one", () => Throws(() => CS.System.IO.Fiel.ReadAllText("x"), "Did you mean 'System.IO.File.ReadAllText'"))
Test("CS.Members lists overloads and filters by name", () => (
    m := CS.Members(CS.System.Math, "abs"), Has(m, "static double Abs(double value)"), IsTrue(!InStr(m, "Sqrt"))))
Test("CS.Members works on an object", () => Has(CS.Members(CS.System.Text.StringBuilder(), "AppendLine"), "StringBuilder AppendLine(string value)"))
Test("CS.Types lists types and child namespaces", () => (
    t := CS.Types("System.IO"), Has(t, "System.IO.File  (static class)"), Has(t, "System.IO.Compression.*")))
Test("CS.Types takes a namespace object and a filter", () => (t := CS.Types(CS.System.Timers, "Timer"), Has(t, "System.Timers.Timer"), IsTrue(!InStr(t, "ElapsedEventArgs"))))
Test("no matching overload lists candidates",() => Throws(() => CS.System.Math.Abs("hello"), "Candidates"))

; ── explain ───────────────────────────────────────────────────────────────────
Test("CS.Explain marks the winner and rejects lossy overloads", () => (
    txt := CS.Explain(CS.System.Math, "Abs", -2.5),
    Has(txt, "=> cost   0  Double Abs"), Has(txt, "rejected  Int32 Abs")))

; ── out / ref parameters via &var ─────────────────────────────────────────────
Test("TryParse fills &n", () => (
    ok := CS.System.Int32.TryParse("12", &n), Eq(ok, 1), Eq(n, 12)))
Test("TryParse failure leaves the default", () => (
    ok := CS.System.Int32.TryParse("zz", &n), Eq(ok, 0), Eq(n, 0)))
Test("Dictionary.TryGetValue fills &value", () => (
    d := CS.System.Collections.Generic.Dictionary(CS.System.String, CS.System.Int32)(),
    d.Add("a", 41), ok := d.TryGetValue("a", &v), Eq(ok, 1), Eq(v, 41)))
Test("ref parameter round trip: Interlocked.Increment(&x)", () => (
    x := 5, CS.System.Threading.Interlocked.Increment(&x), Eq(x, 6)))

; ── generics ──────────────────────────────────────────────────────────────────
Test("List(T)() paren form", () => (
    L := CS.System.Collections.Generic.List(CS.System.Int32)(), L.Add(1), L.Add(2), Eq(L.Count, 2)))
Test("List[T]() bracket form", () => Eq(CS.System.Collections.Generic.List[CS.System.Int32]().Count, 0))
Test("Dictionary indexer", () => (
    d := CS.System.Collections.Generic.Dictionary(CS.System.String, CS.System.Int32)(),
    d["b"] := 2, Eq(d["b"], 2)))

; ── LINQ with AHK lambdas ─────────────────────────────────────────────────────
Test("Where(fn).Count()", () => (L := _ints(5, 3, 9), Eq(L.Where((x) => x > 4).Count(), 2)))
Test("Select(fn).ToAHK()", () => (L := _ints(5, 3, 9), a := L.Select((x) => x * 10).ToAHK(), Eq(a[1], 50), Eq(a[3], 90)))
Test("OrderBy(fn).First()", () => Eq(_ints(5, 3, 9).OrderBy((x) => x).First(), 3))
Test("Any(pred)", () => Eq(_ints(5, 3, 9).Any((x) => x == 9), 1))
Test("Sum() over an AHK Array", () => Eq(CS.System.Linq.Enumerable.Sum([1, 2, 3, 4]), 10))

_ints(vals*) {
    L := CS.System.Collections.Generic.List(CS.System.Int32)()
    for v in vals
        L.Add(v)
    return L
}

RunTests()
