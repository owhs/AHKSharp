# CS Namespace — Call Any .NET Method

The `CS` class is the global entry point for all .NET interop.

## Static Methods

```autohotkey
; CS.{Namespace}.{Class}.{Method}(args)
result := CS.System.Math.Pow(5, 3)           ; → 125
sqrt := CS.System.Math.Sqrt(144)              ; → 12
abs := CS.System.Math.Abs(-42)                ; → 42
```

## Static Properties

```autohotkey
machine := CS.System.Environment.MachineName  ; → "MY-PC"
cpus := CS.System.Environment.ProcessorCount  ; → 8
os := CS.System.Environment.OSVersion         ; → CSProxy<Version>
```

## Constructors

```autohotkey
sb := CS.System.Text.StringBuilder()          ; → new StringBuilder()
list := CS.System.Collections.ArrayList()     ; → new ArrayList()
uri := CS.System.Uri("https://example.com")   ; → new Uri(url)
```

## Generic Types

```autohotkey
; List<string>
list := CS.System.Collections.Generic.List(CS.System.String)()
list.Add("Alice")
list.Add("Bob")

; Dictionary<string, int>
dict := CS.System.Collections.Generic.Dictionary(CS.System.String, CS.System.Int32)()
dict.Add("score", 100)
```

## Fluid Chaining

CSProxy wraps every returned CLR object, enabling fluid dot-chaining:

```autohotkey
sb := CS.System.Text.StringBuilder()
sb.Append("Hello").Append(", ").Append("World!")
text := sb.ToString()  ; → "Hello, World!"
```

## File I/O

```autohotkey
; Write and read files
CS.System.IO.File.WriteAllText("test.txt", "Hello AHK#")
content := CS.System.IO.File.ReadAllText("test.txt")

; With namespace alias (CS.Import)
IO := CS.Import("System.IO")
IO.File.WriteAllText("test.txt", "Hello")
exists := IO.File.Exists("test.txt")
```

## Error Handling

```autohotkey
try {
    result := CS.System.IO.File.ReadAllText("nonexistent.txt")
} catch as e {
    MsgBox("Error: " e.Message)
}
```
