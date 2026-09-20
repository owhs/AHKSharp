# Async/Await — Promises and Parallel Computation

Run .NET methods on the ThreadPool without freezing AHK, and compose the results with JavaScript-style promises: `Then` / `Catch` / `Finally` chains, `Timeout`, `CS.Promise.All` / `Race` / `Delay`.

## CSModule Async

```autohotkey
#Include lib\ahk#.ahk

class Heavy extends _CSModule {
    static CSharp := "
    (
        public static double Compute(int n) {
            double sum = 0;
            for (int i = 0; i < n; i++) sum += Math.Sqrt(i);
            return sum;
        }
    )"
}

; Async call — returns immediately
promise := Heavy.Async.Compute(10000000)
ToolTip("Computing... AHK is responsive!")

; Block until complete (the message pump keeps running while it waits)
result := promise.Await()
ToolTip("")
```

`.Async` also works on .NET types and objects:

```autohotkey
p := CS.System.Threading.Thread.Async.Sleep(500)      ; static call
sb := CS.System.Text.StringBuilder("Hello")
p := sb.Async.Append(" World")                        ; instance call
```

## Promise API

A promise is settled once: with a value, or with an `Error`. `Then`, `Catch`, `Finally` and `Timeout` each return a **new** promise.

| Member | Description |
|--------|-------------|
| `promise.Await(timeoutMs := 0)` | Block (message pump alive) and return the value. `0` waits without limit; a positive value throws `TimeoutError` when it elapses. Throws the failure: for a failed .NET operation `Error("Async operation failed: FormatException: ...")` (the text after the prefix starts with the .NET exception type name) |
| `promise.Then(onOk := "", onFail := "")` | Returns a **new promise**. `onOk(value)` runs when this one succeeds, `onFail(err)` when it fails; the new promise takes the value the callback **returns** (a returned promise is followed). An omitted callback passes the outcome on unchanged. May be called repeatedly on one promise |
| `promise.Catch(onFail)` | `Then("", onFail)`: handles a failure; what `onFail` returns becomes the value, so the chain continues |
| `promise.Finally(fn)` | Runs `fn()` (no arguments) whether it succeeded or failed, then passes the value or the error on. `fn`'s return value is ignored (a promise it returns is not waited for); if `fn` throws, that error replaces the outcome |
| `promise.Timeout(ms, cancelSource := "")` | A new promise that follows this one but fails with a `TimeoutError` if this one is not settled within `ms`. Pass a `CancellationTokenSource` proxy and `Cancel()` is called on it at that moment ([Cancellation](#timeouts-and-cancellation)) |
| `promise.IsComplete` | `true` once finished (successfully or not). Asks the bridge directly, so it is accurate even before the completion message was delivered |
| `promise.Error` | `""` while running or on success, otherwise the error text (same rule: no waiting for the message) |
| `CS.Promise.Resolve(value := "")` | A promise for `value`. A promise comes back as is, a .NET Task proxy becomes its promise |
| `CS.Promise.Reject(err)` | An already-failed promise; `err` is an `Error` object or any value (turned into `Error(String(err))`) |
| `CS.Promise.Delay(ms, value := "")` | Resolves with `value` after `ms` milliseconds (an AHK timer: nothing blocks, no thread is used) |
| `CS.Promise.All(promises*)` | A promise of an **Array** of the results in input order; it **fails as soon as one input fails**. Inputs may be promises, .NET Task proxies or plain values. `All()` with no arguments resolves with `[]` |
| `CS.Promise.Race(promises*)` | A promise that settles like the **first** input to settle (`Race()` with no arguments never settles) |
| `CS.Promise.AwaitAll(promises*)` | Blocking form of `All`: returns the Array of results, throws as soon as any input fails |
| `CS.Promise.AwaitAny(promises*)` | Blocking form of `Race`: returns the value of the first to settle, throws if that one failed |

```autohotkey
; Callback chains
promise.Then((result) => MsgBox("Done: " result))
       .Catch((err) => MsgBox("Error: " err.Message))

; Wait with a limit
try
    result := promise.Await(5000)          ; 5 seconds
catch TimeoutError
    MsgBox("Took too long")

; Check completion
if promise.IsComplete
    result := promise.Await()
```

Behaviour you can rely on:

- `Await`, `Then` and `Catch` are race-free: each runs in a `Critical` section, so a completion message cannot slip in between "is it done?" and "take the result / register the callback".
- Callbacks run on the **AHK thread** (queued through a one-shot timer), never on a ThreadPool thread.
- `Then` / `Catch` / `Finally` **fire even when attached after the promise completed**, and you can attach several callbacks to one promise.
- A callback may declare fewer parameters than it is given (`(*) => ...`, `() => ...`).
- `Await`, `AwaitAll` and `AwaitAny` keep AHK's message pump alive (they `Sleep(1)` in a loop), so hotkeys, timers, GUI events and other callbacks still run while you wait. Long-running work should still not sit inside a callback.
- Completion is announced by `PostMessage`, so callbacks need the message pump: they fire while you `Sleep`, while a GUI or hotkey script is idle, or from a timer. A script that has already finished its auto-execute section and would exit never sees them; call `Persistent()` or wait with `Await`.
- What happens to an error nobody handles: see [Unhandled errors](#unhandled-errors).

## Chaining

`Then` returns a new promise, as in JavaScript:

```autohotkey
CS.System.Math.Async.Abs(-5)
    .Then((v) => v * 2)                          ; the next promise's value is 10
    .Then((v) => CS.Promise.Delay(100, v + 1))   ; a returned promise is followed → 11 after 100 ms
    .Then((v) => MsgBox("got " v))
    .Catch((e) => MsgBox("failed: " e.Message))  ; any failure above lands here
    .Finally(() => ToolTip())                    ; runs either way
```

The rules, all in one place:

- **Value.** The new promise's value is what the callback returns (`""` when it returns nothing). If the callback returns a **promise** (`CS.Promise.Delay`, another `.Async` call) or a **.NET Task** proxy, the new promise waits for it and takes its value or its error.
- **Failure flows down.** A failed promise skips every `Then` that has no `onFail` and reaches the first `Catch` (or `onFail`) below it. `Catch` **recovers**: the chain after it carries `Catch`'s return value.
- **A throwing callback rejects the new promise** with the error it threw (it is never lost, and never a dialog at the moment it happens). Rethrowing the very error you were handed just passes it on.
- **Several branches.** Each `Then` on the same promise is independent and gets the same value:

```autohotkey
p := CS.System.Math.Async.Abs(-3)
p.Then((v) => state["a"] := v)          ; both callbacks receive 3
p.Then((v) => state["b"] := v * 10)
```

- **`Finally`** does not change the outcome: `p.Finally(cleanup).Await()` returns `p`'s value, or throws `p`'s error, after `cleanup()` ran.

`Then(f)` used to return the promise it was called on. It now returns a derived promise: keep a reference to the original (`p := ...Async.X()`, then `p.Then(f)`) if you later call `p.Await()` or read `p.Error`. `p.Then(f).Await()` waits for `f` and returns **its** result.

## Parallel Execution

Fire multiple tasks simultaneously:

```autohotkey
p1 := Heavy.Async.Compute(5000000)
p2 := Heavy.Async.Compute(7500000)
p3 := Heavy.Async.Compute(10000000)

results := CS.Promise.AwaitAll(p1, p2, p3)   ; All 3 ran in parallel
MsgBox(results[1] "`n" results[2] "`n" results[3])
```

## Combinators

`AwaitAll` / `AwaitAny` block; `All` / `Race` give you a promise instead, so they compose with `Then` and `Timeout`. All four take promises, **.NET Tasks** and plain values:

```autohotkey
; several downloads, one result Array, with an overall time limit; fails as soon as one fails
client := CS.System.Net.Http.HttpClient()
pages := CS.Promise.All(client.GetStringAsync("https://example.com"), client.GetStringAsync("https://example.org"))
texts := pages.Timeout(15000).Await()               ; Array of the two strings

; the first to settle wins
winner := CS.Promise.AwaitAny(CS.Promise.Delay(400, "slow"), CS.Promise.Delay(20, "fast"))   ; → "fast"

; already-settled promises for tests and defaults
CS.Promise.Resolve(42).Await()                      ; → 42
CS.Promise.Reject("bad").Catch((e) => MsgBox(e.Message))
```

`AwaitAll` (and `All`) **fail fast**: a failed input fails the whole thing at once instead of waiting for the slow ones. Use `Then` on each input if you need every outcome.

## Timeouts and cancellation

`Await(timeoutMs)` stops *waiting*; it does not stop the work. `Timeout(ms)` turns "too slow" into a failure you can handle in a chain, and can also stop the work when the .NET operation accepts a `CancellationToken`:

```autohotkey
; a slow operation that observes a token, abandoned after 2 seconds
cts := CS.System.Threading.CancellationTokenSource()
task := CS.System.Threading.Tasks.Task.Delay(60000, cts.Token)     ; stands in for any token-aware operation
try
    task.Timeout(2000, cts).Await()        ; at 2 s: TimeoutError, and cts.Cancel() has been called
catch TimeoutError
    MsgBox("gave up; cancellation requested: " cts.IsCancellationRequested)   ; → 1
```

- The new promise fails with `TimeoutError` (`Async operation did not finish within 2000 ms`) if the original is not settled in time; a fast one passes through untouched and the timer is cancelled.
- The original operation is not stopped by the promise itself. Handing the `CancellationTokenSource` to `Timeout` makes AHK# call `Cancel()` at that moment; the operation stops only if it was given `cts.Token`. Its late failure (a canceled task) stays silent, see [Unhandled errors](#unhandled-errors).
- `Timeout` is an AHK timer, so it needs the message pump (`Await` or `Sleep` are fine).
- It works on Task proxies too (`task.Timeout(...)`, see [.NET Tasks](#net-tasks)) and on any promise from `Then` / `All` / `Delay`. The same idea composes: `CS.Promise.All(a, b).Timeout(5000, cts)`.

## Collecting Results from Callbacks

AHK fat-arrow functions assign **local** variables, so `(v) => total := v` does not change a variable outside the lambda. Record results in an object or Map, or chain and `Await` the last promise:

```autohotkey
state := Map()
CS.System.Math.Async.Abs(-9).Then((v) => state["value"] := v)
Sleep(200)                                    ; let the message pump deliver it
MsgBox(state.Has("value") ? state["value"] : "not yet")   ; → 9

MsgBox(CS.System.Math.Async.Abs(-9).Then((v) => v + 1).Await())   ; → 10, no Map needed
```

## Errors

```autohotkey
p := CS.System.Int32.Async.Parse("abc")
p.Catch((e) => MsgBox("Failed: " e.Message))  ; FormatException: Input string was not in a correct format.
; or, on a promise with no Catch attached:
p2 := CS.System.Int32.Async.Parse("abc")
try
    p2.Await()
catch as e
    MsgBox(e.Message)                         ; Async operation failed: FormatException: ...
```

A failed .NET operation keeps its **.NET identity**, both in a `Catch` callback and around `Await`: the `Error` has `e.NetType`, `e.NetBases`, `e.NetStack`, `e.NetHResult`, so `CS.ErrorIs` works ([Error handling](15_api_reference.md#error-handling)):

```autohotkey
try
    CS.System.Int32.Async.Parse("abc").Await(3000)
catch as e {
    CS.ErrorIs(e, "FormatException")          ; → 1
    MsgBox e.NetType                          ; → System.FormatException
    ; e.Message → "Async operation failed: FormatException: Input string was not in a correct format."
}

CS.System.Int32.Async.Parse("abc").Catch((e) => MsgBox(CS.ErrorIs(e, "FormatException")))   ; the same in a callback
```

`Await` prefixes the message with `Async operation failed: `; a `Catch` callback gets the message without it (`FormatException: ...`). The failure passes down a chain unchanged, so the typed error is still there after several `Then`s.

`CS.Stats()["PendingAsyncTasks"]` counts async slots the bridge still holds; it is `0` once every promise has completed or been awaited.

### Unhandled errors

- A **failed .NET operation** that nobody handles stays silent: it is kept on the promise. `p.Error` reports it and `p.Await()` throws it.
- An error thrown by **your callback** that nothing observes is reported as an ordinary AHK error 100 ms after it happened (your `OnError` handler, or the usual error dialog). "Observes" means a `Catch` / `Then` / `Finally` attached to the derived promise, a call to its `Await`, or a read of its `Error`. So `p.Then((v) => oops(v))` with nothing after it surfaces the bug, while `p.Then(f).Catch(handle)` handles it.

```autohotkey
Oops(v) {                                     ; (a fat arrow cannot contain `throw`: use a named function)
    throw Error("bug in my callback " v)
}
CS.System.Math.Async.Abs(-1).Then(Oops)                              ; nothing observes the result:
                                                                     ; an AHK error appears ~100 ms later
CS.System.Math.Async.Abs(-1).Then(Oops).Catch((e) => MsgBox(e.Message))   ; handled → "bug in my callback 1"
```

## .NET Tasks

Any proxy that holds a `System.Threading.Tasks.Task` (or `Task<T>`) is awaitable. `HttpClient.GetStringAsync`, `Task.Delay`, `Task.Run`, ... all return one:

```autohotkey
client := CS.System.Net.Http.HttpClient()          ; resolves although System.Net.Http is not a default reference
html := client.GetStringAsync("https://example.com").Await(15000)   ; blocks, pump alive, TimeoutError after 15 s

client.GetStringAsync("https://example.com")
      .Then((html) => MsgBox(StrLen(html) " characters"))
      .Catch((e) => MsgBox("Failed: " e.Message))
      .Finally(() => client.Dispose())

CS.System.Threading.Tasks.Task.Delay(100).Then((*) => ToolTip("100 ms later"))
```

| Member (on a Task proxy) | Description |
|--------------------------|-------------|
| `task.ToPromise()` | Returns an ordinary `_CSPromise` for the task. The other helpers call this for you |
| `task.Await(timeoutMs := 0)` | Same as `promise.Await`: the result of a `Task<T>` (nothing useful for a plain `Task`); `TimeoutError` after `timeoutMs` |
| `task.Then(onOk := "", onFail := "")` | `task.ToPromise().Then(...)`: a new promise; callbacks run on the AHK thread |
| `task.Catch(onFail)` | `task.ToPromise().Catch(...)`: `onFail(err)` when it faulted or was canceled |
| `task.Finally(fn)` | `task.ToPromise().Finally(fn)` |
| `task.Timeout(ms, cancelSource := "")` | `task.ToPromise().Timeout(...)` |

- The task is watched with a continuation: **no thread is blocked**, and completion is announced with the same `WM_APP+1` message as any other promise, so the pump rules above apply.
- A **faulted** task's `Await` throws with the real .NET error (`Async operation failed: ...`, not an `AggregateException` wrapper), and the error keeps its type (`e.NetType`, `CS.ErrorIs(e, "HttpRequestException")`).
- `obj.Async.Method(args)` on a method that **returns a Task** waits for that task on the pool thread and hands you its **result** (not the Task object).
- `Await`, `Then`, `Catch`, `Finally`, `Timeout` and `ToPromise` are AHK# proxy helpers, used only when the .NET object has no member of that name (**.NET always wins**, see [CS Namespace](02_cs_namespace.md#the-proxy-rule-net-always-wins)). Calling them on a proxy that is not a Task throws `ToPromise: Not a System.Threading.Tasks.Task: ...`. To call a .NET method with one of those names use `proxy._Invoke("Name", args*)`.
- Do not use the .NET `task.Wait()` / `.Result` from AHK when the task needs an AHK callback: see the next section.

## AHK Functions on .NET Worker Threads

Passing an AHK function to .NET on a call that runs on another thread works. The function still runs **on the AHK thread**:

```autohotkey
state := Map("ran", "no")
CS.System.Threading.Tasks.Task.Run(() => state["ran"] := "yes").Await(5000)   ; runs on a pool thread → your function runs on the AHK thread
MsgBox state["ran"]                                                           ; → yes
```

How it works: when .NET calls the function from a worker thread the call is **queued**, a `WM_APP+3` message wakes the AHK message loop, the AHK thread runs the function and the result goes back to the waiting worker. This covers `Task.Run(fn)`, a `System.Threading.Timer` whose callback is an AHK function, and an object made with [`CS.Implement`](07_delegates.md#implementing-net-interfaces-with-csimplement) that .NET calls from a pool thread. Callbacks that .NET makes **on the AHK thread itself** (`list.Where(fn)`, `list.Sort(fn)`) are still ordinary direct calls.

The AHK thread has to be **pumping messages** while the worker waits: `Sleep`, a GUI, `promise.Await()`, a timer. It is not pumping when it is stuck inside a synchronous .NET call that waits for the workers:

```autohotkey
CS.System.Threading.Tasks.Task.Run(() => 1).Wait()          ; Wait() blocks the AHK thread; the worker needs it → deadlock
; the worker gets a TimeoutException after CS.Config.CallbackTimeoutMs (default 5000):
;   "An AHK function called from a .NET worker thread was not run within 5000 ms:
;    the AHK thread is not pumping messages. ..."
```

The same happens with `Parallel.ForEach` and anything else that blocks the AHK thread until the workers finish (the AHK thread stays frozen for the whole timeout, then the call fails). The fix is to keep the AHK thread pumping:

```autohotkey
CS.System.Threading.Tasks.Task.Run(fn).Await(5000)          ; instead of .Wait(): Await keeps the pump alive
; a blocking .NET method: run it on the pool with .Async and Await() the promise
;   CS.System.Some.Type.Async.BlockingMethod(args).Await()
CS.Config.CallbackTimeoutMs := 15000                        ; slow callbacks: give the AHK thread more time
```

See [Troubleshooting](18_troubleshooting.md#the-ahk-thread-is-not-pumping-messages) for the error message.

A complete script (out parameters, Tasks, `CS.Implement` and a worker-thread callback in one file): [implement_and_tasks.ahk](../examples/features/implement_and_tasks.ahk).

## Threading Model

```
AHK Main Thread                    .NET ThreadPool
     │                                   │
     ├─ promise := Module.Async.Fn()     │
     │   └─ Bridge.BeginAsync*() ────────┤
     │                                   ├─ Execute Fn()
     │   (AHK is responsive here)        │
     │                                   ├─ PostMessage(WM_APP+1)
     ├─ OnMessage handler fires ◄────────┘
     │   └─ promise settles; its callbacks are queued (SetTimer), each settles the promise Then returned
     ├─ result := promise.Await()
     │   └─ returns the cached result, or throws the stored error
```

Promises made on the AHK side (`Then`, `Catch`, `Finally`, `Timeout`, `All`, `Race`, `Delay`, `Resolve`, `Reject`) have no bridge slot: they are settled by AHK code and AHK timers, on the AHK thread.

Arguments are packed on the AHK thread; overload binding and the call itself run on the ThreadPool thread. An AHK function passed as an argument to a `.Async` call is invoked from that ThreadPool thread, so it takes the worker-thread path described above: it is queued and runs on the AHK thread while you `Await()` (or `Sleep`).

```
Worker thread                       AHK thread (pumping)
  fn(...) called by .NET
  ├─ queue the call
  ├─ PostMessage(WM_APP+3) ────────► message loop wakes
  │  (waits up to CallbackTimeoutMs)  └─ runs fn on the AHK thread, hands the result back
  └─ continues with the result ◄────────┘
```
