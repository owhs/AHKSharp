# NuGet Package Manager

Download and use NuGet packages from [nuget.org](https://nuget.org) with one line. Dependencies are installed too.

## Quick Start

```autohotkey
#Include lib\ahk#.ahk

; Install a package (throws on failure)
CS.NuGet.Install("Newtonsoft.Json", "13.0.3")

; Use in a CSModule
class JsonHelper extends _CSModule {
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

The C# is written in C# 4 on purpose (no `?.`) so it compiles with the built-in compiler. To use `?.` or `$"..."` add `static CSVersion := "6.0"` (see [Version Targeting](13_version_targeting.md)).

## API

### `CS.NuGet.Install(packageId, version := "", showGui := unset)`
Downloads and extracts a package **and its dependencies**.
- If `version` is omitted, resolves the latest stable version **that this runtime can load** from nuget.org (needs the network): newer releases that only target frameworks such as `net8.0` are skipped ([Latest means "latest that works here"](#latest-means-latest-that-works-here)).
- Returns the package install directory.
- Cached: an installed package is not downloaded again.
- **Throws** an `Error` on failure (offline, unknown package or version, bad archive). It no longer returns an empty string.
- **Throws** a `NotSupportedException` when the package has assemblies but none this runtime can load; the message names what the package offers ([Framework Targeting](#framework-targeting)):

```autohotkey
CS.NuGet.Install("Aspire.Hosting", "8.2.2")
; NuGet install of 'Aspire.Hosting 8.2.2' failed: Aspire.Hosting 8.2.2 has no assemblies this runtime can load.
; It offers: net8.0. AHK# runs on .NET Framework 4.x (this machine: 4080, netstandard up to 2.0 is usable), so it
; can load net20-net4x and netstandard1.0-2.0 builds, not net5.0+. Try an older version of the package.
```

- `showGui` overrides `CS.Config.NuGetGui` for this call.

### `CS.NuGet.Require(packageId, version := "")`
Installs if needed and returns the semicolon-separated DLL paths of the package and its dependencies, ready for `static References`. Throws if the install fails or if the package contains no assemblies usable from .NET Framework. Pin a version to stay independent of the network once the package is cached (an empty `version` asks nuget.org for the latest usable one every time).

### `CS.NuGet.Search(query, take := 20, includeIncompatible := false)`
Searches nuget.org (needs the network) and returns an **Array of Maps**, best match first:

| Key | Value |
|-----|-------|
| `Id` | package id |
| `Version` | the version `Require` / `Install` would pick for it: the newest stable one this runtime can load |
| `Latest` | the newest stable version nuget.org lists (may be newer than `Version`) |
| `Downloads` | total downloads (Integer) |
| `Description` | one line, cut at 200 characters |

```autohotkey
for p in CS.NuGet.Search("json", 5)
    MsgBox p["Id"] " " p["Version"] " (latest " p["Latest"] ", " p["Downloads"] " downloads)`n" p["Description"]

refs := CS.NuGet.Require(CS.NuGet.Search("newtonsoft.json", 1)[1]["Id"])     ; search, then use the first hit
```

- **Packages with no usable version are hidden** (the check reads each candidate's `.nuspec` dependency groups, a good but not perfect predictor of what `Install` will accept). `includeIncompatible := true` returns every hit as nuget.org ranks it (`Version` then equals `Latest`).
- `take` is limited to 1..100 (anything below 1 means 20). With the filter on, AHK# asks for twice as many hits and drops the unusable ones, so you can get fewer than `take` results.
- Prereleases are not searched. If the `.nuspec` lookup itself fails the package is listed rather than hidden.

### `CS.NuGet.IsInstalled(packageId, version := "")`
Returns `true` if the package (that version, or any version when omitted) is cached.

### `CS.NuGet.Uninstall(packageId, version := "")` / `CS.NuGet.Remove(...)`
Deletes a cached version, or all versions when `version` is empty. Returns `true` on success.

### Headless scripts

```autohotkey
CS.Config.NuGetGui := false        ; never show the progress window
CS.Config.ShowErrorGui := false    ; never show the compile-error window
```

## How It Works

1. Downloads the `.nupkg` from `https://api.nuget.org/v3-flatcontainer/` (TLS 1.2) and verifies its SHA-512 ([Integrity Check](#integrity-check)).
2. Extracts it as ZIP.
3. Selects the best framework folder under `lib\` **for this runtime** ([Framework Targeting](#framework-targeting)): `net4x` up to the Framework installed on the machine, then `netstandard1.0`-`2.0`, then `net20`-`net35`. Nothing newer is ever picked; a package with DLLs directly in `lib\` (old layout) works too. A package that has assemblies but none of these throws `NotSupportedException`.
4. Copies the DLLs to `%LocalAppData%\AhkSharp\Packages\{id}\{version}\lib\` (id lower-cased).
5. Reads the `.nuspec`, picks the dependency group with the same ranking, and installs each dependency at the **lowest version** its range allows. The list is saved in `deps.txt`; `Require` returns the DLLs of the whole tree. Metadata-only packages (`NETStandard.Library`, ...) are skipped, and a dependency that fails to download (or fails the hash check) is skipped rather than failing the whole install.
6. Returns DLL paths for use as CSModule `References`.

Each downloaded package is [checked against the hash nuget.org publishes](#integrity-check). **Signatures and author trust are not checked**, and the package's code runs inside your process. See [Security](19_security.md).

## Integrity Check

Every `.nupkg` AHK# downloads (the package itself, each dependency and the Roslyn compiler) is verified before it is extracted:

1. The published SHA-512 for that **exact id and version** is fetched from nuget.org (registration index, then the catalog entry's `packageHash`).
2. The downloaded file is hashed and compared.
3. **Mismatch:** the file is deleted and `Install` / `Require` throws (`failed integrity verification`).
4. **Hash could not be fetched** (offline metadata service, unexpected format): AHK# continues and records a warning in the bridge's NuGet status text, unless you set `CS.Config.NuGetStrict := true`, which fails the install instead.

```autohotkey
CS.Config.VerifyNuGet := false      ; skip the check entirely (default: true)
CS.Config.NuGetStrict := true       ; also fail when the hash cannot be fetched (default: false)
```

Both are read on every `Install` / `Require` call. A package that is already installed (cached) is not verified again.

What this **does not** say anything about: package **signatures** and **author trust** (they are not checked), and what the package's code does once you use it (it runs in your process, with your rights). The hash tells you the file is the one nuget.org lists for that version, not that the package is safe.

## Framework Targeting

AHK# runs on the .NET Framework 4.x CLR, so a folder built for a newer runtime holds assemblies that call APIs this CLR does not have. Each `lib\` folder (and each dependency group in the `.nuspec`) is ranked, and the best usable one wins:

| Rank | Target folder | Used when |
|------|---------------|-----------|
| 1 (best) | `net48`, `net472`, ... `net45`, `net40` (highest first) | up to the .NET Framework **installed on this machine** (read from the registry `Release` value): on a machine with 4.7.2, `net48` is skipped |
| 2 | `netstandard2.0` ... `netstandard1.0` (highest first) | only when Framework **4.7.2 or later** is installed (older Frameworks lack the `netstandard.dll` facade) |
| 3 | `net35`, `net30`, `net20` | always |
| never | `net5.0` and newer, `netcoreapp*`, `netstandard2.1`, `portable-*`, `uap*`, ... | its assemblies cannot load on the .NET Framework CLR |

A DLL straight in `lib\` (older packages) counts as usable for every framework. Before this rule AHK# fell back to "any folder that has DLLs" and accepted `netstandard2.1`, which could install assemblies that then failed at run time; those folders are now refused up front.

If a package has assemblies but **none** in a usable folder, `Install` deletes the download and throws a `NotSupportedException` that lists what the package offers (see the `Aspire.Hosting` example above). The usual fix is an older version of the package that still targets `netstandard2.0` or `net4x`; `CS.NuGet.Search` shows the newest version of each package that works here.

### Latest means "latest that works here"

With no version, `Install` / `Require` take the newest stable release **whose `.nuspec` lists a dependency group this runtime can use**. A newer release that only targets `net6.0` / `net8.0` is skipped, so `CS.NuGet.Require("SomePackage")` returns the newest version that loads, not simply the newest. Details:

- Only the newest 12 releases are examined. If none passes, the newest release is used and `Install` explains what it offers.
- A release whose `.nuspec` has no dependency groups is assumed usable (it is tried; the real folder check happens on install), and so is one whose `.nuspec` could not be fetched.
- The choice is recorded in the bridge's NuGet status text (`SomePackage 9.0.0 targets only frameworks newer than this runtime; using 8.0.1.`).
- Pin a version to skip all of this: `CS.NuGet.Require("Newtonsoft.Json", "13.0.3")`.

## Progress Window

`Install` shows a small progress window (package name, current status) unless `CS.Config.NuGetGui := false` or you pass `showGui := false`. It closes itself when the install finishes or fails.

## Cache Location

```
%LocalAppData%\AhkSharp\Packages\{package-id}\{version}\
├── lib\          ← Extracted DLLs (best framework folder only)
├── tools\        ← Tool binaries (e.g. the Roslyn compiler)
├── tasks\net472\ ← MSBuild task folder (the newer Roslyn toolset keeps csc.exe here)
├── runtimes\     ← Native runtime binaries
└── deps.txt      ← Installed dependencies (id|version per line)
```

Roslyn is installed here automatically the first time a module uses `CSVersion`: `microsoft.net.compilers` 4.0.1 (`tools\csc.exe`, about 10 MB) for C# up to 10, and `Microsoft.Net.Compilers.Toolset` 4.8.0 (`microsoft.net.compilers.toolset\4.8.0\tasks\net472\csc.exe`, about 20 MB, needs .NET Framework 4.7.2+) for C# 11, 12 and `latest` ([Version Targeting](13_version_targeting.md)).
