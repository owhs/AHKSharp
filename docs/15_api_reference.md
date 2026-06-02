# AHK# v2.0 — Complete API Reference

## CS (Global Router)

| Method/Property | Returns | Description |
|----------------|---------|-------------|
| `CS.{Namespace}.{Class}` | CSProxy/value | Access any .NET type |
| `CS.Eval(expr, refs?)` | any | Evaluate C# expression |
| `CS.Import(namespace)` | CSNamespace | Create namespace alias |
| `CS.GC()` | void | Force garbage collection |
| `CS.Memory()` | int | Get managed heap size (bytes) |
| `CS.Delegate(fn)` | CSDelegateRef | Wrap AHK function as delegate |
| `CS.ModuleRef(modules...)` | string | Get reference paths from modules |
| `CS.Fast` | CSFast | Parallel Map/Filter/Reduce |
| `CS.NuGet` | CSNuGet | NuGet package manager |

## _CSModule

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `CSharp` | string | `""` | C# source code |
| `References` | string | `""` | Assembly references (`;`-separated) |
| `CSVersion` | string | `""` | C# language version (e.g. "7.3") |
| `PrecompiledDLL` | string | `""` | Path to precompiled DLL |

| Method | Returns | Description |
|--------|---------|-------------|
| `Module.Method(args)` | any | Call a static C# method |
| `Module.Async.Method(args)` | CSPromise | Async call via ThreadPool |
| `Module.Precompile(path)` | void | Export DLL for distribution |

## _CSProxy (Object Wrapper)

| Method/Property | Returns | Description |
|----------------|---------|-------------|
| `proxy.Method(args)` | any | Call instance method |
| `proxy.Property` | any | Get property |
| `proxy.Property := val` | void | Set property |
| `proxy[index]` | any | Indexer access |
| `proxy.Async.Method(args)` | CSPromise | Async instance call |
| `proxy.On(event, fn)` | proxy | Subscribe to .NET event |
| `proxy.Type` | string | Get CLR type name |
| `proxy.Raw` | object | Get raw CLR reference |
| `proxy.Members` | string | List all members |
| `proxy.Is(typeName)` | bool | Type check |
| `proxy.Dispose()` | void | Call IDisposable.Dispose() |
| `proxy.ToArray()` | array | Convert collection to AHK array |
| `proxy.ToString()` | string | String representation |

## _CSPromise (Async Result)

| Method/Property | Returns | Description |
|----------------|---------|-------------|
| `promise.Await(timeout?)` | any | Block until complete (default: 30s) |
| `promise.Then(callback)` | promise | Chain success callback |
| `promise.Catch(callback)` | promise | Chain error callback |
| `promise.IsComplete` | bool | Check if finished |

## CS.NuGet (_CSNuGet)

| Method | Returns | Description |
|--------|---------|-------------|
| `CS.NuGet.Install(id, ver?)` | string | Download + extract package |
| `CS.NuGet.Require(id, ver?)` | string | Install if needed, return refs |
| `CS.NuGet.IsInstalled(id, ver?)` | bool | Check if cached |

## CS.Delegate (_CSDelegate)

| Method | Returns | Description |
|--------|---------|-------------|
| `CS.Delegate(fn)` | CSDelegateRef | Register AHK function |
| `ref.Id` | int | Delegate ID |
| `ref.Unregister()` | void | Remove subscription |

## CS.Fast (_CSFast)

| Method | Returns | Description |
|--------|---------|-------------|
| `CS.Fast.Map(arr, lambda, refs?)` | array | Parallel map |
| `CS.Fast.Filter(arr, lambda, refs?)` | array | Parallel filter |
| `CS.Fast.Reduce(arr, lambda, init, refs?)` | any | Parallel reduce |

## Extensions

### Http (ext/ahk#.http.ahk)

| Method | Returns | Description |
|--------|---------|-------------|
| `Http.Get(url, headers?)` | string | HTTP GET |
| `Http.Post(url, body, headers?)` | string | HTTP POST |
| `Http.Put(url, body, headers?)` | string | HTTP PUT |
| `Http.Delete(url, headers?)` | string | HTTP DELETE |
| `Http.Head(url)` | string | HTTP HEAD (status\|type\|server) |
| `Http.Download(url, path)` | void | Download file |
| `Http.Upload(url, path)` | string | Upload file |

### Json (ext/ahk#.http.ahk)

| Method | Returns | Description |
|--------|---------|-------------|
| `Json.Query(json, path)` | string | JSONPath-like query |
| `Json.Stringify(obj)` | string | Object to JSON |
| `Json.Flatten(json)` | string | JSON to key=value lines |
| `Json.Build(k1,v1,k2,v2...)` | string | Build JSON from pairs |
| `Json.IsValid(json)` | bool | Validate JSON |

### SQLite (ext/ahk#.sqlite.ahk)

| Method | Returns | Description |
|--------|---------|-------------|
| `db := SQLite(path)` | SQLite | Open database |
| `db.Execute(sql, params...)` | int | Execute non-query |
| `db.Query(sql, params...)` | array | Execute query → array of maps |
| `db.Scalar(sql, params...)` | any | Execute scalar query |
| `db.Transaction(fn)` | void | Run in transaction |
| `db.LastId` | int | Last insert rowid |
| `db.Close()` | void | Close database |

### SharedMemory (ext/ahk#.ipc.ahk)

| Method | Returns | Description |
|--------|---------|-------------|
| `sm := SharedMemory(name, size?)` | SharedMemory | Create/open |
| `sm.Write(data)` | SharedMemory | Write string |
| `sm.Read()` | string | Read string |
| `sm.Clear()` | SharedMemory | Clear buffer |
| `sm.OnChanged(callback, ms?)` | SharedMemory | Poll for changes |
| `sm.Close()` | void | Close mapping |

## Lower-Level Host (_AhkSharpEngine)

| Method/Property | Returns | Description |
|----------------|---------|-------------|
| `_AhkSharpEngine.Boot()` | ComObject | Start CLR, bootstrap host, and return the underlying raw bridge controller |
| `bridge.InvokeModule(asmId, class, method, args)` | any | Dynamic invocation of compiled C# static methods by assembly ID |

## Version Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `AHK_SHARP_VERSION` | `"2.0.0"` | Library version |
| `AHK_SHARP_CLR` | `"v4.0.30319"` | Target CLR version |
