# Contributing to AHK#

Thanks for helping. This page covers the repository layout, building the bridge, running the tests and the docs lint, adding a test, adding a bridge method with its AHK side, and the style we keep.

## Repository layout

```
AHKSharp/
├── lib/
│   ├── ahk#.ahk               the AHK library (CS, proxies, promises, _CSModule, ...)
│   ├── ahk#.bridge.dll        the prebuilt bridge (committed); its SHA-256 is pinned inside ahk#.ahk
│   └── build.ps1              compiles src\**\*.cs into the DLL and re-pins the hash
├── src/
│   ├── bridge/                the bridge, one file per concern
│   │   ├── AhkSharpBridge.cs    the COM entry class + every method AHK calls
│   │   ├── OverloadBinder.cs    overload scoring / coercion, Explain
│   │   ├── Discovery.cs         CS.Members / CS.Types, "did you mean" for type paths
│   │   ├── MemberHints.cs       "did you mean" for members
│   │   ├── Declarations.cs      CS.Declare: generates the ahk#.d.ahk editor declaration file
│   │   ├── AhkCallback.cs       AHK functions called by .NET, worker-thread queue
│   │   ├── ValueBox.cs          structs and arrays as real references
│   │   ├── Extras.cs            CS.Implement (RealProxy) and the CS.Wrap generator
│   │   ├── TypeResolver.cs      type-name lookup
│   │   ├── MarshalEngine.cs     CLR <-> COM value conversion
│   │   ├── RuntimeCompiler.cs   _CSModule / CS.Eval / CS.Run compilation and cache, Roslyn for CSVersion
│   │   ├── ErrorInfo.cs         typed-exception recorder + MemberCache
│   │   ├── AsyncRouter.cs       ThreadPool / Task -> promise
│   │   ├── FastParallel.cs      CS.Fast
│   │   ├── NuGetManager.cs      packages, SHA-512 check, dependencies, "latest that works here", Roslyn download
│   │   ├── FrameworkPicker.cs   which NuGet target frameworks the .NET Framework CLR can load (ranking)
│   │   ├── NuGetSearch.cs       CS.NuGet.Search (partial class of NuGetManager)
│   │   └── DelegateBridge.cs    event subscription
│   └── ext/                   the C# behind the extensions (same DLL)
├── ext/                       the AHK side of the extensions (sqlite, http/json, ipc, ui, uia, spatial)
├── tests/                     harness, suites, run_tests.ps1, run-ahk.ps1, lint_docs.ps1
├── docs/                      documentation (README links to it)
├── examples/                  runnable scripts, one folder per category
├── workbench/                 sources of the playground (ahk#_playground.ahk)
├── .github/workflows/         tests.yml: the suites on a Windows runner
└── README.md, CHANGELOG.md, CONTRIBUTING.md
```

`ext\` (AutoHotkey) and `src\ext\` (C#) are different folders on purpose: the first is what users `#Include`, the second is compiled into the bridge.

## Building the bridge

```powershell
powershell -File lib\build.ps1 -Force        # always rebuild
powershell -File lib\build.ps1 -Verbose      # also print the compiler command and the source list
```

Without `-Force` the script hashes `src\**\*.cs` and does nothing when the sources are unchanged. A build prints the compiler errors **and warnings** (fix new warnings), writes `lib\ahk#.bridge.dll` and **rewrites `AHK_SHARP_BRIDGE_SHA256` in `lib\ahk#.ahk`**. Commit the DLL and `lib\ahk#.ahk` together: `Boot()` refuses a DLL that does not match the pin.

While you edit `src\`, set the environment variable `AHKSHARP_DEV=1`: every start then runs `build.ps1` and skips the hash check. Unset it for normal runs. The bridge is loaded from bytes and a CLR AppDomain cannot be unloaded, so restart the script (or the AutoHotkey process) after a rebuild.

### The C# must stay C# 4.0

**Everything under `src\` (`src\bridge\` and `src\ext\`, new files included) must stay C# 4 syntax.** The bridge is compiled by the `csc.exe` that ships with Windows (`%windir%\Microsoft.NET\Framework64\v4.0.30319\csc.exe`, version 4.0.30319), so nothing needs to be installed. That compiler only knows C# 4.0. In `src\` (bridge and `src\ext\`) do **not** use:

- the `?.` null-conditional operator,
- `$"..."` string interpolation (use `string.Format` or `+`),
- expression-bodied members (`int X => 1;`, `void F() => G();`) and auto-property initializers,
- `nameof`, `out var`, tuples, pattern matching (`x is T t`), `async` / `await`, `using static`.

Optional and named arguments, `dynamic`, LINQ and lambdas are fine (they are C# 4.0). If a build fails with a syntax error on a line that looks modern, this is why. (Snippets that users compile through `_CSModule` may use newer syntax with `static CSVersion := "12.0"` (or `"latest"`); that is a different compiler path and does not apply to `src\`.)

## Running the tests and the docs lint

Use **PowerShell**. Never start AutoHotkey for the tests from Git Bash: Bash rewrites the `/ErrorStdOut` flag and paths, and the runners break.

```powershell
powershell -File tests\run_tests.ps1                     # all suites; exit code = failing tests + suites that did not finish
powershell -File tests\run_tests.ps1 -Filter binder      # only suites whose name contains "binder"
$env:AHKSHARP_NET = "1"; powershell -File tests\run_tests.ps1    # also the network tests (Http, NuGet) and test_net_modern
powershell -File tests\lint_docs.ps1                     # documentation drift; exit code = number of problems
```

Run the tests after every bridge change, and `lint_docs.ps1` after touching `README.md`, `docs\*.md`, or renaming a `CS` member or file. Details: [docs/20_testing.md](docs/20_testing.md). Do not hard-code test counts in the docs: they change.

### AHK v2 pitfalls the tests taught us

- **Fat-arrow lambdas assign LOCAL variables.** `() => done := true` sets a variable inside the lambda. Record results in a Map or object (the harness gives tests a global `__state`).
- **A variable named like a class clashes with it.** AHK is case-insensitive: `json := Json.Query(...)` makes `json` and the `Json` class the same name. Same for `http` / `Http`, `sqlite` / `SQLite`, `cs` / `CS`.
- **`throw` cannot be used inside an expression.** A one-line test body cannot `throw`; call a named function that throws.
- **A space followed by `;` inside a quoted string is treated as a comment start** on that line. Build the text with `Chr(59)` or use a continuation section.
- Callbacks (`.Then`, `.On`, worker-thread functions) only run while the AHK message pump runs (`Sleep`, `WaitFor`, `Await`, a GUI).
- `Then` / `Catch` / `Finally` return a **new** promise: keep a reference to the original if you `Await` it, and use a named function when a callback has to `throw` (a fat arrow cannot).

## Adding a test

Any file named `tests\test_*.ahk` is picked up by `run_tests.ps1`. A suite that needs the network (it downloads the Roslyn toolset or queries nuget.org) is named `tests\test_net*.ahk`: `run_tests.ps1` starts those only when `AHKSHARP_NET=1` (see `tests\test_net_modern.ahk`).

```autohotkey
#Include harness.ahk

Test("Math.Abs keeps the fraction", () => Eq(CS.System.Math.Abs(-2.5), 2.5))
Test("a bad parse throws a FormatException", () => (
    e := _catch(() => CS.System.Int32.Parse("abc")), IsTrue(CS.ErrorIs(e, "FormatException"), "type")))

_catch(fn) {
    try
        fn()
    catch as e
        return e
    throw Error("expected an error", -2)
}

RunTests()
```

- A test body is one expression; chain several with commas inside parentheses, or call a named function for longer bodies.
- Assertions: `Eq`, `Near`, `IsTrue`, `Has`, `Throws`, `WaitFor`; `Skip(name, why)` for opt-in tests. All are in `tests\harness.ahk` and described in the testing doc.
- Define any `_CSModule` class above the tests that use it (class bodies initialise in order).
- Suites share one process: put `CS.Config.*` values you change back.
- A regression test goes in the suite that owns the area (`test_binder` for overloads, `test_marshaling` for value conversion, `test_extensions` for `ext\`, and so on); new areas get their own file.

## Adding a bridge method and its AHK side

1. **C# side.** Put the logic in the file that owns the concern (for example marshaling in `MarshalEngine.cs`, overload work in `OverloadBinder.cs`) and expose it with a `public` method on `AhkSharpBridge` in `AhkSharpBridge.cs`. That class is the COM object AHK calls through IDispatch, so:
   - use simple parameter and return types (`string`, `int`, `long`, `bool`, `object`, `object[]`); arguments from AHK arrive as `object` (a proxy arrives as the .NET object itself, a boxed struct or array as a `ValueBox`: call `MarshalEngine.Unbox` first);
   - do not overload public methods: COM renames overloads (`GetType_2` in `Boot()` is such a rename), so give each method its own name;
   - return values through `MarshalEngine.PackResult` so DateTime, `ulong`, `decimal`, arrays and structs follow the marshaling rules;
   - let exceptions propagate. The AHK side turns them into `Error` objects with `NetType` and friends; do not catch and return text;
   - stay in C# 4.0.
2. **Rebuild:** `powershell -File lib\build.ps1 -Force` (this re-pins the hash in `lib\ahk#.ahk`).
3. **AHK side, in `lib\ahk#.ahk`.** Boot the bridge with `_AhkSharpEngine.Boot()`, convert arguments with `_PackArgs` / `_ToBridgeValue` (a proxy passes as `proxy._obj`), wrap the call so a failure becomes a clean error, and wrap the result:

   ```autohotkey
   ; CS.Thing(x): one line saying what it does and why it exists
   static Thing(x) {
       bridge := _AhkSharpEngine.Boot()
       try
           result := bridge.Thing(_ToBridgeValue(x))
       catch as e
           throw _CSError(e, "CS.Thing")
       return _WrapResult(result)
   }
   ```

   A member of `class CS` is a static method at four-space indent; that is how the docs lint learns the real member list. A new proxy helper also needs an entry in `_CSProxy._helpers` (methods) or `_CSProxy._props` (properties), remembering the rule: **a helper is only used when the .NET object has no member of that name**.
4. **Tests** for the new behaviour (above), including the error path.
5. **Docs:** the API reference (`docs\15_api_reference.md`), the page for the feature, the README features table if it is user-visible, and `CHANGELOG.md` (flag anything **BREAKING**). Then run `tests\lint_docs.ps1`.

## Style

- Keep comments short and explain **why**, not what: a subtle ordering, a COM quirk, a bug the code avoids. The tests are the place for "what".
- Code first in the docs: a small working AHK v2 snippet before the prose. Every snippet must be valid AHK v2 and match the real API; run it, or copy it from a test.
- Say only what the code and the tests prove. Where something is not checked (package signatures, the compile cache), say that it is not checked.
- Keep the bridge free of global state that outlives its purpose: caches must be bounded (`test_stress.ahk` watches `CS.Stats()`).
- No new dependencies: the project runs from a clone with Windows' own .NET Framework and AutoHotkey v2.
