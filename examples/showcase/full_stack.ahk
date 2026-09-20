;; AHK# — Full Stack Demo
;; Combines multiple AHK# modules in a single script.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk
#Include ..\..\ext\ahk#.sqlite.ahk

; ══════════════════════════════════════════════════════════════════════════════
; 1. CSModule — Embedded C# with LINQ
; ══════════════════════════════════════════════════════════════════════════════

class DataProcessor extends _CSModule {
    static CSharp := "
    (
        using System.Linq;

        // AHK arrays arrive as object[]; convert to doubles for LINQ
        public static double StandardDeviation(object[] values) {
            double[] v = values.Select(x => Convert.ToDouble(x)).ToArray();
            double avg = v.Average();
            double sumOfSquares = v.Sum(d => (d - avg) * (d - avg));
            return Math.Sqrt(sumOfSquares / v.Length);
        }

        public static string[] SortWords(string text) {
            return text.Split(' ')
                .Where(w => w.Length > 0)
                .OrderBy(w => w)
                .ToArray();
        }
    )"
}

scores := [95.5, 87.3, 92.1, 78.4, 88.8]
stdDev := DataProcessor.StandardDeviation(scores)

sortedWords := ""
for word in DataProcessor.SortWords("the quick brown fox jumps over the lazy dog")
    sortedWords .= (A_Index > 1 ? ", " : "") word

; ══════════════════════════════════════════════════════════════════════════════
; 2. Direct .NET Access
; ══════════════════════════════════════════════════════════════════════════════

guid1 := CS.System.Guid.NewGuid()
guid2 := CS.System.Guid.NewGuid()

cores := CS.System.Environment.ProcessorCount
machine := CS.System.Environment.MachineName

; ══════════════════════════════════════════════════════════════════════════════
; 3. SQLite (in-memory)
; ══════════════════════════════════════════════════════════════════════════════

db := SQLite(":memory:")
db.Execute("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, score REAL)")
db.Execute("INSERT INTO users (name, score) VALUES (?, ?)", "Alice", 95.5)
db.Execute("INSERT INTO users (name, score) VALUES (?, ?)", "Bob", 87.3)
db.Execute("INSERT INTO users (name, score) VALUES (?, ?)", "Charlie", 92.1)

topScore := db.Scalar("SELECT name FROM users ORDER BY score DESC LIMIT 1")
userCount := db.Scalar("SELECT COUNT(*) FROM users")

; ══════════════════════════════════════════════════════════════════════════════
; 4. Display Results
; ══════════════════════════════════════════════════════════════════════════════

msg := "═══ AHK# Full Stack Demo ═══"
    . "`n"
    . "`n▸ CSModule (LINQ): std dev of 95.5, 87.3, 92.1, 78.4, 88.8 = " Format("{:.2f}", stdDev)
    . "`n        sorted words: " sortedWords
    . "`n"
    . "`n▸ GUIDs: " guid1
    . "`n        " guid2
    . "`n▸ Machine: " machine " (" cores " cores)"
    . "`n"
    . "`n▸ SQLite: " userCount " users, top scorer = " topScore

MsgBox(msg, "AHK# — Full Stack", 0x40)

db.Close()
ExitApp()
