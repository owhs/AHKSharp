# Cross-Module References

```autohotkey
#Include lib\ahk#.ahk

class Core extends _CSModule {
    static CSharp := 'public static double Add(double a, double b) { return a + b; }'
}

class App extends _CSModule {
    static References := CS.ModuleRef(Core)
    static CSharp := 'public static double Sum3(double a, double b, double c) { return Core.Add(Core.Add(a, b), c); }'
}

MsgBox(App.Sum3(1, 2, 3))    ; → 6.0
```

`CS.ModuleRef(Core)` returns the compiled DLL path of one or more modules (joined with `;`), so the dependent module can call the referenced module's public classes directly. Define the referenced module first: class bodies initialise in order of appearance.

The example is in C# 4 syntax (a `{ return ...; }` body instead of `=>`). For expression-bodied members and other newer syntax add `static CSVersion := "6.0"` (or a newer one, up to `"12.0"` / `"latest"`) to the module ([Version Targeting](13_version_targeting.md)).
