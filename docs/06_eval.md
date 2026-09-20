# CS.Eval — One-Liner Expressions

Evaluate C# expressions inline without defining a CSModule class.

## Usage

```autohotkey
#Include lib\ahk#.ahk

result := CS.Eval("Math.Sqrt(144) + Math.PI")   ; → 15.14159...
guid := CS.Eval("Guid.NewGuid().ToString()")     ; → "a1b2c3d4-..."
cores := CS.Eval("Environment.ProcessorCount")   ; → 8
```

`CS.Eval(expression, references := "")` returns the value converted by the usual rules ([Marshaling](17_marshaling.md)): numbers stay numbers, `bool` is 1/0, objects come back as proxies.

## How It Works

1. The expression is wrapped: `public class __Eval { public static object Run() { return EXPR; } }`
2. It is compiled like a CSModule (`CSharpCodeProvider`, C# 4.0 syntax).
3. The result is cached by source hash (memory and `%LocalAppData%\AhkSharp\CompileCache`), so a second call with the same text does not recompile.

A syntax error throws an AHK error containing the compiler message. Because every distinct expression string is compiled, build data into arguments of a module method instead of pasting new values into the expression text inside a loop. Never evaluate text you do not trust: it is compiled and run in your process ([Security](19_security.md)).

## Available Namespaces

These `using` directives are automatically included:
- `System`
- `System.Linq`
- `System.Collections.Generic`
- `System.IO`
- `System.Text`
- `System.Text.RegularExpressions`

## Examples

```autohotkey
; Math
CS.Eval("Math.Pow(2, 10)")                    ; → 1024.0
CS.Eval("Math.Round(Math.PI, 4)")              ; → 3.1416

; Strings
CS.Eval('"hello".ToUpper()')                   ; → "HELLO"
CS.Eval('string.Join(", ", new[]{"a","b","c"})') ; → "a, b, c"

; LINQ
CS.Eval("Enumerable.Range(1, 100).Sum()")      ; → 5050
CS.Eval("Enumerable.Range(1, 10).Where(x => x % 2 == 0).Count()") ; → 5

; System
CS.Eval("DateTime.Now")                        ; → an AHK timestamp, e.g. "20260528210000"
CS.Eval("DateTime.Now.ToString()")             ; → e.g. "5/28/2026 9:00:00 PM" (a string, so locale dependent)
CS.Eval("Environment.MachineName")             ; → "MY-PC"
CS.Eval("Path.GetTempPath()")                  ; → "C:\Users\...\Temp\"

; Base64
CS.Eval('Convert.ToBase64String(Encoding.UTF8.GetBytes("Hello"))') ; → "SGVsbG8="
```

## With Custom References

```autohotkey
; Use assemblies not in the default reference set
result := CS.Eval("System.Drawing.Color.Red.ToArgb()", "System.Drawing.dll")
```

## CS.Run

`CS.Eval` takes one expression. `CS.Run(statements, refs := "")` takes a whole **statement body** (declarations, loops, several statements) and returns what it `return`s:

```autohotkey
total := CS.Run("int s = 0; for (int i = 1; i <= 10; i++) s += i; return s;")   ; → 55
CS.Run("int x = 1; x++;")                       ; no return → ""
```

The body is compiled inside a static method with the same `using` directives as `CS.Eval` (`System`, `System.Linq`, `System.Collections.Generic`, `System.IO`, `System.Text`, `System.Text.RegularExpressions`), C# 4.0 syntax, and the same on-disk compile cache. A compile error throws an error whose message is prefixed `CS.Run`. Like `CS.Eval`, never run text you do not trust ([Security](19_security.md)).
