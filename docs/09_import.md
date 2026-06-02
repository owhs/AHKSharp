# CS.Import — Namespace Aliasing

```Autohotkey
IO := CS.Import('System.IO')
IO.File.WriteAllText('test.txt', 'Hello')
content := IO.File.ReadAllText('test.txt')

Text := CS.Import('System.Text')
sb := Text.StringBuilder()
sb.Append('Clean!').Append(' Readable!')
```

Equivalent to CS.System.IO but stored in a variable for repeated use.
