# AHK# v2.0.0 — Complete API Reference

Include the library first: `#Include lib\ahk#.ahk` (relative to your script; see [Getting Started](01_getting_started.md)). Extensions live in `ext\` and are included after it.

## CS (Global Router)

| Member | Returns | Description |
|--------|---------|-------------|
| `CS.{Namespace}.{Type}` | type object | Any .NET type; names are case-insensitive |
| `CS.{Namespace}.{Type}.Method(args)` | value / proxy | Static call (overload-resolved) |
| `CS.{Namespace}.{Type}.Prop` / `.Prop := v` | value | Static property or field |
| `CS.{Namespace}.{Type}(args)` | proxy | Constructor. Struct results stay usable proxies |
| `CS.{Namespace}.Generic(T1, T2)(args)` or `CS.{Namespace}.Generic[T1, T2]()` (constructor arguments go in the last pair of parentheses) | proxy | Generic type; type arguments are type objects or full-name strings |
| `CS.{Namespace}.{Type}.Async.Method(args)` | `_CSPromise` | Static call on the ThreadPool |
| `CS.{Namespace}.{Type}.On(event, fn)` / `.Off(event := "")` | type object | Subscribe to / unsubscribe from a **static** .NET event (`CS.System.Console.On("CancelKeyPress", (e, sender) => ...)`); a .NET static member called `On` / `Off` wins ([Delegates](07_delegates.md#static-events)) |
| `CS("Type.Name")` | type object | Type from a string |
| `CS.Eval(expr, refs := "")` | any | Evaluate a C# expression ([CS.Eval](06_eval.md)) |
| `CS.Run(statements, refs := "")` | any | Compile and run a multi-statement C# body and `return` a value (falling off the end gives `""`); compile errors are prefixed `CS.Run` ([CS.Eval](06_eval.md#csrun)) |
| `CS.CallGeneric(typeOrProxy, method, typeArgs, args*)` | any | Call a generic method with **explicit** type arguments; `typeArgs` is one type object or an Array of them ([CS Namespace](02_cs_namespace.md#explicit-generic-arguments)) |
| `CS.Import(namespace)` | namespace / type object | Namespace alias |
| `CS.GC()` | | Force a full garbage collection |
| `CS.Memory()` | Integer | Managed heap size in bytes |
| `CS.Delegate(fn)` | `_CSDelegateRef` | Register an AHK function for events ([Delegates](07_delegates.md)) |
| `CS.ModuleRef(modules*)` | string | `;`-joined DLL paths of compiled modules |
| `CS.LoadAssembly(pathOrName)` | | Load a .NET DLL (file path) or assembly name; its types become resolvable. Throws on failure. A name that `Assembly.Load` refuses (`"System.Net.Http"`) falls back to `LoadWithPartialName` |
| `CS.CreateObject(type, asmPath := "")` | proxy | `CS(type)()`, loading `asmPath` first when given |
| `CS.Implement(iface, handlers)` | proxy | An object implementing a .NET interface (or a `MarshalByRefObject` class) with AHK functions; `handlers` is a Map or object literal of `name → function` ([Delegates](07_delegates.md#implementing-net-interfaces-with-csimplement)) |
| `CS.Explain(typeOrProxy, method, args*)` | string | Report of every overload of `method` for these arguments: cost, or `rejected`; `=>` marks the winner |
| `CS.Members(typeOrObject, filter := "")` | string | What can I call? One line per public member, sorted (`static double Abs(double value)`, `int Length { get; set; }`, `event ... Name`); `filter` is a case-insensitive name substring. Takes a type object, a type-name string or a proxy |
| `CS.Types(namespace, filter := "")` | string | Public types (`(static class)`, `(interface)`, `(enum)`, `(struct)` noted) and child namespaces (`Sub.*`) directly in a namespace, from the loaded framework assemblies plus any `CS.LoadAssembly` ones |
| `CS.Declare(specs*)` | string | Write `ahk#.d.ahk` next to `ahk#.ahk` (in `lib\`): an editor declaration file for the AutoHotkey v2 language server (completion, hover, signature help for .NET types). Each spec is a type name, a namespace name (every public non-generic top-level type in it) or a type / namespace object; repeated calls **add**. Returns the file's path ([Editor Support](21_editor_support.md)) |
| `CS.Wrap(typeName, outPath := "", className := "")` | string | AHK source of a class mirroring a .NET type; written to `outPath` (UTF-8) when given |
| `CS.ErrorIs(e, typeName)` | bool | Was this AHK error raised by that .NET exception type (full name, short name or any base class)? See [Error handling](#error-handling) |
| `CS.Stats()` | Map | The bridge's internal counters (heap, delegates, pending async tasks, caches ...); see [CS.Stats](#csstats) |
| `CS.Same(a, b)` | bool | Are two proxies the same .NET object? (proxies compare by AHK identity, so `a == b` is not the test) |
| `CS.Using(obj, fn)` | any | Run `fn(obj)`, then `Dispose` the object even if `fn` throws; returns `fn`'s value |
| `CS.Bool(value)` | COM bool | Pass a real .NET `bool`: `sb.Append(CS.Bool(true))` → `"True"`, while `sb.Append(true)` → `"1"` (AHK `true` / `false` are the integers `1` / `0` and choose integer overloads) |
| `CS.ToAHK(proxy)` / `CS.ToBuffer(proxy)` | Array or Map / Buffer | Function forms of `proxy.ToAHK()` / `proxy.ToBuffer()`; they can never clash with a .NET member |
| `&var` argument | | `out` / `ref` parameter of a static or instance method call: `CS.System.Int32.TryParse("12", &n)` ([Marshaling](17_marshaling.md#out-and-ref-parameters)) |
| `CS.Fast` | `_CSFast` | Parallel Map and Filter, sequential Reduce |
| `CS.NuGet` | `_CSNuGet` | NuGet package manager |
| `CS.Config` | `_CSConfig` | Global switches |
| `CS.Promise` | `_CSPromise` | Promise combinators: `CS.Promise.Resolve` / `Reject` / `Delay` / `All` / `Race` / `AwaitAll` / `AwaitAny` ([_CSPromise](#_cspromise-async-result)) |

Aliases without the underscore: `CSProxy`, `CSModule`, `CSPromise`, `CSFast`, `CSType`, `CSNamespace`, `CSNuGet`, `CSConfig`, `CSDelegate`, and `AHKSharp` (same as `CS`).

## CS.Config (`_CSConfig`)

| Setting | Default | Description |
|---------|---------|-------------|
| `CS.Config.ShowErrorGui` | `true` | Show the diagnosis window on a `_CSModule` compile error (it waits until closed). `false`: throw only |
| `CS.Config.NuGetGui` | `true` | Show the NuGet progress window. `false` for headless / scheduled scripts |
| `CS.Config.Trace` | `""` | A function `(line) => ...` called for every .NET **method call** made through a type or proxy, with the arguments, result and timing: `System.Math.Abs(-3) => 3  [12.3 us]`. Failures are logged with `ERROR`. `""` turns tracing off. Property reads and writes are not traced |
| `CS.Config.VerifyBridge` | `true` | Check the bridge DLL's SHA-256 against `AHK_SHARP_BRIDGE_SHA256` in `ahk#.ahk` and refuse a mismatch. `false` disables the check ([Security](19_security.md)) |
| `CS.Config.BridgeDll` | `""` | Load the bridge from this path instead of `lib\ahk#.bridge.dll` (for example the copy a compiled script extracts with `FileInstall`, [Precompile](12_precompile.md)). The hash pin **is** checked for that file too (unless `VerifyBridge` is `false` or `AHKSHARP_DEV` is set), so it must be the very DLL that belongs to this `ahk#.ahk` |
| `CS.Config.VerifyNuGet` | `true` | Check every downloaded `.nupkg` against the SHA-512 nuget.org publishes for that exact version; a mismatch deletes the file and throws. `false` turns the check off ([NuGet](05_nuget.md#integrity-check)) |
| `CS.Config.NuGetStrict` | `false` | Also fail when that hash cannot be fetched. By default an unverifiable package is installed anyway, with the verdict recorded only in the bridge's NuGet status text (`_AhkSharpEngine.Boot().NuGetStatus()`) |
| `CS.Config.CallbackTimeoutMs` | `5000` | How long a .NET worker thread waits for the AHK thread to run one of your functions before it gets a `TimeoutException` ([Async](04_async.md#ahk-functions-on-net-worker-threads)). Takes effect immediately, also after start-up |

Set `ShowErrorGui` and `NuGetGui` to `false` before the module classes are defined in scripts that run unattended. `VerifyBridge` and `BridgeDll` are read once when the runtime starts (the first `CS` call), so set them at the top of the script. `VerifyNuGet` and `NuGetStrict` are read on every `CS.NuGet.Install` / `Require` call.

```autohotkey
CS.Config.Trace := (line) => OutputDebug(line)      ; e.g. see the calls in DebugView
CS.System.Math.Abs(-3)                              ; → "System.Math.Abs(-3) => 3  [12.3 us]"
CS.Config.Trace := ""                               ; off
```

## _CSModule

```autohotkey
class MyMod extends _CSModule {
    static CSharp := '...'
}
```

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `CSharp` | string | `""` | C# source code (required unless `PrecompiledDLL`) |
| `References` | string | `""` | Assembly references (`;`-separated names or paths) |
| `CSVersion` | string | `""` | C# language version: `"5.0"`–`"12.0"`, `"latest"` or `"preview"`; needs Roslyn (auto-downloaded). Up to `"10.0"`: `microsoft.net.compilers` 4.0.1; `"11.0"` and up: `Microsoft.Net.Compilers.Toolset` 4.8.0 (about 20 MB, needs .NET Framework 4.7.2+). Syntax only, the code still runs on the .NET Framework 4 CLR ([Version Targeting](13_version_targeting.md)) |
| `PrecompiledDLL` | string | `""` | Path to a precompiled DLL (skips compilation) |

| Member | Returns | Description |
|--------|---------|-------------|
| `Module.Method(args)` | any | Call a public C# method. Overloads work. Instance methods run on one persistent instance per module |
| `Module.Member` | any | Read a public static (or instance) field / property. A misspelled name throws |
| `Module.Async.Method(args)` | `_CSPromise` | Call on the ThreadPool |
| `Module.Precompile(path)` | | Copy the compiled DLL for distribution |
| `Module.Reload(csharpSource)` | | Recompile the module from new C# source. If it does not compile the old code is kept and `CSModule 'Name' reload failed: ...` is thrown; the module's instance state starts fresh |
| `Module.Watch(path, onReload := "", intervalMs := 500)` | timer function | `Reload` whenever the content of the `.cs` file at `path` changes; `onReload(ok, message)` is called after each attempt. `SetTimer(fn, 0)` stops watching ([CSModule](03_csmodule.md#hot-reload)) |

A compile error throws `CSModule 'Name' failed to compile: ...` (after showing the diagnosis window unless `CS.Config.ShowErrorGui` is `false`). `CSharp` is wrapped into `public class <Name> { ... }` unless it has a line starting with (modifiers and) `class Name`; then it is a complete file ([CSModule](03_csmodule.md#basic-usage), [Version Targeting](13_version_targeting.md#the-source-is-wrapped-unless-it-is-a-whole-file)).

## _CSProxy (Object Wrapper)

**.NET always wins.** The AHK# helper members in the second half of this table (`ToAHK`, `ToArray`, `ToBuffer`, `FromBuffer`, `ToPromise`, `Await`, `Then`, `Catch`, `Finally`, `Timeout`, `On`, `Off`, `Is`, `Dispose`, `AutoDispose`, and the property helpers `Type`, `Raw`, `Members`) are used **only when the .NET object has no public instance member of that name** (checked and cached per type). A .NET `Type` property or `On()` method behaves exactly as .NET defines it. `proxy._Invoke("Name", args*)` always forces the .NET call, and `CS.ToAHK(x)` / `CS.ToBuffer(x)` never clash. `Async` is the one name that is always AHK#'s.

| Member | Returns | Description |
|--------|---------|-------------|
| `proxy.Method(args)` | any | Instance method; falls back to LINQ extension methods on any `IEnumerable` |
| `proxy.Property` / `proxy.Property := v` | any | Property or field |
| `proxy[index]` / `proxy[index] := v` | any | Indexer; arrays and lists use 0-based .NET indexes; dictionaries take a key |
| `proxy[i, j]` / `proxy[i, j] := v` | any | Multi-dimensional array (`int[,]`) or an indexer with several parameters; reading and writing. A wrong index count throws |
| `proxy.Method(args)` with `&var` arguments | any | `out` / `ref` parameters: the variable is filled after the call (`d.TryGetValue("a", &v)`) |
| `proxy.Async.Method(args)` | `_CSPromise` | Instance call on the ThreadPool. If the method returns a Task, the promise's value is the task's **result** |
| `task.ToPromise()` | `_CSPromise` | For a proxy holding a `System.Threading.Tasks.Task`: a promise that completes when the task does (throws for anything else) |
| `task.Await(timeoutMs := 0)` | any | `task.ToPromise().Await(timeoutMs)`; a faulted task throws with the real .NET error |
| `task.Then(onOk := "", onFail := "")` / `task.Catch(onFail)` | `_CSPromise` | `task.ToPromise().Then(...)` / `.Catch(...)`: a **new** promise |
| `task.Finally(fn)` / `task.Timeout(ms, cancelSource := "")` | `_CSPromise` | `task.ToPromise().Finally(...)` / `.Timeout(...)` |
| `proxy._Explain(name, args*)` | string | Overload report for `name` with these arguments (same as `CS.Explain(proxy, name, args*)`) |
| `proxy.On(event, fn)` | proxy | Subscribe to a .NET event; `fn` gets `(eventArgs, sender)` for `EventHandler`-shaped events, otherwise the delegate's own arguments. Delivered on the AHK thread |
| `proxy.Off(event := "")` | proxy | Remove the handlers added with `On` for that event (all events when omitted) |
| `proxy.ToAHK()` / `proxy.ToArray()` | Array / Map | Native AHK copy: Array (1-based) or Map for dictionaries |
| `proxy.ToBuffer()` | Buffer | Copy a primitive array into a Buffer (one memcpy) |
| `proxy.FromBuffer(buf, bytes := buf.Size)` | proxy | Fill a primitive array from a Buffer (one memcpy) |
| `for x in proxy` / `for k, v in proxy` | | Native iteration (collections in bulk, lazy sequences item by item) |
| `proxy.ToString(args*)` | string | Simply the .NET `ToString`, with whatever arguments you pass (`dt.ToString("yyyy-MM-dd")`) |
| `proxy.Type` | string | CLR type name (helper: only when .NET has no `Type` member) |
| `proxy.Is(typeName)` | bool | Type test (`IsInstanceOfType`) |
| `proxy.Members` | string | `"K:Name|K:Name..."` list of public members |
| `proxy.Raw` | object | Underlying raw object reference |
| `proxy.Dispose()` | | Calls `IDisposable.Dispose()`; also a plain public `Dispose()` on a class that does not implement `IDisposable` |
| `proxy.AutoDispose()` | proxy | Dispose the object when the last AHK reference to this proxy is released. Call it only on the **one** proxy that owns the object |
| `proxy._Invoke(name, args*)` | any | Always call the .NET method `name`, even when AHK# has a helper of that name |

## _CSPromise (Async Result)

| Member | Returns | Description |
|--------|---------|-------------|
A promise is settled once, with a value or an `Error`. `Then`, `Catch`, `Finally` and `Timeout` return a **new** promise (JavaScript semantics). Full guide with examples: [Async/Await](04_async.md).

| Member | Returns | Description |
|--------|---------|-------------|
| `promise.Await(timeoutMs := 0)` | any | Wait (message pump stays alive, so worker-thread callbacks can run). `0` = no limit; otherwise throws `TimeoutError`. Throws the failure; for a failed .NET operation the message is `Async operation failed: ` followed by `FormatException: ...` (the .NET type name, then its message) and the error keeps `e.NetType` / `CS.ErrorIs` |
| `promise.Then(onOk := "", onFail := "")` | promise | `onOk(value)` / `onFail(err)` run on the AHK thread (even after completion; repeatable). The new promise's value is the callback's return value (a returned promise is followed); a throwing callback rejects it; an omitted callback passes the outcome on |
| `promise.Catch(onFail)` | promise | `Then("", onFail)`: `onFail(err)` gets an `Error` (message starts with the .NET type name, `FormatException: ...`; `e.NetType`, `CS.ErrorIs` work). Its return value continues the chain |
| `promise.Finally(fn)` | promise | Runs `fn()` on success or failure, then passes the value / error on (unless `fn` throws). `fn`'s return value is ignored |
| `promise.Timeout(ms, cancelSource := "")` | promise | Follows this promise but fails with `TimeoutError` if it is not settled within `ms`; calls `Cancel()` on `cancelSource` (a `CancellationTokenSource` proxy) at that moment |
| `promise.IsComplete` | bool | Finished (success or failure); asks the bridge, no wait for the completion message |
| `promise.Error` | string | `""` unless it failed, then the error text; the failure of a .NET operation nobody handles stays here and `Await` throws it |
| `CS.Promise.Resolve(value := "")` | promise | A promise for `value` (a promise is returned as is, a .NET Task proxy becomes its promise) |
| `CS.Promise.Reject(err)` | promise | A failed promise; `err` is an `Error` or any value (becomes `Error(String(err))`) |
| `CS.Promise.Delay(ms, value := "")` | promise | Resolves with `value` after `ms` ms (AHK timer) |
| `CS.Promise.All(promises*)` | promise | Array of all results in input order; **fails as soon as one input fails**; accepts promises, .NET Task proxies and plain values; `All()` resolves with `[]` |
| `CS.Promise.Race(promises*)` | promise | Settles like the first input to settle |
| `CS.Promise.AwaitAll(promises*)` | Array | Blocking `All`: results in order; throws as soon as any input fails |
| `CS.Promise.AwaitAny(promises*)` | any | Blocking `Race`: the first to settle; throws if that one failed |

An error thrown by **your** callback that nothing observes (no `Catch` / `Then` / `Await` / `Error` read on the derived promise) is reported as an ordinary AHK error after 100 ms; a failed .NET task that nobody handles stays silent ([Async/Await](04_async.md#unhandled-errors)). Code that relied on `p.Then(f)` returning `p` itself must keep its own reference to `p`.

## CS.NuGet (`_CSNuGet`)

| Method | Returns | Description |
|--------|---------|-------------|
| `CS.NuGet.Install(id, ver := "", showGui := unset)` | string | Download + extract the package **and its dependencies**; returns the install directory. **Throws** on failure, and a `NotSupportedException` (`... has no assemblies this runtime can load. It offers: net8.0 ...`) when the package has assemblies but none for the .NET Framework. An empty `ver` means the newest stable version that works here |
| `CS.NuGet.Require(id, ver := "")` | string | Install if needed; returns `;`-joined DLL paths (package + dependencies). Throws on failure or if no .NET Framework-usable assemblies |
| `CS.NuGet.Search(query, take := 20, includeIncompatible := false)` | Array of Map | nuget.org search. Each Map: `Id`, `Version` (what `Require` would install), `Latest`, `Downloads` (Integer), `Description`. Packages with no usable version are hidden unless `includeIncompatible` is `true`; `take` is 1..100 |
| `CS.NuGet.IsInstalled(id, ver := "")` | bool | Cached? |
| `CS.NuGet.Uninstall(id, ver := "")` / `.Remove(...)` | bool | Delete one version, or all when `ver` is empty |

Framework selection (`net4x` up to the installed Framework, then `netstandard1.0`-`2.0`, then `net20`-`net35`; never `net5.0`+ or `netstandard2.1`) and the "latest that works here" rule are described in [NuGet](05_nuget.md#framework-targeting).

Every downloaded `.nupkg` (dependencies and Roslyn included) is checked against the SHA-512 nuget.org publishes for that exact version; a mismatch deletes the file and throws. `CS.Config.VerifyNuGet := false` turns the check off and `CS.Config.NuGetStrict := true` also fails when the hash cannot be fetched. Package **signatures / author trust are not checked**, and the package's code still runs in your process ([NuGet](05_nuget.md#integrity-check), [Security](19_security.md)).

## Delegates (`_CSDelegate`)

| Member | Returns | Description |
|--------|---------|-------------|
| `CS.Delegate(fn)` | `_CSDelegateRef` | Register an AHK function |
| `ref.Id` | Integer | Registration id |
| `ref.Unregister()` | | Remove the registration and its subscription; drops queued events |

## CS.Fast (`_CSFast`)

The lambda is a C# **expression string**: `x` is the element, `acc` the running value in `Reduce`; both are C# `dynamic`. AHK Integers are widened to `Int64` first, so sums do not overflow at 2^31. Results are AHK Arrays (1-based).

| Method | Returns | Description |
|--------|---------|-------------|
| `CS.Fast.Map(arr, lambda, refs := "")` | Array | Applies the expression to every element, **in parallel**, order preserved |
| `CS.Fast.Filter(arr, lambda, refs := "")` | Array | Keeps elements where the expression is true, in parallel, order preserved |
| `CS.Fast.Reduce(arr, lambda, initial := 0, refs := "")` | any | Folds the array with `acc` / `x`; **sequential** (an arbitrary combine function is not associative) |

```autohotkey
CS.Fast.Map([1, 2, 3], "x * 2")                 ; → [2, 4, 6]
CS.Fast.Filter([1, 2, 3, 4], "x % 2 == 0")      ; → [2, 4]
CS.Fast.Reduce([1, 2, 3, 4], "acc + x", 0)      ; → 10
```

## Error handling

A .NET failure reaches AHK as an ordinary `Error` whose message is prefixed with the call that failed. The error also carries the .NET exception's details:

| Property | Type | Description |
|----------|------|-------------|
| `e.NetType` | string | Full type name, e.g. `"System.IO.DirectoryNotFoundException"` |
| `e.NetBases` | Array | Base-class names, nearest first (`System.IO.IOException`, `System.SystemException`, ...) |
| `e.NetStack` | string | The .NET stack frames at the throw site |
| `e.NetHResult` | Integer | The exception's HRESULT |

```autohotkey
try
    CS.System.IO.File.ReadAllText("C:\definitely\not\here.txt")
catch as e {
    CS.ErrorIs(e, "System.IO.DirectoryNotFoundException")   ; → 1  the exact type
    CS.ErrorIs(e, "DirectoryNotFoundException")             ; → 1  its short name
    CS.ErrorIs(e, "IOException")                            ; → 1  a base class
    CS.ErrorIs(e, "FormatException")                        ; → 0
    MsgBox e.NetType "`n" e.NetStack
}
```

`CS.ErrorIs(e, typeName)` is case-insensitive and returns `false` for an error without .NET details (test with `HasProp(e, "NetType")`).

- The details are attached only when the error really came from a .NET exception. Errors raised on the AHK side, such as `AHK# could not resolve '...'`, carry no `NetType`. A failed overload binding is itself a .NET `MissingMethodException`, so it does carry one.
- **Async failures** keep their .NET identity: `promise.Await()` throws an `Error` whose message is `Async operation failed: ` plus `FormatException: Input string was not in a correct format.`, and a `.Catch` callback gets an `Error` whose message starts with the .NET type name (`FormatException: ...`). Both carry `NetType`, `NetBases`, `NetStack` and `NetHResult`, so `CS.ErrorIs(e, "FormatException")` works around `Await` and inside `Catch` ([Async/Await](04_async.md#errors)). Errors from AHK callbacks, `CS.Promise.Reject(...)` and `Timeout` are plain AHK errors (no `NetType`).
- `TimeoutError` from `Await(timeoutMs)` and the `AHK# ...` resolution errors are AHK-side errors.

## Developer Tools

### CS.Stats

`CS.Stats()` returns a `Map` of the bridge's internal counters, for leak checks and monitoring:

| Key | Meaning |
|-----|---------|
| `ManagedHeapBytes` | Managed heap size (same idea as `CS.Memory()`, no forced collection) |
| `Delegates` | Registered event / callback delegates (`On`, `CS.Delegate`); returns to its starting value after `Off` / `Unregister` |
| `PendingAsyncTasks` | Async slots not yet collected; `0` when every promise has been awaited or completed |
| `QueuedCallbacks` | AHK functions queued for the AHK thread by worker threads; `0` when the queue is drained |
| `ResolvedTypes` | Cached type-name lookups |
| `OverloadCacheEntries`, `BoundCallCacheEntries` | Sizes of the overload caches; they do not grow with repeated calls of the same shape |

```autohotkey
CS.GC()
s := CS.Stats()
MsgBox s["ManagedHeapBytes"] " bytes, " s["Delegates"] " delegates, " s["PendingAsyncTasks"] " pending tasks"
```

`Delegates`, `PendingAsyncTasks` and `QueuedCallbacks` should return to `0` once you are done with the objects that use them; `tests\test_stress.ahk` checks exactly that.

### CS.Implement

```autohotkey
cmp := CS.Implement(CS.System.Collections.IComparer, Map("Compare", (a, b) => b - a))
CS.System.Array.Sort(arr, cmp)

gen := CS.Implement(CS.System.Collections.Generic.IComparer(CS.System.Int32), {Compare: (a, b) => a - b})
cmp.Compare(9, 4)                                    ; the returned object can be called from AHK
```

Handlers are a Map or object literal of `name → function`; properties use `"get_Name"` / `"set_Name"` (or `"Name"`). A non-void member without a handler throws `NotImplementedException` naming it. Built on `RealProxy` (.NET Framework 4.x). Full rules: [Delegates](07_delegates.md#implementing-net-interfaces-with-csimplement).

### CS.Explain and proxy._Explain

Show why an overload is (not) chosen. Every candidate is listed with its conversion cost or `rejected`, and `=>` marks the winner:

```autohotkey
MsgBox CS.Explain(CS.System.Math, "Abs", -2.5)       ; static: pass the type object
MsgBox CS.Explain(sb, "Append", "x")                 ; instance: pass the proxy (same as sb._Explain("Append", "x"))
```

```
System.Math.Abs(Double)
   => cost   0  Double Abs(Double value)
      rejected  Int32 Abs(Int32 value)
      ...
```

(The line list is longer: one line per overload.) Costs are explained in [Marshaling](17_marshaling.md#overload-scoring).

### CS.Config.Trace

Log every method call through a type or proxy with its result and timing (`System.Math.Abs(-3) => 3  [12.3 us]`); a failure is logged with `ERROR` and the message. See the Config table above.

### CS.Wrap

Generate an AHK class that mirrors a .NET type, so editors see real parameter names and every overload:

```autohotkey
CS.Wrap("System.Math", A_ScriptDir "\MathW.ahk", "MathW")     ; write the file once
#Include MathW.ahk                                           ; after lib\ahk#.ahk
MsgBox MathW.Round(2.567, 2) " " MathW.PI                    ; → 2.57 and 3.14159... (PI is a public const field)
```

- The result is the source text (also returned when `outPath` is empty); the file is written as UTF-8. `typeName` may be a string or a type object; `className` defaults to the .NET type name, so pass one when that name is already an AHK class (`String`, `Array`, `Map`, `Buffer`, ...).
- Static members become static AHK members; a non-static type gets `__New(args*)` (constructs the real object) and `Class.FromObject(obj)` to wrap an existing one. **Properties and public fields** (such as `Math.PI`) become AHK properties with get (and set when writable).
- Every overload appears as a comment above its method (`; Double Round(Double value, Int32 digits)`); the method takes the parameter names of the widest overload, the parameters missing from shorter overloads are optional, and calls forward only the arguments you passed to the real member.

### CS.Declare

Give your editor completion, hover and signature help for .NET types:

```autohotkey
CS.Declare("System.Text.StringBuilder", "System.IO", CS.System.Math)     ; run once, then reopen the script in the editor
```

It writes `ahk#.d.ahk` next to `ahk#.ahk` (in `lib\`); the AutoHotkey v2 language server (thqby's VS Code extension) picks the file up on its own. Specs are type names, namespace names or type / namespace objects, and later calls **add** to what is already declared. It returns the file's path. Full guide and limits: [Editor Support](21_editor_support.md).

### CS.Members and CS.Types

`CS.Members(typeOrObject, filter := "")` and `CS.Types(namespace, filter := "")` list what you can call: see [CS Namespace](02_cs_namespace.md#discovering-what-is-there). A misspelled member, type or namespace ends its error with `Did you mean: ...?`.

### Module hot reload

`MyModule.Reload(csharpSource)` and `MyModule.Watch(path, onReload := "", intervalMs := 500)`: see [CSModule](03_csmodule.md#hot-reload).

## Extensions

### Http (ext\ahk#.http.ahk) — see [HTTP/JSON](08_http_json.md)

| Method | Returns | Description |
|--------|---------|-------------|
| `Http.Get(url, headers := "")` | string | HTTP GET |
| `Http.Post(url, body, headers := "")` | string | HTTP POST (JSON content type) |
| `Http.Put(url, body, headers := "")` | string | HTTP PUT |
| `Http.Delete(url, headers := "")` | string | HTTP DELETE |
| `Http.Head(url)` | string | `"status|contentType|server"` |
| `Http.Download(url, path)` | | Download to a file |
| `Http.Upload(url, path)` | string | Upload a file |

### Json (ext\ahk#.http.ahk)

| Method | Returns | Description |
|--------|---------|-------------|
| `Json.Query(json, path)` | string | Dotted path (`"a.b.0.c"`) into a JSON object; numeric segments step into arrays |
| `Json.Stringify(obj)` | string | Serialize a Map / Array / value |
| `Json.Flatten(json)` | string | `key=value` lines |
| `Json.Build(k1, v1, k2, v2, ...)` | string | Alternating keys and values as separate arguments (or one Array `[k1, v1, ...]`) |
| `Json.IsValid(json)` | bool | Validate |

### SQLite (ext\ahk#.sqlite.ahk)

| Method | Returns | Description |
|--------|---------|-------------|
| `db := SQLite(path := ":memory:")` | SQLite | Open a database |
| `db.Execute(sql, params*)` | Integer | Non-query; rows affected |
| `db.Query(sql, params*)` | Array | Array of Maps (column name → value), the whole result set in one bulk COM call. `NULL` comes back as `""` |
| `db.Scalar(sql, params*)` | string | First column of the first row |
| `db.Transaction(fn)` | | Run `fn` in a transaction (rollback + rethrow on error) |
| `db.LastId` | Integer | Last inserted rowid |
| `db.Close()` | | Close the database |

Text is UTF-8 in and out (non-ASCII text and column names round-trip), bound parameters are copied by SQLite (`SQLITE_TRANSIENT`), and floats are formatted with the invariant culture.

### SharedMemory (ext\ahk#.ipc.ahk)

| Method | Returns | Description |
|--------|---------|-------------|
| `SharedMemory(name, size := 1048576)` | SharedMemory | Create or open a named channel |
| `sm.Write(text)` / `sm.Read()` | self / string | UTF-8 text |
| `sm.WriteBytes(data)` / `sm.ReadBytes()` | self / Buffer | Raw bytes (Buffer, byte[] proxy or byte SafeArray in) |
| `sm.WriteAt(offset, text)` / `sm.ReadAt(offset, length)` | self / string | Text at a byte offset in the data area |
| `sm.Length` / `sm.Capacity` | Integer | Data length / capacity |
| `sm.Clear()` | self | Reset the data length to 0 |
| `sm.OnChanged(callback, ms := 50)` | self | Poll and call `callback(text)` on change |
| `sm.Close()` | | Release |

### NativeUI / NativeControl (ext\ahk#.ui.ahk)

| Member | Returns | Description |
|--------|---------|-------------|
| `NativeUI.DataGridView(gui, x, y, w, h)` | NativeControl | DataGridView inside an AHK Gui (`gui` may be a Gui or an hwnd) |
| `NativeUI.RichTextBox(gui, x, y, w, h)` | NativeControl | RichTextBox |
| `NativeUI.Panel(gui, x, y, w, h)` | NativeControl | Panel |
| `ctrl.AddColumn(name, header := "")` | ctrl | Grid column |
| `ctrl.AddRow(values*)` | ctrl | Grid row |
| `ctrl.GetCell(row, col)` | string | Grid cell (0-based) |
| `ctrl.Clear()` | ctrl | Remove grid rows |
| `ctrl.Text` | string | Get / set the control text |
| `ctrl.Resize(x, y, w, h)` | ctrl | Move / resize |
| `ctrl.Destroy()` | | Dispose the control |
| `ctrl.Prop := v` | | Set any public WinForms property by reflection |

### UIA2 (ext\ahk#.uia.ahk)

| Method | Returns | Description |
|--------|---------|-------------|
| `UIA2.CrawlTree(hwnd := 0, maxDepth := 50)` | Array (1-based) of `UIAElement` | All elements below the window, fetched in one bulk COM call |
| `UIA2.Find(hwnd, condition, maxDepth := 50)` | Array (1-based) of `UIAElement` | Elements matching `Name=`, `AutomationId=`, `ClassName=` or `ControlType=` |
| `UIA2.FromPoint(x, y)` | `UIAElement` or `""` | Element at a screen point |
| `UIA2.Focused()` | `UIAElement` or `""` | Focused element |
| `UIA2.Invoke(hwnd, automationId)` | bool | Click via the Invoke pattern |
| `UIA2.SetValue(hwnd, automationId, value)` | bool | Set a ValuePattern value |

A `UIAElement` has plain AHK properties (no COM calls): `Name`, `AutomationId`, `ClassName`, `ControlType`, `LocalizedControlType`, `ProcessId`, `NativeWindowHandle`, `BoundingX`, `BoundingY`, `BoundingW`, `BoundingH`, `IsEnabled`, `IsOffscreen`, `Value`, `Depth`, `ChildCount`. Iterate with `for el in elements`; the arrays are 1-based like every AHK Array (code that indexed `elements[A_Index - 1]` must change).

### Spatial (ext\ahk#.spatial.ahk)

AHK# ships no OCR engine: set `Spatial.Reader := (x, y, w, h) => text` (an `OCR` class with `Text(x, y, w, h)` is used if present) ([Extensions](14_extensions.md#spatial-extahkspatialahk)).

| Member | Returns | Description |
|--------|---------|-------------|
| `Spatial.Reader` | function | `(x, y, w, h) => text`, supplied by you |
| `Spatial.Parser` | function | Optional `(text) => {...}`; its properties are merged into the `Watch` callback object |
| `Spatial.OnError` | function | Optional `(e, watcherId) => ...`; default is `OutputDebug`. Reader / Parser / callback errors are reported here, not swallowed |
| `Spatial.Watch(x, y, w, h, intervalMs, callback)` | id | Poll the region; `callback({text, ...})` when the text is non-empty and changed |
| `Spatial.WatchFor(x, y, w, h, pattern, callback, intervalMs := 500)` | id | `callback({text, match})` when the regex matches |
| `Spatial.Stop(id)` / `Spatial.StopAll()` | | Cancel the watcher's timer / all timers |
| `Spatial.Count` | Integer | Active watchers |

## Lower-Level Host (`_AhkSharpEngine`)

| Member | Returns | Description |
|--------|---------|-------------|
| `_AhkSharpEngine.Boot()` | ComObject | Start the CLR (first call only), load the bridge, return the raw bridge object. Later calls return the same object |

The raw bridge exposes methods such as `InvokeModule(asmId, class, method, args)`, `HasType(name)` and `EvalExpression(expr, refs)`. It is an internal interface, not a stable API; prefer the `CS` classes.

## Environment Variables and Files

| Name | Purpose |
|------|---------|
| `AHKSHARP_DEV=1` | Run `lib\build.ps1` on every start (hash-checked; no-op when the sources are unchanged) and skip the bridge-hash check while you rebuild from `src\` |
| `AHKSHARP_NET=1` | Also run the network tests in `tests\run_tests.ps1`: the network part of `tests\test_extensions.ahk` and the whole `tests\test_net_modern.ahk` suite ([Testing](20_testing.md)) |
| `AHK_EXE` | Path to the AutoHotkey v2 exe used by `tests\run-ahk.ps1` |
| `%LocalAppData%\AhkSharp\CompileCache\` | Compiled module DLLs, named by source hash |
| `%LocalAppData%\AhkSharp\Packages\` | NuGet packages and the Roslyn compilers (`microsoft.net.compilers`, `microsoft.net.compilers.toolset`) |
| `ahk#.d.ahk` (next to `ahk#.ahk`) | Editor declarations written by `CS.Declare` (machine output: add it to `.gitignore` in a project) |
| `lib\.bridge_hash` | Hash of `src\*.cs` used by `build.ps1` |

## Version Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `AHK_SHARP_VERSION` | `"2.0.0"` | Library version |
| `AHK_SHARP_CLR` | `"v4.0.30319"` | Target CLR version |
| `AHK_SHARP_BRIDGE_SHA256` | 64 hex digits | SHA-256 of `lib\ahk#.bridge.dll`, rewritten by `lib\build.ps1` on every build; `Boot()` refuses a DLL that differs |

## Changes

Every added, changed, fixed and removed behaviour since 1.0.0, including the breaking ones, is listed in the [CHANGELOG](../CHANGELOG.md).
