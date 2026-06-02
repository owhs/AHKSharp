# AHK#

> Bridge the entire .NET CLR into AutoHotkey v2 through a fluid, native syntax.

## What is AHK#?

AHK# lets you call **any** .NET method, create **any** .NET object, and embed **custom C# code** — all from AutoHotkey v2 with zero setup, zero COM registration, and zero dependencies beyond Windows itself.

```autohotkey
#Include <ahk#>

; Call any .NET method directly
result := CS.System.Math.Pow(5, 3)        ; → 125

; Create .NET objects with fluid chaining
sb := CS.System.Text.StringBuilder()
sb.Append("Hello").Append(" World")
text := sb.ToString()                     ; → "Hello World"

; One-liner C# expressions
guid := CS.Eval("Guid.NewGuid().ToString()")

; Embed full C# classes
class MathHelper extends _CSModule {
    static CSharp := "
    (
        public static double Hypotenuse(double a, double b) {
            return Math.Sqrt(a * a + b * b);
        }
    )"
}
result := MathHelper.Hypotenuse(3, 4)    ; → 5
```

## Features

| Feature | Description |
|---------|-------------|
| **CS.Namespace** | Call any .NET static method, property, or constructor |
| **CS.Eval()** | One-liner C# expression evaluator |
| **CS.Import()** | Namespace aliasing for cleaner code |
| **_CSModule** | Embed C# code in AHK classes, compiled and cached |
| **CS.NuGet** | Download and use NuGet packages with one line |
| **CS.Delegate()** | Pass AHK functions as C# event handlers |
| **CS.ModuleRef()** | Cross-module references between CSModules |
| **CS.GC()** | Garbage collection and memory management |
| **CSVersion** | Target C# 5.0–7.3 via auto-downloaded Roslyn compiler |
| **Precompile** | Export compiled DLLs for zero-dependency distribution |
| **Async/Await** | Non-blocking parallel computation via ThreadPool |
| **Extensions** | Built-in SQLite, HTTP/JSON, IPC, UI, and UIA modules |

## Quick Start

1. Clone or download this repository
2. Run any example: `AutoHotkey.exe examples\01_hello_dotnet.ahk`
3. That's it — the bridge DLL auto-compiles on first run

## Requirements

- **AutoHotkey v2.0+**
- **Windows 7 SP1+** (any Windows with .NET Framework 4.0+)
- No admin rights required
- No Visual Studio required
- No NuGet CLI required

## Architecture

```
AHK Process
  └─ mscoree.dll (CLR Host)
       └─ AppDomain (v4.0.30319)
            └─ AhkSharpBridge.dll (COM-visible)
                 ├─ TypeResolver     (FQN → System.Type)
                 ├─ MarshalEngine    (CLR ↔ SafeArray)
                 ├─ RuntimeCompiler  (CSharpCodeProvider)
                 ├─ AsyncRouter      (ThreadPool → PostMessage)
                 ├─ NuGetManager     (Package download/extract)
                 └─ DelegateBridge   (AHK Func → C# Event)
```

## Documentation

| Doc | Topic |
|-----|-------|
| [Getting Started](docs/01_getting_started.md) | Installation, first script, how it works |
| [CS Namespace](docs/02_cs_namespace.md) | Static calls, properties, constructors |
| [CSModule](docs/03_csmodule.md) | Embedded C# paradigm |
| [Async/Await](docs/04_async.md) | Parallel computation |
| [NuGet](docs/05_nuget.md) | Package management |
| [CS.Eval](docs/06_eval.md) | One-liner expressions |
| [Delegates](docs/07_delegates.md) | Event subscription |
| [HTTP/JSON](docs/08_http_json.md) | Built-in HTTP client |
| [CS.Import](docs/09_import.md) | Namespace aliasing |
| [Cross-Module](docs/10_cross_module.md) | Module references |
| [GC & Memory](docs/11_gc.md) | Garbage collection |
| [Precompile](docs/12_precompile.md) | Distribution workflow |
| [Version Targeting](docs/13_version_targeting.md) | C# version selection |
| [Extensions](docs/14_extensions.md) | SQLite, IPC, UI, UIA |
| [API Reference](docs/15_api_reference.md) | Complete API |
| [Architecture](docs/16_architecture.md) | Internal design |

## 🎮 Developer Playground & Studio

The root directory contains the **Developer Studio Playground**, a powerful visual companion to make scripting, exploring, and testing with AHK# easier:

| Playground | Description |
|------------|-------------|
| [ahk#_playground.ahk](ahk%23_playground.ahk) | **Developer Studio** — GUI with an interactive scratchpad, bidirectional Precompiler/AHK script router, .NET type explorer, NuGet package manager, C# DLL compiler, cache pruner, and live CLR diagnostics |

All workbench modular assets and subclassing scripts reside cleanly inside the [workbench/](workbench/) subdirectory.

## Examples

The [examples/](examples/) directory contains 40 complete scripts demonstrating AHK#'s capabilities, organized into logical categories:

### 📗 Basics
| Example | Description |
|---------|-------------|
| [hello_dotnet.ahk](examples/basics/hello_dotnet.ahk) | Basic CLR interop and loading |
| [csmodule.ahk](examples/basics/csmodule.ahk) | The `_CSModule` base class |
| [cs_eval.ahk](examples/basics/cs_eval.ahk) | One-liner `CS.Eval()` expressions |
| [collections.ahk](examples/basics/collections.ahk) | .NET generic collections |
| [import_namespaces.ahk](examples/basics/import_namespaces.ahk) | Namespace aliasing (`CS.Import`) |

### 🚀 Core Features
| Example | Description |
|---------|-------------|
| [async.ahk](examples/features/async.ahk) | Async/Await & parallel tasks |
| [delegate_events.ahk](examples/features/delegate_events.ahk) | Event subscriptions and callbacks |
| [ipc.ahk](examples/features/ipc.ahk) | High-speed Inter-Process Communication |
| [precompile.ahk](examples/features/precompile.ahk) | Developer to Distribution workflow |
| [nuget_json.ahk](examples/features/nuget_json.ahk) | Using `CS.NuGet` to load packages |
| [cross_module.ahk](examples/features/cross_module.ahk) | Module inter-dependencies |
| [version_targeting.ahk](examples/features/version_targeting.ahk) | Targeting specific C# compiler versions |
| [gc_memory.ahk](examples/features/gc_memory.ahk) | Manual garbage collection |

### 🛠️ Practical Tools
| Example | Description |
|---------|-------------|
| [excel_reader.ahk](examples/tools/excel_reader.ahk) | COM-free high-speed XLSX read/write |
| [profiler.ahk](examples/tools/profiler.ahk) | Head-to-head AHK vs C# benchmarks |
| [regex_workbench.ahk](examples/tools/regex_workbench.ahk) | Live .NET Regex tester |
| [crypto_toolkit.ahk](examples/tools/crypto_toolkit.ahk) | AES encryption & Hashing |
| [file_searcher.ahk](examples/tools/file_searcher.ahk) | Ultra-fast multi-threaded file search |
| [zip_archiver.ahk](examples/tools/zip_archiver.ahk) | Creating and extracting zip files |
| [image_processor.ahk](examples/tools/image_processor.ahk) | Hardware-accelerated image filters |

### 💻 System & Hardware
| Example | Description |
|---------|-------------|
| [toast_notifications.ahk](examples/system/toast_notifications.ahk) | Native Windows 10+ Action Center toasts |
| [memory_bridge.ahk](examples/system/memory_bridge.ahk) | Read/write process memory (Mini Cheat Engine) |
| [file_watcher.ahk](examples/system/file_watcher.ahk) | Instant filesystem change events |
| [xinput_gamepad.ahk](examples/system/xinput_gamepad.ahk) | Live Xbox controller visualizer |
| [wmi_hardware.ahk](examples/system/wmi_hardware.ahk) | WMI hardware and system querying |
| [uia_inspector.ahk](examples/system/uia_inspector.ahk) | UIAutomation accessibility scraping |

### 🌐 Network & Web
| Example | Description |
|---------|-------------|
| [http_api_client.ahk](examples/network/http_api_client.ahk) | Modern HTTP requests |
| [websocket_server.ahk](examples/network/websocket_server.ahk) | Two-way WebSocket communication |

### 🎨 Showcase Demos
| Example | Description |
|---------|-------------|
| [mandelbrot.ahk](examples/showcase/mandelbrot.ahk) | Real-time fractal generation |
| [physics_engine.ahk](examples/showcase/physics_engine.ahk) | 2D particle physics simulation |
| [full_stack.ahk](examples/showcase/full_stack.ahk) | Full application demo |
| [sqlite.ahk](examples/showcase/sqlite.ahk) | Fast SQLite database integration |
| [native_ui.ahk](examples/showcase/native_ui.ahk) | WinForms/WPF bridging |

### ⏱️ Benchmarks
| Example | Description |
|---------|-------------|
| [speed_benchmark.ahk](examples/benchmarks/speed_benchmark.ahk) | Core language operations |
| [ecosystem_benchmark.ahk](examples/benchmarks/ecosystem_benchmark.ahk) | Community libs vs .NET |
