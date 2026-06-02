# Precompile & Distribute

## Dev Workflow

```Autohotkey
class MyLib extends _CSModule {
    static CSharp := '...'
}

; Export for distribution
MyLib.Precompile(A_ScriptDir '\lib\MyLib.dll')
```

## Distribution

```Autohotkey
class MyLib extends _CSModule {
    static PrecompiledDLL := A_ScriptDir '\lib\MyLib.dll'
}

; Works without csc.exe!
result := MyLib.SomeMethod()
```

End users only need the DLL + AHK script. No compiler required.
