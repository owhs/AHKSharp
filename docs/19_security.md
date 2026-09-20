# Security

AHK# runs .NET code inside your AutoHotkey process, with your privileges. Anything it loads or compiles can do anything your script can. This page lists what is loaded, from where, and what is **not** verified. None of this is exotic; it is what you accept when you host a runtime and compile code at run time.

## What runs, and what is checked

| What | Where it comes from | Verified? |
|------|--------------------|-----------|
| `lib\ahk#.bridge.dll` | The repository (committed), or built by `build.ps1` | **Integrity check only.** Its SHA-256 must equal `AHK_SHARP_BRIDGE_SHA256` in `lib\ahk#.ahk`, otherwise `Boot()` refuses to load it. That is not a signature and not a link to `src\` (details below). Loaded with `Assembly.Load(byte[])`. `lib\.bridge_hash` is a different thing: a hash of the *sources* used to skip rebuilds |
| Compiled modules, `CS.Eval`, `CS.Fast` lambdas | Your C# source, compiled on this machine | Cached DLLs in `%LocalAppData%\AhkSharp\CompileCache\` are trusted **by source-hash file name only** |
| NuGet packages and dependencies | `api.nuget.org` over HTTPS (TLS 1.2) | **Download integrity only.** The `.nupkg` must match the SHA-512 nuget.org publishes for that exact version (details below). **No signature / author-trust check.** Their code runs in-process |
| Roslyn (`CSVersion`) | `microsoft.net.compilers` 4.0.1 (C# up to 10) or `Microsoft.Net.Compilers.Toolset` 4.8.0 (C# 11, 12, `latest`; about 20 MB) from NuGet | The download gets the same SHA-512 check; the package is otherwise trusted, and its `csc.exe` is executed as a child process |
| DLLs loaded by `CS.LoadAssembly`, `PrecompiledDLL`, `References` | You name them | Not verified. Static constructors and module initialisers run when the code is used |

## The bridge DLL and its pinned hash

Every time `lib\build.ps1` compiles the bridge it writes the DLL's SHA-256 into `AHK_SHARP_BRIDGE_SHA256` in `lib\ahk#.ahk`. `Boot()` hashes `lib\ahk#.bridge.dll` (Windows CNG, `bcrypt.dll`) before loading it and, on a mismatch, throws a clear error with the expected and found hashes instead of loading it ([Troubleshooting](18_troubleshooting.md#ahk-bridge-dll-does-not-match-the-hash-pinned-in-ahkahk)).

What this **does** protect against:

- a DLL that was swapped, patched or corrupted on disk while `ahk#.ahk` stayed as it was;
- a stale DLL next to a newer `ahk#.ahk` (or the reverse), which would otherwise fail in strange ways.

What it does **not** protect against:

- **Anyone who can edit `lib\ahk#.ahk` too.** The pin lives in the folder it guards, so an attacker who can replace the DLL can also replace the hash (or run `build.ps1`, which re-pins on purpose). It is an **integrity check, not a signature**: there is no key and no trust anchor outside the folder.
- **A DLL that does not match `src\`.** The hash says "this is the file `ahk#.ahk` was built with", not "this was built from the sources you read".
- A swap **between** the hash and the load: the file is read twice, once to hash it and once to load it.
- **Anything you switch off:** `CS.Config.VerifyBridge := false` and the environment variable `AHKSHARP_DEV` (set while you rebuild from `src\`, the check is skipped).

The check runs on **whichever file `Boot()` loads**, including one named by `CS.Config.BridgeDll` (for example a copy extracted with `FileInstall`): whenever `CS.Config.VerifyBridge` is `true` (the default) and `AHKSHARP_DEV` is unset, that file's SHA-256 must equal the pin.

Nothing else ties `lib\ahk#.bridge.dll` to the sources in `src\`. If you need to trust it, build it yourself: read `src\`, then `powershell -File lib\build.ps1 -Force`, and use your build (the build re-pins the new DLL's hash in `ahk#.ahk`, so your copy passes the check). `build.ps1` is deterministic in its **inputs** (it compiles every `src\**\*.cs` with the .NET Framework `csc.exe`), but the compiler does not run in deterministic mode, so two builds of the same source do not produce identical bytes and you cannot compare hashes with the committed file. Treat the `lib\` folder like any executable directory: keep it writable only by you.

The pin covers the bridge DLL only. The compile cache, the NuGet and Roslyn files already on disk and every other DLL you load are exactly as unverified as the table above says (a NuGet download is hash-checked once, when it is downloaded).

When the DLL is missing, `Boot()` runs `powershell -NoProfile -ExecutionPolicy Bypass -File lib\build.ps1`. That executes whatever `build.ps1` contains (it also **rewrites `lib\ahk#.ahk`** with the new hash), and with `AHKSHARP_DEV=1` it does so on every start and the hash check is skipped. Do not set `AHKSHARP_DEV` in a shared or production environment, and do not run a library folder you did not fetch yourself.

## The compile cache

Compiled modules are stored as `%LocalAppData%\AhkSharp\CompileCache\{hash}.dll` and loaded when a module's source hash matches the file name. The file's contents are **not** checked. Anyone who can write to that folder (another program running as you, malware, a shared profile) can place a DLL named after a module's hash and it will run inside your script the next time that module loads. The same applies to `%LocalAppData%\AhkSharp\Packages\` for NuGet packages and Roslyn. Protect both folders like a `PATH` entry: do not make them world-writable, and clear them if you suspect tampering (they are rebuilt or re-downloaded on demand).

## Text that becomes code

- `CS.Eval(text)` and the lambda strings of `CS.Fast.Map/Filter/Reduce` are compiled and executed as C#. Never build them from untrusted input (file contents, web responses, user text): that is code injection.
- `_CSModule` source, `References` and `PrecompiledDLL` paths run with your rights.
- `Module.Reload(source)` and `Module.Watch(path)` compile and run whatever they are given or whatever the watched `.cs` file contains, on every change. Keep a watched file (and its folder) writable only by you, and do not use `Watch` in a deployed script.
- A precompiled DLL you receive from someone else is a program. Only load DLLs you built or trust.

## NuGet integrity

Every `.nupkg` that `CS.NuGet.Install` / `Require` downloads (the package, each dependency and Roslyn) is verified before it is extracted:

1. AHK# asks nuget.org's registration service for that exact id and version, follows the catalog entry it returns, and reads the published `packageHash` (SHA-512);
2. it hashes the downloaded file and compares;
3. on a **mismatch** the file is deleted and the install throws (`failed integrity verification`); a dependency that fails is deleted and skipped like any dependency that cannot be installed;
4. if the published hash **cannot be fetched** (offline, service down, unexpected format) it continues with a warning recorded in the NuGet status text, unless `CS.Config.NuGetStrict := true`, which makes that a failure too.

`CS.Config.VerifyNuGet := false` turns the check off.

What this **does** protect against: a truncated or corrupted download, and a `.nupkg` altered in transit or on a mirror while the nuget.org metadata stayed as published.

What it does **not** cover:

- **Package signatures and author trust are not checked.** The hash comes from the same nuget.org that serves the package, so it tells you the file is the one nuget.org lists, not who made it or that it is safe. A malicious package published to nuget.org verifies fine.
- **The package's code runs in your process** with your privileges, and cached packages in `%LocalAppData%\AhkSharp\Packages\` are not re-verified after installation.
- A package whose hash cannot be fetched is installed anyway unless `NuGetStrict` is on.

## Network

NuGet downloads use `https://api.nuget.org/v3-flatcontainer/` with TLS 1.2 and follow whatever the server returns; there is no certificate or server pinning and no signature validation (the SHA-512 check above is the only integrity check). The `Http` extension is a general HTTP client with no restrictions of its own. Pin package versions (`CS.NuGet.Require("Id", "1.2.3")`) so an update cannot change what you run, and prefer packages you recognise.

## IPC and native UI

`SharedMemory` channels are named memory-mapped files guarded by a named mutex. There is no authentication or encryption: any process that knows the name and runs as the same user in the same logon session can read and write the channel. Do not put secrets in one and do not treat its contents as trusted commands.

## ext\ahk#.spatial.ahk

`Spatial` reads text from a screen region using a function that **you must supply** (`Spatial.Reader`; AHK# ships no OCR engine). All it does is poll the region and pass `{text, ...}` (or `{text, match}`) to **your callback**, after your optional `Spatial.Parser`. It does not compile or execute the text itself. If your callback executes what it receives (for example by compiling and running it), then anyone who can put text on that part of the screen controls your script. Do not do that with untrusted screen content.

## Examples that touch other processes

`examples\system\memory_bridge.ahk` (a memory scanner and trainer generator), `frida_process_explorer.ahk` and `frida_browser_hook.ahk` (Frida instrumentation) read, write or hook **other programs**. Use them only on processes you own or are explicitly authorized to inspect. Doing this to online games or other people's software can violate their terms of service and end-user license, is detected by anti-cheat systems (account bans are possible), and can crash or corrupt the target. `memory_target_mock.ahk` exists as a safe target for practising with `memory_bridge.ahk`. The Frida scripts also need the `frida-clr` DLL, which is not shipped here; take it only from the official Frida releases.

## Practical checklist

- Keep `lib\`, `%LocalAppData%\AhkSharp\CompileCache` and `%LocalAppData%\AhkSharp\Packages` writable only by you.
- Pin NuGet versions; review what a package does before you reference it. Leave `CS.Config.VerifyNuGet` on, and consider `CS.Config.NuGetStrict := true`.
- Never feed untrusted text to `CS.Eval`, `CS.Fast` or module `CSharp` sources.
- Unset `AHKSHARP_DEV` outside development, and leave `CS.Config.VerifyBridge` on. The pin only detects a changed DLL: keep `lib\ahk#.ahk` writable only by you as well.
- Load only DLLs you built or verified.
- Use `memory_bridge` and `frida_*` only on your own or explicitly authorized processes.
