# NuGet Package Manager

Download and use any NuGet package from [nuget.org](https://nuget.org) with one line.

## Quick Start

```autohotkey
; Install a package
CS.NuGet.Install("Newtonsoft.Json", "13.0.3")

; Use in a CSModule
class JsonHelper extends _CSModule {
    static References := CS.NuGet.Require("Newtonsoft.Json", "13.0.3")
    static CSharp := '
    (
        using Newtonsoft.Json.Linq;
        public static string Query(string json, string path) {
            return JObject.Parse(json).SelectToken(path)?.ToString() ?? "";
        }
    )'
}
```

## API

### `CS.NuGet.Install(packageId, version?)`
Downloads and extracts a NuGet package. Shows a progress GUI during download.
- If `version` is omitted, resolves the latest stable version
- Returns the package install directory path
- Packages are cached — subsequent calls are instant

### `CS.NuGet.Require(packageId, version?)`
Installs if needed and returns semicolon-separated DLL paths.
Designed for use in `static References`:
```autohotkey
static References := CS.NuGet.Require("Newtonsoft.Json", "13.0.3")
```

### `CS.NuGet.IsInstalled(packageId, version?)`
Returns `true` if the package is already cached locally.

## How It Works

1. Downloads `.nupkg` from NuGet v3 flat container API
2. Extracts as ZIP (`.nupkg` files are standard ZIP archives)
3. Selects the best framework target: `net48` → `net472` → `net45` → `netstandard2.0`
4. Copies DLLs to `%LocalAppData%\AhkSharp\Packages\{id}\{version}\lib\`
5. Returns DLL paths for use as CSModule references

## Framework Targeting

The NuGet manager automatically selects the best DLLs for .NET Framework 4.x:

| Priority | Target | Notes |
|----------|--------|-------|
| 1 | `net48` | Best match |
| 2 | `net472` | Very compatible |
| 3 | `net462` | Good |
| 4 | `net45` | Acceptable |
| 5 | `netstandard2.0` | Cross-platform compatible |
| 6 | `netstandard1.x` | Limited API surface |

## Progress GUI

When downloading packages, a small progress window appears:
- Shows package name and current status
- Auto-closes when complete
- Displays error messages if download fails

## Cache Location

All packages are stored in:
```
%LocalAppData%\AhkSharp\Packages\{package-id}\{version}\
├── lib\          ← Extracted DLLs
├── tools\        ← Tool binaries (e.g., Roslyn compiler)
└── runtimes\     ← Native runtime binaries
```
