;; AHK# — Async/Await & Parallel Computation
;; Run C# code on the .NET ThreadPool with Module.Async.Method(...).
;; You get a promise back: .Await() waits (while AHK keeps pumping messages),
;; .Then() / .Catch() attach callbacks.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

class HeavyCompute extends _CSModule {
    static CSharp := "
    (
        using System.Threading;

        public static double MonteCarloPi(int iterations) {
            int inside = 0;
            var rng = new Random();
            for (int i = 0; i < iterations; i++) {
                double x = rng.NextDouble();
                double y = rng.NextDouble();
                if (x * x + y * y <= 1.0) inside++;
            }
            return 4.0 * inside / iterations;
        }

        public static long SumPrimes(int limit) {
            long sum = 0;
            for (int n = 2; n <= limit; n++) {
                bool isPrime = true;
                for (int d = 2; d * d <= n; d++) {
                    if (n % d == 0) { isPrime = false; break; }
                }
                if (isPrime) sum += n;
            }
            return sum;
        }
    )"
}

; ── 1. Single async call, awaited ─────────────────────────────────────────────
MsgBox("Starting Monte Carlo Pi estimation (10M iterations)...`nThis runs on a .NET ThreadPool thread.", "AHK# Async")

promise := HeavyCompute.Async.MonteCarloPi(10000000)
ToolTip("Computing... (AHK is still responsive! Move your mouse.)")
pi := promise.Await()
ToolTip("")
MsgBox("Monte Carlo Pi ≈ " pi, "AHK# — Async Result")

; ── 2. Multiple parallel tasks (timed) ────────────────────────────────────────
t := A_TickCount
p1 := HeavyCompute.Async.SumPrimes(50000)
p2 := HeavyCompute.Async.SumPrimes(75000)
p3 := HeavyCompute.Async.MonteCarloPi(5000000)

r1 := p1.Await()
r2 := p2.Await()
r3 := p3.Await()
elapsed := A_TickCount - t

MsgBox("3 parallel tasks completed in " elapsed "ms:`n"
    . "  SumPrimes(50K)  = " r1 "`n"
    . "  SumPrimes(75K)  = " r2 "`n"
    . "  MonteCarloPi(5M) ≈ " r3
    , "AHK# — Parallel Results")

; ── 3. Callbacks with Then / Catch ────────────────────────────────────────────
; Done after the timing block above so the callback cannot skew "elapsed".
thenFired := false

OnSumDone(result) {
    global thenFired := true
    ToolTip("Then callback: sum of primes up to 100,000 = " result)
}

OnSumFailed(err) {
    global thenFired := true
    ToolTip("Catch callback: " err.Message)
}

sumPromise := HeavyCompute.Async.SumPrimes(100000)
sumPromise.Then(OnSumDone)          ; Then / Catch return NEW promises: keep sumPromise for Await
sumPromise.Catch(OnSumFailed)

; Await the original promise instead of sleeping a fixed time: it returns as soon as
; the work is done, and keeps pumping messages so the callback can run.
total := sumPromise.Await()
Loop 50 {                       ; the callback is queued, give AHK a moment to run it
    if (thenFired)
        break
    Sleep(10)
}

MsgBox("SumPrimes(100K) = " total "`nThen callback fired: " (thenFired ? "yes (see tooltip)" : "no")
    , "AHK# — Callback Result")
ToolTip("")

ExitApp()
