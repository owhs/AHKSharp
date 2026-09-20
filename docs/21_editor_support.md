# Editor Support — Completion and Hover for .NET Types

`CS.System.Text.StringBuilder()` is resolved at run time, so an editor cannot know what a `StringBuilder` offers. `CS.Declare` writes a **declaration file** that tells it:

```autohotkey
#Include lib\ahk#.ahk
CS.Declare("System.Text.StringBuilder", "System.IO", CS.System.Math)     ; run once
```

Afterwards, in an editor that runs the AutoHotkey v2 language server, this script gets completion, hover (with the overload list) and signature help:

```autohotkey
#Include lib\ahk#.ahk
sb := CS.System.Text.StringBuilder()     ; constructor: signature help
sb.Append("a").AppendLine("b")           ; Append( ... : completion after the dot, chained calls keep working
n := CS.System.Math.Abs(-3)              ; static member: CS.System.Math. lists Abs, Max, PI, ...
text := CS.System.IO.File.ReadAllText(path)
```

## Set it up in VS Code

1. Install the extension **AutoHotkey v2 Language Support** by thqby (`thqby.vscode-autohotkey2-lsp`).
2. Run a one-line script once. `CS.Declare` takes the types you want (a type name, a namespace name, or an object such as `CS.System.Math`):

   ```autohotkey
   #Include lib\ahk#.ahk
   CS.Declare("System.Text.StringBuilder", "System.IO", "System.Diagnostics.Stopwatch")
   ```

   It writes `ahk#.d.ahk` next to `ahk#.ahk` (in `lib\`) and returns the path.
3. Reopen the script that includes `ahk#.ahk` (or run "Developer: Reload Window"). The language server references a `.d.ahk` file with the **same base name as an included file** on its own, so `#Include lib\ahk#.ahk` is all a script needs: no extra include, no setting.

Add more types any time: calls **add** to the set, they do not replace it. The first line of the file records the set (`;@specs System.Text.StringBuilder;System.IO;...`); delete the file to start over. It is machine output: in a project of your own put it in `.gitignore`.

```autohotkey
CS.Declare("System.Text.RegularExpressions")   ; later: adds the namespace, keeps the earlier ones
CS.Declare()                                   ; rewrites the file from the recorded set (for example after upgrading the library)
```

## What you can pass

| Spec | Declares |
|------|----------|
| `"System.Text.StringBuilder"` | that type |
| `"System.IO"` | every public, non-generic, top-level type in the namespace |
| `CS.System.Math` / `CS.System.IO` (a type or namespace object) | the same as the name |

Types and namespaces are looked up in the assemblies loaded when you call `CS.Declare` (the framework plus anything you loaded with `CS.LoadAssembly`). A spec that matches nothing is remembered in the first line but declares nothing and raises no error, so check the result if a type does not show up. Discover names with `CS.Types("System")` and `CS.Members(...)` ([CS Namespace](02_cs_namespace.md#discovering-what-is-there)).

## What is in the file

The file is never executed; the language server only reads it. It holds one `class CS { ... }` that mirrors the namespaces you declared, with a shared base class (`_Object`, inside `CS`) for the helper members every proxy has (`ToAHK`, `Then`, `Await`, `On`, `Dispose`, ..., see [the proxy rule](02_cs_namespace.md#the-proxy-rule-net-always-wins)). An abridged excerpt (parameter names and overloads come from .NET; the real file writes the base class with its full path):

```autohotkey
;@specs System.Text.StringBuilder
class CS {
    class _Object { ToAHK() => ""  ...  Then(onOk := "", onFail := "") => CSPromise()  ... }
    class System {
        class Text {
            /** System.Text.StringBuilder (class) */
            class StringBuilder extends _Object {
                /**
                 * __New()
                 * __New(int capacity)
                 * __New(string value)
                 */
                __New(capacity := "", ...) => ""
                /**
                 * Append(bool value)
                 * Append(char value)
                 * ...
                 * @returns {CS.System.Text.StringBuilder}
                 */
                Append(value, ...) => ""
                /** int
                 * @type {Integer} */
                Length {
                    get => ""
                    set => ""
                }
            }
        }
    }
}
```

- **Methods:** one declaration per method name, so the parameters are those of the longest overload and the ones beyond the shortest overload are optional (`:= ""`). Hover shows the overload list in the doc comment (the first 8, fewest parameters first, then `... N more overloads`).
- **Chaining:** a method whose overloads all return the same non-void type carries `@returns`. A method that returns its own class (`Append`) returns that declared class, so `sb.Append("a").Append("b")` keeps completing; a result whose type is one of your declared types is typed as that type.
- **Properties and fields** are typed with `@type` (`String`, `Integer`, `Float`, `Array`, the declared class, or `Any`); read-only ones have a getter only. **Enums** list their names as static members (`CS.System.DayOfWeek.Friday`).
- **Static members** (`CS.System.Math.Abs`, `CS.System.Math.PI`) are declared `static`. A static or abstract class has no constructor.

## Limits

- **One declaration per method name.** All overloads share the longest overload's parameter list; the exact overloads are in the hover text, not in the signature help.
- **Generic types and generic methods are not declared** (`List<T>`, `Enumerable.Select`); use `CS.System.Collections.Generic.List(CS.System.String)()` as usual, the editor just will not complete on it. Nested types and non-public types are skipped, and so are indexers.
- **Events** are not declared: reach them through `.On("Name", fn)` ([Delegates](07_delegates.md)).
- **Typed `Any`.** A result whose .NET type is not among the types you declared is typed `Any`: declare that type (or its namespace) too and the chain continues to complete.
- **Only what you declared.** The file knows nothing else. Add types with another `CS.Declare(...)` call.
- **Regenerate after upgrading** a library or the .NET Framework: the file describes the assemblies loaded on the machine that generated it.
- `Equals`, `GetHashCode`, `GetType` and other `Object` plumbing are left out. Parameter names that are AHK keywords (`in`, `is`, `class`, ...) get a trailing `_`.
- It is editor help only: nothing at run time depends on it, and a script works the same without the file.

## At run time instead

`CS.Members(CS.System.Math, "abs")` and `CS.Types("System.IO")` list the same information from a running script, and a misspelled name gets `Did you mean ...?` ([CS Namespace](02_cs_namespace.md#discovering-what-is-there)). `CS.Wrap("System.Math", path)` writes a real AHK class for one type instead of declarations ([API reference](15_api_reference.md#cswrap)). The playground's *Wrapper Gen* tab generates `.d.ahk` files for whole assemblies ([README](../README.md#developer-playground--studio)).
