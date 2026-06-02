;; AHK# Example 13 — Interactive Regex Workbench
;; Full .NET Regex engine in a live GUI — type a pattern, see matches instantly.
;; Pure AHK RegExMatch can't do named groups, lookaheads, or multiline well.
;; AHK# gives you the full System.Text.RegularExpressions engine.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

class RegexEngine extends _CSModule {
    static CSharp := "
    (
        using System.Text.RegularExpressions;
        using System.Linq;

        public static string TestRegex(string pattern, string input, string options) {
            try {
                RegexOptions opts = RegexOptions.None;
                if (options.Contains("i")) opts |= RegexOptions.IgnoreCase;
                if (options.Contains("m")) opts |= RegexOptions.Multiline;
                if (options.Contains("s")) opts |= RegexOptions.Singleline;

                var matches = Regex.Matches(input, pattern, opts);
                if (matches.Count == 0) return "NO_MATCH";

                var lines = matches.Cast<Match>().Select((m, idx) => {
                    var groups = m.Groups.Cast<Group>()
                        .Skip(1)
                        .Where(g => g.Success)
                        .Select(g => g.Name + "=" + g.Value);
                    string gs = groups.Any() ? " [" + string.Join(", ", groups) + "]" : "";
                    return idx + "|" + m.Index + "|" + m.Length + "|" + m.Value + gs;
                });
                return string.Join("\n", lines);
            }
            catch (System.Exception ex) {
                return "ERROR|" + ex.Message;
            }
        }

        public static string ReplaceRegex(string pattern, string input, string replacement, string options) {
            try {
                RegexOptions opts = RegexOptions.None;
                if (options.Contains("i")) opts |= RegexOptions.IgnoreCase;
                if (options.Contains("m")) opts |= RegexOptions.Multiline;
                return Regex.Replace(input, pattern, replacement, opts);
            }
            catch (System.Exception ex) {
                return "ERROR: " + ex.Message;
            }
        }
    )"
}

; ── GUI ───────────────────────────────────────────────────────────────────────

g := Gui("+Resize", "AHK# — Regex Workbench")
g.SetFont("s10", "Segoe UI")
g.BackColor := "0x1e1e2e"
g.SetFont("cCDD6F4")

g.Add("Text", "x10 y10 w80", "Pattern:")
patternEdit := g.Add("Edit", "x90 y8 w400 h24 Background0x313244 cCDD6F4", "\b(\w+)@(\w+)\.(\w+)\b")

g.Add("Text", "x10 y40 w80", "Options:")
optEdit := g.Add("Edit", "x90 y38 w60 h24 Background0x313244 cCDD6F4", "im")

g.Add("Text", "x160 y40 w80", "Replace:")
replEdit := g.Add("Edit", "x240 y38 w250 h24 Background0x313244 cCDD6F4", "[$1 AT $2]")

g.Add("Text", "x10 y72 w80", "Input:")
g.SetFont("s9", "Cascadia Mono")
inputEdit := g.Add("Edit", "x10 y92 w480 h120 Multi Background0x313244 cCDD6F4"
    , "Contact us at support@example.com or sales@company.org`n"
    . "Invalid: not-an-email`n"
    . "Also try: dev@github.io and hello@world.net")

btnMatch := g.Add("Button", "x10 y220 w120 h30", "▶ Find Matches")
btnReplace := g.Add("Button", "x140 y220 w120 h30", "⟳ Replace All")

g.Add("Text", "x10 y260 w80", "Results:")
resultEdit := g.Add("Edit", "x10 y280 w480 h200 Multi ReadOnly Background0x181825 cA6E3A1")

; ── Event Handlers ────────────────────────────────────────────────────────────

btnMatch.OnEvent("Click", (*) => DoMatch())
btnReplace.OnEvent("Click", (*) => DoReplace())

DoMatch() {
    pattern := patternEdit.Value
    input := inputEdit.Value
    opts := optEdit.Value
    if (pattern == "") {
        resultEdit.Value := "Enter a regex pattern"
        return
    }
    raw := RegexEngine.TestRegex(pattern, input, opts)
    if (raw == "NO_MATCH") {
        resultEdit.Value := "No matches found."
        return
    }
    if (SubStr(raw, 1, 5) == "ERROR") {
        resultEdit.Value := "Regex Error: " SubStr(raw, 7)
        return
    }
    out := "Found matches:`n"
    Loop Parse, raw, "`n" {
        parts := StrSplit(A_LoopField, "|",, 4)
        if parts.Length >= 4
            out .= Format("  #{} pos:{} len:{} → `"{}`"`n"
                , Integer(parts[1]) + 1, parts[2], parts[3], parts[4])
    }
    resultEdit.Value := out
}

DoReplace() {
    pattern := patternEdit.Value
    input := inputEdit.Value
    opts := optEdit.Value
    repl := replEdit.Value
    result := RegexEngine.ReplaceRegex(pattern, input, repl, opts)
    resultEdit.Value := "Replaced:`n" result
}

; Trigger initial match
DoMatch()

g.Show("w500 h490")
WinWaitClose(g.Hwnd)
ExitApp()
