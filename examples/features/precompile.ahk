;; AHK# Example 33 — Precompile & Distribute
;; Export compiled CSModule DLLs for distribution.
;; End users load precompiled DLLs — no csc.exe needed!

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

; ── Step 1: Define and compile a module normally ──────────────────────────────

class TextProcessor extends _CSModule {
    static CSharp := '
    (
        using System.Text;
        using System.Text.RegularExpressions;

        public static string Slugify(string text) {
            text = text.ToLowerInvariant();
            text = Regex.Replace(text, @"[^a-z0-9\s-]", "");
            text = Regex.Replace(text, @"\s+", "-");
            text = Regex.Replace(text, @"-+", "-");
            return text.Trim((char)45);
        }

        public static string WordCount(string text) {
            var words = text.Split(new string[] {" ", "\t", "\n", "\r"},
                System.StringSplitOptions.RemoveEmptyEntries);
            return words.Length.ToString();
        }

        public static string Capitalize(string text) {
            if (string.IsNullOrEmpty(text)) return text;
            var sb = new StringBuilder();
            bool capitalizeNext = true;
            foreach (char c in text) {
                if (char.IsWhiteSpace(c)) {
                    capitalizeNext = true;
                    sb.Append(c);
                } else {
                    sb.Append(capitalizeNext ? char.ToUpper(c) : c);
                    capitalizeNext = false;
                }
            }
            return sb.ToString();
        }
    )'
}

; ── Step 2: Test it works ─────────────────────────────────────────────────────

slug := TextProcessor.Slugify("Hello World! This is AHK# v2.0")
words := TextProcessor.WordCount("The quick brown fox jumps over the lazy dog")
caps := TextProcessor.Capitalize("hello world from ahk sharp")

MsgBox("Slug: " slug "`nWord count: " words "`nCapitalized: " caps
    , "AHK# — TextProcessor (compiled from source)")

; ── Step 3: Precompile for distribution ───────────────────────────────────────

outputPath := A_ScriptDir "\lib\TextProcessor.dll"
TextProcessor.Precompile(outputPath)
MsgBox("Exported to: " outputPath "`n`nThis DLL can be distributed to users who don't have csc.exe!"
    , "AHK# — Precompiled")

; ── Step 4: Load from precompiled DLL (simulating distribution) ───────────────
; In a real distribution, the user would ONLY have this class — no CSharp source.

class TextProcessorDistributed extends _CSModule {
    static PrecompiledDLL := A_ScriptDir "\lib\TextProcessor.dll"
}

; Test the precompiled version
slug2 := TextProcessorDistributed.Slugify("Precompiled Module Loading Works!")
MsgBox("From precompiled DLL: " slug2, "AHK# — Precompiled Load")

MsgBox("Dev → Distribute workflow complete!`n`n"
    . "1. Write CSModule with CSharp source`n"
    . "2. Call Module.Precompile('output.dll')`n"
    . "3. Ship the DLL + AHK script (no source needed)`n"
    . "4. Users load via PrecompiledDLL property"
    , "AHK# — Done", 0x40)

ExitApp()
