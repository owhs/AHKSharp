# C# Version Targeting

```Autohotkey
class Modern extends _CSModule {
    static CSVersion := '7.3'
    static CSharp := '...'
}
```

## Available Versions

| Version | Features | Notes |
|---------|----------|-------|
| (default) | C# 4.0 | Built-in csc.exe, always available |
| 5.0 | async/await | Requires Roslyn (auto-downloaded) |
| 6.0 | String interpolation, null-conditional | Requires Roslyn |
| 7.0 | Tuples, pattern matching, out var | Requires Roslyn |
| 7.1-7.3 | Default expressions, ref struct | Requires Roslyn |
| 8.0 | Nullable refs, switch expressions | Partial support on .NET FX |

## First Use

The first compilation with CSVersion downloads the Roslyn compiler (~10MB) from NuGet. Stored in %LocalAppData%\AhkSharp\Packages\microsoft.net.compilers\4.0.1\tools\.
