# CSModule — Embedded C# Paradigm

Embed C# code directly in AHK classes. Code compiles once and caches to disk.

## Basic Usage

```autohotkey
class MathHelper extends _CSModule {
    static CSharp := "
    (
        public static double Hypotenuse(double a, double b) {
            return Math.Sqrt(a * a + b * b);
        }

        public static bool IsPrime(int n) {
            if (n < 2) return false;
            for (int i = 2; i * i <= n; i++)
                if (n % i == 0) return false;
            return true;
        }
    )"
}

; Call methods directly on the class
result := MathHelper.Hypotenuse(3, 4)  ; → 5.0
prime := MathHelper.IsPrime(997)        ; → true
```

## Properties

| Property | Required | Description |
|----------|----------|-------------|
| `static CSharp` | Yes* | C# source code |
| `static References` | No | Semicolon-separated assembly references |
| `static CSVersion` | No | C# language version ("7.3", "6.0", etc.) |
| `static PrecompiledDLL` | No | Path to precompiled DLL (skips compilation) |

*Required unless `PrecompiledDLL` is set.

## Using Directives

Standard `using` directives are extracted automatically:

```autohotkey
class FileHelper extends _CSModule {
    static CSharp := '
    (
        using System.IO;
        using System.Text;

        public static string ReadFile(string path) {
            return File.ReadAllText(path, Encoding.UTF8);
        }
    )'
}
```

## Assembly References

Reference additional .NET assemblies:

```autohotkey
class WinFormsHelper extends _CSModule {
    static References := "System.Windows.Forms.dll;System.Drawing.dll"
    static CSharp := '
    (
        using System.Windows.Forms;
        public static void ShowNotification(string msg) {
            MessageBox.Show(msg, "AHK#");
        }
    )'
}
```

## Async Execution

Every CSModule automatically gets `.Async` for ThreadPool dispatch:

```autohotkey
class HeavyWork extends _CSModule {
    static CSharp := "
    (
        public static double MonteCarloPi(int iterations) {
            int inside = 0;
            var rng = new Random();
            for (int i = 0; i < iterations; i++) {
                double x = rng.NextDouble(), y = rng.NextDouble();
                if (x*x + y*y <= 1.0) inside++;
            }
            return 4.0 * inside / iterations;
        }
    )"
}

; Non-blocking execution
promise := HeavyWork.Async.MonteCarloPi(10000000)
; ... AHK is responsive while computing ...
pi := promise.Await()
```

## C# Version Targeting

Use newer C# syntax with the `CSVersion` property:

```autohotkey
class Modern extends _CSModule {
    static CSVersion := "7.3"
    static CSharp := '
    (
        public static string Demo() {
            var (x, y) = (10, 20);           // C# 7.0 tuples
            if (int.TryParse("42", out var n)) // C# 7.0 out var
                return $"Sum: {x + y + n}";    // C# 6.0 interpolation
            return "failed";
        }
    )'
}
```

> **Note:** First use of `CSVersion` downloads the Roslyn compiler (~10MB) from NuGet.
> Subsequent compilations use the cached Roslyn.

## NuGet Package References

```autohotkey
class JsonParser extends _CSModule {
    static References := CS.NuGet.Require("Newtonsoft.Json", "13.0.3")
    static CSharp := '
    (
        using Newtonsoft.Json.Linq;

        public static string Query(string json, string path) {
            return JObject.Parse(json).SelectToken(path)?.ToString() ?? "";
        }
    )'
}
```

## Precompilation

Export compiled DLLs for distribution:

```autohotkey
; Dev: compile and export
MathHelper.Precompile(A_ScriptDir "\lib\MathHelper.dll")

; Distribution: load without compiler
class MathHelper extends _CSModule {
    static PrecompiledDLL := A_ScriptDir "\lib\MathHelper.dll"
}
```

## Cross-Module References

One CSModule can reference another:

```autohotkey
class Core extends _CSModule {
    static CSharp := "public static double Add(double a, double b) => a + b;"
}

class App extends _CSModule {
    static References := CS.ModuleRef(Core)
    static CSharp := "public static double AddSquared(double a, double b) => Math.Pow(Core.Add(a,b), 2);"
}
```

## How Compilation Works

1. AHK class definition triggers `static __New()`
2. C# source is hashed (SHA256, 16-char prefix)
3. Bridge checks memory cache → disk cache → compile
4. `CSharpCodeProvider` compiles to `%LocalAppData%\AhkSharp\CompileCache\{hash}.dll`
5. Assembly is loaded and methods are invoked via reflection
6. Subsequent runs skip compilation entirely (hash match)
