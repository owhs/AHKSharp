#Include harness.ahk

; ── promises ──────────────────────────────────────────────────────────────────
Test("Then attached BEFORE completion", () => (
    _clear("early"), CS.System.Threading.Thread.Async.Sleep(50).Then((*) => __state["early"] := "fired"),
    IsTrue(WaitFor(() => __state.Has("early")), "callback")))
Test("Then attached AFTER completion still fires", () => (
    _clear("late"), p := CS.System.Threading.Thread.Async.Sleep(20), Sleep(300),
    p.Then((*) => __state["late"] := "fired"), IsTrue(WaitFor(() => __state.Has("late")), "callback")))
Test("several Then callbacks on one promise", () => (
    _clear("a"), _clear("b"), p := CS.System.Threading.Thread.Async.Sleep(20),
    p.Then((*) => __state["a"] := 1), p.Then((*) => __state["b"] := 1),
    IsTrue(WaitFor(() => __state.Has("a") && __state.Has("b")), "both callbacks")))
Test("Then receives the value", () => (
    _clear("v"), CS.System.Math.Async.Abs(-9).Then((v) => __state["v"] := v),
    IsTrue(WaitFor(() => __state.Has("v")), "callback"), Eq(__state["v"], 9)))
Test("Catch receives the .NET error", () => (
    _clear("c"), CS.System.Int32.Async.Parse("abc").Catch((e) => __state["c"] := e.Message),
    IsTrue(WaitFor(() => __state.Has("c")), "catch"), Has(__state["c"], "FormatException")))
Test("Catch attached after failure still fires", () => (
    _clear("c2"), p := CS.System.Int32.Async.Parse("abc"), Sleep(300),
    p.Catch((e) => __state["c2"] := 1), IsTrue(WaitFor(() => __state.Has("c2")), "catch")))
Test("Await(timeout) throws TimeoutError", () => Throws(() => CS.System.Threading.Thread.Async.Sleep(2000).Await(100), "did not finish"))
Test("Await on a failed promise throws the error", () => Throws(() => CS.System.Int32.Async.Parse("abc").Await(), "FormatException"))
Test("CS.Promise.AwaitAll", () => (
    r := CS.Promise.AwaitAll(CS.System.Math.Async.Abs(-3), CS.System.Math.Async.Abs(-4)), Eq(r[1], 3), Eq(r[2], 4)))

; ── chaining, combinators, typed errors ───────────────────────────────────────
_boom(*) {
    throw Error("boom from callback")
}
_ahkErr(e) {
    return e
}
_caught(fn) {
    try
        fn()
    catch as e
        return e
    return ""
}

Test("Then returns a new promise carrying the callback's value", () => (
    _clear("ch"), CS.System.Math.Async.Abs(-5).Then((v) => v * 2).Then((v) => __state["ch"] := v),
    IsTrue(WaitFor(() => __state.Has("ch")), "chain"), Eq(__state["ch"], 10)))
Test("a callback that returns a promise is followed", () => (
    Eq(CS.System.Math.Async.Abs(-5).Then((v) => CS.Promise.Delay(20, v + 1)).Await(3000), 6)))
Test("a callback that returns a .NET Task is awaited too", () => (
    Eq(CS.System.Math.Async.Abs(-5).Then((v) => CS.System.Threading.Tasks.Task.FromResult(v + 4)).Await(3000), 9)))
Test("Catch recovers and the chain continues", () => (
    Eq(CS.System.Int32.Async.Parse("abc").Catch((e) => "recovered").Then((v) => v " ok").Await(3000), "recovered ok")))
Test("a failure skips Then and reaches a later Catch", () => (
    _clear("skipped"), _clear("reached"),
    CS.System.Int32.Async.Parse("abc").Then((v) => __state["skipped"] := 1).Catch((e) => __state["reached"] := e.Message),
    IsTrue(WaitFor(() => __state.Has("reached")), "catch reached"), IsTrue(!__state.Has("skipped"), "Then skipped")))
Test("a throwing callback rejects the chain instead of vanishing", () => (
    e := _caught(() => CS.System.Math.Async.Abs(-1).Then(_boom).Catch(_ahkErr).Then((x) => _boom()).Await(3000)),
    Has(e.Message, "boom from callback")))
Test("Finally runs on success and passes the value on", () => (
    _clear("fin"), v := CS.System.Math.Async.Abs(-7).Finally(() => __state["fin"] := 1).Await(3000),
    Eq(v, 7), Eq(__state["fin"], 1)))
Test("Finally runs on failure and the error still arrives", () => (
    _clear("fin2"),
    e := _caught(() => CS.System.Int32.Async.Parse("abc").Finally(() => __state["fin2"] := 1).Await(3000)),
    Eq(__state["fin2"], 1), Has(e.Message, "FormatException")))
Test("Await keeps the .NET exception type", () => (
    e := _caught(() => CS.System.Int32.Async.Parse("abc").Await(3000)),
    IsTrue(CS.ErrorIs(e, "FormatException"), "ErrorIs"), Eq(e.NetType, "System.FormatException")))
Test("Catch gets the .NET exception type too", () => (
    _clear("nt"), CS.System.Int32.Async.Parse("abc").Catch((e) => __state["nt"] := e.NetType),
    IsTrue(WaitFor(() => __state.Has("nt")), "catch"), Eq(__state["nt"], "System.FormatException")))
Test("a Task's failure keeps its type as well", () => (
    e := _caught(() => CS.System.Net.Http.HttpClient().GetStringAsync("http://localhost:1/x").Await(8000)),
    IsTrue(CS.ErrorIs(e, "HttpRequestException"), "ErrorIs")))
Test("Timeout fails a slow promise with TimeoutError", () => (
    e := _caught(() => CS.Promise.Delay(2000).Timeout(80).Await(3000)), IsTrue(e is TimeoutError, "TimeoutError")))
Test("Timeout leaves a fast promise alone", () => Eq(CS.Promise.Delay(20, "quick").Timeout(2000).Await(3000), "quick"))
Test("Task.Timeout(ms, cts) cancels the token source", () => (
    cts := CS.System.Threading.CancellationTokenSource(),
    e := _caught(() => CS.System.Threading.Tasks.Task.Delay(5000, cts.Token).Timeout(100, cts).Await(3000)),
    IsTrue(e is TimeoutError, "TimeoutError"), IsTrue(cts.IsCancellationRequested, "cancelled")))
Test("CS.Promise.All resolves in input order", () => (
    r := CS.Promise.All(CS.Promise.Delay(60, "a"), CS.Promise.Delay(10, "b"), 3).Await(3000), Eq(r[1], "a"), Eq(r[2], "b"), Eq(r[3], 3)))
Test("CS.Promise.All fails fast", () => (
    e := _caught(() => CS.Promise.All(CS.Promise.Delay(2000), CS.Promise.Reject("nope")).Await(3000)), Has(e.Message, "nope")))
Test("CS.Promise.All accepts .NET Tasks", () => (
    r := CS.Promise.AwaitAll(CS.System.Threading.Tasks.Task.FromResult(4), CS.System.Threading.Tasks.Task.FromResult(5)), Eq(r[1], 4), Eq(r[2], 5)))
Test("CS.Promise.AwaitAny returns the first to settle", () => Eq(CS.Promise.AwaitAny(CS.Promise.Delay(400, "slow"), CS.Promise.Delay(20, "fast")), "fast"))
Test("CS.Promise.Resolve / Reject", () => (
    Eq(CS.Promise.Resolve(42).Await(), 42), Has(_caught(() => CS.Promise.Reject("bad").Await()).Message, "bad")))
_burst(n) {
    list := []
    Loop n
        list.Push(CS.System.Math.Async.Abs(-A_Index))
    return list
}
Test("1,000 promises settle even when AutoHotkey drops completion messages (non-blocking All)", () => (
    r := CS.Promise.All(_burst(1000)*).Await(20000), Eq(r.Length, 1000), Eq(r[1000], 1000), Eq(CS.Stats()["PendingAsyncTasks"], 0)))
Test("a settled promise reports IsComplete / Error without waiting", () => (
    p := CS.System.Int32.Async.Parse("abc"), IsTrue(WaitFor(() => p.IsComplete), "done"), Has(p.Error, "FormatException")))

; ── .NET Tasks become promises ────────────────────────────────────────────────
Test("Task.Delay(...).Await()", () => (CS.System.Threading.Tasks.Task.Delay(100).Await(3000), true))
Test("Task.Then fires", () => (
    _clear("t"), CS.System.Threading.Tasks.Task.Delay(50).Then((*) => __state["t"] := 1),
    IsTrue(WaitFor(() => __state.Has("t")), "callback")))
Test("Task.Run(fn) runs your function on the AHK thread", () => (
    _clear("pool"), CS.System.Threading.Tasks.Task.Run(() => __state["pool"] := "ran").Await(5000), Eq(__state["pool"], "ran")))
Test("a blocked AHK thread gets a clear error, not a hang", () => (
    CS.Config.CallbackTimeoutMs := 300,
    Throws(() => CS.System.Threading.Tasks.Task.Run(() => 1).Wait(), "not pumping messages"),
    CS.Config.CallbackTimeoutMs := 5000))
Test("faulted Task.Await throws", () => Throws(() => CS.System.Net.Http.HttpClient().GetStringAsync("http://localhost:1/x").Await(8000), "failed"))

; ── implementing .NET interfaces with AHK functions ───────────────────────────
Test("Array.Sort with an AHK IComparer", () => (
    a := CS.System.Array.CreateInstance(CS.System.Int32, 4), a[0] := 5, a[1] := 3, a[2] := 9, a[3] := 1,
    CS.System.Array.Sort(a, CS.Implement(CS.System.Collections.IComparer, Map("Compare", (x, y) => y - x))),
    r := a.ToAHK(), Eq(r[1], 9), Eq(r[4], 1)))
Test("List<int>.Sort(IComparer<int>) with an object literal", () => (
    L := CS.System.Collections.Generic.List(CS.System.Int32)(), L.Add(2), L.Add(8), L.Add(4),
    L.Sort(CS.Implement(CS.System.Collections.Generic.IComparer(CS.System.Int32), {Compare: (x, y) => x - y})),
    a := L.ToAHK(), Eq(a[1], 2), Eq(a[3], 8)))
Test("implemented methods can be called from AHK", () => Eq(CS.Implement(CS.System.Collections.IComparer, Map("Compare", (x, y) => x - y)).Compare(9, 4), 5))
Test("a missing handler reports which one", () => Throws(() => CS.Implement(CS.System.Collections.IComparer, Map()).Compare(1, 2), "no handler for 'Compare'"))

; ── events deliver real objects ───────────────────────────────────────────────
Test("Timer.On('Elapsed') passes the EventArgs proxy", () => (
    _clear("tick"), t := CS.System.Timers.Timer(80), t.On("Elapsed", (e, sender) => __state["tick"] := Type(e)),
    t.Start(), ok := WaitFor(() => __state.Has("tick")), t.Stop(), IsTrue(ok, "tick"), Eq(__state["tick"], "_CSProxy")))
Test("FileSystemWatcher.On('Created') gives e.Name", () => _watcherTest())
Test("Off() stops delivery", () => (
    _clear("n"), __state["n"] := 0, t := CS.System.Timers.Timer(40), t.On("Elapsed", (*) => __state["n"] += 1),
    t.Start(), Sleep(300), t.Off("Elapsed"), before := __state["n"], Sleep(300), t.Stop(),
    IsTrue(before > 0, "events before Off"), Eq(__state["n"], before)))

_clear(key) {
    global __state
    if __state.Has(key)
        __state.Delete(key)
}

_watcherTest() {
    global __state
    _clear("file")
    dir := A_Temp "\ahksharp_watch_" A_TickCount
    DirCreate(dir)
    w := CS.System.IO.FileSystemWatcher(dir, "*.zzz")
    w.On("Created", (e) => __state["file"] := e.Name)
    w.EnableRaisingEvents := true
    FileAppend("x", dir "\probe.zzz")
    ok := WaitFor(() => __state.Has("file"), 4000)
    w.EnableRaisingEvents := false
    w.Off()
    try DirDelete(dir, true)
    IsTrue(ok, "Created event")
    Eq(__state["file"], "probe.zzz")
}

RunTests()
