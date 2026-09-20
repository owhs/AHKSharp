# Delegates — C# Event Subscription

Subscribe to .NET events using AHK functions as handlers. Your function receives the **real event objects**, not strings.

## Usage

```autohotkey
#Include lib\ahk#.ahk

; FileSystemWatcher.Created is an EventHandler<FileSystemEventArgs>:
; the handler gets (eventArgs, sender) — declare only what you need
watcher := CS.System.IO.FileSystemWatcher("C:\MyFolder", "*.txt")
watcher.On("Created", (e) => MsgBox("New file: " e.FullPath))
watcher.EnableRaisingEvents := true

; Timer events: ignore the arguments entirely
timer := CS.System.Timers.Timer(1000)
timer.On("Elapsed", (*) => ToolTip(A_Now))
timer.Start()

; Stop listening
watcher.Off("Created")     ; removes every handler you added for that event
timer.Off()                ; no name: removes every handler on this proxy
```

## What Your Function Receives

- For the standard **`(object sender, TEventArgs e)`** pattern (`EventHandler`, `EventHandler<T>`, `ElapsedEventHandler`, `FileSystemEventHandler`, ...) the function is called with **`(e, sender)`**, both as proxies. Declare fewer parameters if you like: `(e) => ...` or `(*) => ...`.
- For any other delegate shape it receives the delegate's own arguments **in order**. Objects arrive as proxies, numbers and strings as plain values.
- `ref` / `out` event parameters are not supported (`On` throws).

```autohotkey
timer.On("Elapsed", (e, sender) => ToolTip(e.SignalTime "`n" sender.Interval))
watcher.On("Renamed", (e) => MsgBox(e.OldFullPath " -> " e.FullPath))
```

## Threads and Delivery

.NET raises events on whatever thread it likes (timers and file watchers use ThreadPool threads). AHK# handles this for you:

- every event is **queued** and one `PostMessage(WM_APP+2)` is sent per event;
- the AHK thread pops one event per message and calls your function, so it always runs on the **AHK thread**;
- **none are dropped**: a burst of 100 events calls your function 100 times, in order;
- an error inside your handler surfaces as a normal AHK error (dialog, or your `OnError` handler); it does not stop later events.

Because delivery is message based, AHK's message pump must be running: the script must have a GUI, hotkey, timer or a `Sleep` in progress (or call `Persistent()`).

AHK fat-arrow lambdas assign **local** variables. To keep results, write into a Map or object captured by the lambda: `(e) => log.Push(e.Name)` works, `(e) => last := e.Name` does not.

## Static Events

Some .NET events are `static`, so there is no object to call `.On` on. Call `On` / `Off` on the **type**:

```autohotkey
CS.System.Console.On("CancelKeyPress", (e, sender) => MsgBox("Ctrl+C"))
CS.System.Console.Off("CancelKeyPress")        ; no name: removes every handler added through this type object
```

The handler receives the same arguments as for instance events (see above). A .NET **static member named `On` or `Off`** on that type wins over the AHK# helper, like everywhere else. Calling `On` with an event name the type does not have throws an error that names it. Each subscription is one entry in `CS.Stats()["Delegates"]`, so a balanced `On` / `Off` returns the counter to where it was.

## Low-Level: CS.Delegate

`proxy.On(...)` is built on `CS.Delegate`:

```autohotkey
ref := CS.Delegate(MyHandler)       ; registers the function with the bridge
ref.Id                              ; integer id of the registration
ref.Unregister()                    ; unsubscribe and drop any queued events
```

`CS.Delegate` alone does not subscribe to anything; `proxy.On` registers the function and subscribes it to the named event in one step (the event name is case-insensitive). Use `proxy.Off()` rather than calling `Unregister` yourself, so the proxy forgets the registration too.

`On`, `Off` and the other proxy helpers follow the ".NET always wins" rule: if the object's .NET class has its own `On` method, `proxy.On(...)` calls that one, and `proxy._Invoke("On", ...)` is always the .NET call ([CS Namespace](02_cs_namespace.md#the-proxy-rule-net-always-wins)). On such a class `On` is therefore not available as an event helper.

## Implementing .NET Interfaces with CS.Implement

Some .NET APIs want an **object** that implements an interface (`IComparer`, `IEqualityComparer<T>`, ...), not a single delegate. `CS.Implement(iface, handlers)` builds one whose members call your AHK functions:

```autohotkey
; non-generic interface, handlers in a Map
arr := CS.System.Array.CreateInstance(CS.System.Int32, 4)
arr[0] := 5, arr[1] := 3, arr[2] := 9, arr[3] := 1
cmp := CS.Implement(CS.System.Collections.IComparer, Map("Compare", (a, b) => b - a))
CS.System.Array.Sort(arr, cmp)               ; arr is now 9, 5, 3, 1 (sorted by YOUR function)

; generic interface, handlers in an object literal
list := CS.System.Collections.Generic.List(CS.System.Int32)()
list.Add(2), list.Add(8), list.Add(4)
list.Sort(CS.Implement(CS.System.Collections.Generic.IComparer(CS.System.Int32), {Compare: (a, b) => a - b}))

; the result is a normal proxy: call it from AHK too
cmp.Compare(9, 4)                            ; → -5 (b - a)
```

- `iface` is an interface type object (`CS.System.Collections.IComparer`, or a generic built with `IComparer(CS.System.Int32)`) or a full type-name string. A class deriving from `MarshalByRefObject` is accepted too; anything else throws.
- `handlers` is a **Map** or an **object literal** of `name → function`. Method names are case-insensitive. A property is served by `"get_Name"` / `"set_Name"`, or just `"Name"` for both accessors.
- Your function receives the .NET arguments as AHK values (objects as proxies) and may declare fewer parameters; its return value is converted to the member's return type ([Marshaling](17_marshaling.md)).
- A member with **no handler** throws `NotImplementedException` naming it (`The AHK implementation of IComparer has no handler for 'Compare'.`); `void` members without a handler do nothing. `Dispose` and event `add_` / `remove_` accessors are no-ops.
- It is built on `RealProxy`, which is part of every .NET Framework 4.x, so no compiler and no generated assembly are needed.
- The handlers always run on the **AHK thread**, even when .NET calls the object from a worker thread (see below).

## Worker Threads

An AHK function passed as a delegate (or a `CS.Implement` handler) can be called by .NET **from a worker thread** (`Task.Run(fn)`, a `System.Threading.Timer`, a pool thread calling an implemented interface). The call is queued, a `WM_APP+3` message wakes the AHK message loop, the function runs on the AHK thread and the result goes back to the worker. This needs the AHK thread to be **pumping messages** (`Sleep`, a GUI, `promise.Await()`); if it is blocked in a synchronous .NET call that waits for the workers (`Task.Run(fn).Wait()`, `Parallel.ForEach`), the worker gets a `TimeoutException` after `CS.Config.CallbackTimeoutMs` (5000 by default). Use `Task.Run(fn).Await()` or an `.Async` call. Details and the fix: [Async/Await](04_async.md#ahk-functions-on-net-worker-threads).

Callbacks made on the AHK thread itself (`list.Where(fn)`, `list.Sort(fn)`) are plain direct calls and need no pump.

## API

| Method | Description |
|--------|-------------|
| `proxy.On(event, fn)` | Subscribe; returns the proxy so calls chain. May be called several times for one event |
| `proxy.Off(event := "")` | Unsubscribe every handler for that event, or all events when no name is given |
| `CS.Some.Type.On(event, fn)` / `.Off(event := "")` | The same for a **static** event, called on the type object |
| `CS.Delegate(fn)` | Register an AHK function; returns a ref with `.Id` and `.Unregister()` |
| `CS.Implement(iface, handlers)` | An object implementing a .NET interface with AHK functions; returns a proxy |

## Different from passing a function as an argument

Passing an AHK function where a .NET method wants a delegate (`list.Where(fn)`, `list.Sort(fn)`) is a different path from events: it is a **synchronous call** into your function, and it always runs on the AHK thread (directly when .NET is on that thread, queued through the message loop when .NET is on a worker thread). Events (`proxy.On`) are queued and delivered one message each, so nothing is lost and nothing blocks the .NET side. See [Marshaling](17_marshaling.md).

A runnable tour of `CS.Implement`, Tasks, `out` parameters and worker-thread callbacks: [implement_and_tasks.ahk](../examples/features/implement_and_tasks.ahk).
