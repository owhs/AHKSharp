# Testing

The `tests\` folder holds a small TAP-style harness and the suites that check AHK# itself. They are also the most reliable examples of every feature: each test is a working call.

```
tests/
├── harness.ahk            Test / Skip / Eq / Near / IsTrue / Has / Throws / WaitFor / RunTests
├── test_abstractions.ahk  the proxy rule (.NET wins), CS.Same / CS.Using / AutoDispose, typed exceptions (CS.ErrorIs), CS.Bool, DateTime timestamps
├── test_advanced.ahk      struct results (CancellationToken, Point ...), matrix[i, j], CS.CallGeneric, CS.Run, static events
├── test_async_events.ahk  promises (chaining, Finally, Timeout, All / Race, typed errors), .NET Tasks, worker-thread callbacks, CS.Implement, events
├── test_binder.ahk        overload resolution, params, out/ref, generics, LINQ, CS.Explain, CS.Members / CS.Types, "Did you mean"
├── test_extensions.ahk    Json, SQLite (UTF-8, NULL, transactions), UIA2, SharedMemory (+ Http / NuGet when the network is on)
├── test_features.ahk      CS.Config.Trace, CS.Wrap, CS.Declare, the bridge hash pin, Config
├── test_marshaling.ahk    Arrays, Maps, Buffers, structs, iteration, arrays as references
├── test_modules.ahk       _CSModule, hot reload (Reload / Watch), CS.Fast, CS.Eval
├── test_net_modern.ahk    C# 9-12 syntax through Roslyn (CSVersion "12.0"), NuGet.Search, framework selection: needs the network, runs only with AHKSHARP_NET=1
├── test_spatial.ahk       ext\ahk#.spatial.ahk with a fake Reader (no OCR engine needed)
├── test_stress.ahk        leak / soak: proxy churn, 100k calls, delegate On/Off churn, 500 concurrent async calls, 200 worker-thread callbacks, a 10 MB string, a 1M-element array, an exception storm, cache growth
├── run_tests.ps1          runs every suite in its own process and summarises
├── run-ahk.ps1            runs ONE script headlessly; dialogs and errors become text
├── lint_docs.ps1          documentation drift lint (see below)
└── prelude.ahk            injected into every run: unhandled errors go to stderr, never a dialog
```

## Running

Needs AutoHotkey v2 installed (`run-ahk.ps1` looks in `%ProgramFiles%\AutoHotkey`; set `AHK_EXE` to use another exe).

```powershell
powershell -File tests\run_tests.ps1                      # every suite
powershell -File tests\run_tests.ps1 -Filter binder       # only suites whose file name contains "binder"
powershell -File tests\run_tests.ps1 -Filter stress       # the leak / soak suite alone
powershell -File tests\run_tests.ps1 -TimeoutSec 60       # per-suite time limit (default 180)

$env:AHKSHARP_NET = "1"; powershell -File tests\run_tests.ps1   # also the network tests (Http, NuGet) and test_net_modern
```

Each suite is one AutoHotkey process. `run_tests.ps1` prints every failing test, a `pass= fail= skip=` line per suite and a `TOTAL` line; its **exit code is the number of failing tests plus suites that did not finish**, so `0` means green. Without `AHKSHARP_NET=1` the network tests inside `test_extensions.ahk` (Http, NuGet) are reported as a skip, and `test_net_modern.ahk` is not started at all (`run_tests.ps1` prints `skipped (set AHKSHARP_NET=1)` for it: its module class compiles when the script loads, and that needs the network). The number of tests changes as suites grow, so read the `TOTAL` line instead of counting.

Use PowerShell (not Git Bash) to start these scripts: Bash rewrites the `/ErrorStdOut` flag that `run-ahk.ps1` passes to AutoHotkey. Never launch AutoHotkey for the tests from Git Bash (its path mangling breaks the runner); use the PowerShell runners.

### The documentation lint

```powershell
powershell -File tests\lint_docs.ps1         # exit code = number of problems
```

`lint_docs.ps1` catches documentation drift in `README.md` and `docs\*.md`. It reports:

1. relative markdown links that point at files that do not exist;
2. repository paths written in backticks (`lib\`, `src\`, `ext\`, `examples\`, `tests\`, `docs\`, `workbench\`) that do not exist;
3. `CS.<Member>` names in code or inline code that are not real members of the `CS` class (the list is read from `lib\ahk#.ahk`, not hard-coded);
4. `_CS...` helper names mentioned in the docs that `lib\ahk#.ahk` does not define;
5. `.cs` file names that are not in `src\`, `workbench\` or `examples\`.

Run it after renaming or adding a member or a file, and before a release. It does not check anchors (`#section`) or that a code sample is correct.

### The network suite

`test_net_modern.ahk` defines a module with `static CSVersion := "12.0"`, so **loading the script downloads the Roslyn toolset** (about 20 MB, once, into `%LocalAppData%\AhkSharp\Packages\`) and the tests query nuget.org (`CS.NuGet.Search`, an `Install` that must be refused, latest-version resolution). It needs .NET Framework 4.7.2+. Any file named `tests\test_net*.ahk` is skipped by `run_tests.ps1` unless `AHKSHARP_NET=1`.

### The stress suite

`test_stress.ahk` is a leak and soak check. Its limits are deliberately generous: they catch "grows without bound", not small fluctuations. It reads `CS.Stats()` to check that delegates, pending async slots and queued callbacks return to zero and that the overload caches stop growing.

### Running a single script

```powershell
powershell -File tests\run-ahk.ps1 -Script tests\test_binder.ahk -TimeoutSec 60
powershell -File tests\run-ahk.ps1 -Script examples\basics\hello_dotnet.ahk -AutoDismiss
```

`run-ahk.ps1` starts the script hidden, watches its windows and prints `EXIT`, `STDOUT`, `STDERR` and `DIALOGS` sections. If an error dialog or MsgBox appears it reads the text, kills the process and reports it (exit code `3`); a script that runs too long is killed (exit code `4`); an unhandled error caught by `prelude.ahk` exits with `9`; otherwise you get the script's own exit code. `-Validate` only syntax-checks (AutoHotkey `/validate`), `-AutoDismiss` clicks OK / Yes / Continue on plain MsgBoxes and logs their text.

## Writing a test

```autohotkey
; tests\test_mine.ahk  (any file called test_*.ahk in tests\ is picked up)
#Include harness.ahk

Test("Math.Abs keeps the fraction", () => Eq(CS.System.Math.Abs(-2.5), 2.5))
Test("bad parse throws", () => Throws(() => CS.System.Int32.Parse("abc"), "not in a correct format"))
Test("TryParse fills &n", () => (ok := CS.System.Int32.TryParse("12", &n), Eq(ok, 1), Eq(n, 12)))

RunTests()
```

`harness.ahk` includes `..\lib\ahk#.ahk` itself and sets `CS.Config.ShowErrorGui` and `CS.Config.NuGetGui` to `false`, so a compile error throws instead of opening a window. Output is TAP on stdout: `ok N - name` or `not ok N - name # reason`, then `# pass=.. fail=.. skip=..`; the exit code is the number of failures.

| Function | Checks |
|----------|--------|
| `Test(name, fn)` | Registers a test; `fn` passes when it does not throw |
| `Skip(name, why)` | Registers a skipped test (`ok N - name # SKIP why`) |
| `Eq(actual, expected, what := "")` | Both converted to strings and compared |
| `Near(actual, expected, eps := 0.000001)` | Numbers within `eps` |
| `IsTrue(cond, what := "condition")` | Truthy |
| `Has(text, needle, what := "text")` | `InStr(text, needle)` |
| `Throws(fn, needle := "")` | `fn()` must throw; when `needle` is given the message must contain it |
| `WaitFor(cond, timeoutMs := 5000)` | Polls `cond()` while pumping messages (`Sleep`); returns `true` / `false` |
| `RunTests()` | Runs everything, prints the summary and exits |

A test body is one expression. Chain several with commas inside parentheses, or call a named function for anything longer:

```autohotkey
Test("Task.Run(fn) runs your function on the AHK thread", () => (
    __state["pool"] := "",
    CS.System.Threading.Tasks.Task.Run(() => __state["pool"] := "ran").Await(5000),
    Eq(__state["pool"], "ran")))

Test("hot reload", () => _reloadTest())
_reloadTest() {
    ; ... any number of statements ...
}
```

Test a `_CSModule` by defining the class above the tests (class bodies initialise in order) and calling it like any other:

```autohotkey
class Calc extends _CSModule {
    static CSharp := "public static int Add(int a, int b) { return a + b; }"
}
Test("Calc.Add", () => Eq(Calc.Add(2, 3), 5))
```

### Gotchas

- **Fat-arrow lambdas assign LOCAL variables.** `() => done := true` sets a variable inside the lambda, not yours. The harness gives you `__state`, a global Map: write `__state["done"] := true` and read it back in the test or in `WaitFor(() => __state.Has("done"))`.
- **Do not name a variable like a class.** AHK is case-insensitive, so `json := Json.Query(...)` makes `json` and the `Json` class the same name and breaks the next `Json.` lookup. The same goes for `http` / `Http`, `sqlite` / `SQLite`, `cs` / `CS`. Use `doc`, `body`, `db`.
- **`throw` cannot be used inside an expression.** A one-expression test body such as `() => throw Error("x")` is a syntax error; call a named helper that throws (`_boom(x) { throw Error("inner") }`, see `test_abstractions.ahk`).
- **Avoid a space followed by `;` inside a quoted string.** It was treated as the start of a comment and cut the line off; build such text with `Chr(59)` (`"a" Chr(59) " b"`) or put it in a continuation section.
- **Callbacks need the message pump.** Anything delivered by `.Then`, `.On` or a worker thread only arrives while AHK is in `Sleep` / `Await` / `WaitFor`. Do not sit in a busy loop.
- **Reset what you change.** All tests of a suite share one process: put `CS.Config.Trace` and `CS.Config.CallbackTimeoutMs` back after a test that sets them (the existing tests do).
- **Child processes** (the bridge-hash and `CS.Wrap` tests in `test_features.ahk`) are started with `/include prelude.ahk`, so a failure comes back as stderr text and exit code `9`, never a dialog. Copy `RunChild` from that file.

## Continuous integration

`.github\workflows\tests.yml` runs the suites on a `windows-latest` GitHub runner (it does not run `tests\lint_docs.ps1`; run that yourself): it installs AutoHotkey v2 with `choco install autohotkey`, sets `AHK_EXE`, builds the bridge with `lib\build.ps1 -Force` (this also proves the SHA-256 pinning step works, see [Security](19_security.md)) and runs `tests\run_tests.ps1` with `AHKSHARP_NET=1`. The workflow is written but has **not yet been exercised on GitHub**: expect to fix small things (the AutoHotkey install path, timeouts) on its first run.
