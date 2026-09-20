#Include harness.ahk

; Leak / stress checks. Numbers are deliberately generous — they catch "grows without bound",
; not small fluctuations.

heap() {
    CS.GC()
    return CS.Stats()["ManagedHeapBytes"]
}

processBytes() {
    return CS.System.Diagnostics.Process.GetCurrentProcess().PrivateMemorySize64
}

; ── proxies are released ──────────────────────────────────────────────────────
Test("20,000 short-lived proxies (1 KB each) do not accumulate", () => _proxyChurn())

_proxyChurn() {
    baseline := heap()
    Loop 20000 {
        sb := CS.System.Text.StringBuilder(1024)
        sb.Append("x")
        sb := ""
    }
    grown := heap() - baseline
    IsTrue(grown < 8 * 1024 * 1024, "managed heap grew " Round(grown / 1048576, 1) " MB (a leak would be ~20 MB+)")
}

Test("100,000 primitive calls leave the process flat", () => _callChurn())

_callChurn() {
    heap()
    before := processBytes()
    m := CS.System.Math
    Loop 100000
        m.Abs(-A_Index)
    heap()
    grown := processBytes() - before
    IsTrue(grown < 40 * 1024 * 1024, "process grew " Round(grown / 1048576, 1) " MB")
}

; ── delegates and async slots are released ────────────────────────────────────
Test("On()/Off() 2,000 times leaves no delegates behind", () => _delegateChurn())

_delegateChurn() {
    start := CS.Stats()["Delegates"]
    t := CS.System.Timers.Timer(100000)
    Loop 2000 {
        t.On("Elapsed", (*) => 1)
        t.Off("Elapsed")
    }
    Eq(CS.Stats()["Delegates"], start, "registered delegates")
}

Test("500 concurrent async calls all complete and free their slots", () => _asyncBurst())

_asyncBurst() {
    promises := []
    Loop 500
        promises.Push(CS.System.Math.Async.Abs(-A_Index))
    results := CS.Promise.AwaitAll(promises*)
    sum := 0
    for r in results
        sum += r
    Eq(sum, 125250, "sum of 1..500")
    Eq(CS.Stats()["PendingAsyncTasks"], 0, "bridge-side async slots")
    Eq(CS.Stats()["QueuedCallbacks"], 0, "queued AHK callbacks")
}

Test("200 Tasks with AHK callbacks on pool threads all run", () => _callbackBurst())

_callbackBurst() {
    global __state
    __state["n"] := 0
    tasks := []
    Loop 200
        tasks.Push(CS.System.Threading.Tasks.Task.Run(() => __state["n"] += 1))
    for t in tasks
        t.Await(15000)
    Eq(__state["n"], 200, "callbacks executed")
    Eq(CS.Stats()["QueuedCallbacks"], 0, "queue drained")
}

; ── big data ──────────────────────────────────────────────────────────────────
Test("a 10 MB string crosses both ways intact", () => _bigString())

_bigString() {
    s := "0123456789"
    Loop 20
        s .= s                                            ; 10 * 2^20 = 10,485,760 chars
    Eq(StrLen(s), 10485760)
    Eq(CS.System.String.IsNullOrEmpty(s), 0)
    back := CS.System.String.Concat(s, "!")
    Eq(StrLen(back), 10485761)
    Eq(SubStr(back, -1), "!")
    Eq(SubStr(back, 5242881, 10), SubStr(s, 5242881, 10))
}

Test("a 1,000,000-element int array round trips", () => _bigArray())

_bigArray() {
    a := []
    a.Capacity := 1000000
    Loop 1000000
        a.Push(A_Index)
    Eq(CS.System.Linq.Enumerable.Sum(a), 500000500000)
    back := CS.System.Linq.Enumerable.ToArray(a).ToAHK()
    Eq(back.Length, 1000000)
    Eq(back[1000000], 1000000)
}

; ── error storm ───────────────────────────────────────────────────────────────
Test("2,000 caught .NET exceptions stay fast and leak nothing", () => _errorStorm())

_errorStorm() {
    baseline := heap()
    t0 := A_TickCount
    Loop 2000 {
        try
            CS.System.Int32.Parse("x")
        catch as e
            n := e.NetType
    }
    ms := A_TickCount - t0
    IsTrue(ms < 20000, "2,000 exceptions took " ms " ms")
    IsTrue(heap() - baseline < 8 * 1024 * 1024, "heap growth after the storm")
}

; ── caches stay bounded ───────────────────────────────────────────────────────
Test("overload caches do not grow per call", () => _cacheGrowth())

_cacheGrowth() {
    Loop 50
        CS.System.Math.Abs(-1)
    before := CS.Stats()["BoundCallCacheEntries"]
    Loop 5000
        CS.System.Math.Abs(-A_Index)
    Eq(CS.Stats()["BoundCallCacheEntries"], before, "cache entries after 5,000 identical-shape calls")
}

RunTests()
