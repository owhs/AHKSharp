# CS.Import — Namespace Aliasing

```autohotkey
#Include lib\ahk#.ahk

IO := CS.Import("System.IO")
IO.File.WriteAllText("test.txt", "Hello")
content := IO.File.ReadAllText("test.txt")

Text := CS.Import("System.Text")
sb := Text.StringBuilder()
sb.Append("Clean!").Append(" Readable!")
```

`CS.Import` is equivalent to `CS.System.IO`, but stored in a variable for repeated use. It works for any namespace (or type) name, including ones from assemblies you loaded with `CS.LoadAssembly`:

```autohotkey
Gen := CS.Import("System.Collections.Generic")
list := Gen.List(CS.System.String)()      ; generic type through the alias
```

Names are case-insensitive, as everywhere else.
