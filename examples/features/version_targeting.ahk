;; AHK# Example 34 — C# Version Targeting
;; Use the CSVersion property to compile with newer C# syntax.
;; On first use, Roslyn compiler is auto-downloaded from NuGet (~10MB, one-time).
;;
;; NOTE: This example requires internet access on first run to download Roslyn.
;; Subsequent runs use the cached compiler.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

; ── Default: C# 4.0 (built-in csc.exe, always available) ─────────────────────

class BasicModule extends _CSModule {
    ; No CSVersion = uses built-in csc.exe (C# 4.0)
    static CSharp := '
    (
        public static string GetInfo() {
            return "C# 4.0 - Default compiler (built-in csc.exe)";
        }
    )'
}

MsgBox(BasicModule.GetInfo(), "AHK# — Default C# Version")

; ── C# 7.3: Tuple deconstruction, pattern matching, out variables ─────────────

class ModernModule extends _CSModule {
    static CSVersion := "7.3"
    static CSharp := '
    (
        using System;

        public static string TupleDemo() {
            // C# 7.0+ tuple syntax
            var point = (X: 10, Y: 20);
            return $"Point: ({point.X}, {point.Y}) - Sum: {point.X + point.Y}";
        }

        public static string PatternDemo(object value) {
            // C# 7.0+ pattern matching
            switch (value) {
                case int i when i > 0:
                    return $"Positive integer: {i}";
                case string s:
                    return $"String of length {s.Length}: {s}";
                default:
                    return $"Unknown type: {value}";
            }
        }

        public static string OutVarDemo() {
            // C# 7.0+ inline out variables
            if (int.TryParse("42", out var result)) {
                return $"Parsed: {result} (type: {result.GetType().Name})";
            }
            return "Failed to parse";
        }

        public static string LocalFunctionDemo() {
            // C# 7.0+ local functions
            int Factorial(int n) => n <= 1 ? 1 : n * Factorial(n - 1);
            return $"10! = {Factorial(10)}";
        }
    )'
}

msg := "── C# 7.3 Features ──"
    . "`n" ModernModule.TupleDemo()
    . "`n" ModernModule.PatternDemo(42)
    . "`n" ModernModule.PatternDemo("Hello")
    . "`n" ModernModule.OutVarDemo()
    . "`n" ModernModule.LocalFunctionDemo()
MsgBox(msg, "AHK# — C# 7.3 via Roslyn")

MsgBox("C# version targeting demo complete!`n`n"
    . "Available versions: 4.0 (default), 5.0, 6.0, 7.0, 7.1, 7.2, 7.3`n"
    . "C# 8.0 partially supported (some runtime features unavailable on .NET Framework)"
    , "AHK# — Done", 0x40)

ExitApp()
