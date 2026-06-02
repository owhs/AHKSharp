# Async/Await — Parallel Computation

Run .NET methods on the ThreadPool without freezing AHK.

## CSModule Async

```autohotkey
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

; Block until complete
result := promise.Await()
ToolTip("")
```

## Promise API

```autohotkey
; Await with timeout (default: 30 seconds)
result := promise.Await(60000)  ; 60 second timeout

; Callback chains
promise.Then((result) => MsgBox("Done: " result))
       .Catch((err) => MsgBox("Error: " err.Message))

; Check completion
if promise.IsComplete
    result := promise.Await()
```

## Parallel Execution

Fire multiple tasks simultaneously:

```autohotkey
p1 := Heavy.Async.Compute(5000000)
p2 := Heavy.Async.Compute(7500000)
p3 := Heavy.Async.Compute(10000000)

r1 := p1.Await()  ; All 3 ran in parallel!
r2 := p2.Await()
r3 := p3.Await()
```

## CSProxy Async

Instance methods can also be called async:

```autohotkey
obj := CS.System.Text.StringBuilder("Hello")
promise := obj.Async.Append(" World")
result := promise.Await()
```

## Threading Model

```
AHK Main Thread                    .NET ThreadPool
     │                                   │
     ├─ promise := Module.Async.Fn()     │
     │   └─ Bridge.BeginAsync() ─────────┤
     │                                   ├─ Execute Fn()
     │   (AHK is responsive here)        │
     │                                   ├─ PostMessage(WM_APP+1)
     ├─ OnMessage handler fires ◄────────┘
     │   └─ promise._complete = true
     ├─ result := promise.Await()
     │   └─ Bridge.EndAsync() → result
```
