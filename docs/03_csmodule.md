# CSModule — Embedded C# Paradigm

Embed C# code directly in AHK classes. Code compiles once and caches to disk.

## Basic Usage

```autohotkey
#Include lib\ahk#.ahk

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
prime := MathHelper.IsPrime(997)        ; → 1 (bool is 1/0 in AHK)
```

The AHK class name is used as the C# class name. If your code has no `class` declaration it is wrapped in `public class <Name> { ... }` with `using System; using System.Linq; using System.Collections.Generic;` added. Leading `using` lines you write are hoisted out of the class body.

**"No `class` declaration" means no line that starts with (optional modifiers and) `class Name`.** A source that has such a line, even a nested helper class in a snippet of members, is taken as a **complete file** and is not wrapped: then it needs its own wrapper class named like the AHK class, and its own `using` lines (the three defaults are added only when the text has no `using System`). Details and the trap: [Version Targeting](13_version_targeting.md#the-source-is-wrapped-unless-it-is-a-whole-file).

Class bodies initialise in order of appearance, so **define a module class before the code that calls it**.

The default compiler accepts **C# 4.0** syntax: no `?.`, no `=>` method bodies, no `$"..."` interpolation, no `out var`. Add `static CSVersion := "6.0"` (or newer, up to `"12.0"` / `"latest"`) if you want those ([Version Targeting](13_version_targeting.md)).

## Properties

| Property | Required | Description |
|----------|----------|-------------|
| `static CSharp` | Yes* | C# source code |
| `static References` | No | Semicolon-separated assembly references |
| `static CSVersion` | No | C# language version: `"5.0"` .. `"12.0"`, `"latest"` or `"preview"`; needs Roslyn (auto-downloaded; `"11.0"` and up need .NET Framework 4.7.2+) |
| `static PrecompiledDLL` | No | Path to a precompiled DLL (skips compilation) |

*Required unless `PrecompiledDLL` is set.

## Overloads, Instances and Fields

```autohotkey
class Counter extends _CSModule {
    static CSharp := '
    (
        public static int Add(int a, int b) { return a + b; }
        public static double Add(double a, double b) { return a + b; }
        public static int Total = 7;

        private int _n;
        public int Bump() { return ++_n; }
    )'
}

Counter.Add(2, 3)        ; → 5      (int overload)
Counter.Add(2.5, 3)      ; → 5.5    (double overload)
Counter.Total            ; → 7      public static fields and properties are readable
Counter.Bump()           ; → 1
Counter.Bump()           ; → 2      instance (non-static) methods share ONE persistent instance per module
```

- Overloads are resolved by the same binder as `CS.System...` calls ([Marshaling](17_marshaling.md)); an unmatched call lists the candidates.
- **State persists**: non-static C# methods run on one instance that lives as long as the process.
- **Typos throw.** `Counter.Nope(1)` and `Counter.Nmae` raise an error instead of returning an empty string.

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

See [Async/Await](04_async.md) for `.Then` / `.Catch` / `.Finally` chains, `.Timeout`, `CS.Promise.All` / `Race` / `AwaitAll`.

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

```autohotkey
class Modern12 extends _CSModule {
    static CSVersion := "12.0"                      ; records, init, switch expressions, raw strings ...
    static CSharp := '
    (
        public record Point(int X, int Y);
        public static string Where(int x) => x switch { < 0 => "left", 0 => "middle", _ => "right" };
    )'
}
```

> **Note:** the first use of `CSVersion` downloads the Roslyn compiler from NuGet (about 10 MB up to `"10.0"`, about 20 MB for `"11.0"`, `"12.0"` and `"latest"`). Later compilations reuse it. A newer compiler gives newer *syntax*; the code still runs on the .NET Framework 4 CLR, so `Span<T>`, `System.Index` / `Range` (`^1`, `..`), default interface members and async streams are not available ([Version Targeting](13_version_targeting.md#what-runs-syntax-not-new-runtime-apis)).

## Hot Reload

Recompile a module while the script runs:

```autohotkey
class Scratch extends _CSModule {
    static CSharp := FileRead(A_ScriptDir "\Scratch.cs", "UTF-8")
}

Scratch.Reload("public static int V() { return 2; }")   ; recompile from new source
MsgBox Scratch.V()                                      ; → 2

; Reload automatically whenever the .cs file's CONTENT changes
timer := Scratch.Watch(A_ScriptDir "\Scratch.cs", (ok, message) => ToolTip(ok ? "reloaded" : message))
; ...
SetTimer(timer, 0)                                       ; stop watching
```

- `Module.Reload(csharpSource)` compiles the new source (with the same `References` and `CSVersion`). **If it does not compile, the old code keeps running** and an error is thrown (`CSModule 'Name' reload failed: ...`). On success the module's `CSharp` is updated. The module's instance state (the one persistent instance behind non-static methods) starts fresh.
- `Module.Watch(path, onReload := "", intervalMs := 500)` polls the file with a timer and calls `Reload` whenever its **content** changes (not its timestamp: AHK file times have one-second resolution, so two saves within a second would look identical). `onReload(ok, message)` is called after each attempt: `ok` is `true` / `false` and `message` is the error text on failure (declare fewer parameters if you like). It returns the timer function; `SetTimer(fn, 0)` stops it. The file must exist when you call `Watch`, and, being a timer, it needs the message pump (`Sleep`, a GUI, `Persistent()`).
## Compile Errors

A compile error **throws** from the class initialiser (`CSModule 'Name' failed to compile: ...`), so a broken module fails at start-up instead of returning empty values later. Before throwing, AHK# shows a diagnosis window (compiler messages, likely fixes, the first 30 lines of generated source) and waits for you to close it. For headless or scheduled scripts switch the window off *before* the module classes are defined:

```autohotkey
#Include lib\ahk#.ahk
CS.Config.ShowErrorGui := false     ; throw only, never open the window
CS.Config.NuGetGui := false         ; same for the NuGet progress window
```

## NuGet Package References

```autohotkey
class JsonParser extends _CSModule {
    static References := CS.NuGet.Require("Newtonsoft.Json", "13.0.3")
    static CSharp := '
    (
        using Newtonsoft.Json.Linq;

        public static string Query(string json, string path) {
            JToken token = JObject.Parse(json).SelectToken(path);
            return token == null ? "" : token.ToString();
        }
    )'
}
```

(Written in C# 4 on purpose: no `?.`, so no Roslyn download is needed.)

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

One CSModule can reference another (C# 4 syntax):

```autohotkey
class Core extends _CSModule {
    static CSharp := "public static double Add(double a, double b) { return a + b; }"
}

class App extends _CSModule {
    static References := CS.ModuleRef(Core)
    static CSharp := "public static double AddSquared(double a, double b) { return Math.Pow(Core.Add(a, b), 2); }"
}
```

## How Compilation Works

1. The AHK class definition triggers `static __New()`.
2. The C# source (plus references and version) is hashed with SHA256 (16-char prefix).
3. The bridge checks the in-memory cache, then the disk cache, then compiles.
4. `CSharpCodeProvider` (or Roslyn for `CSVersion`) compiles to `%LocalAppData%\AhkSharp\CompileCache\{hash}.dll`, written to a temporary file first and moved into place.
5. The assembly is loaded and methods are invoked through the overload binder.
6. Later runs skip compilation (hash match). The cache is trusted by hash only: see [Security](19_security.md).
