;; AHK# Example 17 — MEGA Speed Benchmark: Native AHK vs AHK# (.NET)
;; Full graphical dashboard rendered pixel-perfect via System.Drawing.
;; 17 head-to-head benchmarks. DPI-aware. Zero stretching.
;;
;; Methodology
;;   - Timing uses QueryPerformanceCounter; each test is run 3 times and the MEDIAN is used.
;;   - The C# side is warmed up (JIT + bridge binding) once before it is timed.
;;   - Every test returns a result/checksum on both sides; the OK column reports whether the
;;     AHK and C# answers actually match (mismatched tests are excluded from the summary).
;;   - C# times are in-process compute measured around a single bridge call per run, except
;;     "Fib(70)x10K", which deliberately makes 10,000 bridge calls.
;;   - The headline number is the GEOMETRIC MEAN of the per-test speedups (AHK ms / C# ms),
;;     so a few huge ratios cannot dominate it.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

ListLines(0)   ; stop AHK from logging every executed line (it slows the native loops)

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
            byte[] d = Encoding.UTF8.GetBytes(input);
            using (var sha = SHA256.Create()) {
                for (int i = 0; i < iterations; i++) d = sha.ComputeHash(d);
            }
            return BitConverter.ToString(d).Replace("-", "").ToLower();
        }
        public static int RegexExtract(string text) {
            return Regex.Matches(text, @"\b[\w.]+@[\w]+\.[\w]+\b").Count;
        }
        public static int BuildCSV(int rows, int cols) {
            var sb = new StringBuilder();
            for (int r = 0; r < rows; r++) {
                for (int c = 0; c < cols; c++) { if (c > 0) sb.Append(','); sb.Append(r * cols + c); }
                sb.Append('\n');
            } return sb.Length;
        }
        // Same LCG as the AHK side so both sort identical data
        public static long SortArray(int count) {
            long seed = 42; long[] arr = new long[count];
            for (int i = 0; i < count; i++) { seed = (seed * 1103515245L + 12345L) % 2147483648L; arr[i] = seed; }
            Array.Sort(arr); return arr[0];
        }
        public static double ComputePi(int terms) {
            double pi = 0;
            for (int i = 0; i < terms; i++) pi += (i % 2 == 0 ? 1.0 : -1.0) / (2 * i + 1);
            return pi * 4;
        }
        // Ordinal (case-sensitive) replace - matches StrReplace(..., CaseSense=true)
        public static string StringReplace(string text, int iterations) {
            string result = text;
            for (int i = 0; i < iterations; i++) result = result.Replace("the", "THE").Replace("THE", "the");
            return result;
        }
        public static int CollatzMax(int limit) {
            int maxLen = 0;
            for (int n = 2; n < limit; n++) {
                long x = n; int len = 0;
                while (x != 1) { x = x % 2 == 0 ? x / 2 : 3 * x + 1; len++; }
                if (len > maxLen) maxLen = len;
            } return maxLen;
        }
        public static long WordFrequency(string text) {
            var words = text.Split(new[] { ' ', '\n', '\r', '\t' }, StringSplitOptions.RemoveEmptyEntries);
            var freq = new Dictionary<string, int>();
            foreach (var w in words) { string l = w.ToLower(); if (freq.ContainsKey(l)) freq[l]++; else freq[l] = 1; }
            return freq.Count * 100000L + (freq.ContainsKey("alpha") ? freq["alpha"] : 0);
        }
        // Same LCG as the AHK side; returns the sum of all result elements
        public static double MatrixMultiply(int size) {
            double[,] a = new double[size, size], b = new double[size, size];
            long seed = 42;
            for (int i = 0; i < size; i++) for (int j = 0; j < size; j++) {
                seed = (seed * 1103515245L + 12345L) % 2147483648L; a[i,j] = seed / 2147483648.0;
                seed = (seed * 1103515245L + 12345L) % 2147483648L; b[i,j] = seed / 2147483648.0;
            }
            double total = 0;
            for (int i = 0; i < size; i++) for (int j = 0; j < size; j++) {
                double s = 0; for (int k = 0; k < size; k++) s += a[i,k] * b[k,j]; total += s;
            }
            return total;
        }

        // ── Tests where AHK is competitive ──────────────────────────
        public static long MapInsertLookup(int count) {
            var dict = new Dictionary<string, int>();
            for (int i = 1; i <= count; i++) dict["key" + i] = i;
            long sum = 0;
            for (int i = 1; i <= count; i++) sum += dict["key" + i];
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
        public static long ArrayBuild(int count) {
            var list = new List<long>();
            for (int i = 1; i <= count; i++) list.Add(i * 3L + 7);
            long sum = 0;
            foreach (var v in list) sum += v;
            return sum;
        }
        public static long Conditionals(int iterations) {
            long sum = 0;
            for (int i = 1; i <= iterations; i++) {
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
        using System.Globalization;
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

        // Small helpers so every Brush/Pen is disposed right after use
        static void Txt(Graphics g, string s, Font f, Color c, float x, float y) {
            using (var br = new SolidBrush(c)) g.DrawString(s, f, br, x, y);
        }
        static void Fill(Graphics g, Color c, int x, int y, int w, int h) {
            using (var br = new SolidBrush(c)) g.FillRectangle(br, x, y, w, h);
        }
        static void Line(Graphics g, Color c, int x1, int y1, int x2, int y2) {
            using (var p = new Pen(c, 1)) g.DrawLine(p, x1, y1, x2, y2);
        }

        // dataStr: name|ahkMs|csMs|ok ; ...   (ahkMs = -1 -> not benchmarked, ok = 0 -> results mismatched)
        public static string Render(string dataStr, int w, int h, string path) {
            var inv = CultureInfo.InvariantCulture;
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

                Font fTitle = null, fSub = null, fLabel = null, fTime = null, fSpd = null, fLeg = null;
                try {
                    fTitle = new Font("Segoe UI", 14, FontStyle.Bold);
                    fSub = new Font("Segoe UI", 8.5f);
                    fLabel = new Font("Segoe UI", 10, FontStyle.Bold);
                    fTime = new Font("Cascadia Mono", 7.5f);
                    fSpd = new Font("Segoe UI", 11, FontStyle.Bold);
                    fLeg = new Font("Segoe UI", 7.5f);

                    int y = pad;
                    Txt(g, "⚡ SPEEDUP CHART", fTitle, Accent, pad, y);
                    y += 24;
                    Txt(g, "Log scale • Bar = C# speed advantage over native AHK • median of 3 runs", fSub, Dim, pad, y);
                    y += 18;

                    Line(g, Color.FromArgb(40, 40, 60), pad, y, pad + cw, y);
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
                        double a = double.Parse(it[1], inv), c = double.Parse(it[2], inv);
                        if (a >= 0 && it[3] == "1") { double r = Math.Max(a, 0.001) / Math.Max(c, 0.001); if (r > maxR) maxR = r; }
                    }
                    double logMax = Math.Log10(Math.Max(maxR, 10));

                    for (int i = 0; i < items.Count; i++) {
                        var it = items[i];
                        double ahk = double.Parse(it[1], inv), cs = double.Parse(it[2], inv);
                        bool ok = it[3] == "1";
                        double ratio = ahk < 0 ? -1 : Math.Max(ahk, 0.001) / Math.Max(cs, 0.001);

                        // Label
                        Txt(g, it[0], fLabel, White, pad, y + 2);

                        Fill(g, Color.FromArgb(22, 22, 42), barLeft, y, barArea, barH);

                        if (ratio < 0) {
                            using (var pb = new LinearGradientBrush(new Rectangle(barLeft, y, barArea, barH),
                                Color.FromArgb(130, 55, 190), Color.FromArgb(80, 30, 140), 0f))
                                g.FillRectangle(pb, barLeft, y, barArea, barH);
                            Txt(g, "NOT BENCHMARKED", fLabel, Color.FromArgb(210, 180, 250), barLeft + 6, y + 2);
                            Txt(g, "n/b", fSpd, Color.FromArgb(190, 150, 240), barLeft + barArea + 8, y + 1);
                        } else if (!ok) {
                            Fill(g, Color.FromArgb(90, 25, 25), barLeft, y, barArea, barH);
                            Txt(g, "RESULT MISMATCH - not compared", fLabel, Color.FromArgb(255, 150, 150), barLeft + 6, y + 2);
                            Txt(g, "!", fSpd, Color.FromArgb(255, 100, 100), barLeft + barArea + 8, y + 1);
                        } else {
                            double logR = Math.Log10(Math.Max(ratio, 1));
                            int bw = (int)Math.Max(logR / logMax * barArea, 3);
                            Color clr = BarColor(ratio);

                            if (bw > 2) {
                                Color clr2 = Color.FromArgb(clr.R*3/4, clr.G*3/4, clr.B*3/4);
                                using (var bb = new LinearGradientBrush(new Rectangle(barLeft, y, bw+1, barH), clr, clr2, 0f))
                                    g.FillRectangle(bb, barLeft, y, bw, barH);
                                Line(g, Color.FromArgb(100, clr), barLeft, y, barLeft + bw, y);
                            }
                            string tl = ahk.ToString("F1", inv) + " vs " + cs.ToString("F1", inv) + "ms";
                            Txt(g, tl, fTime, Color.FromArgb(140, 145, 165), barLeft + 4, y + barH - 12);
                            Txt(g, ratio.ToString("F1", inv) + "x", fSpd, clr, barLeft + barArea + 6, y + 1);
                        }
                        y += barH + gap;
                    }

                    // Legend
                    y = h - legendH - pad / 2;
                    Line(g, Color.FromArgb(40, 40, 60), pad, y, pad + cw, y);
                    y += 5;
                    int lsz = 10;
                    Action<int, Color, string> lg = (lx, cl, tx) => {
                        Fill(g, cl, lx, y + 2, lsz, lsz);
                        Txt(g, tx, fLeg, Dim, lx + lsz + 4, y + 1);
                    };
                    int stp = cw / 5;
                    lg(pad, Color.FromArgb(0,255,120), ">100x");
                    lg(pad+stp, Color.FromArgb(0,220,180), "20-100x");
                    lg(pad+stp*2, Color.FromArgb(80,180,255), "5-20x");
                    lg(pad+stp*3, Color.FromArgb(255,200,80), "1-5x");
                    lg(pad+stp*4, Color.FromArgb(130,55,190), "not benchmarked");

                    bmp.Save(path, System.Drawing.Imaging.ImageFormat.Png);
                    return "ok";
                } finally {
                    if (fTitle != null) fTitle.Dispose();
                    if (fSub != null) fSub.Dispose();
                    if (fLabel != null) fLabel.Dispose();
                    if (fTime != null) fTime.Dispose();
                    if (fSpd != null) fSpd.Dispose();
                    if (fLeg != null) fLeg.Dispose();
                }
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
FmtMs(ms) => ms >= 100 ? String(Round(ms)) : Format("{:.1f}", ms)

; ══════════════════════════════════════════════════════════════════════════════
; Timing / comparison helpers
; ══════════════════════════════════════════════════════════════════════════════

; High-resolution timestamp in milliseconds (QueryPerformanceCounter)
QPCms() {
    static freq := 0
    if !freq {
        DllCall("QueryPerformanceFrequency", "Int64*", &f := 0)
        freq := f
    }
    DllCall("QueryPerformanceCounter", "Int64*", &c := 0)
    return c * 1000.0 / freq
}

Median(arr) {
    sorted := []
    for v in arr {
        pos := sorted.Length + 1
        while pos > 1 && sorted[pos - 1] > v
            pos--
        sorted.InsertAt(pos, v)
    }
    n := sorted.Length
    return Mod(n, 2) ? sorted[(n + 1) // 2] : (sorted[n // 2] + sorted[n // 2 + 1]) / 2
}

; Integers must match exactly; floating point results within 1e-9 (relative); anything else as strings.
SameResult(a, b) {
    if Type(a) == "String" && Type(b) == "String"
        return a == b                  ; e.g. hex digests, replaced text (case-sensitive)
    if IsInteger(a) && IsInteger(b)
        return Integer(a) = Integer(b)
    if IsNumber(a) && IsNumber(b)
        return Abs(a - b) <= 1e-9 * Max(1, Abs(a), Abs(b))
    return String(a) == String(b)
}

; Run one test: C# warm-up, then median of 3 timed runs each for C# and AHK.
RunOne(tst) {
    r := {name: tst.name, ahk: -1, cs: 0, ok: 0, note: ""}
    ; Copy the callables into locals: obj.prop() would pass the object as an extra first argument
    csFn := tst.cs, ahkFn := tst.ahk

    csFn()                                     ; warm-up: JIT + bridge binding, not timed
    times := [], csVal := ""
    Loop 3 {
        t0 := QPCms()
        csVal := csFn()
        times.Push(QPCms() - t0)
    }
    r.cs := Median(times)

    try {
        times := [], ahkVal := ""
        Loop 3 {
            t0 := QPCms()
            ahkVal := ahkFn()
            times.Push(QPCms() - t0)
        }
        r.ahk := Median(times)
        r.ok := SameResult(ahkVal, csVal) ? 1 : 0
        if !r.ok
            r.note := "AHK=" ahkVal "  C#=" csVal
    } catch as e {
        r.ahk := -1
        r.note := "AHK side not run: " e.Message
    }
    return r
}

; ══════════════════════════════════════════════════════════════════════════════
; Shared test data (built once, outside the timed regions)
; ══════════════════════════════════════════════════════════════════════════════

gRegexText := ""
Loop 5000
    gRegexText .= "Line " A_Index " user" A_Index "@example.com`n"

gStrText := "the quick brown fox jumps over the lazy dog and the cat sat on the mat"

gWordText := ""
wds := ["alpha","bravo","charlie","delta","echo","foxtrot","golf","hotel"]
wSeed := 42
Loop 50000 {
    wSeed := Mod(wSeed * 1103515245 + 12345, 2147483648)
    gWordText .= wds[Mod(wSeed, wds.Length) + 1] " "
}

gParseText := ""
Loop 50000
    gParseText .= "Line " A_Index " data here`n"

; ══════════════════════════════════════════════════════════════════════════════
; AHK implementations — each returns a result that is compared against the C# one
; ══════════════════════════════════════════════════════════════════════════════

AhkSum() {
    sum := 0
    Loop 10000000
        sum += A_Index
    return sum
}

; Sieve of Eratosthenes - the same algorithm as CSBench.CountPrimes (byte array instead of trial division)
AhkPrimes() {
    limit := 500000
    sieve := Buffer(limit + 1, 0)
    c := 0
    Loop limit - 1 {
        i := A_Index + 1
        if !NumGet(sieve, i, "UChar") {
            c++
            j := i * i
            while j <= limit {
                NumPut("UChar", 1, sieve, j)
                j += i
            }
        }
    }
    return c
}

AhkFibRepeat() {
    total := 0
    Loop 10000 {
        fA := 0, fB := 1
        Loop 70 {
            tmp := fA + fB
            fA := fB
            fB := tmp
        }
        total += fA
    }
    return total
}
CsFibRepeat() {
    total := 0
    Loop 10000
        total += CSBench.Fibonacci(70)   ; 10,000 bridge calls on purpose
    return total
}

; SHA-256 chain through the native CNG API (BCryptHash, Windows 10+)
AhkSha256() {
    if DllCall("bcrypt\BCryptOpenAlgorithmProvider", "Ptr*", &hAlg := 0, "WStr", "SHA256", "Ptr", 0, "UInt", 0, "UInt") != 0
        throw Error("BCrypt SHA256 provider unavailable")
    try {
        input := "AHK# benchmark"
        len := StrPut(input, "UTF-8") - 1
        cur := Buffer(Max(len + 1, 32))
        StrPut(input, cur, "UTF-8")
        nxt := Buffer(32)
        Loop 10000 {
            if DllCall("bcrypt\BCryptHash", "Ptr", hAlg, "Ptr", 0, "UInt", 0, "Ptr", cur, "UInt", len, "Ptr", nxt, "UInt", 32, "UInt") != 0
                throw Error("BCryptHash failed (requires Windows 10 or later)")
            tmp := cur, cur := nxt, nxt := tmp
            len := 32
        }
        hex := ""
        Loop 32
            hex .= Format("{:02x}", NumGet(cur, A_Index - 1, "UChar"))
        return hex
    } finally {
        DllCall("bcrypt\BCryptCloseAlgorithmProvider", "Ptr", hAlg, "UInt", 0)
    }
}

AhkRegex() {
    count := 0, pos := 1
    while RegExMatch(gRegexText, "\b[\w.]+@[\w]+\.[\w]+\b", &m, pos)
        count++, pos := m.Pos + m.Len
    return count
}

AhkCsv() {
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
    return StrLen(csv)
}

; Same LCG data as CSBench.SortArray; AHK's idiomatic sort is Sort() on a delimited string
AhkSort() {
    seed := 42, s := ""
    Loop 100000 {
        seed := Mod(seed * 1103515245 + 12345, 2147483648)
        s .= (A_Index > 1 ? "`n" : "") seed
    }
    s := Sort(s, "N")
    return Integer(SubStr(s, 1, InStr(s, "`n") - 1))
}

AhkPi() {
    pi := 0.0
    Loop 10000000 {
        ii := A_Index - 1
        pi += (Mod(ii, 2) == 0 ? 1.0 : -1.0) / (2 * ii + 1)
    }
    return pi * 4
}

AhkStrReplace() {
    ss := gStrText
    Loop 1000
        ss := StrReplace(StrReplace(ss, "the", "THE", true), "THE", "the", true)   ; CaseSense=true == ordinal
    return ss
}

AhkCollatz() {
    maxChain := 0
    Loop 99998 {                       ; n = 2 .. 99999, same range as CSBench.CollatzMax(100000)
        nn := A_Index + 1, steps := 0, xx := nn
        while xx != 1 {
            xx := Mod(xx, 2) == 0 ? xx // 2 : 3 * xx + 1
            steps++
        }
        if steps > maxChain
            maxChain := steps
    }
    return maxChain
}

AhkWordFreq() {
    freq := Map()
    Loop Parse, gWordText, " " {
        if A_LoopField == ""
            continue
        ww := StrLower(A_LoopField)
        freq[ww] := freq.Has(ww) ? freq[ww] + 1 : 1
    }
    return freq.Count * 100000 + (freq.Has("alpha") ? freq["alpha"] : 0)
}

; Same LCG data as CSBench.MatrixMultiply; returns the sum of all elements of A*B
AhkMatrix() {
    size := 100
    seed := 42
    a := [], b := []
    Loop size {
        ra := [], rb := []
        Loop size {
            seed := Mod(seed * 1103515245 + 12345, 2147483648)
            ra.Push(seed / 2147483648)
            seed := Mod(seed * 1103515245 + 12345, 2147483648)
            rb.Push(seed / 2147483648)
        }
        a.Push(ra), b.Push(rb)
    }
    total := 0.0
    Loop size {
        ai := a[A_Index]
        Loop size {
            j := A_Index
            s := 0.0
            Loop size
                s += ai[A_Index] * b[A_Index][j]
            total += s
        }
    }
    return total
}

AhkMap() {
    myMap := Map()
    Loop 100000
        myMap["key" A_Index] := A_Index
    mapSum := 0
    Loop 100000
        mapSum += myMap["key" A_Index]
    return mapSum
}

AhkParse() {
    lineCount := 0
    Loop Parse, gParseText, "`n" {
        if A_LoopField != ""
            lineCount++
    }
    return lineCount
}

AhkSmallRegex() {
    rxText := "abc 123 def 456 ghi 789 jkl 012"
    rxTotal := 0
    Loop 10000 {
        rxPos := 1
        while RegExMatch(rxText, "\d+", &rxM, rxPos) {
            rxTotal++
            rxPos := rxM.Pos + rxM.Len
        }
    }
    return rxTotal
}

AhkArray() {
    arr := []
    Loop 100000
        arr.Push(A_Index * 3 + 7)
    arrSum := 0
    for val in arr
        arrSum += val
    return arrSum
}

AhkConditionals() {
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
    return cndSum
}

BuildTests() {
    return [
        {name: "Sum 1..10M",     ahk: AhkSum,          cs: () => CSBench.SumTo(10000000)},
        {name: "Primes ≤500K",   ahk: AhkPrimes,       cs: () => CSBench.CountPrimes(500000)},
        {name: "Fib(70)×10K",    ahk: AhkFibRepeat,    cs: CsFibRepeat},
        {name: "SHA256 ×10K",    ahk: AhkSha256,       cs: () => CSBench.HashRepeat("AHK# benchmark", 10000)},
        {name: "Regex 5K",       ahk: AhkRegex,        cs: () => CSBench.RegexExtract(gRegexText)},
        {name: "CSV 5K×20",      ahk: AhkCsv,          cs: () => CSBench.BuildCSV(5000, 20)},
        {name: "Sort 100K",      ahk: AhkSort,         cs: () => CSBench.SortArray(100000)},
        {name: "Pi 10M",         ahk: AhkPi,           cs: () => CSBench.ComputePi(10000000)},
        {name: "StrReplace ×1K", ahk: AhkStrReplace,   cs: () => CSBench.StringReplace(gStrText, 1000)},
        {name: "Collatz <100K",  ahk: AhkCollatz,      cs: () => CSBench.CollatzMax(100000)},
        {name: "WordFreq 50K",   ahk: AhkWordFreq,     cs: () => CSBench.WordFrequency(gWordText)},
        {name: "Matrix 100²",    ahk: AhkMatrix,       cs: () => CSBench.MatrixMultiply(100)},
        {name: "Map 100K",      ahk: AhkMap,          cs: () => CSBench.MapInsertLookup(100000)},
        {name: "Parse 50K ln",   ahk: AhkParse,        cs: () => CSBench.ParseLines(gParseText)},
        {name: "SmallRx ×10K",   ahk: AhkSmallRegex,   cs: () => CSBench.SmallRegex("abc 123 def 456 ghi 789 jkl 012", 10000)},
        {name: "Array 100K",     ahk: AhkArray,        cs: () => CSBench.ArrayBuild(100000)},
        {name: "Cond 10M",       ahk: AhkConditionals, cs: () => CSBench.Conditionals(10000000)}
    ]
}

; ══════════════════════════════════════════════════════════════════════════════
; BENCHMARK RUNNER
; ══════════════════════════════════════════════════════════════════════════════

SetStatus(msg) {
    statusText.Value := msg
    Sleep(1)
}

RunAll() {
    global lastChartData
    tests := BuildTests()
    total := tests.Length
    results := []
    btnRun.Enabled := false

    try {
        for idx, tst in tests {
            SetStatus("[" idx "/" total "] " tst.name " (warm-up + 3 runs)")
            results.Push(RunOne(tst))
        }
    } catch as e {
        btnRun.Enabled := true
        SetStatus("Benchmark failed: " e.Message)
        MsgBox("Benchmark aborted:`n`n" e.Message, "AHK# Speed Benchmark", "Icon!")
        return
    }

    ; ══════════════════════════════════════════════════════════════════
    ; Build table text (Tab 2)
    ; ══════════════════════════════════════════════════════════════════
    SetStatus("Rendering...")

    hdr := " " Pad("BENCHMARK", 16) " │ " PadR("AHK", 8) " │ " PadR("C#", 8) " │ " PadR("SPEEDUP", 9) " │ OK"
    sep := " " Pad("────────────────", 16) " ┼ " PadR("────────", 8) " ┼ " PadR("────────", 8) " ┼ " PadR("─────────", 9) " ┼ ──"
    tbl := "═══════════════════════════════════════════════════════════`n"
    tbl .= "  ⚡ AHK# MEGA SPEED BENCHMARK — " total " Tests`n"
    tbl .= "═══════════════════════════════════════════════════════════`n`n"
    tbl .= hdr "`n" sep "`n"

    logSum := 0.0, compared := 0, mismatched := 0, notBenchmarked := 0
    totalAhk := 0.0, totalCs := 0.0
    notes := ""
    for r in results {
        csStr := PadR(FmtMs(r.cs) "ms", 8)
        if (r.ahk < 0) {
            notBenchmarked++
            tbl .= " " Pad(r.name, 16) " │ " PadR("n/b", 8) " │ " csStr " │ " PadR("not bench.", 9) " │ -`n"
        } else if (!r.ok) {
            mismatched++
            tbl .= " " Pad(r.name, 16) " │ " PadR(FmtMs(r.ahk) "ms", 8) " │ " csStr " │ " PadR("—", 9) " │ ✗`n"
        } else {
            ratio := Max(r.ahk, 0.001) / Max(r.cs, 0.001)
            logSum += Ln(ratio)
            compared++
            totalAhk += r.ahk, totalCs += r.cs
            tbl .= " " Pad(r.name, 16) " │ " PadR(FmtMs(r.ahk) "ms", 8) " │ " csStr " │ " PadR(Round(ratio, 1) "×", 9) " │ ✓`n"
        }
        if (r.note != "")
            notes .= "  * " r.name ": " r.note "`n"
    }

    geoMean := compared > 0 ? Round(Exp(logSum / compared), 1) : 0
    tbl .= sep "`n"
    tbl .= " " Pad("TOTAL (checked)", 16) " │ " PadR(FmtMs(totalAhk) "ms", 8) " │ " PadR(FmtMs(totalCs) "ms", 8) " │ " PadR(geoMean "×", 9) " │`n"
    tbl .= "`n═══════════════════════════════════════════════════════════`n"
    tbl .= "  Geometric-mean speedup: C# via AHK# is " geoMean "× vs AHK`n"
    tbl .= "  over " compared " tests with matching results"
    if (mismatched)
        tbl .= " (" mismatched " mismatched, excluded)"
    if (notBenchmarked)
        tbl .= " (" notBenchmarked " not benchmarked)"
    tbl .= "`n  Timing: QueryPerformanceCounter, median of 3 runs, C# warmed up first.`n"
    tbl .= "  C# times are in-process compute (one bridge call per run; Fib(70)×10K = 10K calls).`n"
    if (notes != "")
        tbl .= "`n  Notes:`n" notes
    tbl .= "═══════════════════════════════════════════════════════════"

    tableEdit.Value := tbl

    ; ══════════════════════════════════════════════════════════════════
    ; Render chart (Tab 1) — at exact control size × DPI
    ; ══════════════════════════════════════════════════════════════════
    chartData := ""
    for r in results {
        if chartData != ""
            chartData .= ";"
        ahkTxt := r.ahk < 0 ? "-1" : String(Round(r.ahk, 3))
        csTxt := String(Round(r.cs, 3))
        chartData .= r.name "|" ahkTxt "|" csTxt "|" r.ok
    }

    ; Store globally for re-render on resize
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
    SetStatus("Done — geometric-mean speedup " geoMean "× over " compared " matching tests"
        . (mismatched ? " (" mismatched " mismatched)" : ""))
}

g.Show("w700 h620")
WinWaitClose(g.Hwnd)
try FileDelete(A_Temp "\ahk_bench_chart.png")
ExitApp()
