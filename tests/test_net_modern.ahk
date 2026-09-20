#Include harness.ahk

; Needs the network (Roslyn toolset and NuGet metadata are downloaded on first use): run_tests.ps1 only runs this with AHKSHARP_NET=1.

; ── C# 12 on the .NET Framework 4 runtime ─────────────────────────────────────
class Modern extends _CSModule {
    static CSVersion := "12.0"
    static CSharp := "
    (
        public class Modern {
            public record Point(int X, int Y);
            public class Shape { public string Name { get; init; } = `"?`"; }
            public static string Describe(int n) => n switch { < 0 => `"neg`", 0 => `"zero`", _ => `"pos`" };
            public static string Rec(int a, int b) { var p = new Point(a, b); return $`"{p}`"; }
            public static string Raw() => `"`"`"
                raw `"quoted`" text
                `"`"`";
            public static string Init() { var s = new Shape { Name = `"circle`" }; return s.Name; }
            public static int Len(string s) => s?.Length ?? -1;
        }
    )"
}

Test("C# 12: switch expressions and relational patterns", () => (Eq(Modern.Describe(-3), "neg"), Eq(Modern.Describe(0), "zero"), Eq(Modern.Describe(5), "pos")))
Test("C# 9: records and init accessors compile (IsExternalInit is supplied)", () => (Eq(Modern.Rec(1, 2), "Point { X = 1, Y = 2 }"), Eq(Modern.Init(), "circle")))
Test("C# 11: raw string literals", () => Eq(StrReplace(Modern.Raw(), "`n", "|"), "raw `"quoted`" text"))
Test("C# 6: null-conditional and null-coalescing", () => Eq(Modern.Len("abcd"), 4))

; ── NuGet: only packages this runtime can load ────────────────────────────────
Test("NuGet.Search returns Maps and lists Newtonsoft.Json", () => (
    r := CS.NuGet.Search("newtonsoft.json", 5), IsTrue(r.Length > 0, "results"),
    IsTrue(_anyId(r, "Newtonsoft.Json"), "Newtonsoft.Json in the results"), Has(r[1]["Version"], ".")))
Test("a package that only targets net8.0 is refused with what it offers", () => Throws(() => CS.NuGet.Install("Aspire.Hosting", "8.2.2", false), "offers: net8.0"))
Test("latest-version resolution never returns a prerelease", () => IsTrue(!InStr(_bridge().NuGetResolveVersion("Newtonsoft.Json"), "-"), "stable"))
Test("an invalid C# language version is rejected", () => Throws(() => _bridge().CompileModuleVersioned("public static int A() { return 1; }", "", "12.0; calc"), "Invalid C# language version"))

_anyId(results, id) {
    for p in results
        if (p["Id"] = id)
            return true
    return false
}

_bridge() {
    return _AhkSharpEngine.Boot()
}

RunTests()
