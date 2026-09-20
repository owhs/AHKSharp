# Marshaling — How Values Convert

Every call crosses COM (IDispatch), where AHK values arrive as Int32 / Int64 / Double / String / SafeArray / COM object. The bridge converts them to whatever the chosen .NET overload needs and converts results back. This page lists the rules. To see what a call would do, use the **Marshalling** and **Overloads** tabs of `ahk#_playground.ahk`.

## AHK → .NET

| AHK value | Becomes | Notes |
|-----------|---------|-------|
| Integer | `Int32` if it fits, else `Int64` | Passed on as the parameter type needs: widening is free; narrowing (to `Int16`, `Byte`, `UInt32`, ...) only if the value **fits**; also to `Double` / `Single` / `Decimal`, to `IntPtr` / `UIntPtr`, to an enum (by number) and to `char` (0–65535) |
| Float | `Double` | To `Single` / `Decimal` as needed. To an integer parameter only if it has **no fractional part** and fits (`3.0` yes, `2.5` never): a value is never truncated |
| String | `string` | Parsed when the parameter needs it: number, enum name (case-insensitive, `"Read, Write"` for flags), `bool` (`"true"` / `"false"`), `char` (1-character string), `Guid`, `Uri`, `TimeSpan`, other types with a string type converter, `Type` (a type name). Numbers are parsed with the invariant culture. A `DateTime` parameter takes an AHK timestamp, see the next row |
| AHK timestamp (string of 4, 6, 8, 10, 12 or 14 digits) | `DateTime` | `YYYY`, `YYYYMM`, `YYYYMMDD`, `YYYYMMDDHH24`, `YYYYMMDDHH24MI` or `YYYYMMDDHH24MISS` (so `A_Now` works): `CS.System.DateTime.Compare("20200101", "20210101")` → `-1`. Other date text goes through the type converter (invariant culture) |
| `""` | `null` | For every reference-type parameter except `string` (AHK has no null). Omitted / unset arguments also arrive as `""` |
| `true` / `false` | `1` / `0` | They are just integers in AHK, so they pick **integer** overloads (`sb.Append(true)` appends `"1"`). A `bool` parameter accepts exactly `0` or `1` (or `"true"` / `"false"`); other numbers do not bind |
| `CS.Bool(true)` | `bool` | A real .NET `bool` (COM `VT_BOOL`): `sb.Append(CS.Bool(true))` appends `"True"` |
| Array | `object[]` | See "Arrays and Maps" below |
| Map | `Dictionary<K,V>` / `IDictionary` | A plain `object` parameter gets `Dictionary<string,object>` (or `<object,object>` if a key is not a string) |
| Buffer | `byte[]` | A copy. To avoid the copy pass **`buf.Ptr`** to an `IntPtr` parameter (zero-copy) |
| Proxy (`_CSProxy`) | the same .NET object | Struct proxies are unwrapped to the struct |
| Type object (`CS.System.String`) | `System.Type` | |
| AHK function / closure / bound method | any delegate type | `Func<>`, `Action<>`, `Comparison<>`, `Predicate<>`, ... See "Callbacks". For an interface, wrap the functions with `CS.Implement` |
| `&var` | `out` / `ref` argument | See "out and ref parameters" |
| COM object (`ComValue`) | passed through | |

An integer or float can also be passed to a `string` parameter (formatted with the invariant culture), but that is the most expensive conversion, so an overload that takes the number directly wins if there is one.

### Overload scoring

Each overload is scored by the total conversion cost and the cheapest wins. Roughly, from cheap to expensive: exact type, assignable type, widening numeric conversion, enum from a number or name, AHK function to delegate, `IntPtr` from integer, `bool` from 0/1, narrowing numeric conversion that fits, Array to a typed array or list, plain `object`, Map to a dictionary, string parsed to a number or other type, params expansion (added on top), number to `string`. A conversion that would lose information (`2.5` to `int`, `300` to `byte`) is rejected outright, which is why `Math.Abs(-2.5)` returns `2.5` and `Math.Max(3.7, 2)` returns `3.7`.

Also supported: **params arrays** (`String.Join(",", "a", "b")`), **optional parameters**, **generic method inference** from the arguments, and **LINQ extension methods** on any `IEnumerable` (`list.Where(fn).Count()`, `Select`, `OrderBy`, `First`, `Any`, `Sum`, ...). When nothing matches, the error lists the candidate overloads.

The winner is cached per argument-type signature when the choice depends on the types alone; choices that depend on values (a string that has to be parsed, a float that has to fit an integer) are re-scored each call.

## out and ref parameters

Pass an AHK variable by reference with `&`. The call returns the method's return value as usual, and the variable receives the value the method assigned:

```autohotkey
ok := CS.System.Int32.TryParse("12", &n)     ; ok → 1, n → 12
ok := CS.System.Int32.TryParse("zz", &n)     ; ok → 0, n → 0 (an out parameter is the default value on failure)

dict.Add("a", 41)
ok := dict.TryGetValue("a", &v)              ; instance call: v → 41

x := 5
CS.System.Threading.Interlocked.Increment(&x) ; ref parameter: takes x's current value and writes it back → x is 6
```

- **`out`**: the variable does not need a value beforehand (an unset variable is passed as "nothing"). **`ref`**: the variable's current value goes in, the new value comes out, so assign the variable first.
- Works for **static and instance method calls** on .NET types and objects (the `&var` form is handled where the call is dispatched). Constructors, `.Async` calls and `_CSModule` methods do not take `&var`.
- Ordinary and `&var` arguments can be mixed in one call. The out value is converted with the usual .NET → AHK rules (`bool` is `1` / `0`, objects arrive as proxies).
- Overload choice, params and optional parameters work as usual; use `CS.Explain` to see the choice ([API reference](15_api_reference.md#developer-tools)).

## Arrays and Maps

AHK Arrays are converted **in bulk**, not element by element (one memory copy instead of one COM call each):

| AHK Array holds | Crosses as |
|-----------------|-----------|
| only Integers | `long[]` |
| Integers and Floats (a Float present) | `double[]` |
| only Strings | `string[]` (one join + one split) |
| anything else (mixed, objects, nested Arrays) | `object[]`, elements converted one by one |

The bridge then converts that to whatever the parameter asks for: `int[]`, `List<int>`, `IEnumerable<string>`, `double[]`, `IList<T>`, ... (element values are checked to fit). Sending 10,000 integers takes about 6 ms (measured).

```autohotkey
CS.System.Linq.Enumerable.Sum([1, 2, 3, 4])                 ; long[] → IEnumerable<long> → 10
CS.System.String.Join("|", ["a", "bb", "", "dddd"])         ; string[] → "a|bb||dddd"
list := CS.System.Collections.Generic.List(CS.System.Int32)([4, 5, 6])   ; List<int>(IEnumerable<int>)
```

A Map becomes a dictionary; keys and values are converted to the dictionary's key and value types:

```autohotkey
d := CS.System.Collections.Generic.Dictionary(CS.System.String, CS.System.Int32)(Map("x", 1, "y", 2))
```

## Callbacks (AHK function → delegate)

Pass an AHK function anywhere a .NET method wants a delegate:

```autohotkey
list.Sort((a, b) => b - a)                 ; Comparison<int>
n := list.Where((x) => x > 4).Count()      ; Func<int,bool>
first := list.OrderBy((x) => x).First()
```

- The function always runs **on the AHK thread**. When .NET calls it on that thread (`list.Where(fn)`, `list.Sort(fn)`, LINQ) it is a **direct call**. When .NET calls it from a **worker thread** (`Task.Run(fn)`, a timer, a pool thread calling an interface made with `CS.Implement`) the call is **queued**: a `WM_APP+3` message wakes the AHK message loop, the AHK thread runs the function and the result goes back to the worker.
- The queued path needs the AHK thread to be **pumping messages** (`Sleep`, a GUI, `promise.Await()`). If the AHK thread is blocked inside a synchronous .NET call that waits for the workers (`Task.Run(fn).Wait()`, `Parallel.ForEach`), the worker gets a `TimeoutException` after `CS.Config.CallbackTimeoutMs` (default 5000): *"An AHK function called from a .NET worker thread was not run within N ms: the AHK thread is not pumping messages ..."*. Call it through `.Async` and `Await()`, or `.Await()` the Task instead of `.Wait()` ([Async/Await](04_async.md#ahk-functions-on-net-worker-threads)).
- For events use `proxy.On(...)` ([Delegates](07_delegates.md)); to hand .NET a whole object that implements an interface, use `CS.Implement`.
- Arguments arrive as AHK values (objects as proxies). The function may declare fewer parameters than the delegate has.
- The return value is converted to the delegate's return type by the rules above (`1` / `0` for `bool`); a function that returns nothing yields `default(T)`.
- AHK fat-arrow functions assign **local** variables. `(x) => total += x` does not change an outer `total`; record results in an object or Map.

## .NET → AHK

| .NET value | AHK gets | Notes |
|------------|----------|-------|
| `bool` | `1` / `0` | |
| `byte`, `sbyte`, `short`, `ushort`, `int`, `uint`, `long` | Integer | |
| `ulong` | Integer, or a **numeric string** above `Int64.MaxValue` | |
| `float`, `double` | Float | |
| `decimal` | numeric **string** | Full precision, invariant culture |
| `char` | 1-character string | |
| `string` | string | |
| `enum` | its name as a string | `CS.System.DayOfWeek.Friday` → `"Friday"` |
| `Guid`, `TimeSpan`, `DateTimeOffset` | string | From calls and properties; the binder parses the string back when you pass it to a parameter of that type. A `TimeSpan` **constructed** from AHK stays a proxy |
| `DateTime` | AHK **timestamp** string `YYYYMMDDHH24MISS` | Locale-independent; works with `FormatTime`, `DateAdd`, `DateDiff`. Fractions of a second are dropped. It converts back to a `DateTime` when passed to a `DateTime` parameter |
| `IntPtr`, `UIntPtr` | Integer | |
| Any **other struct**, from a call, a property or a constructor (`CancellationToken`, `Point`, `Size`, `Rectangle`, `Color`, `KeyValuePair`, `DateTime(2020,5,17)`, `TimeSpan(...)`) | proxy | A real object you can read (`rect.Location.X`), call and **pass back to .NET** (`Task.Delay(500, cts.Token)`). Calls on a struct proxy that return structs also give proxies (`.ToString("yyyy-MM-dd")` works) |
| Arrays | proxy of the **real** array | See below |
| `Task` / `Task<T>` | proxy | Awaitable: `task.Await(ms)`, `task.Then(cb)`, `task.Catch(cb)`, `task.ToPromise()`; see below |
| Any other object | proxy | |

```autohotkey
CS.System.DateTime(2020, 5, 17).ToString("yyyy-MM-dd")       ; → "2020-05-17"  (a constructed DateTime stays a proxy)
CS.System.DateTime.Parse("2020-05-17 13:45:09")              ; → "20200517134509"  (a DateTime RESULT is an AHK timestamp)
FormatTime(CS.System.DateTime.Parse("2020-05-17 13:45:09"), "yyyy-MM-dd HH:mm")   ; → "2020-05-17 13:45"
CS.System.DateTime.DaysInMonth(2024, 2)                      ; → 29
CS.System.UInt64.MaxValue                                    ; → "18446744073709551615" (a string)
CS.System.TimeSpan(0, 0, 90).TotalSeconds                    ; → 90.0

; a struct RESULT stays a real object, so it can go straight back into .NET
cts := CS.System.Threading.CancellationTokenSource()
CS.System.Threading.Tasks.Task.Delay(500, cts.Token).Await(3000)    ; cts.Token is a CancellationToken proxy
rect := CS.System.Drawing.Rectangle(1, 2, 30, 40)
MsgBox rect.Location.X                                       ; → 1  (Location is a Point proxy)
```

### Arrays are references

A .NET array returned to AHK is **not** copied. The proxy refers to the real array, so reading, writing, `Length`, `for ... in` and passing it back to .NET all act on the same array:

```autohotkey
arr := CS.System.Text.Encoding.UTF8.GetBytes("héllo")      ; byte[] proxy
arr.Length                                                 ; → 6
arr[0] := 72                                               ; writes into the real array (index is 0-based, like C#)
CS.System.Array.Sort(arr)                                  ; sorts that array in place
```

Note the two index conventions: a proxy indexer (`arr[i]`, `list[i]`) uses .NET **0-based** indexes; an AHK Array from `ToAHK()` is **1-based**.

Multi-dimensional arrays and indexers with several parameters take all the indexes in one bracket, for reading and writing:

```autohotkey
m := CS.System.Array.CreateInstance(CS.System.Int32, 2, 3)   ; int[2, 3]
m[1, 2] := 7                                                 ; row, column (0-based)
MsgBox m[1, 2]                                               ; → 7
```

A wrong number of indexes throws an error that mentions the indexer.

### Tasks become promises

A proxy that holds a `System.Threading.Tasks.Task` has extra members (`Await`, `Then`, `Catch`, `Finally`, `Timeout`, `ToPromise`) that turn it into an AHK# promise ([Async/Await](04_async.md#net-tasks)):

```autohotkey
client := CS.System.Net.Http.HttpClient()
html := client.GetStringAsync("https://example.com").Await(15000)      ; the Task<string>'s result; TimeoutError after 15 s
client.GetStringAsync(url).Then((html) => ...).Catch((e) => ...)      ; callbacks on the AHK thread
CS.System.Threading.Tasks.Task.Delay(100).Then((*) => ToolTip("done"))
```

The result of a `Task<T>` is marshaled like any other return value; a faulted task's `Await` throws with the real .NET error message (and keeps `e.NetType`). `obj.Async.Method()` on a method that returns a Task unwraps the task's result for you.

### Converting to native AHK

| Call | Result |
|------|--------|
| `proxy.ToAHK()` | Array (1-based) for arrays, lists and any `IEnumerable`; Map for dictionaries. Homogeneous number / string collections are read straight from memory (10,000 ints in about 3 ms, measured); other element types are read one by one (objects become proxies) |
| `for x in proxy` | Iterates natively. Collections (`ICollection`: lists, arrays, sets, ...) are read in bulk first (a snapshot); lazy sequences (LINQ, `File.ReadLines`) are pulled one item at a time |
| `for k, v in proxy` | `(key, value)` for dictionaries, `(index, value)` for lists and arrays |
| `proxy.ToBuffer()` | Copies a **primitive** array (`byte[]`, `int[]`, `double[]`, ...) into an AHK `Buffer` with **one** `memcpy`. Read it with `NumGet` / `StrGet` |
| `proxy.FromBuffer(buf, bytes := buf.Size)` | Fills a primitive .NET array from a Buffer with one `memcpy`; returns the proxy. Throws if the array is too small |

```autohotkey
bytes := CS.System.Text.Encoding.UTF8.GetBytes("héllo wörld")
buf := bytes.ToBuffer()
MsgBox(StrGet(buf, buf.Size, "UTF-8"))                      ; → héllo wörld

ints := CS.System.Linq.Enumerable.ToArray(CS.System.Linq.Enumerable.Range(10, 5))
ib := ints.ToBuffer()
MsgBox(NumGet(ib, 0, "Int"))                                ; → 10

target := CS.System.Array.CreateInstance(CS.System.Byte, 4)
b2 := Buffer(4), NumPut("UInt", 0x04030201, b2)
target.FromBuffer(b2)
MsgBox(target.ToAHK()[1])                                   ; → 1
```

### ToString and the proxy rule (.NET always wins)

`proxy.ToString(args*)` is simply the .NET `ToString`, with whatever arguments you pass: `number.ToString("X2")`, `dt.ToString("yyyy-MM-dd")`.

AHK# adds helper members to every proxy: `ToAHK`, `ToArray`, `ToBuffer`, `FromBuffer`, `ToPromise`, `Await`, `Then`, `Catch`, `Finally`, `Timeout`, `On`, `Off`, `Is`, `Dispose`, `AutoDispose` and the property helpers `Type`, `Raw`, `Members`. Each is used **only when the .NET object has no public instance member of that name** (checked and cached per type), so a .NET class with its own `Type` property or `On()` method behaves exactly as .NET defines it. Two ways never clash:

```autohotkey
proxy._Invoke("On", "x")                                     ; always the .NET method, whatever helpers exist
CS.System.Text.StringBuilder("hi")._Invoke("ToString")       ; → "hi"
CS.ToAHK(list)                                               ; the function forms CS.ToAHK(x) / CS.ToBuffer(x)
```

When the helper is what you get: `proxy.Type` is the CLR type name, `proxy.Is("System.Collections.IList")` a type test, `proxy.Members` a `"K:Name|K:Name"` list of members, `proxy.Raw` the raw COM object, `proxy.Dispose()` calls `IDisposable.Dispose` (or a plain public `Dispose()`), `proxy.AutoDispose()` disposes when the last AHK reference goes away. `Async` is always AHK#'s ([Async/Await](04_async.md)).

## Quick reference of gotchas

- `bool` is `1` / `0` both ways; `CS.Bool(x)` passes a real .NET `bool` (`sb.Append(true)` → `"1"`, `sb.Append(CS.Bool(true))` → `"True"`).
- A `DateTime` result is an AHK timestamp (`YYYYMMDDHH24MISS`); a `DateTime` parameter accepts one (4, 6, 8, 10, 12 or 14 digits). A constructed `DateTime` is a proxy.
- A proxy's own helper names give way to .NET members of the same name; `_Invoke` forces the .NET call.
- Proxy indexers are 0-based; `ToAHK()` arrays are 1-based.
- Integral Floats (`3.0`) may go to integer parameters; fractional ones never do.
- Callbacks: always run on the AHK thread (queued when .NET is on a worker thread, which needs the pump), lambdas assign locals.
- `out` / `ref` values come back through `&var` (method calls only).
- A Task proxy is awaitable (`.Await`, `.Then`, `.Catch`, `.Finally`, `.Timeout`); do not `.Wait()` on it from AHK when it needs an AHK callback.
