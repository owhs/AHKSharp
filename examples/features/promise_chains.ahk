;; AHK# — Promise chains: Then / Catch / Finally, Timeout, All / Race, typed errors

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

logText := ""
note(s) {
    global logText
    logText .= s "`n"
}

; ── 1. a chain: every Then returns a NEW promise carrying the callback's value ─
;      .Async runs a .NET method on the thread pool; the message loop stays free.
CS.System.Math.Async.Abs(-21)
    .Then((v) => v * 2)                                   ; 42
    .Then((v) => CS.Promise.Delay(100, v + 1))            ; a returned promise is followed
    .Then((v) => note("chain: " v))
    .Finally(() => note("finally ran"))

; ── 2. errors flow down the chain and keep their .NET identity ───────────────
CS.System.Int32.Async.Parse("not a number")
    .Then((v) => note("never reached"))
    .Catch((e) => note("caught " e.NetType " (FormatException? " CS.ErrorIs(e, "FormatException") ")"))

; ── 3. a timeout, with cancellation of the .NET side ─────────────────────────
cts := CS.System.Threading.CancellationTokenSource()
CS.System.Threading.Tasks.Task.Delay(10000, cts.Token)
    .Timeout(300, cts)                                    ; fails with TimeoutError and cancels the token
    .Catch((e) => note("timeout: " Type(e) ", cancelled=" cts.IsCancellationRequested))

; ── 4. wait for several at once, or take the first to finish ─────────────────
a := CS.Promise.Delay(400, "slow")
b := CS.Promise.Delay(50, "fast")
note("AwaitAny: " CS.Promise.AwaitAny(a, b))
all := CS.Promise.AwaitAll(CS.System.Math.Async.Abs(-1), CS.System.Math.Async.Abs(-2), CS.System.Math.Async.Abs(-3))
note("AwaitAll: " all[1] "," all[2] "," all[3])

Sleep(700)                                                ; let the callbacks run (they run on the AHK thread)
MsgBox(logText, "Promise chains")
