# CS Namespace — Call Any .NET Method

The `CS` class is the global entry point for all .NET interop.

## Static Methods

```autohotkey
; CS.{Namespace}.{Type}.{Method}(args)
result := CS.System.Math.Pow(5, 3)           ; → 125.0 (Double)
sqrt := CS.System.Math.Sqrt(144)             ; → 12.0
abs := CS.System.Math.Abs(-42)               ; → 42 (Int32 overload)
abs := CS.System.Math.Abs(-2.5)              ; → 2.5 (Double overload; never rounded)
```

## Static Properties

```autohotkey
machine := CS.System.Environment.MachineName ; → "MY-PC"
cpus := CS.System.Environment.ProcessorCount ; → 8
os := CS.System.Environment.OSVersion        ; → a proxy (System.OperatingSystem)
day := CS.System.DayOfWeek.Friday            ; → "Friday" (enums come back as strings)
```

Static properties can be assigned too: `CS.System.Environment.CurrentDirectory := "C:\Temp"`.

## Name Resolution

`CS.System.Math` becomes a **type object** as soon as the dotted path names a .NET type; before that it is a namespace object that just collects names. Consequences:

- Names are **case-insensitive**: `CS.system.math.pow(2, 10)` works.
- Types from other assemblies need `CS.LoadAssembly(path)` first (or a NuGet reference / `References`); an unknown name throws `AHK# could not resolve '...'`.
- `CS("Type.Name")` returns a type object from a string, handy when the name is built at run time:

```autohotkey
T := CS("System.Text.StringBuilder")
sb := T("start")                             ; same as CS.System.Text.StringBuilder("start")
os := CS("System.Environment").OSVersion
```

- Nested types are reached like properties: `CS.System.Environment.SpecialFolder`.

## Constructors

Call the type like a function. Both spellings work (the name is resolved either way):

```autohotkey
sb := CS.System.Text.StringBuilder()         ; new StringBuilder()
list := CS.System.Collections.ArrayList()    ; new ArrayList()
uri := CS.System.Uri("https://example.com")  ; new Uri(string)
d := CS.System.DateTime(2020, 5, 17)         ; a struct: stays a usable proxy
MsgBox(d.ToString("yyyy-MM-dd"))             ; → 2020-05-17
```

## Generic Types

Two equivalent forms; type arguments are type objects (or full-name strings):

```autohotkey
; List<string>
list := CS.System.Collections.Generic.List(CS.System.String)()
list := CS.System.Collections.Generic.List[CS.System.String]()   ; bracket form
list.Add("Alice")
list.Add("Bob")

; Dictionary<string, int>
dict := CS.System.Collections.Generic.Dictionary(CS.System.String, CS.System.Int32)()
dict.Add("score", 100)
dict["level"] := 7                           ; indexer set: key/value converted to string/int
MsgBox(dict["score"])                        ; → 100

; Generic arguments may come from any loaded assembly (MyLib.Widget is a made-up example)
CS.LoadAssembly(A_ScriptDir "\MyLib.dll")
items := CS.System.Collections.Generic.List(CS.MyLib.Widget)()
```

Generic **methods** (e.g. `Enumerable.Select`) are inferred from the call arguments. When inference cannot guess the type arguments, pass them with `CS.CallGeneric`:

### Explicit generic arguments

`CS.CallGeneric(typeOrProxy, "Method", typeArgOrArray, args*)` calls a generic method with the type arguments you give (one type object, or an Array of them). It works on a type (static method) or a proxy (instance method):

```autohotkey
empty := CS.CallGeneric(CS.System.Linq.Enumerable, "Empty", CS.System.Int32)          ; Enumerable.Empty<int>()
sb := CS.CallGeneric(CS.System.Activator, "CreateInstance", [CS.System.Text.StringBuilder])   ; Activator.CreateInstance<StringBuilder>()
sb.Append("ok")
```

A wrong number of type arguments is reported as `No generic overload ...`.

## Fluid Chaining

Every returned .NET object is wrapped in a proxy (`_CSProxy`), so calls chain:

```autohotkey
sb := CS.System.Text.StringBuilder()
sb.Append("Hello").Append(", ").Append("World!")
text := sb.ToString()  ; → "Hello, World!"
```

### The proxy rule: .NET always wins

AHK# adds a few helper members to every proxy:

| Kind | Names |
|------|-------|
| Methods | `ToAHK`, `ToArray`, `ToBuffer`, `FromBuffer`, `ToPromise`, `Await`, `Then`, `Catch`, `Finally`, `Timeout`, `On`, `Off`, `Is`, `Dispose`, `AutoDispose` |
| Properties | `Type`, `Raw`, `Members` |

A helper is used **only when the .NET object has no public instance member of that name** (case-insensitive; checked once per type and cached). If the class has its own `Type` property or `On()` method, you get exactly what .NET defines. `proxy.ToString(...)` is simply the .NET `ToString`, with any arguments you pass.

```autohotkey
class Widget extends _CSModule {
    static CSharp := '
    (
        public class Inner {
            public string Type { get { return "widget"; } }       // clashes with the AHK# Type helper
            public string On(string e) { return "on:" + e; }      // clashes with the AHK# On helper
        }
        public class Widget {
            public static object Make() { return new Inner(); }
        }
    )'
}

w := Widget.Make()
w.Type                       ; → "widget"  (the .NET property wins)
w.On("x")                    ; → "on:x"    (the .NET method wins)
w._Invoke("On", "q")         ; → "on:q"    _Invoke always forces the .NET call

list := CS.System.Collections.Generic.List(CS.System.Int32)()
list.Type                    ; List<T> has no member called Type, so this is the AHK# helper: the CLR type name
```

Two escape hatches never clash with .NET:

- `proxy._Invoke("Name", args*)` calls the .NET method `Name`, whatever AHK# helpers exist (`_Invoke` and `_Explain` are AHK#'s own underscore members).
- `CS.ToAHK(x)` and `CS.ToBuffer(x)` are the function forms of `ToAHK()` / `ToBuffer()`.

The one exception is `.Async` (`obj.Async.Method()` runs the call on the ThreadPool): it is always AHK#'s, even if the .NET type has a member called `Async`.

## Overload Resolution

The bridge scores every overload by conversion cost and calls the cheapest; an exact type match always wins and a **lossy conversion is never chosen**:

```autohotkey
CS.System.Math.Abs(-2.5)                     ; → 2.5   (not rounded to an int)
CS.System.Math.Max(3.7, 2)                   ; → 3.7
CS.System.String.Join(",", "a", "b", "c")    ; params array → "a,b,c"
CS.System.String.Join(",", [1, 2, 3])        ; AHK Array → IEnumerable → "1,2,3"
CS.System.Uri("http://a.b/c?d=1").Host       ; optional parameters may be omitted
CS.System.Convert.ToString(255, 16)          ; → "ff" (ToString(Int32, Int32) chosen by argument types)
```

What you get for free:

- **params arrays**, **optional parameters**, **generic method inference**;
- **LINQ extension methods on any `IEnumerable`**: `list.Where(fn).Count()`, `Select`, `OrderBy`, `First`, `Any`, `Sum`, ...;
- **enum parameters** from a name (`"Friday"`) or an integer, **IntPtr** from an integer, **Guid / Uri / TimeSpan / Type** parameters from strings, and `""` as null for reference-type parameters;
- **DateTime parameters** from an AHK timestamp of 4, 6, 8, 10, 12 or 14 digits (`"20200101"`, `A_Now`): `CS.System.DateTime.Compare("20200101", "20210101")` → `-1`;
- an error that lists the candidate overloads when nothing matches.

### bool and DateTime

AHK's `true` / `false` are the integers `1` / `0`, so they choose **integer** overloads. `CS.Bool(x)` passes a real .NET `bool`:

```autohotkey
sb := CS.System.Text.StringBuilder()
sb.Append(true)                  ; → "1"     (Append(Int32))
sb.Append(CS.Bool(true))         ; → "True"  (Append(Boolean))
```

A `DateTime` that .NET returns arrives as an **AHK timestamp** (`YYYYMMDDHH24MISS`, independent of the system locale), so it works with `FormatTime`, `DateAdd` and `DateDiff`:

```autohotkey
t := CS.System.DateTime.Parse("2020-05-17 13:45:09")     ; → "20200517134509"
MsgBox FormatTime(t, "yyyy-MM-dd HH:mm")                 ; → 2020-05-17 13:45
MsgBox CS.System.DateTime.Compare(t, A_Now)              ; → -1 (a timestamp goes back in as a DateTime)
```

Fractions of a second are not part of a timestamp. A `DateTime` you **construct** (`CS.System.DateTime(2020, 5, 17)`) stays a usable proxy.

### out / ref parameters

Pass the variable by reference with `&`. The method's return value is returned as usual and the variable receives what the method assigned:

```autohotkey
ok := CS.System.Int32.TryParse("12", &n)     ; ok → 1, n → 12   (the variable needs no value beforehand)
ok := CS.System.Int32.TryParse("zz", &n)     ; ok → 0, n → 0    (the out value is the default)

d := CS.System.Collections.Generic.Dictionary(CS.System.String, CS.System.Int32)()
d.Add("a", 41)
ok := d.TryGetValue("a", &v)                 ; instance call: v → 41

x := 5
CS.System.Threading.Interlocked.Increment(&x) ; a ref parameter reads x and writes it back: x → 6
```

Works for static and instance method calls. See [Marshaling](17_marshaling.md#out-and-ref-parameters) for the rules.

### Seeing how an overload is chosen

```autohotkey
MsgBox CS.Explain(CS.System.Math, "Abs", -2.5)   ; every overload with its cost or "rejected"; "=>" marks the winner
```

Details and the full conversion tables are in [Marshaling](17_marshaling.md); `CS.Explain`, `CS.Config.Trace` and `CS.Wrap` are described in the [API reference](15_api_reference.md#developer-tools).

## Discovering what is there

`CS.Members` and `CS.Types` answer "what can I call?" from AHK, and a typo tells you what you probably meant:

```autohotkey
MsgBox CS.Members(CS.System.Math, "abs")             ; a type: one line per public member whose name contains "abs"
                                                     ;   static double Abs(double value)  (and the other overloads)
MsgBox CS.Members(CS.System.Text.StringBuilder(), "AppendLine")   ; an object: its instance members
                                                     ;   StringBuilder AppendLine(string value)  ...
MsgBox CS.Members("System.IO.Path")                  ; a type-name string works too

MsgBox CS.Types("System.IO")                         ; types and child namespaces directly in a namespace:
                                                     ;   System.IO.File  (static class)
                                                     ;   System.IO.Compression.*   (a child namespace)
MsgBox CS.Types(CS.System.Timers, "Timer")           ; a namespace object, filtered by name
```

- `CS.Members(target, filter := "")` lists constructors (`new X(...)`), methods, properties, fields, events (`event ... Name`) and nested types, sorted by name; `filter` is a case-insensitive substring of the member name. A namespace object is passed on to `CS.Types`.
- `CS.Types(namespace, filter := "")` lists public types (`(static class)`, `(interface)`, `(enum)`, `(struct)` noted) and child namespaces (`Sub.*`) from the loaded framework assemblies plus anything you loaded with `CS.LoadAssembly`.
- A misspelled name ends its error with a suggestion (nothing close enough: no hint):

```autohotkey
CS.System.Math.Abss(1)                ; ... Did you mean: Abs?
CS.System.Text.StringBuilder().Lenght ; ... Did you mean: Length?
CS.System.Tex.StringBuilder()         ; ... Did you mean 'System.Text.StringBuilder'?
CS.System.String.Length               ; ... 'Length' is an instance member: call it on an object.
```

Method, property, static property, event, type and namespace typos all get this. For completion **in your editor** instead of at run time, see [Editor Support](21_editor_support.md) (`CS.Declare`).

## Collections and Arrays

```autohotkey
list := CS.System.Collections.Generic.List(CS.System.Int32)()
list.Add(5), list.Add(3), list.Add(9)

for x in list                                ; collections iterate natively
    MsgBox(x)
arr := list.ToAHK()                          ; → native Array [5, 3, 9] (1-based)
n := list.Where((x) => x > 4).Count()        ; AHK lambda as a .NET delegate → 2
list.Sort((a, b) => b - a)                   ; Comparison<int> from an AHK function

m := CS.System.Array.CreateInstance(CS.System.Int32, 2, 3)   ; int[2, 3]
m[1, 2] := 7                                 ; multi-dimensional and multi-parameter indexers: proxy[i, j]
MsgBox(m[1, 2])                              ; → 7
```

Structs that .NET returns (`CancellationToken`, `Point`, `Rectangle`, `Color`, `KeyValuePair`, ...) stay usable proxies: read their members (`rect.Location.X`) or hand them straight back to .NET (`Task.Delay(500, cts.Token)`). Only enums, `Guid`, `TimeSpan` and `DateTimeOffset` come back as strings, which the binder parses back when you pass them on; `DateTime` is an AHK timestamp ([Marshaling](17_marshaling.md)).

## File I/O

```autohotkey
; Write and read files
CS.System.IO.File.WriteAllText("test.txt", "Hello AHK#")
content := CS.System.IO.File.ReadAllText("test.txt")

; With namespace alias (CS.Import)
IO := CS.Import("System.IO")
IO.File.WriteAllText("test.txt", "Hello")
exists := IO.File.Exists("test.txt")         ; → 1 (bool is 1/0 in AHK)
```

## Error Handling

.NET exceptions reach AHK as normal errors with clean messages, prefixed by the call that failed:

```autohotkey
try {
    CS.System.IO.File.ReadAllText("C:\nonexistent.txt")
} catch as e {
    MsgBox("Error: " e.Message)
    ; → System.IO.File.ReadAllText(): Could not find a part of the path 'C:\nonexistent.txt'.
}
```

A wrong name is reported as such (`AHK# could not resolve ...`, or `No overload of ... accepts (...). Candidates: ...`); a real .NET exception is never masked as "could not resolve".

The error also carries the .NET exception's details, so you can react to the **kind** of failure instead of matching message text:

```autohotkey
try {
    CS.System.IO.File.ReadAllText("C:\definitely\not\here.txt")
} catch as e {
    if CS.ErrorIs(e, "IOException")           ; true for the exact type, its short name and any base class
        MsgBox("I/O problem: " e.NetType)     ; → System.IO.DirectoryNotFoundException
    else
        throw e
}
```

`e.NetType`, `e.NetBases`, `e.NetStack` and `e.NetHResult` are described in the [API reference](15_api_reference.md#error-handling).

## Identity and Lifetime

```autohotkey
sb := CS.System.Text.StringBuilder()
same := sb.Append("x")                        ; Append returns the same .NET object, wrapped in a NEW proxy
CS.Same(sb, same)                             ; → 1   (are these the same .NET object?)
sb == same                                    ; → 0   (proxies compare by AHK identity, so == is not the test)

; scoped disposal: fn(obj) runs, then Dispose, even if fn throws; the function's value is returned
text := CS.Using(CS.System.IO.StreamReader("C:\Temp\notes.txt"), (r) => r.ReadToEnd())

; dispose when the last AHK reference to this proxy is released
stream := CS.System.IO.File.OpenRead("C:\Temp\notes.txt").AutoDispose()
stream := ""                                  ; the stream is disposed now
```

- `AutoDispose()` belongs on the **one** proxy that owns the object: a second proxy of the same object (like `same` above) would find it already disposed.
- `Dispose` (the helper, `CS.Using` and `AutoDispose`) calls `IDisposable.Dispose`, and also a plain public `Dispose()` on a class that does not implement `IDisposable`.
- `CS.Stats()` shows what is still alive on the .NET side ([API reference](15_api_reference.md#csstats)); [GC & Memory](11_gc.md) has the details.
