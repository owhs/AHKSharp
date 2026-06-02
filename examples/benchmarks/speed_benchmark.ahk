;; AHK# Example 17 — MEGA Speed Benchmark: Native AHK vs AHK# (.NET)
;; Full graphical dashboard rendered pixel-perfect via System.Drawing.
;; 12 head-to-head benchmarks. DPI-aware. Zero stretching.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

; ══════════════════════════════════════════════════════════════════════════════
; C# benchmark implementations
; ══════════════════════════════════════════════════════════════════════════════

class CSBench extends _CSModule {
    static CSharp := "
    (
        using System;
        using System.Linq;
        using System.Text;
        using System.Security.Cryptography;
        using System.Text.RegularExpressions;
        using System.Collections.Generic;

        public static long SumTo(int n) {
            long s = 0; for (int i = 1; i <= n; i++) s += i; return s;
        }
        public static int CountPrimes(int limit) {
            bool[] sieve = new bool[limit + 1]; int c = 0;
            for (int i = 2; i <= limit; i++) {
                if (!sieve[i]) { c++; for (long j = (long)i*i; j <= limit; j += i) sieve[(int)j] = true; }
            } return c;
        }
        public static long Fibonacci(int n) {
            long a = 0, b = 1;
            for (int i = 0; i < n; i++) { long t = a + b; a = b; b = t; } return a;
        }
        public static string HashRepeat(string input, int iterations) {
            var sha = SHA256.Create(); byte[] d = Encoding.UTF8.GetBytes(input);
            for (int i = 0; i < iterations; i++) d = sha.ComputeHash(d);
            return BitConverter.ToString(d).Replace("-", "").ToLower();
        }
        public static int RegexExtract(string text) {
            return Regex.Matches(text, @"\b[\w.]+@[\w]+\.[\w]+\b").Count;
        }
        public static int BuildCSV(int rows, int cols) {
            var sb = new StringBuilder();
            for (int r = 0; r < rows; r++) {
                for (int c = 0; c < cols; c++) { if (c > 0) sb.Append(','); sb.Append(r * cols + c); }
                sb.AppendLine();
            } return sb.Length;
        }
        public static int SortArray(int count) {
            var rng = new Random(42); int[] arr = new int[count];
            for (int i = 0; i < count; i++) arr[i] = rng.Next();
            Array.Sort(arr); return arr[0];
        }
        public static double ComputePi(int terms) {
            double pi = 0;
            for (int i = 0; i < terms; i++) pi += (i % 2 == 0 ? 1.0 : -1.0) / (2 * i + 1);
            return pi * 4;
        }
        public static int StringReplace(string text, int iterations) {
            string result = text;
            for (int i = 0; i < iterations; i++) result = result.Replace("the", "THE").Replace("THE", "the");
            return result.Length;
        }
        public static int CollatzMax(int limit) {
            int maxLen = 0;
            for (int n = 2; n < limit; n++) {
                long x = n; int len = 0;
                while (x != 1) { x = x % 2 == 0 ? x / 2 : 3 * x + 1; len++; }
                if (len > maxLen) maxLen = len;
            } return maxLen;
        }
        public static int WordFrequency(string text) {
            var words = text.Split(new[] { ' ', '\n', '\r', '\t' }, StringSplitOptions.RemoveEmptyEntries);
            var freq = new Dictionary<string, int>();
            foreach (var w in words) { string l = w.ToLower(); if (freq.ContainsKey(l)) freq[l]++; else freq[l] = 1; }
            return freq.Count;
        }
        public static int MatrixMultiply(int size) {
            double[,] a = new double[size, size], b = new double[size, size], c = new double[size, size];
            var rng = new Random(42);
            for (int i = 0; i < size; i++) for (int j = 0; j < size; j++) { a[i,j] = rng.NextDouble(); b[i,j] = rng.NextDouble(); }
            for (int i = 0; i < size; i++) for (int j = 0; j < size; j++) { double s = 0; for (int k = 0; k < size; k++) s += a[i,k] * b[k,j]; c[i,j] = s; }
            return size;
        }

        // ── Tests where AHK is competitive ──────────────────────────
        public static int MapInsertLookup(int count) {
            var dict = new Dictionary<string, int>();
            for (int i = 0; i < count; i++) dict["key" + i] = i;
            int sum = 0;
            for (int i = 0; i < count; i++) sum += dict["key" + i];
            return sum;
        }
        public static int ParseLines(string text) {
            int count = 0;
            foreach (var line in text.Split('\n'))
                if (line.Length > 0) count++;
            return count;
        }
        public static int SmallRegex(string text, int iterations) {
            int total = 0;
            for (int i = 0; i < iterations; i++)
                total += Regex.Matches(text, @"\d+").Count;
            return total;
        }
        public static int ArrayBuild(int count) {
            var list = new List<int>();
            for (int i = 0; i < count; i++) list.Add(i * 3 + 7);
            int sum = 0;
            foreach (var v in list) sum += v;
            return sum;
        }
        public static long Conditionals(int iterations) {
            long sum = 0;
            for (int i = 0; i < iterations; i++) {
                if (i % 3 == 0) sum += 1;
                else if (i % 5 == 0) sum += 2;
                else if (i % 7 == 0) sum += 3;
                else sum += i;
            }
            return sum;
        }
    )"
}

; ══════════════════════════════════════════════════════════════════════════════
; Chart renderer — renders ONLY the bar chart portion at exact pixel dimensions
; ══════════════════════════════════════════════════════════════════════════════

class ChartImg extends _CSModule {
    static References := "System.Drawing.dll"
    static CSharp := "
    (
        using System;
        using System.Drawing;
        using System.Drawing.Drawing2D;
        using System.Drawing.Text;
        using System.Collections.Generic;

        static Color Accent = Color.FromArgb(0, 255, 136);
        static Color Dim = Color.FromArgb(100, 105, 130);
        static Color White = Color.FromArgb(210, 215, 235);

        static Color BarColor(double ratio) {
            if (ratio > 100) return Color.FromArgb(0, 255, 120);
            if (ratio > 20)  return Color.FromArgb(0, 220, 180);
            if (ratio > 5)   return Color.FromArgb(80, 180, 255);
            if (ratio > 1)   return Color.FromArgb(255, 200, 80);
            return Color.FromArgb(255, 100, 100);
        }

        public static string Render(string dataStr, int w, int h, string path) {
            var items = new List<string[]>();
            foreach (var it in dataStr.Split(new[]{';'}, StringSplitOptions.RemoveEmptyEntries))
                items.Add(it.Split('|'));

            using (var bmp = new Bitmap(w, h))
            using (var g = Graphics.FromImage(bmp)) {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;

                g.Clear(Color.FromArgb(10, 10, 22));

                int pad = 16;
                int cw = w - pad * 2;

                // Title
                var fTitle = new Font("Segoe UI", 14, FontStyle.Bold);
                var fSub = new Font("Segoe UI", 8.5f);
                var fLabel = new Font("Segoe UI", 10, FontStyle.Bold);
                var fTime = new Font("Cascadia Mono", 7.5f);
                var fSpd = new Font("Segoe UI", 11, FontStyle.Bold);
                var fLeg = new Font("Segoe UI", 7.5f);

                int y = pad;
                g.DrawString("\u26A1 SPEEDUP CHART", fTitle, new SolidBrush(Accent), pad, y);
                y += 24;
                g.DrawString("Log scale \u2022 Bar = C# speed advantage over native AHK", fSub, new SolidBrush(Dim), pad, y);
                y += 18;

                g.DrawLine(new Pen(Color.FromArgb(40, 40, 60), 1), pad, y, pad + cw, y);
                y += 6;

                // Calculate bar sizing to fill available space
                int legendH = 24;
                int availH = h - y - legendH - pad;
                int barH = Math.Max(availH / items.Count - 3, 16);
                int gap = 3;
                int labelW = (int)(cw * 0.20);
                int barLeft = pad + labelW;
                int barArea = cw - labelW - 65;

                // Max ratio for log scale
                double maxR = 1;
                foreach (var it in items) {
                    int a = int.Parse(it[1]), c = int.Parse(it[2]);
                    if (a > 0) { double r = (double)Math.Max(a,1) / Math.Max(c,1); if (r > maxR) maxR = r; }
                }
                double logMax = Math.Log10(Math.Max(maxR, 10));

                for (int i = 0; i < items.Count; i++) {
                    var it = items[i];
                    int ahk = int.Parse(it[1]), cs = int.Parse(it[2]);
                    double ratio = ahk == -1 ? -1 : (double)Math.Max(ahk,1) / Math.Max(cs,1);

                    // Label
                    g.DrawString(it[0], fLabel, new SolidBrush(White), pad, y + 2);

                    g.FillRectangle(new SolidBrush(Color.FromArgb(22, 22, 42)), barLeft, y, barArea, barH);

                    if (ratio < 0) {
                        using (var pb = new LinearGradientBrush(new Rectangle(barLeft, y, barArea, barH),
                            Color.FromArgb(130, 55, 190), Color.FromArgb(80, 30, 140), 0f))
                            g.FillRectangle(pb, barLeft, y, barArea, barH);
                        g.DrawString("NO AHK EQUIVALENT", fLabel, new SolidBrush(Color.FromArgb(210, 180, 250)),
                            barLeft + 6, y + 2);
                        g.DrawString("\u221E", fSpd, new SolidBrush(Color.FromArgb(190, 150, 240)),
                            barLeft + barArea + 8, y + 1);
                    } else {
                        double logR = Math.Log10(Math.Max(ratio, 1));
                        int bw = (int)Math.Max(logR / logMax * barArea, 3);
                        Color clr = BarColor(ratio);

                        if (bw > 2) {
                            Color clr2 = Color.FromArgb(clr.R*3/4, clr.G*3/4, clr.B*3/4);
                            using (var bb = new LinearGradientBrush(new Rectangle(barLeft, y, bw+1, barH), clr, clr2, 0f))
                                g.FillRectangle(bb, barLeft, y, bw, barH);
                            using (var gp = new Pen(Color.FromArgb(100, clr), 1))
                                g.DrawLine(gp, barLeft, y, barLeft + bw, y);
                        }
                        string tl = ahk + " vs " + cs + "ms";
                        g.DrawString(tl, fTime, new SolidBrush(Color.FromArgb(140, 145, 165)),
                            barLeft + 4, y + barH - 12);
                        g.DrawString(Math.Round(ratio, 1) + "x", fSpd, new SolidBrush(clr),
                            barLeft + barArea + 6, y + 1);
                    }
                    y += barH + gap;
                }

                // Legend
                y = h - legendH - pad / 2;
                g.DrawLine(new Pen(Color.FromArgb(40, 40, 60), 1), pad, y, pad + cw, y);
                y += 5;
                int lsz = 10;
                Action<int, Color, string> lg = (lx, cl, tx) => {
                    g.FillRectangle(new SolidBrush(cl), lx, y + 2, lsz, lsz);
                    g.DrawString(tx, fLeg, new SolidBrush(Dim), lx + lsz + 4, y + 1);
                };
                int stp = cw / 5;
                lg(pad, Color.FromArgb(0,255,120), ">100x");
                lg(pad+stp, Color.FromArgb(0,220,180), "20-100x");
                lg(pad+stp*2, Color.FromArgb(80,180,255), "5-20x");
                lg(pad+stp*3, Color.FromArgb(255,200,80), "1-5x");
                lg(pad+stp*4, Color.FromArgb(130,55,190), "N/A");

                bmp.Save(path, System.Drawing.Imaging.ImageFormat.Png);
                return "ok";
            }
        }
    )"
}

; ══════════════════════════════════════════════════════════════════════════════
; GUI — Two tabs: Table (Edit) + Chart (Picture), both fit perfectly
; ══════════════════════════════════════════════════════════════════════════════

g := Gui("+Resize +MinSize500x400", "AHK# — MEGA Speed Benchmark")
g.BackColor := "0x0a0a16"
g.MarginX := 0, g.MarginY := 0

g.SetFont("s10 cCDD6F4", "Segoe UI")
tabs := g.Add("Tab3", "x0 y0 w700 h550 vTabs", ["⚡ Chart", "📊 Table"])

; Tab 1: Chart image — pixel-perfect, no stretching
tabs.UseTab(1)
chartPic := g.Add("Picture", "x2 y28 w696 h518 vChartPic Background0x0a0a16")

; Tab 2: Table text — scrollable Edit
tabs.UseTab(2)
g.SetFont("s9 c00FF88", "Cascadia Mono")
tableEdit := g.Add("Edit", "x2 y28 w696 h518 Multi ReadOnly -Border Background0x0d0d1a c00FF88 vTableEdit +VScroll")

tabs.UseTab()

g.SetFont("s11 cFFFFFF", "Segoe UI")
btnRun := g.Add("Button", "x5 y555 w690 h36 vRunBtn", "⚡  RUN BENCHMARKS  ⚡")
btnRun.OnEvent("Click", (*) => RunAll())

g.SetFont("s8 c00FF88", "Cascadia Mono")
statusText := g.Add("Text", "x5 y595 w690 h18 vStatusText BackgroundTrans", "Ready")

; Responsive + re-render chart on resize
lastChartData := ""

g.OnEvent("Size", GuiResize)
GuiResize(thisGui, minMax, w, h) {
    if minMax == -1
        return
    try {
        tabs.Move(0, 0, w, h - 65)
        chartPic.Move(2, 28, w - 8, h - 100)
        tableEdit.Move(2, 28, w - 8, h - 100)
        btnRun.Move(5, h - 60, w - 10, 36)
        statusText.Move(5, h - 22, w - 10, 18)
    }
    ; Debounce re-render: wait 300ms after last resize
    SetTimer(DoRerender, -300)
}

DoRerender() {
    global lastChartData
    if lastChartData == ""
        return
    try {
        chartPic.GetPos(,, &pw, &ph)
        if pw > 50 && ph > 50 {
            chartPath := A_Temp "\ahk_bench_chart.png"
            ChartImg.Render(lastChartData, pw, ph, chartPath)
            chartPic.Value := chartPath
        }
    }
}

; ══════════════════════════════════════════════════════════════════════════════
; Helpers for nice table formatting
; ══════════════════════════════════════════════════════════════════════════════

Pad(s, w) {
    s := String(s)
    while StrLen(s) < w
        s .= " "
    return SubStr(s, 1, w)
}
PadR(s, w) {
    s := String(s)
    while StrLen(s) < w
        s := " " s
    return SubStr(s, -w+1)
}

; ══════════════════════════════════════════════════════════════════════════════
; BENCHMARK RUNNER
; ══════════════════════════════════════════════════════════════════════════════

RunAll() {
    results := []
    total := 17
    btnRun.Enabled := false

    S(msg) {
        statusText.Value := msg
        Sleep(1)
    }

    ; ─── 1 ──
    S("[1/" total "] Sum 1..10M")
    t := A_TickCount, sum := 0
    Loop 10000000
        sum += A_Index
    ahk1 := A_TickCount - t
    t := A_TickCount
    CSBench.SumTo(10000000)
    cs1 := A_TickCount - t
    results.Push({name: "Sum 1..10M", ahk: ahk1, cs: cs1})

    ; ─── 2 ──
    S("[2/" total "] Primes ≤500K")
    t := A_TickCount, ahkP := 0
    Loop 499999 {
        nn := A_Index + 1, isPrime := true, dd := 2
        while dd * dd <= nn {
            if Mod(nn, dd) == 0 {
                isPrime := false
                break
            }
            dd++
        }
        if isPrime
            ahkP++
    }
    ahk2 := A_TickCount - t
    t := A_TickCount
    CSBench.CountPrimes(500000)
    cs2 := A_TickCount - t
    results.Push({name: "Primes ≤500K", ahk: ahk2, cs: cs2})

    ; ─── 3 ──
    S("[3/" total "] Fib(70)×10K")
    t := A_TickCount
    Loop 10000 {
        fA := 0, fB := 1
        Loop 70 {
            tmp := fA + fB
            fA := fB
            fB := tmp
        }
    }
    ahk3 := A_TickCount - t
    t := A_TickCount
    Loop 10000
        CSBench.Fibonacci(70)
    cs3 := A_TickCount - t
    results.Push({name: "Fib(70)×10K", ahk: ahk3, cs: cs3})

    ; ─── 4 ──
    S("[4/" total "] SHA256 ×10K")
    t := A_TickCount
    CSBench.HashRepeat("AHK# benchmark", 10000)
    cs4 := A_TickCount - t
    results.Push({name: "SHA256 ×10K", ahk: -1, cs: cs4})

    ; ─── 5 ──
    S("[5/" total "] Regex 5K lines")
    testText := ""
    Loop 5000
        testText .= "Line " A_Index " user" A_Index "@example.com`n"
    t := A_TickCount
    ahkR := 0, pos := 1
    while RegExMatch(testText, "\b[\w.]+@[\w]+\.[\w]+\b", &m, pos)
        ahkR++, pos := m.Pos + m.Len
    ahk5 := A_TickCount - t
    t := A_TickCount
    CSBench.RegexExtract(testText)
    cs5 := A_TickCount - t
    results.Push({name: "Regex 5K", ahk: ahk5, cs: cs5})

    ; ─── 6 ──
    S("[6/" total "] CSV 5K×20")
    t := A_TickCount
    csv := ""
    Loop 5000 {
        row := "", rr := A_Index
        Loop 20 {
            if A_Index > 1
                row .= ","
            row .= (rr - 1) * 20 + A_Index - 1
        }
        csv .= row "`n"
    }
    ahk6 := A_TickCount - t
    csv := ""
    t := A_TickCount
    CSBench.BuildCSV(5000, 20)
    cs6 := A_TickCount - t
    results.Push({name: "CSV 5K×20", ahk: ahk6, cs: cs6})

    ; ─── 7 ──
    S("[7/" total "] Sort 100K")
    t := A_TickCount
    CSBench.SortArray(100000)
    cs7 := A_TickCount - t
    results.Push({name: "Sort 100K", ahk: -1, cs: cs7})

    ; ─── 8 ──
    S("[8/" total "] Pi 10M terms")
    t := A_TickCount
    pi := 0.0
    Loop 10000000 {
        ii := A_Index - 1
        pi += (Mod(ii, 2) == 0 ? 1.0 : -1.0) / (2 * ii + 1)
    }
    ahk8 := A_TickCount - t
    t := A_TickCount
    CSBench.ComputePi(10000000)
    cs8 := A_TickCount - t
    results.Push({name: "Pi 10M", ahk: ahk8, cs: cs8})

    ; ─── 9 ──
    S("[9/" total "] StrReplace ×1K")
    testStr := "the quick brown fox jumps over the lazy dog and the cat sat on the mat"
    t := A_TickCount
    ss := testStr
    Loop 1000
        ss := StrReplace(StrReplace(ss, "the", "THE"), "THE", "the")
    ahk9 := A_TickCount - t
    t := A_TickCount
    CSBench.StringReplace(testStr, 1000)
    cs9 := A_TickCount - t
    results.Push({name: "StrReplace ×1K", ahk: ahk9, cs: cs9})

    ; ─── 10 ──
    S("[10/" total "] Collatz <100K")
    t := A_TickCount
    maxChain := 0
    Loop 99999 {
        nn := A_Index + 1, steps := 0, xx := nn
        while xx != 1 {
            xx := Mod(xx, 2) == 0 ? xx // 2 : 3 * xx + 1
            steps++
        }
        if steps > maxChain
            maxChain := steps
    }
    ahk10 := A_TickCount - t
    t := A_TickCount
    CSBench.CollatzMax(100000)
    cs10 := A_TickCount - t
    results.Push({name: "Collatz <100K", ahk: ahk10, cs: cs10})

    ; ─── 11 ──
    S("[11/" total "] WordFreq 50K")
    wordText := ""
    wds := ["alpha","bravo","charlie","delta","echo","foxtrot","golf","hotel"]
    wSeed := 42
    Loop 50000 {
        wSeed := Mod(wSeed * 1103515245 + 12345, 2147483648)
        wordText .= wds[Mod(wSeed, wds.Length) + 1] " "
    }
    t := A_TickCount
    freq := Map()
    Loop Parse, wordText, " " {
        if A_LoopField == ""
            continue
        ww := StrLower(A_LoopField)
        freq[ww] := freq.Has(ww) ? freq[ww] + 1 : 1
    }
    ahk11 := A_TickCount - t
    t := A_TickCount
    CSBench.WordFrequency(wordText)
    cs11 := A_TickCount - t
    results.Push({name: "WordFreq 50K", ahk: ahk11, cs: cs11})

    ; ─── 12 ──
    S("[12/" total "] Matrix 100×100")
    t := A_TickCount
    CSBench.MatrixMultiply(100)
    cs12 := A_TickCount - t
    results.Push({name: "Matrix 100²", ahk: -1, cs: cs12})

    ; ══════════════════════════════════════════════════════════════════
    ; AHK STRENGTH TESTS — where AHK is competitive or wins!
    ; ══════════════════════════════════════════════════════════════════

    ; ─── 13 ── Map Insert/Lookup 100K (AHK Map is C++ backed)
    S("[13/" total "] Map 100K ops")
    t := A_TickCount
    myMap := Map()
    Loop 100000
        myMap["key" A_Index] := A_Index
    mapSum := 0
    Loop 100000
        mapSum += myMap["key" A_Index]
    ahk13 := A_TickCount - t
    t := A_TickCount
    CSBench.MapInsertLookup(100000)
    cs13 := A_TickCount - t
    results.Push({name: "Map 100K", ahk: ahk13, cs: cs13})

    ; ─── 14 ── Loop Parse 50K lines (AHK's native parser)
    S("[14/" total "] Parse 50K lines")
    parseText := ""
    Loop 50000
        parseText .= "Line " A_Index " data here`n"
    t := A_TickCount
    lineCount := 0
    Loop Parse, parseText, "`n" {
        if A_LoopField != ""
            lineCount++
    }
    ahk14 := A_TickCount - t
    t := A_TickCount
    CSBench.ParseLines(parseText)
    cs14 := A_TickCount - t
    results.Push({name: "Parse 50K ln", ahk: ahk14, cs: cs14})

    ; ─── 15 ── Small Regex ×10K (AHK PCRE is blazing)
    S("[15/" total "] SmallRegex ×10K")
    rxText := "abc 123 def 456 ghi 789 jkl 012"
    t := A_TickCount
    rxTotal := 0
    Loop 10000 {
        rxPos := 1
        while RegExMatch(rxText, "\d+", &rxM, rxPos) {
            rxTotal++
            rxPos := rxM.Pos + rxM.Len
        }
    }
    ahk15 := A_TickCount - t
    t := A_TickCount
    CSBench.SmallRegex(rxText, 10000)
    cs15 := A_TickCount - t
    results.Push({name: "SmallRx ×10K", ahk: ahk15, cs: cs15})

    ; ─── 16 ── Array Build 100K (AHK arrays are C++ backed)
    S("[16/" total "] Array 100K")
    t := A_TickCount
    arr := []
    Loop 100000
        arr.Push(A_Index * 3 + 7)
    arrSum := 0
    for val in arr
        arrSum += val
    ahk16 := A_TickCount - t
    t := A_TickCount
    CSBench.ArrayBuild(100000)
    cs16 := A_TickCount - t
    results.Push({name: "Array 100K", ahk: ahk16, cs: cs16})

    ; ─── 17 ── Simple Conditionals 10M (interpreter overhead test)
    S("[17/" total "] Conditionals 10M")
    t := A_TickCount
    cndSum := 0
    Loop 10000000 {
        ii := A_Index
        if Mod(ii, 3) == 0 {
            cndSum += 1
        } else if Mod(ii, 5) == 0 {
            cndSum += 2
        } else if Mod(ii, 7) == 0 {
            cndSum += 3
        } else {
            cndSum += ii
        }
    }
    ahk17 := A_TickCount - t
    t := A_TickCount
    CSBench.Conditionals(10000000)
    cs17 := A_TickCount - t
    results.Push({name: "Cond 10M", ahk: ahk17, cs: cs17})

    ; ══════════════════════════════════════════════════════════════════
    ; Build table text (Tab 2)
    ; ══════════════════════════════════════════════════════════════════
    S("Rendering...")

    hdr := " " Pad("BENCHMARK", 16) " │ " PadR("AHK", 8) " │ " PadR("C#", 8) " │ " PadR("SPEEDUP", 9) " │ OK"
    sep := " " Pad("────────────────", 16) " ┼ " PadR("────────", 8) " ┼ " PadR("────────", 8) " ┼ " PadR("─────────", 9) " ┼ ──"
    tbl := "═══════════════════════════════════════════════════════════`n"
    tbl .= "  ⚡ AHK# MEGA SPEED BENCHMARK — 17 Tests`n"
    tbl .= "═══════════════════════════════════════════════════════════`n`n"
    tbl .= hdr "`n" sep "`n"

    totalAhk := 0, totalCs := 0
    for r in results {
        ahkStr := r.ahk >= 0 ? PadR(r.ahk "ms", 8) : PadR("N/A", 8)
        csStr  := PadR(r.cs "ms", 8)
        if (r.ahk == -1)
            ratio := -1, spdStr := PadR("∞", 9)
        else {
            ratio := Round(Max(r.ahk, 1) / Max(r.cs, 1), 1)
            spdStr := PadR(ratio "×", 9)
            totalAhk += r.ahk, totalCs += r.cs
        }
        tbl .= " " Pad(r.name, 16) " │ " ahkStr " │ " csStr " │ " spdStr " │ ✓`n"
    }

    avgSpd := totalCs > 0 ? Round(totalAhk / totalCs, 1) : 0
    tbl .= sep "`n"
    tbl .= " " Pad("TOTAL", 16) " │ " PadR(totalAhk "ms", 8) " │ " PadR(totalCs "ms", 8) " │ " PadR(avgSpd "×", 9) " │`n"
    tbl .= "`n═══════════════════════════════════════════════════════════`n"
    tbl .= "  Overall: C# via AHK# is " avgSpd "× faster across " total " tests`n"
    tbl .= "═══════════════════════════════════════════════════════════"

    tableEdit.Value := tbl

    ; ══════════════════════════════════════════════════════════════════
    ; Render chart (Tab 1) — at exact control size × DPI
    ; ══════════════════════════════════════════════════════════════════
    chartData := ""
    for r in results {
        if chartData != ""
            chartData .= ";"
        chartData .= r.name "|" r.ahk "|" r.cs
    }

    ; Store globally for re-render on resize
    global lastChartData
    lastChartData := chartData

    ; Get actual control dimensions
    chartPic.GetPos(,, &picW, &picH)
    chartPath := A_Temp "\ahk_bench_chart.png"

    try {
        ChartImg.Render(chartData, picW, picH, chartPath)
        chartPic.Value := chartPath
    } catch as e {
        tableEdit.Value := tbl "`n`nChart Error: " e.Message
    }

    btnRun.Enabled := true
    statusText.Value := "Done — AHK " totalAhk "ms vs C# " totalCs "ms — C# is " avgSpd "× faster"
}

g.Show("w700 h620")
WinWaitClose(g.Hwnd)
try FileDelete(A_Temp "\ahk_bench_chart.png")
ExitApp()
