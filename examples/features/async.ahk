;; AHK# Example 03 — Async/Await & Parallel Computation

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

MsgBox("Starting Monte Carlo Pi estimation (10M iterations)...`nThis runs on a .NET ThreadPool thread.", "AHK# Async")

promise := HeavyCompute.Async.MonteCarloPi(10000000)
ToolTip("Computing... (AHK is still responsive! Move your mouse.)")
pi := promise.Await()
ToolTip("")
MsgBox("Monte Carlo Pi ≈ " pi, "AHK# — Async Result")

; Fire-and-forget with Then/Catch callbacks
HeavyCompute.Async.SumPrimes(100000)
    .Then((result) => MsgBox("Sum of primes up to 100,000 = " result, "AHK# — Callback Result"))
    .Catch((err) => MsgBox("Error: " err.Message, "AHK# — Error"))

; Multiple parallel tasks
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

Sleep(3000)
ExitApp()

