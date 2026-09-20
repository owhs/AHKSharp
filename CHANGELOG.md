# Changelog

All notable changes to AHK# are recorded here, in the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) style. The baseline is the `1.0.0` commit. Items marked **BREAKING** can break a script written against 1.0.0; the fix is in the item.

## [2.0.0] — 2026-09-20 — changes since 1.0.0

### Breaking changes at a glance

- `UIA2.CrawlTree` / `UIA2.Find` return an ordinary **1-based AHK Array** of `UIAElement` objects (not a raw 0-based COM array); `UIA2.FromPoint` / `Focused` return a `UIAElement` or `""`. Replace `elements[A_Index - 1]` with `for el in elements`.
- `SharedMemory.ReadBytes()` returns an AHK **Buffer** (it used to return the raw byte SafeArray).
- A `DateTime` that .NET returns is an **AHK timestamp** (`YYYYMMDDHH24MISS`), no longer a locale-format string.
- Any other .NET **struct** result (`Point`, `Rectangle`, `Color`, `CancellationToken`, `KeyValuePair`, ...) is a usable **proxy**, no longer its `ToString()` text.
- Arrays returned by .NET are **references** (a proxy of the real array), no longer by-value copies.
- `CS.Fast.Map` / `Filter` return **AHK Arrays** (1-based).
- `.On()` handlers receive **event objects** (`(e, sender)`), no longer strings.
- A `_CSModule` that does not compile, and a NuGet install that fails, now **throw**.
- Proxy helper members (`ToAHK`, `On`, `Type`, `Dispose`, ...) **no longer shadow** .NET members of the same name; `ToString(args*)` is now just the .NET `ToString`.
- `promise.Then(f)` returns a **new** promise (JavaScript semantics), no longer the promise it was called on. Code that relied on `p.Then(f)` returning `p` must keep a reference to `p` (`p := ...Async.X()`, then `p.Then(f)`); `p.Then(f).Await()` now returns what `f` returned. An error thrown inside a `Then` callback is no longer an immediate dialog: it rejects the derived promise and, if nothing observes it, is reported as an ordinary AHK error 100 ms later.
- NuGet no longer picks `net5.0`+, `netcoreapp` or `netstandard2.1` folders (it used to fall back to "any folder with DLLs"), and `CS.NuGet.Install` / `Require` **without a version** now resolve "the newest release that works here", which can be older than the newest on nuget.org. A package with assemblies but none this runtime can load throws a `NotSupportedException` naming what it offers.

### Added

Language surface

- **Typed .NET exceptions.** An AHK `Error` raised from a .NET failure carries `e.NetType` (full type name), `e.NetBases` (base-class names, nearest first), `e.NetStack` (the throw-site frames) and `e.NetHResult`. `CS.ErrorIs(e, "IOException")` is true for the type, its short name and any base class.
- **`out` / `ref` parameters** with `&var` on static and instance method calls: `CS.System.Int32.TryParse("12", &n)`.
- **Awaitable .NET Tasks:** a `Task` proxy has `.Await(timeoutMs)`, `.Then(cb)`, `.Catch(cb)` and `.ToPromise()`, plus `.Finally(fn)` and `.Timeout(ms, cts)`. A pool call (`.Async`) that returns a Task now waits for it and gives its result.
- **AHK functions on .NET worker threads** (`Task.Run(fn)`, timers, pool threads calling a `CS.Implement` object): the call is queued and runs on the AHK thread while it pumps messages; `CS.Config.CallbackTimeoutMs` (default 5000) bounds the wait and a blocked AHK thread gives a clear `TimeoutException` instead of a hang.
- **`CS.Implement(iface, handlers)`:** a .NET interface (or `MarshalByRefObject` class) implemented with AHK functions.
- **`CS.Run(statements)`** runs a multi-statement C# body and returns what it `return`s (falling off the end gives `""`); compile errors are prefixed `CS.Run`.
- **`CS.CallGeneric(typeOrProxy, "Method", typeArgs, args*)`** for explicit generic type arguments (`Enumerable.Empty<int>()`, `Activator.CreateInstance<T>()`); a wrong number of type arguments reports `No generic overload ...`.
- **Static events:** `CS.System.Console.On("CancelKeyPress", fn)` / `.Off(...)` on a type (a .NET static member named `On` / `Off` wins).
- **Identity and lifetime:** `CS.Same(a, b)`, `CS.Using(obj, fn)` (runs `fn(obj)`, then `Dispose`, even on error), `proxy.AutoDispose()` (dispose when the last AHK reference to that proxy is released), and `CS.Stats()` (`ManagedHeapBytes`, `Delegates`, `PendingAsyncTasks`, `ResolvedTypes`, `OverloadCacheEntries`, `BoundCallCacheEntries`, `QueuedCallbacks`).
- **`CS.Bool(value)`** passes a real .NET `bool` (AHK `true` / `false` are the integers `1` / `0` and choose integer overloads: `sb.Append(true)` → `"1"`, `sb.Append(CS.Bool(true))` → `"True"`).
- **`CS.ToAHK(x)` / `CS.ToBuffer(x)`**, function forms of the proxy helpers that can never clash with a .NET member.
- **`proxy._Invoke("Name", args*)`** always calls the .NET method; `CS.Explain(...)` / `proxy._Explain(...)` show how an overload is chosen; `CS.Config.Trace` logs every method call with timing; `CS.Wrap(typeName, outPath)` writes an AHK class that mirrors a .NET type.
- **Discovery and "did you mean":** `CS.Members(typeOrObject, filter)` lists what a type or object offers, `CS.Types(namespace, filter)` lists a namespace; a misspelled method, property, event, type or namespace (`CS.System.Math.Abss`, `.Lenght`, `CS.System.Tex.StringBuilder`) now ends with `Did you mean: ...?`, and an instance member used on the type (or the reverse) says so.
- **Multi-dimensional and multi-parameter indexers:** `matrix[row, col]`, read and write.
- **DateTime parameters** accept an AHK timestamp of 4, 6, 8, 10, 12 or 14 digits (`CS.System.DateTime.Compare("20200101", "20210101")`, `A_Now`). A `DateTime` created with a constructor stays a usable proxy.
- **`CS.LoadAssembly(path)` / `CS.CreateObject(type, asmPath)`** (added after the 1.0.0 tag); `CS.LoadAssembly("System.Net.Http")` falls back to `LoadWithPartialName` for names `Assembly.Load` refuses.
- **Module hot reload:** `Module.Reload(source)` (the old code keeps running if the new source does not compile) and `Module.Watch(path, onReload, intervalMs)`.
- **Promise chaining.** `promise.Then(onOk := "", onFail := "")` returns a new promise whose value is what the callback returns (a returned promise is followed); a throwing callback rejects it; a failure flows down the chain to the first `Catch` / `onFail`. New `promise.Finally(fn)` (runs either way, passes the outcome on), `promise.Timeout(ms, cancelSource := "")` (fails with `TimeoutError`; cancels a `CancellationTokenSource` proxy when given) and the same `Finally` / `Timeout` helpers on .NET Task proxies (used only when the .NET type has no member of that name). `IsComplete` / `Error` settle immediately: they ask the bridge instead of waiting for the completion message.
- **Promise combinators.** `CS.Promise.Resolve(v)`, `Reject(err)`, `Delay(ms, value)`, `All(...)` (Array of results, fails as soon as one input fails), `Race(...)`, and the blocking `AwaitAll(...)` (fails as soon as any input fails) and `AwaitAny(...)` (the first to settle). All accept promises, .NET Task proxies and plain values.
- **Typed async errors.** A failed .NET operation keeps its .NET identity around `Await` and in `Catch` / `onFail`: `e.NetType`, `e.NetBases`, `e.NetStack`, `e.NetHResult` and `CS.ErrorIs(e, "FormatException")` work (the `Await` message is still `Async operation failed: <Type>: <message>`).
- **Unhandled-error reporting for promises.** An error thrown by **your** callback that nothing observes (no `Catch` / `Then` / `Await` / `Error` read on the derived promise) is reported as an ordinary AHK error after 100 ms; a failed .NET task that nobody handles stays silent (`p.Error` / `p.Await()` report it).
- **NuGet framework selection** (`FrameworkPicker.cs`). Package folders and `.nuspec` dependency groups are ranked for the .NET Framework CLR: `net4x` up to the Framework installed on the machine (registry `Release`), then `netstandard1.0`-`2.0` (only when Framework 4.7.2+ is installed), then `net20`-`net35`; `net5.0`+, `netcoreapp` and `netstandard2.1` are never picked. A package with DLLs directly in `lib\` (old layout) now works. If a package has assemblies but none usable, `Install` throws a `NotSupportedException` such as `Aspire.Hosting 8.2.2 has no assemblies this runtime can load. It offers: net8.0. ...`.
- **`CS.NuGet.Search(query, take := 20, includeIncompatible := false)`** returns an Array of Maps (`Id`, `Version` = what `Require` would install, `Latest`, `Downloads`, `Description`) and hides packages with no usable version.
- **`CSVersion` up to `"12.0"` and `"latest"` / `"preview"`.** Up to `"10.0"` uses `microsoft.net.compilers` 4.0.1 as before; `"11.0"`, `"12.0"` and `"latest"` use `Microsoft.Net.Compilers.Toolset` 4.8.0 (about 20 MB, downloaded once into `%LocalAppData%\AhkSharp\Packages\microsoft.net.compilers.toolset\4.8.0\tasks\net472`, SHA-512 checked like any package; its `csc.exe` needs .NET Framework 4.7.2+, otherwise a `NotSupportedException` says so). For C# 9+ a private `IsExternalInit` marker type is added automatically when the source uses a `record` or `init`. Only syntax and compiler features work: the output still runs on the .NET Framework 4 CLR, so no `System.Index` / `Range`, `Span<T>`, default interface members, static abstract members or async streams. The version string must match `^[A-Za-z0-9.]{1,12}$` (`Invalid C# language version` otherwise).
- **`CS.Declare(specs*)`** writes `ahk#.d.ahk` next to `ahk#.ahk`: declarations of the .NET types or namespaces you name, which the AutoHotkey v2 language server (thqby.vscode-autohotkey2-lsp for VS Code) loads automatically for completion, hover (with the overload list) and signature help. Repeated calls add to the set; generic types and generic methods are not declared. See `docs\21_editor_support.md`.

Integrity

- **Bridge hash pin.** `lib\build.ps1` writes the DLL's SHA-256 into `AHK_SHARP_BRIDGE_SHA256` in `lib\ahk#.ahk`; `Boot()` refuses a DLL that does not match (`CS.Config.VerifyBridge`, `CS.Config.BridgeDll`; `AHKSHARP_DEV` skips the check while you rebuild).
- **NuGet integrity check.** Every downloaded `.nupkg` (dependencies and Roslyn included) is verified against the SHA-512 nuget.org publishes for that exact version (registration, then catalog entry, then `packageHash`). A mismatch deletes the file and throws. If the hash cannot be fetched it continues with a warning recorded in the NuGet status text, unless `CS.Config.NuGetStrict := true`. `CS.Config.VerifyNuGet := false` turns the check off. Package signatures and author trust are **not** checked, and the package's code still runs in-process.

Extensions

- **UIA:** `UIAElement` class with plain AHK properties (`Name`, `AutomationId`, `ClassName`, `ControlType`, `LocalizedControlType`, `ProcessId`, `NativeWindowHandle`, `BoundingX/Y/W/H`, `IsEnabled`, `IsOffscreen`, `Value`, `Depth`, `ChildCount`), built from one bulk COM call instead of one COM call per property.
- **SQLite:** `db.Query()` returns an Array of Map through **one** bulk COM call.
- **IPC:** `SharedMemory.WriteBytes(x)` accepts an AHK Buffer, a .NET `byte[]` proxy or a raw byte SafeArray.
- **Spatial:** `Spatial.Reader := (x, y, w, h) => text` (an `OCR` class with `Text(x, y, w, h)` is used if present), optional `Spatial.Parser := (text) => {...}` merged into the `Watch` callback object, `Spatial.OnError(e, id)` (default `OutputDebug`) and `Spatial.Count`.

Tests, tooling and documentation

- **`tests\`:** a TAP-style harness and the suites `test_abstractions`, `test_advanced`, `test_async_events`, `test_binder`, `test_extensions`, `test_features`, `test_marshaling`, `test_modules`, `test_net_modern`, `test_spatial` and `test_stress` (a leak / soak suite: proxy churn, 100,000 calls, delegate On/Off churn, 500 concurrent async calls, 200 worker-thread callbacks, a 10 MB string, a 1,000,000-element array, an exception storm, cache growth). `tests\test_net_modern.ahk` (C# 9-12 syntax through Roslyn, NuGet search and framework selection) downloads the Roslyn toolset and queries nuget.org, so `tests\run_tests.ps1` starts it only when `AHKSHARP_NET=1`. `tests\run_tests.ps1` runs each suite in its own process (`-Filter` selects suites), `tests\run-ahk.ps1` turns error dialogs into text, and `tests\lint_docs.ps1` is a documentation drift lint.
- `.github\workflows\tests.yml` runs the suites on a Windows runner (written, not yet exercised on GitHub).
- `lib\build.ps1` prints the compiler's warnings.
- Documentation: `docs\17_marshaling.md`, `docs\18_troubleshooting.md`, `docs\19_security.md`, `docs\20_testing.md`, `docs\21_editor_support.md`, this changelog and `CONTRIBUTING.md`.
- Examples: `cs_fast.ahk`, `implement_and_tasks.ahk`, `load_assembly.ahk`.

### Changed

- **BREAKING: UIA2 return types.** `CrawlTree` / `Find` return a 1-based Array of `UIAElement`; `FromPoint` / `Focused` return a `UIAElement` or `""` (they returned a raw 0-based COM array and COM proxies).
- **BREAKING: `SharedMemory.ReadBytes()` returns a Buffer.**
- **BREAKING: DateTime results are AHK timestamps** (`YYYYMMDDHH24MISS`, independent of the system locale; they work with `FormatTime`, `DateAdd`, `DateDiff`). Fractions of a second are dropped.
- **BREAKING: struct results stay proxies.** Any .NET struct returned from a call or property (`CancellationToken`, `Point`, `Rectangle`, `Size`, `Color`, `KeyValuePair`, ...) can be read and passed back to .NET. Only enums, `Guid`, `TimeSpan` and `DateTimeOffset` still come back as strings (the binder parses them back).
- **BREAKING: arrays returned by .NET are references.** `arr[i] := v`, `FromBuffer` and `Array.Sort(arr)` act on the real array (proxy indexes are 0-based; `ToAHK()` gives a 1-based copy).
- **BREAKING: `CS.Fast` returns AHK Arrays** (1-based) for `Map` and `Filter`.
- **BREAKING: `.On()` handlers receive event objects** (`(e, sender)` for `EventHandler`-shaped events, otherwise the delegate's own arguments), not strings. Events raised on any thread are queued and delivered on the AHK thread.
- **BREAKING: `_CSModule` compile errors throw** `CSModule 'Name' failed to compile: ...` (a diagnosis window is shown first unless `CS.Config.ShowErrorGui` is `false`); a misspelled module method or property throws instead of returning `""`.
- **BREAKING: NuGet failures throw.** `CS.NuGet.Install` / `Require` throw on failure (they returned an empty string); `Require` also throws when the package has no assembly usable from .NET Framework.
- **BREAKING: `Then` returns a new promise.** `p.Then(f)` no longer returns `p`; its value is `f`'s return value and a failure passes through it until a `Catch` / `onFail`. Keep your own reference to `p` if you call `p.Await()` or read `p.Error` afterwards. A `Then` / `Catch` callback that throws no longer raises an error dialog at that moment: it rejects the derived promise, and if nothing observes that promise the error is reported as an ordinary AHK error after 100 ms.
- **BREAKING (behaviour): NuGet picks only usable frameworks.** `net5.0`+, `netcoreapp` and `netstandard2.1` folders are never chosen, and the old "any folder that has DLLs" fallback is gone; dependency groups use the same ranking. With no version, `Install` / `Require` take the newest stable release whose `.nuspec` dependency groups target something this runtime can load (the newest 12 releases are examined), so "latest" can be older than nuget.org's latest.
- **`CSVersion` range.** `"5.0"` .. `"12.0"`, `"latest"`, `"preview"` (was `"5.0"` .. `"7.3"`); `"11.0"` and up use the Roslyn toolset 4.8.0.
- **`CS.Promise.AwaitAll` fails as soon as any input fails**, and accepts .NET Task proxies as well as promises.
- **BREAKING: proxy helper members no longer shadow .NET members.** `ToAHK`, `ToArray`, `ToBuffer`, `FromBuffer`, `ToPromise`, `Await`, `Then`, `Catch`, `Finally`, `Timeout`, `On`, `Off`, `Is`, `Dispose`, `AutoDispose` and the property helpers `Type`, `Raw`, `Members` are used only when the .NET object has no member of that name (checked and cached per type); `proxy._Invoke("Name", args*)` always forces the .NET call. `Async` is always AHK#'s.
- **BREAKING: `ToString(args*)` is removed** as an AHK# helper; `proxy.ToString(...)` is simply the .NET `ToString`, with any arguments.
- **The overload binder is cost-based and never lossy.** An exact type wins and a lossy conversion is rejected (`Math.Abs(-2.5)` is `2.5`, `Math.Max(3.7, 2)` is `3.7`); params arrays, optional parameters, LINQ extension methods and generic method inference work; the winner is cached per argument-type signature.
- **Bulk marshaling.** Integer / Float / String AHK Arrays cross as `long[]` / `double[]` / `string[]` in one memory copy, and typed arrays are read straight out of SafeArray memory.
- **SQLite:** text is UTF-8 in and out; NULL comes back as `""`; floats use the invariant culture.
- **Source layout:** `src\bridge\` is split by concern (`AhkSharpBridge.cs`, `OverloadBinder.cs`, `AhkCallback.cs`, `ValueBox.cs`, `Extras.cs`, `TypeResolver.cs`, `MarshalEngine.cs`, `RuntimeCompiler.cs`, `ErrorInfo.cs`, `AsyncRouter.cs`, `FastParallel.cs`, `NuGetManager.cs`, `DelegateBridge.cs`, and the newer `Discovery.cs`, `MemberHints.cs`, `Declarations.cs`, `FrameworkPicker.cs`, `NuGetSearch.cs`); there is no `Binder.cs` any more. `src\swarm\` was renamed `src\ext\` (`MemoryMappedIpc`, `NativeUi`, `PhantomSqlite`, `UiaDeepCrawler`).
- **Spatial no longer depends on `ASTparse` / `ASTgetErrors`**, and no longer requires an `OCR` class (you supply `Spatial.Reader`).

### Fixed

- **Wrong numeric overloads.** `Math.Abs(-2.5)` returned `2` (a lossy `Int32` overload was picked); the binder now rejects any conversion that loses information.
- **Swallowed .NET exceptions.** A .NET exception could come back to AHK as an object instead of an error; failures now throw an `Error` with the .NET message (and `NetType`, `CS.ErrorIs`).
- **`.Then` / `.Catch` never fired** when attached after the promise had already completed; they now fire, and several callbacks can be attached to one promise.
- **`for x in List<T>` crashed** (struct enumerators); iteration works for every `List<T>`, dictionaries and lazy sequences.
- **https failed.** The AHK host has no `app.config`, so .NET fell back to SSL3 / TLS 1.0; the bridge now enables TLS 1.2 (and 1.3 where the framework knows it) for the whole process.
- **`Json.Query` on arrays.** Numeric path segments step into arrays (`items.0.name`).
- **`Json.Build("k", "v", ...)`:** extra arguments pack into the trailing `object` parameter again.
- **SQLite text was mangled** (UTF-8 is now used in and out), and **bound text could be garbage**: parameters were not copied by SQLite and the managed buffer could be moved or freed. Parameters are now bound with `SQLITE_TRANSIENT` (SQLite copies them).
- **`SharedMemory` byte transfer:** `WriteBytes` now takes an AHK Buffer, a `byte[]` proxy or a raw byte SafeArray, and `ReadBytes()` returns a Buffer (see the breaking changes).
- **`DisposeObject` ignored a plain public `Dispose()`** on classes that do not implement `IDisposable`; `Dispose`, `CS.Using` and `AutoDispose` now dispose those too.
- **`Module.Watch` missed edits made within the same second** (it compared file timestamps, which have one-second resolution); it now compares content.
- **Spatial could never call its callback**, swallowed every error, and `Stop(id)` left the timer running; callbacks now fire, errors go to `Spatial.OnError`, and `Stop` cancels that watcher's timer.
- **`System.Net.Http.HttpClient` did not resolve** (the resolver now knows the full assembly name).
- **NuGet packages with DLLs directly in `lib\`** (older layout) are installed instead of being skipped, and `netstandard2.1` / `net5.0`+ assemblies are no longer loaded "because nothing else is there" (they could install and then fail at run time).
- **`Await` / `Then` / `Catch` races.** AHK may run a completion handler between any two lines of these functions, which could consume the bridge's result slot ("Unknown task") or lose a callback registered at that moment. Each now runs in a `Critical` section, so "is it done?" and "take the result / register the callback" are one uninterruptible step.

### Removed

- The legacy `AhkSharpEntry` start-up class and the `AHKSHARP_PTR` environment variable (the library boots the bridge through `CreateInstance("AhkSharpBridge")`).
- Four unused bridge methods: `CompileAndInvoke`, `UnloadModule`, `GetDelegateArgs` and `ObjectToString`.
- `src\bridge\Binder.cs` (its contents moved into `OverloadBinder.cs`, `AhkCallback.cs` and `ValueBox.cs`).
- The proxy `ToString(args*)` helper (use the .NET `ToString`).
- Spatial's dependency on `ASTparse` / `ASTgetErrors` and its (never implemented) "compile and execute the OCR'd code" behaviour.

### Security

- **Bridge integrity:** `Boot()` checks the bridge DLL's SHA-256 against the pin in `lib\ahk#.ahk` before loading it, whichever file it loads (default `lib\ahk#.bridge.dll` or `CS.Config.BridgeDll`). It is an integrity check, **not a signature**: anyone who can replace the DLL and edit `lib\ahk#.ahk` can re-pin. `CS.Config.VerifyBridge := false` and the `AHKSHARP_DEV` environment variable switch it off.
- **NuGet integrity:** downloads are verified against nuget.org's published SHA-512 (see "Added"). Signatures and author trust are not checked, and an already-installed package is not re-verified.
- **Roslyn toolset:** the `Microsoft.Net.Compilers.Toolset` package used for `CSVersion` 11+ is a NuGet download like the others: same SHA-512 check, no signature check, its `csc.exe` runs as a child process.
- **TLS 1.2 (1.3 where known)** is enabled for the whole process.
- `docs\19_security.md` lists what AHK# loads and runs and what is not verified: the compile cache and the NuGet / Roslyn files on disk are trusted by name, `CS.Eval` / `CS.Run` / `CS.Fast` lambdas / module sources are compiled and run as code, and `SharedMemory` has no authentication.
