# Getting Started with AHK#

## Installation

1. **Clone or download** the AHK# repository
2. **Run any example**: `AutoHotkey.exe examples\01_hello_dotnet.ahk`
3. The bridge DLL auto-compiles on first run via `build.ps1`

No admin rights, no Visual Studio, no NuGet CLI required.

## Requirements

| Requirement | Details |
|-------------|---------|
| AutoHotkey | v2.0+ |
| Windows | 7 SP1+ / 8 / 8.1 / 10 / 11 |
| .NET Framework | 4.0+ (pre-installed on all supported Windows) |
| Disk space | ~60KB for bridge DLL |

## Your First Script

```autohotkey
#Requires AutoHotkey v2.0
#Include <ahk#>

; Call any .NET method
result := CS.System.Math.Pow(2, 10)
MsgBox("2^10 = " result)    ; → 1024

; Create .NET objects
sb := CS.System.Text.StringBuilder()
sb.Append("Hello from AHK#!")
MsgBox(sb.ToString())

; One-liner C# expressions
guid := CS.Eval("Guid.NewGuid().ToString()")
MsgBox("GUID: " guid)
```

## How It Works

1. **CLR Bootstrap**: AHK loads `mscoree.dll` and starts the .NET CLR v4.0.30319
2. **Bridge Load**: `AhkSharpBridge.dll` is loaded into the default AppDomain
3. **COM Interface**: AHK communicates with the bridge via IDispatch (COM automation)
4. **Reflection**: The bridge uses `System.Reflection` to invoke any .NET type

```
Your AHK Script
  → #Include <ahk#>
    → _AhkSharpEngine.Boot()
      → mscoree.dll (CorBindToRuntimeEx)
        → CLR v4.0.30319 AppDomain
          → AhkSharpBridge (COM-visible singleton)
            → TypeResolver + MarshalEngine + RuntimeCompiler
```

## Why .NET Framework v4.0.30319?

This is the widest natively-compatible runtime on Windows:

- **Windows 7 SP1+**: .NET 4.0 included via Windows Update
- **Windows 8/8.1**: .NET 4.5 pre-installed (runs 4.0 code)
- **Windows 10/11**: .NET 4.8 pre-installed (runs 4.0 code)

Result: **ZERO dependency installs** on any supported Windows version.

## Project Structure

```
AHK#/
├── lib/
│   ├── ahk#.ahk              ← Main library (include this)
│   ├── ahk#.bridge.dll       ← Auto-compiled bridge DLL
│   └── build.ps1             ← Build script
├── src/
│   ├── bridge/
│   │   ├── AhkSharpBridge.cs  ← Core bridge C# source
│   └── swarm/
│       ├── MemoryMappedIpc.cs  ← IPC extension
│       ├── NativeUi.cs         ← WinForms embedding
│       ├── PhantomSqlite.cs    ← SQLite via winsqlite3
│       └── UiaDeepCrawler.cs   ← UIAutomation
├── ext/
│   ├── ahk#.http.ahk          ← Built-in HTTP/JSON
│   ├── ahk#.sqlite.ahk        ← SQLite wrapper
│   ├── ahk#.ipc.ahk           ← Memory-mapped IPC
│   ├── ahk#.ui.ahk            ← Native UI controls
│   └── ahk#.uia.ahk           ← UIAutomation
├── examples/
│   ├── 01_hello_dotnet.ahk     ← ... through ...
│   └── 35_gc_memory.ahk       ← 35 examples
├── docs/                       ← Documentation
└── README.md                   ← This file
```

## Next Steps

- [CS Namespace](02_cs_namespace.md) — Call any .NET method
- [CSModule](03_csmodule.md) — Embed C# code in AHK
- [NuGet](05_nuget.md) — Use NuGet packages
- [CS.Eval](06_eval.md) — One-liner expressions
