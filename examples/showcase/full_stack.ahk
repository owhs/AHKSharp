;; AHK# Example 05 — Full Stack Demo
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
        
        public static double StandardDeviation(double[] values) {
            double avg = values.Average();
            double sumOfSquares = values.Sum(v => (v - avg) * (v - avg));
            return Math.Sqrt(sumOfSquares / values.Length);
        }
        
        public static string[] SortWords(string text) {
            return text.Split(' ')
                .Where(w => w.Length > 0)
                .OrderBy(w => w)
                .ToArray();
        }
    )"
}

; ══════════════════════════════════════════════════════════════════════════════
; 2. Direct .NET Access
; ══════════════════════════════════════════════════════════════════════════════

guid1 := CS.System.Guid.NewGuid()
guid2 := CS.System.Guid.NewGuid()

cores := CS.System.Environment.ProcessorCount
machine := CS.System.Environment.MachineName

; ══════════════════════════════════════════════════════════════════════════════
; 4. SQLite (in-memory)
; ══════════════════════════════════════════════════════════════════════════════

db := SQLite(":memory:")
db.Execute("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, score REAL)")
db.Execute("INSERT INTO users (name, score) VALUES (?, ?)", "Alice", 95.5)
db.Execute("INSERT INTO users (name, score) VALUES (?, ?)", "Bob", 87.3)
db.Execute("INSERT INTO users (name, score) VALUES (?, ?)", "Charlie", 92.1)

topScore := db.Scalar("SELECT name FROM users ORDER BY score DESC LIMIT 1")
userCount := db.Scalar("SELECT COUNT(*) FROM users")

; ══════════════════════════════════════════════════════════════════════════════
; 5. Display Results
; ══════════════════════════════════════════════════════════════════════════════

msg := "═══ AHK# Full Stack Demo ═══"
    . "`n"
    . "`n▸ GUIDs: " guid1
    . "`n        " guid2
    . "`n▸ Machine: " machine " (" cores " cores)"
    . "`n"
    . "`n▸ SQLite: " userCount " users, top scorer = " topScore

MsgBox(msg, "AHK# — Full Stack", 0x40)

db.Close()
ExitApp()