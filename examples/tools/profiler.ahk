;; AHK# Example 37 — Live Script Profiler
;; Nanosecond-precision timing for any code block. AHK has ZERO profiling tools.
;; This gives you Stopwatch-class precision + memory tracking + comparison tables.
;;
;; Usage:
;;   Profiler.Start("my_operation")
;;   ; ... code to measure ...
;;   elapsed := Profiler.Stop("my_operation")   ; returns microseconds
;;   MsgBox(Profiler.Report())                  ; formatted table

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

; ── CSModule: Profiler ────────────────────────────────────────────────────────

class Profiler extends _CSModule {
    static CSharp := '
    (
        using System;
        using System.Collections.Generic;
        using System.Diagnostics;
        using System.Text;

        private static Dictionary<string, Stopwatch> _active = new Dictionary<string, Stopwatch>();
        private static Dictionary<string, List<double>> _history = new Dictionary<string, List<double>>();
        private static Dictionary<string, long> _memSnap = new Dictionary<string, long>();
        private static Dictionary<string, long> _memDelta = new Dictionary<string, long>();

        public static void Start(string label) {
            _memSnap[label] = GC.GetTotalMemory(false);
            var sw = new Stopwatch();
            _active[label] = sw;
            sw.Start();
        }

        public static double Stop(string label) {
            if (!_active.ContainsKey(label)) return -1;
            _active[label].Stop();
            double us = _active[label].Elapsed.TotalMilliseconds * 1000.0;

            if (!_history.ContainsKey(label))
                _history[label] = new List<double>();
            _history[label].Add(us);

            long memAfter = GC.GetTotalMemory(false);
            _memDelta[label] = memAfter - _memSnap[label];
            _active.Remove(label);
            return us;
        }

        public static double Measure(string label, int iterations) {
            if (!_history.ContainsKey(label))
                _history[label] = new List<double>();

            var sw = new Stopwatch();
            long memBefore = GC.GetTotalMemory(false);
            sw.Start();
            // Returns immediately — caller runs the code and calls MeasureEnd
            _active[label] = sw;
            _memSnap[label] = memBefore;
            return 0;
        }

        public static string Report() {
            if (_history.Count == 0) return "(no profiling data)";

            var sb = new StringBuilder();
            sb.AppendLine(string.Format("{0,-22} {1,12} {2,12} {3,12} {4,12} {5,7} {6,10}",
                "Label", "Last(us)", "Avg(us)", "Min(us)", "Max(us)", "Count", "Mem(KB)"));
            sb.AppendLine(new string((char)0x2500, 92));

            foreach (var kv in _history) {
                var times = kv.Value;
                if (times.Count == 0) continue;
                double last = times[times.Count - 1];
                double sum = 0;
                double min = double.MaxValue;
                double max = 0;
                foreach (double t in times) {
                    sum += t;
                    if (t < min) min = t;
                    if (t > max) max = t;
                }
                double avg = sum / times.Count;
                long mem = 0;
                if (_memDelta.ContainsKey(kv.Key)) mem = _memDelta[kv.Key];

                sb.AppendLine(string.Format("{0,-22} {1,12:F1} {2,12:F1} {3,12:F1} {4,12:F1} {5,7} {6,10:F1}",
                    kv.Key.Length > 21 ? kv.Key.Substring(0, 21) : kv.Key,
                    last, avg, min, max, times.Count, mem / 1024.0));
            }
            return sb.ToString();
        }

        public static string Compare(string labelA, string labelB) {
            if (!_history.ContainsKey(labelA) || !_history.ContainsKey(labelB))
                return "Both labels must have data";

            double avgA = Avg(_history[labelA]);
            double avgB = Avg(_history[labelB]);
            double ratio = avgA > 0 ? avgB / avgA : 0;
            string faster = avgA < avgB ? labelA : labelB;
            double factor = avgA < avgB ? avgB / avgA : avgA / avgB;

            return string.Format("{0} vs {1}: {2} is {3:F1}x faster (avg {4:F0}us vs {5:F0}us)",
                labelA, labelB, faster, factor, Math.Min(avgA, avgB), Math.Max(avgA, avgB));
        }

        public static string TimerResolution() {
            return string.Format("Stopwatch freq: {0:N0} Hz ({1})",
                Stopwatch.Frequency,
                Stopwatch.IsHighResolution ? "high-resolution" : "low-resolution");
        }

        public static void Reset() {
            _active.Clear();
            _history.Clear();
            _memSnap.Clear();
            _memDelta.Clear();
        }

        private static double Avg(List<double> list) {
            if (list.Count == 0) return 0;
            double sum = 0;
            foreach (double v in list) sum += v;
            return sum / list.Count;
        }

        // ── Built-in benchmarks for C# comparison ────────────────────────
        public static string BenchStringBuilder(int len) {
            var sb = new System.Text.StringBuilder();
            for (int i = 0; i < len; i++) sb.Append("x");
            return sb.ToString();
        }

        public static double BenchMathLoop(int count) {
            double s = 0;
            for (int i = 1; i <= count; i++) s += Math.Sqrt(i);
            return s;
        }

        public static bool BenchFileExists(string path, int count) {
            for (int i = 0; i < count; i++)
                System.IO.File.Exists(path);
            return true;
        }

        public static int BenchRegex(string pattern, string input, int count) {
            var r = new System.Text.RegularExpressions.Regex(pattern);
            for (int i = 0; i < count; i++) r.Match(input);
            return count;
        }

        public static int BenchListFill(int count) {
            var l = new System.Collections.Generic.List<int>(count);
            for (int i = 0; i < count; i++) l.Add(i);
            return l.Count;
        }
    )'
}

; ── Demo: Profile Real Operations ─────────────────────────────────────────────

g := Gui("+Resize", "AHK# — Script Profiler")
g.SetFont("s10", "Segoe UI")
g.BackColor := "0x1e1e2e"
g.SetFont("cCDD6F4")

; Header
g.SetFont("s13 cF38BA8 Bold")
g.Add("Text", "x20 y10 w560", Chr(0x23F1) " Live Script Profiler")
g.SetFont("s8 c585B70 Norm")
g.Add("Text", "x20 y34 w560", Profiler.TimerResolution() " — AHK vs C# head-to-head benchmarks")

; Controls
g.SetFont("s10 cCDD6F4", "Segoe UI")
btnRun := g.Add("Button", "x20 y58 w130 h32", Chr(0x25B6) " Run Benchmark")
btnClear := g.Add("Button", "x158 y58 w80 h32", "Reset")
g.SetFont("s9 c585B70")
statusText := g.Add("Text", "x250 y66 w330 Right", "Press Run to start")

; Results
g.SetFont("s10 cF38BA8")
g.Add("Text", "x20 y98", Chr(0x25CF) " Results")
g.SetFont("s9", "Cascadia Mono")
reportEdit := g.Add("Edit", "x20 y118 w560 h320 Multi ReadOnly Background0x181825 cA6E3A1 VScroll HScroll")

; ── Benchmark Suite ───────────────────────────────────────────────────────────

RunBenchmark() {
    statusText.Value := "Running benchmarks..."
    Profiler.Reset()

    ; 1. AHK string concatenation
    Profiler.Start("AHK String Concat")
    s := ""
    Loop 500
        s .= "x"
    Profiler.Stop("AHK String Concat")

    ; 2. C# StringBuilder via CSModule
    Profiler.Start("C# StringBuilder")
    Profiler.BenchStringBuilder(500)
    Profiler.Stop("C# StringBuilder")

    ; 3. AHK Math loop
    Profiler.Start("AHK Math Loop")
    total := 0
    Loop 1000
        total += Sqrt(A_Index)
    Profiler.Stop("AHK Math Loop")

    ; 4. C# Math loop via CSModule
    Profiler.Start("C# Math Loop")
    Profiler.BenchMathLoop(1000)
    Profiler.Stop("C# Math Loop")

    ; 5. File existence check
    Profiler.Start("AHK FileExist")
    Loop 100
        FileExist(A_ScriptFullPath)
    Profiler.Stop("AHK FileExist")

    ; 6. .NET File.Exists via CSModule
    Profiler.Start("C# File.Exists")
    Profiler.BenchFileExists(A_ScriptFullPath, 100)
    Profiler.Stop("C# File.Exists")

    ; 7. AHK RegExMatch
    Profiler.Start("AHK RegExMatch")
    haystack := "The quick brown fox jumps over 42 lazy dogs at 3.14 speed"
    Loop 200
        RegExMatch(haystack, "\d+\.?\d*")
    Profiler.Stop("AHK RegExMatch")

    ; 8. C# Regex via CSModule
    Profiler.Start("C# Regex.Match")
    Profiler.BenchRegex("\d+\.?\d*", "The quick brown fox jumps over 42 lazy dogs at 3.14 speed", 200)
    Profiler.Stop("C# Regex.Match")

    ; 9. AHK array fill
    Profiler.Start("AHK Array Fill")
    arr := []
    Loop 2000
        arr.Push(A_Index)
    Profiler.Stop("AHK Array Fill")

    ; 10. C# List fill via CSModule
    Profiler.Start("C# List Fill")
    Profiler.BenchListFill(2000)
    Profiler.Stop("C# List Fill")

    ; Show report
    report := "╔══════════════════════════════════════════════════════════════╗`r`n"
    report .= "║  AHK vs C# Benchmark Results                               ║`r`n"
    report .= "╚══════════════════════════════════════════════════════════════╝`r`n`r`n"
    report .= Profiler.Report()
    report .= "`r`n── Comparisons ──────────────────────────────────────────────`r`n`r`n"
    report .= "  " Profiler.Compare("AHK String Concat", "C# StringBuilder") "`r`n"
    report .= "  " Profiler.Compare("AHK Math Loop", "C# Math Loop") "`r`n"
    report .= "  " Profiler.Compare("AHK FileExist", "C# File.Exists") "`r`n"
    report .= "  " Profiler.Compare("AHK RegExMatch", "C# Regex.Match") "`r`n"
    report .= "  " Profiler.Compare("AHK Array Fill", "C# List Fill") "`r`n"
    reportEdit.Value := report
    statusText.Value := Chr(0x2705) " Done — " FormatTime(A_Now, "HH:mm:ss")
}

btnRun.OnEvent("Click", (*) => RunBenchmark())
btnClear.OnEvent("Click", (*) => (Profiler.Reset(), reportEdit.Value := "", statusText.Value := "Cleared"))

g.OnEvent("Close", (*) => ExitApp())
g.Show("w600 h450")

WinWaitClose(g.Hwnd)
ExitApp()

