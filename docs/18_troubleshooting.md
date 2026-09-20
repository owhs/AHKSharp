# Troubleshooting

## The bridge DLL is not found, or the build fails

Messages: `AHK# bridge DLL not found: ...` or `AHK# bridge build failed (exit code N)`.

`lib\ahk#.bridge.dll` is committed, so this usually means the file was deleted, quarantined by antivirus, or a checkout dropped it. When the DLL is missing `Boot()` runs `powershell -NoProfile -ExecutionPolicy Bypass -File lib\build.ps1` to rebuild it. That can fail when:

- **`csc.exe` is missing.** `build.ps1` uses the .NET Framework 4.x compiler (`%windir%\Microsoft.NET\Framework64\v4.0.30319\csc.exe`, then `Framework\v4.0.30319`). It ships with Windows 10/11; on older systems install .NET Framework 4.x.
- **Execution policy.** Boot passes `-ExecutionPolicy Bypass`, but a policy set by Group Policy overrides that. Run the script yourself from a prompt where it is allowed: `powershell -ExecutionPolicy Bypass -File lib\build.ps1 -Force -Verbose`. `-Verbose` prints the compiler command and output.
- **The sources moved.** `build.ps1` expects `src\` (with `bridge\` and `ext\`) next to `lib\` and compiles every `*.cs` below it.
- **A compile error in `src\`.** `build.ps1` prints the compiler errors, and also any compiler **warnings**, so read its output. The bridge is compiled by the `csc.exe` that ships with Windows, which only understands C# 4.0 syntax (no `?.`, no `$"..."`, no expression-bodied members): [CONTRIBUTING](../CONTRIBUTING.md).

Rebuild manually with `powershell -File lib\build.ps1 -Force`. Set the environment variable `AHKSHARP_DEV=1` while editing `src\*.cs` so every start rebuilds when the sources changed.

`CorBindToRuntimeEx failed: 0x...` means the CLR v4.0.30319 could not be started: .NET Framework 4.x is missing or damaged.

## A compile error window appears (or a script hangs at start-up)

A `_CSModule` that does not compile opens a **diagnosis window** (compiler messages, likely fixes, the first 30 lines of generated source) and waits until you close it, then **throws** `CSModule 'Name' failed to compile`. In a scheduled, headless or hidden script nobody can close the window, so turn it off before the module classes:

```autohotkey
#Include lib\ahk#.ahk
CS.Config.ShowErrorGui := false    ; throw only
CS.Config.NuGetGui := false        ; same for the NuGet progress window
```

Common causes:

- **C# newer than 4.0** (`?.`, `$"..."`, `=>` bodies, `out var`, tuples, pattern matching, records): rewrite in C# 4 or add `static CSVersion := "6.0"` (or newer, up to `"12.0"` / `"latest"`; Roslyn is downloaded once, [Version Targeting](13_version_targeting.md)).
- **`C# 12.0 needs the newer Roslyn compiler, which runs on .NET Framework 4.7.2 or later`** (a `NotSupportedException`). `"11.0"`, `"12.0"`, `"latest"` and `"preview"` use the Roslyn toolset, whose `csc.exe` needs Framework 4.7.2+. Use `static CSVersion := "10.0"` (or lower) on that machine.
- **`Invalid C# language version: ...`.** The version string must match `^[A-Za-z0-9.]{1,12}$` (`"6.0"`, `"12.0"`, `"latest"`).
- **New C# syntax compiles but a library type is missing** (`^1`, `..`, `Span<T>`, `await foreach`, default interface members). A newer `CSVersion` changes the compiler, not the runtime: the code still runs on the .NET Framework 4 CLR, which has none of these ([Version Targeting](13_version_targeting.md#what-runs-syntax-not-new-runtime-apis)). Records and `init` do work (AHK# adds the `IsExternalInit` marker).
- **`A namespace cannot directly contain members such as fields, methods or statements`** in a module that is just methods. A line that starts with `class Name` (or `public class Name`, ...) anywhere in `static CSharp` makes AHK# treat the source as a complete file and skip the wrapping `public class <Name> { ... }`. Write the whole file (with a wrapper class named like the AHK class) or take the nested class out ([CSModule](03_csmodule.md#basic-usage)).
- **Special characters in the source.** Save the `.ahk` file as UTF-8 **with BOM**. C# code full of `"` is easiest to wrap in a single-quoted continuation section, as the files in `ext\` do.
- **Missing assembly.** Add `static References := "Name.dll"` (or `CS.NuGet.Require("Package")`).
- **A module used before its class was defined.** Class bodies initialise in order of appearance; define module classes above the code that calls them.

Compiled modules are cached in `%LocalAppData%\AhkSharp\CompileCache\`. If something looks stale, delete that folder (or use the playground's **Cache** tab); it is rebuilt on demand.

## Error handling

A .NET failure is an ordinary AHK `Error` (message prefixed with the failing call) that also carries the exception's details: `e.NetType` (full type name), `e.NetBases` (base-class names, nearest first), `e.NetStack` (the throw-site frames) and `e.NetHResult`. Test the kind of failure with `CS.ErrorIs`, which is true for the exact type, its short name and any base class:

```autohotkey
try
    CS.System.IO.File.ReadAllText("C:\definitely\not\here.txt")
catch as e {
    if CS.ErrorIs(e, "IOException")
        MsgBox "I/O problem (" e.NetType ")"
    else
        throw e
}
```

- An error with no `NetType` did not come from a .NET exception (for example `AHK# could not resolve '...'`, or a `TimeoutError` from `Await`). Check with `HasProp(e, "NetType")`; `CS.ErrorIs` returns `false` for such an error.
- A failed promise keeps the .NET identity: `Await()` throws `Async operation failed: FormatException: ...` and `.Catch` gets `FormatException: ...`, and both carry `e.NetType`, so `CS.ErrorIs(e, "FormatException")` works there too. Errors from your own callbacks, `CS.Promise.Reject` and `Timeout` (`TimeoutError`) are plain AHK errors without `NetType`.
- Do not test error text when a type exists: `CS.ErrorIs(e, "FormatException")` survives a change of the .NET message.

The full description is in the [API reference](15_api_reference.md#error-handling).

## `AHK# could not resolve '...'`

The name is not a type, method or namespace the runtime knows.

- Check the spelling. Names are case-insensitive, so `CS.system.math` is fine, but `CS.System.Mth` is not. A close match is suggested in the message (`Did you mean 'System.Text.StringBuilder'?`); a misspelled method, property or event says `Did you mean: Abs?`. `CS.Types("System.Text")` lists a namespace and `CS.Members(CS.System.Math, "abs")` a type ([CS Namespace](02_cs_namespace.md#discovering-what-is-there)).
- The type lives in another assembly: `CS.LoadAssembly("C:\path\Lib.dll")` (or an assembly name) first, or reference it from a module (`References`, `CS.NuGet.Require`). Loading anything invalidates the name cache, so this works at any time.
- Generic types need their arguments: `CS.System.Collections.Generic.List(CS.System.String)()` or `List[CS.System.String]()`; plain `List` is not a type.
- The assembly targets .NET 5+ / .NET Core: only .NET Framework 4.x assemblies load (`BadImageFormatException`).
- A .NET exception raised **inside** a call is reported with its own message (for example `System.IO.File.ReadAllText(): Could not find a part of the path '...'`); it is not a resolution problem.

`No overload of X.Y accepts (String, Int32). Candidates: ...` lists what exists; compare with [Marshaling](17_marshaling.md).

## No completion or hover in the editor

`CS.System....` is resolved at run time, so an editor only knows what you declare. Run `CS.Declare("System.Text.StringBuilder", "System.IO")` once (it writes `ahk#.d.ahk` next to `ahk#.ahk`) and reopen the script; the AutoHotkey v2 language server (thqby.vscode-autohotkey2-lsp) needs to be installed. Nothing shows for a type you did not declare, generic types and generic methods are never declared, and the file is stale after you upgrade the library: [Editor Support](21_editor_support.md#limits).

## NuGet failures

`CS.NuGet.Install` and `Require` **throw** on failure. Typical reasons:

- **Offline.** Installing needs `api.nuget.org`; `Require` without a version also asks for the latest version. Pin a version to work offline once the package is cached.
- **Unknown package or version** (HTTP 404). Package ids are case-insensitive but must exist.
- **`... has no assemblies this runtime can load. It offers: net8.0. ...`** (`NotSupportedException`, from `Install`). The package has assemblies, but only for frameworks the .NET Framework 4.x CLR cannot load (`net5.0`+, `netcoreapp*`, `netstandard2.1`). AHK# only picks `net4x` up to the installed Framework, `netstandard1.0`-`2.0` (Framework 4.7.2+) and `net20`-`net35`, and never a folder "because nothing else is there". Pick an older version of the package that still offers one of those (`CS.NuGet.Search("name")` lists the newest version that works here), or leave the version empty so AHK# takes the newest usable release ([NuGet](05_nuget.md#framework-targeting)).
- **`contains no assemblies usable from .NET Framework`.** `Require` found no DLLs at all for the package (for example a metadata-only package).
- **`Require("X")` installed an older version than nuget.org lists.** That is intended: with no version AHK# skips newer releases that only target frameworks it cannot load ("latest that works here"). `CS.NuGet.Search` shows both (`Version` is what is installed, `Latest` what nuget.org lists).
- **TLS.** When the bridge starts it enables TLS 1.2 (and 1.3 where the framework knows it) for the whole process. Very old Windows 7 installs still need TLS 1.2 support installed; corporate proxies that break the handshake also fail here.
- **`failed integrity verification`.** The downloaded `.nupkg` does not hash to the SHA-512 nuget.org publishes for that version; the file was deleted and the install failed. Retry (a truncated download can cause it) and, if it repeats, treat the package as untrusted. The check can be switched off with `CS.Config.VerifyNuGet := false` ([NuGet](05_nuget.md#integrity-check)).
- **`could not be verified ... strict verification is on`.** `CS.Config.NuGetStrict` is `true` and the hash could not be fetched (offline, or nuget.org's metadata service unreachable). Set it back to `false` to install anyway.
- **A dependency was skipped.** Dependencies are installed best effort (this includes a dependency that fails the hash check: it is deleted and skipped); if one cannot be installed you see a `FileNotFoundException` / type-load error when the package first uses it. Install that dependency explicitly with `CS.NuGet.Install`, which shows the real error.
- **`netstandard` packages on old .NET Framework.** `netstandard1.0`-`2.0` builds are only used when Framework 4.7.2+ is installed (it has the `netstandard.dll` facade); on an older Framework such a package offers nothing usable and `Install` throws the `has no assemblies this runtime can load` error above.

For scripts without a user, set `CS.Config.NuGetGui := false`.

## 32-bit and 64-bit

The CLR takes the bitness of the AutoHotkey exe that runs the script (`AutoHotkey64.exe` or `AutoHotkey32.exe`). Managed DLLs built for AnyCPU work in both. **Native** DLLs you P/Invoke or reference must match: a 64-bit `AutoHotkey64.exe` cannot load a 32-bit native DLL and vice versa (`BadImageFormatException`). Pointers travel as integers, so sizes differ between the two.

## Lambdas and results

AHK fat-arrow functions assign **local** variables:

```autohotkey
total := 0
list.Where((x) => total += x)     ; does NOT change the outer total
```

Record results in a Map or object (`state["total"] += x`), or use a named function that declares the variable `global`.

## Async callbacks never fire

`.Then`, `.Catch` and `proxy.On` handlers (and AHK functions called from .NET worker threads) are delivered through window messages and a timer, so **AHK's message pump must be running**: the script needs a GUI, hotkey, timer, `Persistent()` or a `Sleep` / `promise.Await()` in progress. A script whose auto-execute section simply ends exits before anything arrives.

## The AHK thread is not pumping messages

Message (a `TimeoutException`, seen by the .NET worker and usually surfaced through the call that waits for it):

> An AHK function called from a .NET worker thread was not run within 5000 ms: the AHK thread is not pumping messages. This happens when a synchronous .NET call (Parallel.ForEach, Task.Wait, ...) blocks the AHK thread while its workers need AHK. Call it through .Async and Await() the promise, or keep the script idle (Sleep / GUI) while the work runs.

.NET called one of your AHK functions from a worker thread (`Task.Run(fn)`, a timer, an object made with `CS.Implement`). AHK functions only run on the AHK thread, so the call was queued and a `WM_APP+3` message asked the AHK message loop to run it. Nothing ran it within `CS.Config.CallbackTimeoutMs` (default 5000) because the AHK thread was **blocked inside a synchronous .NET call that waits for those workers**: a deadlock, cut short by the timeout (the AHK thread was frozen for that long). Fixes:

- `.Await()` the Task instead of `.Wait()`: `CS.System.Threading.Tasks.Task.Run(fn).Await(5000)` (`Await` keeps AHK's message pump alive).
- Call the blocking .NET method through `.Async` and `Await()` the promise: `obj.Async.Method(args).Await()`.
- Or keep the script idle (`Sleep`, a GUI, `Persistent()`) while the workers run.
- For slow callbacks raise the limit: `CS.Config.CallbackTimeoutMs := 15000`.

Callbacks that .NET makes on the AHK thread itself (`list.Where(fn)`, `list.Sort(fn)`) are direct calls and never hit this. See [Async/Await](04_async.md#ahk-functions-on-net-worker-threads).

## `AHK# bridge DLL does not match the hash pinned in ahk#.ahk`

Message:

> AHK# bridge DLL does not match the hash pinned in ahk#.ahk — refusing to load it.
>   expected `<the hash pinned in ahk#.ahk>`
>   found    `<the hash of the DLL on disk>`
> Rebuild it with lib\build.ps1 -Force, restore the original file, or set CS.Config.VerifyBridge := false.

`Boot()` hashes `lib\ahk#.bridge.dll` (SHA-256) and compares it with `AHK_SHARP_BRIDGE_SHA256` in `lib\ahk#.ahk`. They differ because the DLL was replaced, modified or corrupted, or because `ahk#.ahk` and the DLL come from different versions (an old DLL next to a new `ahk#.ahk`, or the reverse). What to do:

- **Restore both files from the same checkout / release.**
- **You changed `src\` on purpose:** `powershell -File lib\build.ps1 -Force` rebuilds the DLL and rewrites the pin in `ahk#.ahk`. While you iterate, `AHKSHARP_DEV=1` rebuilds on start and skips the check.
- **You do not know why it changed:** treat the DLL as untrusted ([Security](19_security.md)).
- Last resort: `CS.Config.VerifyBridge := false` (before the first `CS` call). That turns the protection off.

The check also applies to a DLL loaded through `CS.Config.BridgeDll`: a compiled script that extracts the bridge with `FileInstall` must bundle the exact `ahk#.bridge.dll` that belongs to its `ahk#.ahk`. It is skipped only when `CS.Config.VerifyBridge` is `false` or `AHKSHARP_DEV` is set.

## `json` versus `Json` (a variable named like a class)

AHK is case-insensitive, so a variable called `json` is the **same name** as the `Json` class (likewise `http` / `Http`, `sqlite` / `SQLite`, `cs` / `CS`). Assigning to it clashes with the class (an error at load time, or a variable that hides the class inside a function), and the next `Json.Query(...)` fails with a confusing error. Give variables other names: `doc := Json.Query(...)`, `body := Http.Get(...)`.

## Values that look wrong

- **A `DateTime` result looks like `20200517134509`.** That is an AHK timestamp (`YYYYMMDDHH24MISS`), the same in every locale: pass it to `FormatTime`, `DateAdd` or `DateDiff`. Fractions of a second are dropped; if you need them, format inside .NET (`CS.Eval('DateTime.Now.ToString("o")')`). A `DateTime` **parameter** takes a timestamp of 4, 6, 8, 10, 12 or 14 digits (`A_Now` works). A `DateTime` you constructed with `CS.System.DateTime(...)` is a proxy, not a timestamp.
- **`bool` is `1` / `0`.** There is no `true`-typed value in AHK, so `sb.Append(true)` chooses `Append(Int32)` and appends `1`. Use `CS.Bool(true)` to pass a real .NET `bool` (`"True"`). A `bool` parameter accepts exactly 0 or 1.
- **`obj.Type` (or `.On`, `.Dispose`, ...) does something different from what the docs say.** The AHK# helpers only apply when the .NET object has no member of that name; a .NET `Type` property wins. `obj._Invoke("Name", args*)` always calls the .NET method, and `CS.ToAHK(x)` / `CS.ToBuffer(x)` never clash.
- **`a == b` is false for two proxies of one object.** Proxies compare by AHK identity. Use `CS.Same(a, b)`.
- **An `out` variable stays empty.** Pass it with `&`: `ok := CS.System.Int32.TryParse("12", &n)`. Without `&var` the out value is dropped. `&var` works on static and instance method calls only (not constructors, `.Async` calls or `_CSModule` methods).
- **An awaited Task throws `Async operation failed: FormatException: ...`.** That is the real .NET error of the faulted task (`Await` unwraps the `AggregateException`); the text after the prefix starts with the .NET exception type name, and `e.NetType` / `CS.ErrorIs(e, "FormatException")` work on it.
- **`UIA2.CrawlTree(...)[0]` fails.** `CrawlTree` and `Find` now return an ordinary 1-based AHK Array of `UIAElement`; use `for el in elements` or `elements[1]`.
- **`SharedMemory.ReadBytes()` is not a `byte[]`.** It returns an AHK `Buffer` (read it with `NumGet` / `StrGet`).
- **Index conventions.** A proxy indexer (`arr[0]`, `list[0]`) is 0-based like C#; the Array from `ToAHK()` is 1-based.
- **A Float where you expected an int.** `Math.Sqrt(144)` is `12.0`. Integral floats are accepted by integer parameters, fractional ones never are.
- **Large numbers as strings.** `UInt64` above `Int64.MaxValue` and `Decimal` return numeric strings.

## Seeing what a call does

- `MsgBox CS.Explain(CS.System.Math, "Abs", -2.5)` lists every overload with its cost or `rejected`; `=>` marks the one that is called. For an object: `CS.Explain(obj, "Method", args*)` or `obj._Explain("Method", args*)`.
- `CS.Config.Trace := (line) => OutputDebug(line)` logs each method call with its result and timing (`System.Math.Abs(-3) => 3  [12.3 us]`); failures are logged with `ERROR`. Set it back to `""` to stop.
- `CS.Stats()` returns the bridge's counters (delegates, pending async tasks, queued callbacks, caches, heap): call it before and after a suspect piece of code to see whether something is left behind ([API reference](15_api_reference.md#csstats)).
- The suites in `tests\` are working examples of every feature ([Testing](20_testing.md)).

## Performance surprises

`Boot()` on the first `CS` call costs about 100 ms; a first compile of a module costs much more (then it is cached). A single bridge call costs microseconds, so a loop of many tiny calls is slow compared with one .NET method that runs the loop. Move the loop into a `_CSModule` and pass arrays (they cross in bulk). See [Architecture](16_architecture.md) for measured numbers.

## Errors from unattended runs

- Set `CS.Config.ShowErrorGui := false` and `CS.Config.NuGetGui := false`.
- Wrap `Await` in a timeout: `promise.Await(10000)` throws `TimeoutError` instead of waiting forever.
- Errors from event handlers surface as ordinary AHK errors through your `OnError` handler.
- An error thrown by your own `.Then` / `.Catch` callback that nothing observes is reported the same way, 100 ms later; attach a `.Catch` to the chain to handle it ([Async/Await](04_async.md#unhandled-errors)). A failed .NET task nobody handles stays silent.
