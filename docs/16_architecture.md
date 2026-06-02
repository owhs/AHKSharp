# Architecture

## CLR Bootstrap Sequence

1. AHK loads mscoree.dll via DllCall
2. CorBindToRuntimeEx starts CLR v4.0.30319
3. ICorRuntimeHost::Start() initializes the runtime
4. GetDefaultDomain() gets the default AppDomain
5. Bridge DLL loaded via Assembly.Load(byte[])
6. AhkSharpBridge singleton created
7. IDispatch pointer stored in env var AHKSHARP_PTR
8. AHK retrieves pointer as ComValue(VT_DISPATCH)

## COM Interface

All AHK↔.NET communication uses IDispatch (COM automation):
- Method calls → IDispatch::Invoke
- Property access → IDispatch::GetProperty
- Arguments → VT_VARIANT SafeArrays

## Compilation Pipeline

`
CSModule.CSharp → SHA256 hash → memory cache check → disk cache check
  → CSharpCodeProvider.CompileAssemblyFromSource → cached .dll
  → Assembly.LoadFrom → reflection invoke
`

## Module Cache

Location: %LocalAppData%\AhkSharp\CompileCache\
- Each module gets a {hash16}.dll file
- Hash is computed from source code + references
- Changing source = new hash = recompile
- Same source = cache hit = instant load

## Threading

- AHK: Single-threaded message pump
- .NET: ThreadPool for async operations
- Communication: PostMessage(WM_APP+1) for async, PostMessage(WM_APP+2) for delegates
- All callbacks execute on the AHK main thread (safe)
