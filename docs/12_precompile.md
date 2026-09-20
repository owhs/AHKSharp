# Precompile & Distribute

## Dev Workflow

```autohotkey
#Include lib\ahk#.ahk

class MyLib extends _CSModule {
    static CSharp := '...'
}

; Export for distribution
MyLib.Precompile(A_ScriptDir "\lib\MyLib.dll")
```

## Distribution

```autohotkey
#Include lib\ahk#.ahk

class MyLib extends _CSModule {
    static PrecompiledDLL := A_ScriptDir "\lib\MyLib.dll"
}

; Works without compiling anything at run time
result := MyLib.SomeMethod()
```

End users need `ahk#.ahk`, `ahk#.bridge.dll`, your `MyLib.dll` and your AHK script. No compiler is needed for the module. (The bridge DLL itself is prebuilt and committed; `csc.exe` is only needed to rebuild it.)

The module class name is taken from the first public non-abstract class in the DLL. A DLL loaded with `PrecompiledDLL` is trusted as-is: only load DLLs you built or verified ([Security](19_security.md)).

You can also load any other .NET DLL with `CS.LoadAssembly(path)` and use its types through `CS.Namespace.Type` or `CS.CreateObject("Namespace.Type")`.

## Bundling a Compiled Script (Ahk2Exe)

`ahk#.bridge.dll` has to be a real file when the runtime starts, so a script compiled with Ahk2Exe carries it inside the exe and extracts it at run time with `FileInstall`. Copy `lib\ahk#.ahk` and `lib\ahk#.bridge.dll` next to your script, then:

```autohotkey
#Requires AutoHotkey v2.0
#Include ahk#.ahk

DirCreate A_Temp "\myapp"
FileInstall "ahk#.bridge.dll", A_Temp "\myapp\ahk#.bridge.dll", 1     ; 1 = overwrite
CS.Config.BridgeDll := A_Temp "\myapp\ahk#.bridge.dll"                ; load the bridge from the extracted copy

MsgBox CS.System.Math.Pow(2, 10)                                      ; the first CS call boots the runtime
```

Compile with `Ahk2Exe.exe /in myapp.ahk /base AutoHotkey64.exe` (use the 32-bit base for a 32-bit exe). Points to keep in mind:

- Set `CS.Config.BridgeDll` **before the first use of `CS`**, that is before any `_CSModule` class that has C# source is defined (a module compiles when its class is initialised).
- `FileInstall` needs a literal source path; the path is relative to the script being compiled.
- **The hash pin is checked for the extracted copy too.** `Boot()` verifies the SHA-256 of whatever DLL it loads, `CS.Config.BridgeDll` included, whenever `CS.Config.VerifyBridge` is `true` (the default) and `AHKSHARP_DEV` is unset. So bundle the exact `ahk#.bridge.dll` that belongs to the `ahk#.ahk` you compile in (rebuilding with `lib\build.ps1 -Force` re-pins both together); a different build makes `Boot()` throw `AHK# bridge DLL does not match the hash pinned in ahk#.ahk`. See [Security](19_security.md).
- A compiled script has no `build.ps1`: if the DLL is missing `Boot()` throws `AHK# bridge DLL not found` instead of rebuilding.

Modules with a `PrecompiledDLL` are bundled the same way: `FileInstall` the module DLL, then point the class at the extracted copy. Put the `FileInstall` lines **above** the module class, because the class is loaded as soon as its definition is reached:

```autohotkey
FileInstall "MyLib.dll", A_Temp "\myapp\MyLib.dll", 1

class MyLib extends _CSModule {
    static PrecompiledDLL := A_Temp "\myapp\MyLib.dll"
}
```

The end user then needs only the exe: the compiler is not required for the module, and the bridge DLL is unpacked from the exe.
