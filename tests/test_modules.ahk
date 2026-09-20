#Include harness.ahk

class Calc extends _CSModule {
    static CSharp := "
    (
        public static int Add(int a, int b) { return a + b; }
        public static double Add(double a, double b) { return a + b; }
        public static int Add(int a, int b, int c) { return a + b + c; }
        public static string Greet(string n) { return `"hi `" + n; }
        public static int Total = 7;
        private int _n;
        public int Bump() { return ++_n; }
    )"
}

class Reloadable extends _CSModule {
    static CSharp := "
    (
        public static int V() { return 1; }
    )"
}

Test("overload by argument type (int)", () => Eq(Calc.Add(2, 3), 5))
Test("overload by argument type (double)", () => Near(Calc.Add(2.5, 3), 5.5))
Test("overload by argument count", () => Eq(Calc.Add(1, 2, 3), 6))
Test("string method", () => Eq(Calc.Greet("bob"), "hi bob"))
Test("public static field is readable", () => Eq(Calc.Total, 7))
Test("instance methods share one persistent instance", () => (Calc.Bump(), Eq(Calc.Bump(), 2)))
Test(".Async runs on the thread pool", () => Eq(Calc.Async.Add(1, 2).Await(5000), 3))
Test("unknown method throws", () => Throws(() => Calc.Nope(1), "not found"))
Test("mistyped property throws (no silent empty)", () => Throws(() => Calc.Nmae, "not found"))

; ── hot reload ────────────────────────────────────────────────────────────────
Test("Reload swaps the code", () => (Reloadable.Reload("public static int V() { return 2; }"), Eq(Reloadable.V(), 2)))
Test("a failing Reload throws and keeps the old code", () => (
    Throws(() => Reloadable.Reload("public static int V() { return @@@ }"), "reload failed"), Eq(Reloadable.V(), 2)))
Test("Watch reloads when the file changes", () => _watchTest())

_watchTest() {
    global __state
    path := A_Temp "\ahksharp_hr_" A_TickCount ".cs"
    FileAppend("public static int V() { return 10; }", path, "UTF-8")
    __state["reloaded"] := ""
    timer := Reloadable.Watch(path, (ok, msg) => __state["reloaded"] := ok, 200)
    Sleep(600)
    FileDelete(path)
    FileAppend("public static int V() { return 11; }", path, "UTF-8")
    ok := WaitFor(() => __state["reloaded"] != "", 4000)
    SetTimer(timer, 0)
    try FileDelete(path)
    IsTrue(ok, "reload callback")
    Eq(Reloadable.V(), 11)
}

; ── CS.Fast ───────────────────────────────────────────────────────────────────
Test("Fast.Map with dynamic x", () => Eq(CS.Fast.Map([1, 2, 3], "x * 2")[3], 6))
Test("Fast.Filter keeps order", () => (r := CS.Fast.Filter([1, 2, 3, 4, 5, 6], "x % 2 == 0"), Eq(r.Length, 3), Eq(r[1], 2)))
Test("Fast.Reduce does not overflow at 2^31", () => Eq(CS.Fast.Reduce(_range(100000), "acc + x", 0), 5000050000))

_range(n) {
    a := []
    Loop n
        a.Push(A_Index)
    return a
}

; ── eval ──────────────────────────────────────────────────────────────────────
Test("CS.Eval", () => Near(CS.Eval("Math.Sqrt(144)"), 12))
Test("CS.Eval error carries the compiler message", () => Throws(() => CS.Eval("1 +"), "expected"))

RunTests()
