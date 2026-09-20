# Architecture

## CLR Bootstrap Sequence

`_AhkSharpEngine.Boot()` in `lib\ahk#.ahk` runs on the first use of anything in `CS` (about 100 ms) and does this:

1. Locate `ahk#.bridge.dll` next to `ahk#.ahk` (or at `CS.Config.BridgeDll` when set). If it is missing (or `AHKSHARP_DEV` is set) and `build.ps1` exists, run `powershell -NoProfile -ExecutionPolicy Bypass -File lib\build.ps1`. A missing DLL after that, or a failed build, throws.
2. Unless `CS.Config.VerifyBridge` is `false` or `AHKSHARP_DEV` is set, hash the DLL with SHA-256 (Windows CNG) and compare it with `AHK_SHARP_BRIDGE_SHA256` in `ahk#.ahk`; a mismatch throws and nothing is loaded. This applies to whichever file is about to be loaded, a `CS.Config.BridgeDll` path included.
3. `mscoree!CorBindToRuntimeEx("v4.0.30319", ...)` returns an `ICorRuntimeHost` (the version must be given: `null` would load CLR 2.0).
4. `ICorRuntimeHost::Start()`, then `GetDefaultDomain()` gives the default AppDomain, wrapped as a `VT_DISPATCH` `ComValue`.
5. The DLL is read into a byte array and loaded with `Assembly.Load(byte[])`, reached by reflection through the AppDomain's `mscorlib`.
6. `CreateInstance("AhkSharpBridge")` creates the COM-visible bridge singleton; AHK keeps that `ComObject`. Its constructor also enables TLS 1.2 (and 1.3 where known) for the whole process.
7. A hidden Gui receives the async completion message (`WM_APP+1`) and the worker-thread callback message (`WM_APP+3`; `SetAhkWindow` gives the bridge the window handle and message id, `SetCallbackTimeout` the timeout), and the bridge records the AHK thread id.

The bridge is created through `CreateInstance("AhkSharpBridge")` only; the older `AhkSharpEntry` start-up class (and its `AHKSHARP_PTR` environment variable) has been removed.

Because the bridge is loaded from bytes, it has no file lock. It is integrity-checked against a pinned hash, not signature-checked ([Security](19_security.md)).

## COM Interface

All AHK↔.NET communication uses IDispatch (COM automation):
- Method calls → `IDispatch::Invoke`
- Bridge entry points exist in fixed-arity forms (`InvokeStatic0..3`, `InvokeMember0..3`) so small calls pass their arguments as separate COM parameters instead of building a SafeArray
- Larger calls pack arguments into a `VT_VARIANT` SafeArray
- Typed arrays travel as SafeArrays that AHK reads with `NumGet` / `StrGet` straight from memory

## Components

| Component | Where | Role |
|-----------|-------|------|
`src\bridge\` is split by concern; `build.ps1` compiles every `.cs` below `src\` into the one DLL.

| Component | Where | Role |
|-----------|-------|------|
| `AhkSharpBridge` | `AhkSharpBridge.cs` | The COM-visible entry class and every method AHK calls: static and instance calls, properties, indexers, enumeration, `CS.Stats`, `SameObject`, `HasMember`, `DisposeObject` |
| `OverloadBinder` | `OverloadBinder.cs` | Cost-based overload choice, coercion (numbers, strings, AHK timestamp → `DateTime`), params, optional, generic inference, LINQ; caches candidate lists and (type-only) decisions; `CS.Explain` |
| `AhkCallback` | `AhkCallback.cs` | AHK function → .NET delegate. On the AHK thread: a direct call. On another thread: a work item in a queue, `PostMessage(WM_APP+3)`, the AHK thread runs it (`PumpCallbacks`) and signals the waiting worker; a timeout (`CallbackTimeoutMs`) raises a `TimeoutException` |
| `ValueBox` | `ValueBox.cs` | Reference wrapper that keeps structs and arrays as real objects across COM |
| `AhkInterfaceProxy`, `WrapperGenerator` | `Extras.cs` | `CS.Implement`: a `RealProxy` that is-a the interface and routes each call to the AHK function registered under the member's name (through `AhkCallback`). `CS.Wrap`: emits AHK source for a .NET type |
| `TypeResolver` | `TypeResolver.cs` | Name → `System.Type`. Types are resolved **up front** (the AHK side asks `HasType` at every dotted hop), so a real .NET exception is never mistaken for a missing type. Misses are cached and cleared when an assembly loads. Case-insensitive. Generic types are built from any loaded assembly (`List`1[Ns.Foo]`) |
| `MarshalEngine` | `MarshalEngine.cs` | CLR ↔ COM values: `PackResult` (DateTime → AHK timestamp, arrays stay references), arg unpacking, typed-array bulk transfer |
| `RuntimeCompiler` | `RuntimeCompiler.cs` | `CSharpCodeProvider` (C# 4) or Roslyn `csc.exe` (`CSVersion` 5.0-12.0 / `latest`; adds an `IsExternalInit` marker type for C# 9+ records / `init`); on-disk compile cache; module invocation, one persistent instance per module |
| `ErrorInfo`, `MemberCache` | `ErrorInfo.cs` | `ErrorInfo` records the .NET exception that propagated to AHK (type, base types, stack, HRESULT) for `e.NetType` / `CS.ErrorIs`; `MemberCache` answers "does this type have a public instance member called X" (cached), which decides between a .NET member and an AHK# proxy helper |
| `AsyncRouter` | `AsyncRouter.cs` | ThreadPool dispatch and `.NET Task` continuations (`ToPromise`); completion by `PostMessage(WM_APP+1)`. A pool call that returns a Task waits for it and hands back its result |
| `FastParallel` | `FastParallel.cs` | `CS.Fast`: compiles the lambda once, PLINQ (`AsParallel().AsOrdered()`) for Map/Filter, sequential Reduce |
| `NuGetManager` | `NuGetManager.cs` | Package download, SHA-512 verification against nuget.org, dependency install, "latest that works here" version resolution, Roslyn download (`microsoft.net.compilers` 4.0.1 for C# up to 10, `Microsoft.Net.Compilers.Toolset` 4.8.0 for 11+) |
| `FrameworkPicker` | `FrameworkPicker.cs` | Which NuGet target frameworks this CLR can load: ranks `net4x` (up to the Framework in the registry) > `netstandard1.0`-`2.0` (Framework 4.7.2+) > `net20`-`net35`, and rejects `net5.0`+, `netcoreapp`, `netstandard2.1`. Used for the `lib\` folder, the `.nuspec` dependency group and the version check |
| `NuGetSearch` | `NuGetSearch.cs` | `CS.NuGet.Search`: queries nuget.org and, unless asked otherwise, hides packages whose `.nuspec` targets only unusable frameworks (a partial class of `NuGetManager`) |
| `Discovery`, `MemberHints` | `Discovery.cs`, `MemberHints.cs` | `CS.Members` / `CS.Types` (reflection listings) and the `Did you mean ...?` suggestions (Levenshtein distance over member, type and namespace names) for misspelled names |
| `Declarations` | `Declarations.cs` | `CS.Declare`: generates the `ahk#.d.ahk` editor declaration file (classes without bodies mirroring the .NET types you named) that the AHK v2 language server reads ([Editor Support](21_editor_support.md)) |
| `DelegateBridge` | `DelegateBridge.cs` | Event subscription: queue + `PostMessage(WM_APP+2)` |

Promise chaining (`Then` / `Catch` / `Finally` / `Timeout`, `CS.Promise.All` / `Race` / `Delay`) lives entirely in `lib\ahk#.ahk` (`_CSPromise`): the bridge only completes the promises that wrap a ThreadPool call or a .NET Task, and the derived promises are settled by AHK code and AHK timers on the AHK thread.

The extension classes (`MemoryMappedIpc`, `NativeUi`, `PhantomSqlite`, `UiaDeepCrawler`) live in `src\ext\` and are compiled into the same DLL. Their AHK sides are in `ext\` (a different folder: `ext\` holds AutoHotkey, `src\ext\` the C# behind it).

### Typed errors and the proxy rule

- **Errors.** A `FirstChanceException` handler (installed when the bridge is created) remembers the last exception raised on the AHK thread. After a failed call the AHK side asks `LastErrorInfo()` and, when its message matches the COM error it caught, attaches `NetType`, `NetBases`, `NetStack` and `NetHResult` to the `Error` (`_CSError` in `ahk#.ahk`). `CS.ErrorIs` compares against the type and its base types.
- **Proxy helpers.** `_CSProxy.__Call` / `__Get` look the name up in a helper table and call the bridge's `HasMember(obj, name)`; the helper runs only when the object has no such member, otherwise the call goes to the .NET member. `_Invoke` skips the table.
- **Identity and lifetime.** `CS.Same` calls `SameObject` (reference equality). `AutoDispose` sets a flag on the proxy, and `_CSProxy.__Delete` calls `DisposeObject` when AHK releases it.

### Type and overload resolution

`CS.System.Math.Pow(5, 3)` resolves left to right. `CS.System` is a namespace object; each `.Name` asks the bridge whether the dotted path is a type. `System.Math` is, so it becomes a type object and `.Pow(5, 3)` becomes `InvokeStatic2("System.Math", "Pow", 5, 3)`. Namespace children are remembered so the hot path walks the same names cheaply.

`OverloadBinder` then scores each candidate (exact = 0, lossy = rejected), converts arguments for the winner only, and remembers the winner per argument-type signature when the choice does not depend on argument values. If instance binding fails, LINQ extension methods are tried for `IEnumerable` targets. Rules: [Marshaling](17_marshaling.md).

### Async and events

```
AHK thread                          .NET ThreadPool / other threads
  Module.Async.Fn()  ──BeginAsync──►  runs Fn
  (pump running)                      PostMessage(WM_APP+1, taskId)
  OnMessage ◄─────────────────────────┘
  promise settles → its Then/Catch/Finally callbacks run via SetTimer (AHK thread); each settles the promise Then returned

  proxy.On("Event", fn)  ──subscribe──► compiled handler for the event's delegate type
                                        event raised on any thread → args queued (ConcurrentQueue)
                                        PostMessage(WM_APP+2, id)   (one message per event)
  OnMessage: pop ONE queued event, call fn(eventArgs, sender)  (AHK thread)
```

AHK callbacks passed as delegates (`AhkCallback`) call back into AHK through IDispatch, which is only legal on the AHK thread. The bridge records that thread's id when it is created. A callback on that thread is a direct call; from any other thread it goes through a queue:

```
Worker thread                             AHK thread
  delegate(fn) called by .NET
  enqueue work item, PostMessage(WM_APP+3) ──► OnMessage → bridge.PumpCallbacks()
  wait for the item (CallbackTimeoutMs)        runs fn, stores result / exception, signals
  ◄──────────────────────────────────────────  result (or the exception) returns to .NET
```

If the AHK thread never gets to its message loop (it is blocked in `Task.Wait()` / `Parallel.ForEach`), the worker gives up after `CallbackTimeoutMs`, the item is marked abandoned so the function is not run late, and the worker gets a `TimeoutException` ([Troubleshooting](18_troubleshooting.md#the-ahk-thread-is-not-pumping-messages)).

`ref` / `out` arguments: an `&var` argument travels as "nothing" (or the variable's value for `ref`) and the bridge's `InvokeStaticRef` / `InvokeMemberRef` reply with `[returnValue, arg0After, arg1After, ...]`; the AHK side writes each value back into its VarRef.

### Compilation pipeline

```
CSModule.CSharp → SHA256(source|references[|version]) → memory cache → disk cache
  → CSharpCodeProvider (or Roslyn csc.exe via NuGet: microsoft.net.compilers 4.0.1, or the 4.8.0 toolset for C# 11+) → {hash16}.dll (temp file, then moved)
  → Assembly.LoadFrom → overload-bound reflection invoke
```

Cache location: `%LocalAppData%\AhkSharp\CompileCache\`. The hash covers source, references and language version; changing any of them recompiles. The loaded DLL is trusted by hash-name only ([Security](19_security.md)).

## Threading

- AHK: single-threaded message pump.
- .NET: ThreadPool for async work and for wherever events fire.
- `PostMessage(WM_APP+1)` announces async completion; `PostMessage(WM_APP+2)` announces a queued event; `PostMessage(WM_APP+3)` asks the AHK thread to run queued callbacks from worker threads.
- AHK callbacks execute on the AHK main thread: directly when .NET is on that thread, queued (and needing the pump) from any other thread.
- Nothing is delivered unless the pump runs (`Sleep`, GUI, hotkeys, timers, `Persistent()`).

## Performance

Measured on this project's development machine, not promised elsewhere:

| Operation | Measured |
|-----------|----------|
| A cached .NET call (`Math.Abs`, an instance method) | about 7–12 µs |
| Property get | about 5 µs |
| COM transport floor (one bare IDispatch call) | about 1.7 µs |
| Send a 10,000-integer AHK Array to .NET | about 6 ms (was 73 ms) |
| Read a 10,000-element `List<int>` into an AHK Array | about 3 ms (was 23 ms) |
| `Boot()` on the first call | about 100 ms |

What produced these numbers: typed-array bulk transfer (an Integer Array becomes `long[]` with one memory copy, and results are read straight out of the SafeArray memory instead of one COM call per element), fixed-arity entry points, cached namespace hops and type lookups, and an overload decision cached per argument-type signature. Every bridge call still has a COM cost, so a loop of tiny calls stays far slower than one call that does the loop inside .NET; that is the usage the benchmarks show.

The two scripts in `examples\benchmarks\` are in-process comparisons. They warm up (JIT and binding) before timing, take the median of several runs, and verify that both sides return the same result; `speed_benchmark.ahk` compares a native AHK loop with the equivalent loop inside a single .NET call, `ecosystem_benchmark.ahk` compares vendored community AHK libraries with .NET equivalents.
