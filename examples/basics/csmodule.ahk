;; AHK# Example 02 — CSModule Paradigm
;; Embed C# code directly in AHK classes. Methods compile once and cache.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

; ── Embedded C# Math Helper ──────────────────────────────────────────────────

class MathHelper extends _CSModule {
    static CSharp := "
    (
        public static double Hypotenuse(double a, double b) {
            return Math.Sqrt(a * a + b * b);
        }

        public static double CircleArea(double radius) {
            return Math.PI * radius * radius;
        }

        public static long Fibonacci(int n) {
            if (n <= 1) return n;
            long a = 0, b = 1;
            for (int i = 2; i <= n; i++) {
                long temp = a + b;
                a = b;
                b = temp;
            }
            return b;
        }

        public static bool IsPrime(int n) {
            if (n < 2) return false;
            if (n < 4) return true;
            if (n % 2 == 0 || n % 3 == 0) return false;
            for (int i = 5; i * i <= n; i += 6)
                if (n % i == 0 || n % (i + 2) == 0) return false;
            return true;
        }
    )"
}

; ── String Processing Module ─────────────────────────────────────────────────

class StringTools extends _CSModule {
    static CSharp := "
    (
        using System.Text;

        public static string Reverse(string s) {
            char[] arr = s.ToCharArray();
            Array.Reverse(arr);
            return new string(arr);
        }

        public static string Caesar(string text, int shift) {
            var sb = new StringBuilder();
            foreach (char c in text) {
                if (char.IsLetter(c)) {
                    char d = char.IsUpper(c) ? 'A' : 'a';
                    sb.Append((char)((c - d + shift) % 26 + d));
                } else {
                    sb.Append(c);
                }
            }
            return sb.ToString();
        }

        public static int LevenshteinDistance(string a, string b) {
            int[,] d = new int[a.Length + 1, b.Length + 1];
            for (int i = 0; i <= a.Length; i++) d[i, 0] = i;
            for (int j = 0; j <= b.Length; j++) d[0, j] = j;
            for (int i = 1; i <= a.Length; i++)
                for (int j = 1; j <= b.Length; j++)
                    d[i, j] = Math.Min(Math.Min(
                        d[i - 1, j] + 1,
                        d[i, j - 1] + 1),
                        d[i - 1, j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1));
            return d[a.Length, b.Length];
        }
    )"
}

; ── Test Calls ───────────────────────────────────────────────────────────────

hyp := MathHelper.Hypotenuse(3, 4)
area := MathHelper.CircleArea(10)
fib := MathHelper.Fibonacci(50)
prime := MathHelper.IsPrime(997)

msg := "Hypotenuse(3, 4) = " hyp
    . "`nCircle Area(r=10) = " Format("{:.2f}", area)
    . "`nFibonacci(50) = " fib
    . "`nIsPrime(997) = " prime
MsgBox(msg, "AHK# — CSModule: MathHelper")

rev := StringTools.Reverse("AHK Sharp")
caesar := StringTools.Caesar("Hello World", 13)
dist := StringTools.LevenshteinDistance("kitten", "sitting")

msg2 := 'Reverse("AHK Sharp") = ' rev
    . '`nCaesar("Hello World", 13) = ' caesar
    . '`nLevenshtein("kitten", "sitting") = ' dist
MsgBox(msg2, "AHK# — CSModule: StringTools")

ExitApp()
