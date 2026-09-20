# C# Version Targeting

```autohotkey
#Include lib\ahk#.ahk

class Modern extends _CSModule {
    static CSVersion := "12.0"          ; or "6.0", "7.3", "10.0", "latest" ...
    static CSharp := '
    (
        public record Point(int X, int Y);
        public static string Describe(int n) => n switch { < 0 => "neg", 0 => "zero", _ => "pos" };
        public static string Show(int a, int b) => $"{new Point(a, b)}";
    )'
}

MsgBox Modern.Describe(-3) " " Modern.Show(1, 2)     ; → neg Point { X = 1, Y = 2 }
```

## Available Versions

| `CSVersion` | Compiler | Download | Notes |
|-------------|----------|----------|-------|
| (unset) | built-in `CSharpCodeProvider` | none | C# 4.0, always available, no network |
| `"5.0"` ... `"10.0"` | Roslyn `microsoft.net.compilers` 4.0.1 | about 10 MB, once | C# up to 10 |
| `"11.0"`, `"12.0"`, `"latest"`, `"preview"` | Roslyn `Microsoft.Net.Compilers.Toolset` 4.8.0 | about 20 MB, once | C# up to 12; its `csc.exe` needs .NET Framework **4.7.2 or later** |

What each language version adds:

| Version | Language features |
|---------|-------------------|
| 5.0 | async/await, caller info attributes |
| 6.0 | String interpolation `$"..."`, null-conditional `?.`, expression-bodied members, `nameof`, auto-property initializers |
| 7.0-7.3 | Tuples, pattern matching, `out var`, local functions, default literals, `ref` improvements |
| 8.0 | Switch expressions, `using` declarations, nullable reference annotations |
| 9.0 | Records, `init` accessors, target-typed `new`, relational patterns (`< 0`, `and`, `or`, `not`) |
| 10.0 | File-scoped namespaces, global usings, record structs |
| 11.0 | Raw string literals (`"""..."""`) |
| 12.0 | Primary constructors, default parameter values in lambdas |

`tests\test_net_modern.ahk` compiles and runs records, `init` accessors, switch expressions with relational patterns, string interpolation, raw string literals and `?.` under `"12.0"`. C# 4 code has no `?.`, no `=>` method bodies, no `$"..."`. The docs use C# 4 syntax unless a snippet sets `CSVersion`.

## What runs: syntax, not new runtime APIs

The output still runs on the **.NET Framework 4 CLR** (that is the runtime AHK# hosts). A newer compiler gives you newer *syntax and compiler features*; it does not give you newer *runtime libraries*. Works: everything that only needs the compiler (records, `init`, switch expressions, patterns, interpolation, raw strings, `?.`, ...). Does **not** work, because the types or CLR features are not in .NET Framework 4.x:

- `System.Index` / `System.Range`: no `^1`, no `..` ranges or slices
- `Span<T>` / `ReadOnlySpan<T>` and what is built on them
- default interface members and `static abstract` interface members
- async streams (`await foreach`, `IAsyncEnumerable<T>`)
- **NuGet packages built for net5.0 and newer** cannot be loaded ([NuGet](05_nuget.md#framework-targeting))

Two things AHK# does for you:

- **`IsExternalInit`.** Records and `init` accessors need a marker type named `System.Runtime.CompilerServices.IsExternalInit`, which only newer frameworks ship. For `CSVersion` 9.0 or later (`latest`, `preview` too), when the source uses a `record` or an `init` accessor and does not mention `IsExternalInit` itself, AHK# appends an internal `IsExternalInit` marker class to the module's source automatically.
- **Caching.** The compiled DLL is cached by a hash of the source, the references and the language version, so a module that is already in the cache does not need the compiler (or the network) again.

## The source is wrapped unless it is a whole file

`static CSharp` may hold just members (methods, fields, nested types) or a complete source file. AHK# decides by looking for a line that **starts with** an optional modifier list and `class Name` (`public class Modern`, `public static class X`, `class X`):

- **No such line:** the code is wrapped in `public class <YourAhkClassName> { ... }`, with `using System; using System.Linq; using System.Collections.Generic;` added and your leading `using` lines hoisted out of the body. A `record` declaration in the body becomes a nested type.
- **Such a line exists:** the source is taken as a complete file and **not** wrapped. Write your own `using` lines (the three defaults are added only if the text has no `using System`), and give one class the **same name as the AHK class**, because that is the class whose methods `Module.Method(...)` calls (`tests\test_net_modern.ahk` does this: `class Modern extends _CSModule` whose source is `public class Modern { ... }`).

Watch for the trap: a members-only snippet that also declares a nested `class Helper` on its own line is treated as a complete file, so its methods are no longer inside a class and the compile fails with "A namespace cannot directly contain members such as fields, methods or statements". Either write the whole file (wrapper class included) or move the helper into its own module ([Cross-Module](10_cross_module.md)).

## First Use

The first compilation with `CSVersion` downloads the Roslyn compiler for that version from NuGet: `microsoft.net.compilers` 4.0.1 (about 10 MB) for `"5.0"` to `"10.0"`, `Microsoft.Net.Compilers.Toolset` 4.8.0 (about 20 MB) for `"11.0"`, `"12.0"`, `"latest"` and `"preview"`. The download gets the same SHA-512 check as any NuGet package ([NuGet](05_nuget.md#integrity-check)); nothing checks the package's signature ([Security](19_security.md)). Where they go:

| Compiler | Location under `%LocalAppData%\AhkSharp\Packages\` |
|----------|----------------------------------------------------|
| C# up to 10 | `microsoft.net.compilers\4.0.1\tools\` |
| C# 11, 12, latest | `microsoft.net.compilers.toolset\4.8.0\tasks\net472\` |

That needs internet once; afterwards it works offline. Roslyn is run as a separate `csc.exe` process, so expect a slower first compile; the result is cached like any other module.

## Errors

- **`C# 12.0 needs the newer Roslyn compiler, which runs on .NET Framework 4.7.2 or later; this machine has ...`** (`NotSupportedException`): the toolset's `csc.exe` cannot run on an older Framework. Use `CSVersion` up to `"10.0"` there.
- **`Invalid C# language version: ...`** (`ArgumentException`): the string must match `^[A-Za-z0-9.]{1,12}$` (`"6.0"`, `"10.0"`, `"latest"`); it goes to `csc.exe` as `/langversion:`, so anything else is refused before the compiler starts.
- **`Roslyn compilation failed (C# 12.0): ...`**: the compiler's own messages (the diagnosis window shows them, unless `CS.Config.ShowErrorGui := false`). Using `System.Index` / `Span<T>` / async streams ends up here too: see the list above.
- If the download fails you get an error; see [Troubleshooting](18_troubleshooting.md). Set `CS.Config.ShowErrorGui := false` in headless scripts so a compile error throws instead of opening the diagnosis window.

`CS.Eval` and `CS.Run` always use the built-in C# 4 compiler; `Module.Reload(source)` compiles with the module's own `CSVersion`.
