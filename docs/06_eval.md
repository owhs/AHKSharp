# CS.Eval — One-Liner Expressions

Evaluate C# expressions inline without defining a CSModule class.

## Usage

```autohotkey
result := CS.Eval("Math.Sqrt(144) + Math.PI")   ; → 15.14159...
guid := CS.Eval("Guid.NewGuid().ToString()")     ; → "a1b2c3d4-..."
cores := CS.Eval("Environment.ProcessorCount")   ; → 8
```

## How It Works

1. Expression is wrapped: `public class __Eval { public static object Run() { return EXPR; } }`
2. Compiled via `CSharpCodeProvider` (same as CSModule)
3. Result cached by expression hash — second call is instant

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
CS.Eval("Math.Pow(2, 10)")                    ; → 1024
CS.Eval("Math.Round(Math.PI, 4)")              ; → 3.1416

; Strings
CS.Eval('"hello".ToUpper()')                   ; → "HELLO"
CS.Eval('string.Join(", ", new[]{"a","b","c"})') ; → "a, b, c"

; LINQ
CS.Eval("Enumerable.Range(1, 100).Sum()")      ; → 5050
CS.Eval("Enumerable.Range(1, 10).Where(x => x % 2 == 0).Count()") ; → 5

; System
CS.Eval("DateTime.Now.ToString()")             ; → "5/28/2026 9:00:00 PM"
CS.Eval("Environment.MachineName")             ; → "MY-PC"
CS.Eval("Path.GetTempPath()")                  ; → "C:\Users\...\Temp\"

; Base64
CS.Eval('Convert.ToBase64String(Encoding.UTF8.GetBytes("Hello"))') ; → "SGVsbG8="
```

## With Custom References

```autohotkey
; Use assemblies not in default reference set
result := CS.Eval("System.Drawing.Color.Red.ToArgb()", "System.Drawing.dll")
```
