# Cross-Module References

```Autohotkey
class Core extends _CSModule {
    static CSharp := 'public static double Add(double a, double b) => a + b;'
}

class App extends _CSModule {
    static References := CS.ModuleRef(Core)
    static CSharp := 'public static double Sum3(double a, double b, double c) => Core.Add(Core.Add(a,b), c);'
}
```

CS.ModuleRef() returns the compiled DLL path for one or more modules. The dependent module can then call functions from the referenced module directly.
