# AHK#

> Use the .NET Framework CLR from AutoHotkey v2 with a native-looking syntax: `CS.System.Math.Pow(5, 3)`.

## What is AHK#?

AHK# hosts the .NET Framework 4.x CLR inside the AutoHotkey process and talks to it through a small COM-visible bridge DLL. From AHK you can call .NET methods, create .NET objects, compile embedded C# and pull in NuGet packages. There is no COM registration and no installer, and the only extra file the runtime needs is `lib\ahk#.bridge.dll` (committed to this repository).

```autohotkey
#Requires AutoHotkey v2.0
#Include lib\ahk#.ahk            ; relative to THIS script (see "Including the library")

; Call any .NET method directly
result := CS.System.Math.Pow(5, 3)        ; → 125.0 (a Double)

; Create .NET objects with fluid chaining
sb := CS.System.Text.StringBuilder()
sb.Append("Hello").Append(" World")
text := sb.ToString()                     ; → "Hello World"

; One-liner C# expressions
guid := CS.Eval("Guid.NewGuid().ToString()")

; Embed full C# classes (define the class BEFORE the code that calls it)
class MathHelper extends _CSModule {
    static CSharp := "
    (
        public static double Hypotenuse(double a, double b) {
            return Math.Sqrt(a * a + b * b);
        }
    )"
}
result := MathHelper.Hypotenuse(3, 4)    ; → 5.0
```

## Features

| Feature | Description |
|---------|-------------|
| **CS.Namespace** | Call any .NET static method, property, or constructor; names are case-insensitive; generics work |
| **Overload binder** | Picks the best overload by cost, never a lossy conversion; params, optional args, LINQ, generic inference; `CS.CallGeneric` for explicit type arguments |
| **.NET always wins** | AHK# helper members on a proxy (`ToAHK`, `On`, `Type`, `Dispose`, ...) apply only when the .NET object has no member of that name; `proxy._Invoke("Name", ...)` always calls the .NET one |
| **Error handling** | A .NET failure is an AHK `Error` with `e.NetType`, `e.NetBases`, `e.NetStack`, `e.NetHResult`; `CS.ErrorIs(e, "IOException")` matches the type, its short name or any base class |
| **Value types** | `DateTime` results are AHK timestamps (`YYYYMMDDHH24MISS`, work with `FormatTime` / `DateAdd`) and timestamps go back in as `DateTime`; `CS.Bool(true)` passes a real .NET `bool`; structs (`Point`, `CancellationToken`, ...) stay usable proxies; `matrix[i, j]` indexers |
| **Identity and lifetime** | `CS.Same(a, b)`, `CS.Using(obj, fn)` (dispose after `fn`), `proxy.AutoDispose()`, `CS.Stats()` (heap, delegates, pending tasks, caches) |
| **CS.Eval() / CS.Run()** | One-liner C# expression evaluator; `CS.Run` runs a multi-statement body |
| **CS.Import()** | Namespace aliasing for cleaner code |
| **_CSModule** | Embed C# code in AHK classes, compiled and cached on disk |
| **CS.NuGet** | Download NuGet packages (and their dependencies) with one line; every `.nupkg` is verified against the SHA-512 nuget.org publishes (`CS.Config.VerifyNuGet` / `NuGetStrict`); signatures are not checked |
| **NuGet framework selection** | Only assemblies the .NET Framework CLR can load are picked (`net4x` up to the installed Framework, then `netstandard1.0`-`2.0`, then `net35`; never `net5.0`+ / `netstandard2.1`); no version means "latest that works here"; `CS.NuGet.Search(query)` hides packages with nothing usable |
| **CS.LoadAssembly() / CS.CreateObject()** | Use types from any .NET DLL |
| **proxy.On() / CS.Delegate()** | Subscribe to .NET events with real event objects; static events through the type (`CS.System.Console.On("CancelKeyPress", fn)`) |
| **out / ref parameters** | `CS.System.Int32.TryParse("12", &n)` sets `n`; `ref` parameters read and write the variable back |
| **Async / Promise** | ThreadPool work with JavaScript-style promises: `.Then` / `.Catch` / `.Finally` chains (each returns a new promise), `.Timeout(ms, cts)`, `.Await(timeoutMs)`, `CS.Promise.All` / `Race` / `Delay` / `AwaitAll` / `AwaitAny`; .NET failures keep `e.NetType` / `CS.ErrorIs` |
| **Awaitable Tasks** | Any .NET `Task` proxy has `.Await(timeoutMs)` / `.Then` / `.Catch` / `.Finally` / `.Timeout`: `client.GetStringAsync(url).Await(15000)` |
| **Worker-thread callbacks** | AHK functions called from .NET pool threads (`Task.Run(fn)`, timers) run on the AHK thread while it pumps messages |
| **CS.Implement()** | Implement a .NET interface with AHK functions: `CS.Implement(CS.System.Collections.IComparer, Map("Compare", fn))` |
| **CS.Members / CS.Types** | discover a type's or namespace's contents from AHK; typos in names get a `Did you mean ...?` |
| **Editor autocomplete** | `CS.Declare("System.IO", ...)` writes `ahk#.d.ahk`: completion, hover and signature help for .NET types in VS Code with the AutoHotkey v2 language server ([Editor Support](docs/21_editor_support.md)) |
| **CS.Explain / Trace / Wrap** | `CS.Explain` shows how an overload is chosen; `CS.Config.Trace` logs every call with timing; `CS.Wrap` writes an AHK class for a .NET type |
| **Hot reload** | `MyModule.Reload(source)` / `MyModule.Watch(path)` recompile a `_CSModule` when its `.cs` file changes |
| **Integrity check** | `Boot()` refuses a bridge DLL (also one loaded through `CS.Config.BridgeDll`) whose SHA-256 differs from the one pinned in `ahk#.ahk` |
| **CS.Fast** | `Map` / `Filter` (parallel, order kept) and `Reduce` (sequential) over AHK arrays |
| **Bulk marshaling** | Integer / Float / String arrays cross as typed arrays; `ToAHK()`, `ToBuffer()`, `FromBuffer()` |
| **CS.ModuleRef()** | Cross-module references between CSModules |
| **CS.GC()** | Garbage collection and memory information |
| **CSVersion** | Target C# 5.0 up to 12.0 / `"latest"` via an auto-downloaded Roslyn compiler (records, `init`, switch expressions, raw strings, ...); syntax only, the code still runs on the .NET Framework 4 CLR |
| **Precompile** | Export compiled DLLs so end users need no compiler |
| **Extensions** | SQLite (UTF-8), HTTP/JSON, IPC, native UI, UIA (bulk crawl to `UIAElement` arrays) and a screen-region text watcher in `ext\` (you supply the OCR function; AHK# ships none) |

## Quick Start

1. Clone or download this repository.
2. Run an example: `AutoHotkey64.exe examples\basics\hello_dotnet.ahk`
3. The bridge DLL `lib\ahk#.bridge.dll` is **committed**, so nothing is built on a normal first run.
   If the DLL is missing, `Boot()` runs `lib\build.ps1` for you (this needs `csc.exe` from the .NET Framework 4.x that ships with Windows).
   Set the environment variable `AHKSHARP_DEV=1` to make every start run `build.ps1` (it hashes `src\*.cs`, so it is a no-op when nothing changed).
   Rebuild by hand with `powershell -File lib\build.ps1 -Force`.
   Every build writes the DLL's SHA-256 into `AHK_SHARP_BRIDGE_SHA256` in `lib\ahk#.ahk`, and `Boot()` refuses a DLL that does not match ([Security](docs/19_security.md)).

### Including the library

The include path is relative to the script that contains the `#Include` line:

```autohotkey
#Include lib\ahk#.ahk               ; script sits in the repository root
#Include ..\..\lib\ahk#.ahk         ; script two folders down, as every script in examples\ does
#Include ..\..\ext\ahk#.sqlite.ahk  ; optional extensions, same idea
```

`#Include <ahk#>` (the form shown in the header comment of `lib\ahk#.ahk`) only works if the folder that holds `ahk#.ahk` is on AutoHotkey's Lib search path (`<script folder>\Lib`, `Documents\AutoHotkey\Lib` or the `Lib` folder of the AutoHotkey install). `ahk#.bridge.dll` and `build.ps1` must then sit next to `ahk#.ahk` in that folder, because the library looks for the DLL next to itself. Most people should use a relative path instead.

## Requirements

- **AutoHotkey v2.0+**
- **Windows 7 SP1+** with .NET Framework 4.0+ (built into Windows 10/11)
- No admin rights, Visual Studio or NuGet CLI needed
- The CLR takes the bitness of the AutoHotkey exe you run (32- or 64-bit); native DLLs you call must match it

## Architecture

```
AHK Process
  └─ lib\ahk#.ahk  _AhkSharpEngine.Boot()
       ├─ mscoree!CorBindToRuntimeEx("v4.0.30319")  → ICorRuntimeHost → default AppDomain
       ├─ Assembly.Load(byte[])                     ← lib\ahk#.bridge.dll read from disk
       └─ CreateInstance("AhkSharpBridge")          → COM-visible singleton, called via IDispatch
            ├─ TypeResolver     name → System.Type (resolved up front, misses cached, generics from any assembly)
            ├─ OverloadBinder   cost-based overload choice (src\bridge\OverloadBinder.cs)
            ├─ MarshalEngine    CLR ↔ COM values, typed-array bulk transfer
            ├─ RuntimeCompiler  CSharpCodeProvider / Roslyn, on-disk compile cache
            ├─ ErrorInfo        records the .NET exception behind an AHK error (e.NetType ...); MemberCache decides .NET member vs helper
            ├─ AsyncRouter      ThreadPool / .NET Task → PostMessage(WM_APP+1) → Promise
            ├─ FastParallel     CS.Fast lambdas (PLINQ)
            ├─ NuGetManager     package + dependency install, SHA-512 check, Roslyn download; FrameworkPicker (usable target frameworks), NuGetSearch
            ├─ Discovery / MemberHints  CS.Members / CS.Types, "Did you mean ...?"
            ├─ Declarations     CS.Declare: the ahk#.d.ahk editor declaration file
            ├─ DelegateBridge   event queue → PostMessage(WM_APP+2) → AHK thread
            ├─ AhkCallback      AHK function → .NET delegate; from worker threads queued → PostMessage(WM_APP+3)
            ├─ AhkInterfaceProxy CS.Implement: a .NET interface implemented by AHK functions (RealProxy, src\bridge\Extras.cs)
            ├─ WrapperGenerator CS.Wrap: AHK class source for a .NET type (Extras.cs)
            └─ ValueBox         keeps structs and arrays as real references
```

`src\bridge\` holds one file per concern (`AhkSharpBridge.cs` is the COM entry class); the C# behind the extensions is in `src\ext\`. Details: [Architecture](docs/16_architecture.md).

## Performance

Measured on this project's development machine (your numbers will differ; run `examples\benchmarks\` to measure yours):

| Operation | Measured |
|-----------|----------|
| Cached .NET method call | about 7–12 µs |
| Property get | about 5 µs |
| COM transport floor (one bare call) | about 1.7 µs |
| Send a 10,000-integer AHK Array to .NET | about 6 ms (was 73 ms) |
| Read a 10,000-element `List<int>` into an AHK Array | about 3 ms (was 23 ms) |
| `Boot()` (first call) | about 100 ms |

The overload choice is cached per argument-type signature. The two benchmark scripts are in-process comparisons: they warm up first, report the median of several runs and check that both sides return the same result. They compare AHK with the same work done inside one .NET call, so they show what moving a loop into .NET buys you, not what a single bridge call costs.

## Limitations

- .NET Framework 4.x only (CLR v4.0.30319); .NET 5+/Core assemblies cannot be loaded.
- C# 4.0 by default; `static CSVersion := "5.0"` … `"12.0"` / `"latest"` uses an auto-downloaded Roslyn compiler. That changes the syntax only: the code still runs on the .NET Framework 4 CLR, so `Span<T>`, `System.Index` / `Range` (`^1`, `..`), default interface members and async streams do not work, and NuGet packages that only target net5.0+ are refused.
- The AppDomain cannot be unloaded; compiled and loaded assemblies stay until the process exits.
- AHK callbacks (functions passed to .NET) always run on the AHK thread. From a .NET worker thread the call is queued and needs the AHK thread to be pumping messages; if the AHK thread is blocked in a synchronous .NET call that waits for the workers (`Task.Run(fn).Wait()`, `Parallel.ForEach`) the worker gets a `TimeoutException` after `CS.Config.CallbackTimeoutMs` (5000 ms). Use `.Async` + `Await()` instead ([Async/Await](docs/04_async.md)).
- Generic **methods** are inferred from the arguments only (no explicit type arguments).
- `out` / `ref` parameters are supported through `&var` on **method calls** (static and instance), not on constructors, `.Async` calls or `_CSModule` methods.
- Async completion, events and worker-thread callbacks need AHK's message pump (`Sleep`, a GUI, a hotkey, a timer or `Await`).

## Documentation

| Doc | Topic |
|-----|-------|
| [Getting Started](docs/01_getting_started.md) | Installation, first script, project layout, limitations |
| [CS Namespace](docs/02_cs_namespace.md) | Static calls, properties, constructors, generics, overloads |
| [CSModule](docs/03_csmodule.md) | Embedded C# paradigm |
| [Async/Await](docs/04_async.md) | Promises: chaining, `All` / `Race`, timeouts and cancellation, parallel computation |
| [NuGet](docs/05_nuget.md) | Package management, framework selection, `CS.NuGet.Search` |
| [CS.Eval](docs/06_eval.md) | One-liner expressions |
| [Delegates](docs/07_delegates.md) | Event subscription |
| [HTTP/JSON](docs/08_http_json.md) | Built-in HTTP client |
| [CS.Import](docs/09_import.md) | Namespace aliasing |
| [Cross-Module](docs/10_cross_module.md) | Module references |
| [GC & Memory](docs/11_gc.md) | Garbage collection |
| [Precompile](docs/12_precompile.md) | Distribution workflow |
| [Version Targeting](docs/13_version_targeting.md) | C# 5.0 - 12.0 / latest, the Roslyn compilers, what runs on the .NET Framework 4 CLR |
| [Extensions](docs/14_extensions.md) | SQLite, HTTP/JSON, IPC, UI, UIA, Spatial (bring your own OCR) |
| [API Reference](docs/15_api_reference.md) | Complete API |
| [Architecture](docs/16_architecture.md) | Internal design and performance |
| [Marshaling](docs/17_marshaling.md) | How values convert in both directions |
| [Troubleshooting](docs/18_troubleshooting.md) | Common errors and fixes |
| [Security](docs/19_security.md) | What AHK# loads and runs, what is verified (bridge hash, NuGet SHA-512) and what is not |
| [Testing](docs/20_testing.md) | Running the test suites, the docs lint, writing your own |
| [Editor Support](docs/21_editor_support.md) | `CS.Declare`: completion, hover and signature help for .NET types in VS Code |
| [CHANGELOG](CHANGELOG.md) | What changed since 1.0.0, including breaking changes |
| [CONTRIBUTING](CONTRIBUTING.md) | Repository layout, building the bridge, the C# 4.0 rule, tests |

## Tests

`tests\` holds a TAP-style harness and the suites: `test_abstractions`, `test_advanced`, `test_async_events`, `test_binder`, `test_extensions`, `test_features`, `test_marshaling`, `test_modules`, `test_net_modern` (C# 9-12 syntax through Roslyn, NuGet framework selection and search: needs the network, so it only runs with `AHKSHARP_NET=1`), `test_spatial` and `test_stress` (a leak / soak suite: proxy churn, 100,000 calls, delegate churn, 500 concurrent async calls, worker-thread callbacks, a 10 MB string, a 1,000,000-element array, an exception storm, cache growth). Each suite runs in its own AutoHotkey process, and error dialogs become text, so a broken test cannot hang a run:

```powershell
powershell -File tests\run_tests.ps1                      # all suites; exit code = number of failures
powershell -File tests\run_tests.ps1 -Filter binder       # only suites whose file name contains "binder"
$env:AHKSHARP_NET = "1"; powershell -File tests\run_tests.ps1   # also the network tests (Http, NuGet) and test_net_modern (downloads the Roslyn toolset)
powershell -File tests\lint_docs.ps1                      # documentation drift: broken links, missing paths, unknown CS.<Member> names
```

`tests\lint_docs.ps1` checks `README.md` and `docs\*.md` against the repository and `lib\ahk#.ahk`; its exit code is the number of problems. `.github\workflows\tests.yml` runs the suites on a Windows runner (written, but not yet exercised on GitHub). See [Testing](docs/20_testing.md) for the harness API and how to write tests, and [CONTRIBUTING](CONTRIBUTING.md) for building and adding tests.

## Developer Playground & Studio

[ahk#_playground.ahk](ahk%23_playground.ahk) (repository root) is a GUI companion for exploring AHK#. Run it with `AutoHotkey64.exe ahk#_playground.ahk`. It has 10 tabs:

| Tab | What it does |
|-----|--------------|
| 1 Examples | Browse the scripts in `examples\` and launch them |
| 2 Scratchpad | Run C# Expression / C# Class / AHK Script code. **F5** or **Ctrl+Enter** runs, run history, saved snippets, C# version selector, **Export as CSModule .ahk** |
| 3 Type Explorer | Reflection-based .NET member inspector and snippet generator |
| 4 NuGet | Search, install and uninstall packages |
| 5 Precompiler | Compile CSModule source and export DLLs |
| 6 Cache | Inspect, delete and clean the compiled DLL cache |
| 7 CLR Monitor | Managed heap, GC counters, loaded assemblies |
| 8 Marshalling | See how AHK values map to .NET objects |
| 9 Overloads | Predict which C# overload an AHK call resolves to |
| 10 Wrapper Gen | Generate AHK wrappers and IntelliSense (`.d.ahk`) for any assembly |

Settings, history and snippets are stored in `%AppData%\AHKSharp\workbench.ini`. The helper sources live in [workbench/](workbench/).

## Examples

[examples/](examples/) contains **47** scripts (`.ahk` files, not counting the vendored libraries in `examples\benchmarks\lib_bench`). Each one includes the library with `#Include ..\..\lib\ahk#.ahk` (some also include `..\..\ext\...`), so run them from wherever you like.

### Basics
| Example | Description |
|---------|-------------|
| [hello_dotnet.ahk](examples/basics/hello_dotnet.ahk) | Basic CLR interop: static calls, constructors, fluid chaining |
| [csmodule.ahk](examples/basics/csmodule.ahk) | The `_CSModule` base class |
| [cs_eval.ahk](examples/basics/cs_eval.ahk) | One-liner `CS.Eval()` expressions |
| [collections.ahk](examples/basics/collections.ahk) | .NET generic collections |
| [import_namespaces.ahk](examples/basics/import_namespaces.ahk) | Namespace aliasing (`CS.Import`) |

### Core Features
| Example | Description |
|---------|-------------|
| [async.ahk](examples/features/async.ahk) | Async/Await and parallel tasks |
| [cs_fast.ahk](examples/features/cs_fast.ahk) | `CS.Fast` Map / Filter / Reduce over AHK arrays |
| [delegate_events.ahk](examples/features/delegate_events.ahk) | Event subscriptions and callbacks |
| [implement_and_tasks.ahk](examples/features/implement_and_tasks.ahk) | `out` parameters (`&var`), awaitable .NET Tasks, `CS.Implement`, worker-thread callbacks, `CS.Explain` |
| [promise_chains.ahk](examples/features/promise_chains.ahk) | `Then` / `Catch` / `Finally` chains, `Timeout` with cancellation, `AwaitAny` / `AwaitAll`, typed errors |
| [editor_and_discovery.ahk](examples/features/editor_and_discovery.ahk) | `CS.Types`, `CS.Members`, "did you mean" hints, `CS.Declare` for editor autocomplete |
| [ipc.ahk](examples/features/ipc.ahk) | Memory-mapped inter-process communication |
| [precompile.ahk](examples/features/precompile.ahk) | Developer to distribution workflow |
| [nuget_json.ahk](examples/features/nuget_json.ahk) | Using `CS.NuGet` to load packages |
| [load_assembly.ahk](examples/features/load_assembly.ahk) | `CS.LoadAssembly` and `CS.CreateObject` with a compiled DLL |
| [cross_module.ahk](examples/features/cross_module.ahk) | Module inter-dependencies |
| [version_targeting.ahk](examples/features/version_targeting.ahk) | Targeting specific C# compiler versions |
| [gc_memory.ahk](examples/features/gc_memory.ahk) | Manual garbage collection |

### Practical Tools
| Example | Description |
|---------|-------------|
| [excel_reader.ahk](examples/tools/excel_reader.ahk) | XLSX read/write without Excel or COM (System.IO.Packaging) |
| [profiler.ahk](examples/tools/profiler.ahk) | Live script profiler: timing, memory tracking, comparison tables |
| [regex_workbench.ahk](examples/tools/regex_workbench.ahk) | Live .NET Regex tester |
| [crypto_toolkit.ahk](examples/tools/crypto_toolkit.ahk) | Hashing, Base64 and UUIDs via System.Security.Cryptography |
| [file_analyzer.ahk](examples/tools/file_analyzer.ahk) | File hashes, metadata and hex preview |
| [file_searcher.ahk](examples/tools/file_searcher.ahk) | Parallel regex file search (`Parallel.ForEach`) |
| [zip_archiver.ahk](examples/tools/zip_archiver.ahk) | Creating and extracting zip files (System.IO.Compression) |
| [zip_explorer.ahk](examples/tools/zip_explorer.ahk) | Explorer-style zip viewer with extract and create |
| [image_processor.ahk](examples/tools/image_processor.ahk) | Parallel image resizer / converter (drop files on the GUI) |

### System & Hardware
| Example | Description |
|---------|-------------|
| [toast_notifications.ahk](examples/system/toast_notifications.ahk) | Windows toast-style notifications via NotifyIcon |
| [file_watcher.ahk](examples/system/file_watcher.ahk) | FileSystemWatcher events polled from the AHK thread |
| [sysinfo_dashboard.ahk](examples/system/sysinfo_dashboard.ahk) | Live system dashboard (CPU, RAM, drives, processes) |
| [xinput_gamepad.ahk](examples/system/xinput_gamepad.ahk) | XInput gamepad reading (P/Invoke to xinput1_4.dll) |
| [wmi_hardware.ahk](examples/system/wmi_hardware.ahk) | WMI hardware and system querying |
| [uia_inspector.ahk](examples/system/uia_inspector.ahk) | UIAutomation tree crawling and element inspection |
| [pe_inspector.ahk](examples/system/pe_inspector.ahk) | Lists the named exports of any PE32 / PE32+ DLL (reads headers only) |
| [memory_bridge.ahk](examples/system/memory_bridge.ahk) | Process memory scanner ("mini Cheat Engine"). **For your own / authorized processes only** |
| [memory_target_mock.ahk](examples/system/memory_target_mock.ahk) | Harmless target process for `memory_bridge.ahk` (does not use AHK#) |
| [frida_process_explorer.ahk](examples/system/frida_process_explorer.ahk) | Frida process explorer. **Needs the frida-clr DLL; for your own / authorized processes only** |
| [frida_browser_hook.ahk](examples/system/frida_browser_hook.ahk) | Frida browser hook. **Needs the frida-clr DLL; for your own / authorized processes only** |

`memory_bridge.ahk` and the two `frida_*.ahk` scripts read, modify or instrument **other processes**. Use them only on software you own or are explicitly authorized to debug; doing it to games or browsers can break their terms of service and trips anti-cheat systems. The Frida scripts also need the `frida-clr-*-windows-x86_64.dll` bindings, which are not in this repository: see the header of each script (set `FRIDA_CLR_DLL` or put the DLL in `deps\`). See [Security](docs/19_security.md).

### Network & Web
| Example | Description |
|---------|-------------|
| [http_api_client.ahk](examples/network/http_api_client.ahk) | HTTP requests with `Http` / `Json` |
| [async_web_api.ahk](examples/network/async_web_api.ahk) | A non-blocking Web API served from AHK on `http://localhost:8080/` |
| [websocket_server.ahk](examples/network/websocket_server.ahk) | Two-way WebSocket server (port 8181) |

### Showcase Demos
| Example | Description |
|---------|-------------|
| [mandelbrot.ahk](examples/showcase/mandelbrot.ahk) | Parallel Mandelbrot explorer (`Parallel.For`) |
| [physics_engine.ahk](examples/showcase/physics_engine.ahk) | 2D physics rendered with System.Drawing into a Picture control |
| [full_stack.ahk](examples/showcase/full_stack.ahk) | Several AHK# modules combined in one script |
| [sqlite.ahk](examples/showcase/sqlite.ahk) | SQLite manager: tables, CRUD, transactions, queries |
| [native_ui.ahk](examples/showcase/native_ui.ahk) | WinForms DataGridView / RichTextBox inside an AHK Gui |
| [uia_sqlite_combo.ahk](examples/showcase/uia_sqlite_combo.ahk) | UIA crawl stored in SQLite, analyzed with a CSModule |

### Benchmarks
| Example | Description |
|---------|-------------|
| [speed_benchmark.ahk](examples/benchmarks/speed_benchmark.ahk) | Native AHK vs .NET on 17 tasks: warm-up, median of 3 runs, result check per test |
| [ecosystem_benchmark.ahk](examples/benchmarks/ecosystem_benchmark.ahk) | Vendored community AHK libraries vs .NET equivalents (third-party code lives in `lib_bench\`, see its `NOTICE.md`) |
