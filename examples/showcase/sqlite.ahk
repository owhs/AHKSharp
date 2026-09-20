;; AHK# — SQLite Database Manager
;; Demonstrates the full SQLite extension: tables, CRUD, transactions, queries.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk
#Include ..\..\ext\ahk#.sqlite.ahk

; ══════════════════════════════════════════════════════════════════════════════
; 1. Create In-Memory Database with Schema
; ══════════════════════════════════════════════════════════════════════════════

db := SQLite(":memory:")

; Multi-table schema — single-line SQL avoids AHK2 continuation section issues
db.Execute("CREATE TABLE projects (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, language TEXT, stars INTEGER DEFAULT 0, created_at TEXT)")

db.Execute("CREATE TABLE contributors (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, project_id INTEGER, commits INTEGER DEFAULT 0)")

; ══════════════════════════════════════════════════════════════════════════════
; 2. Insert Data with Parameterized Queries
; ══════════════════════════════════════════════════════════════════════════════
; NOTE: all rows below are sample data — the star counts are illustrative, not live figures.

db.Execute("INSERT INTO projects (name, language, stars, created_at) VALUES (?, ?, ?, ?)"
    , "AHK#", "AHK2/C#", 1500, "2024-01-15")
ahkId := db.LastId

db.Execute("INSERT INTO projects (name, language, stars, created_at) VALUES (?, ?, ?, ?)"
    , "AutoHotkey", "C++", 8900, "2003-11-10")
ahkClassicId := db.LastId

db.Execute("INSERT INTO projects (name, language, stars, created_at) VALUES (?, ?, ?, ?)"
    , "VSCode", "TypeScript", 165000, "2015-04-29")

db.Execute("INSERT INTO projects (name, language, stars, created_at) VALUES (?, ?, ?, ?)"
    , "Neovim", "Lua/C", 82000, "2014-11-01")

; Contributors
db.Execute("INSERT INTO contributors (name, project_id, commits) VALUES (?, ?, ?)", "Alice", ahkId, 342)
db.Execute("INSERT INTO contributors (name, project_id, commits) VALUES (?, ?, ?)", "Bob", ahkId, 189)
db.Execute("INSERT INTO contributors (name, project_id, commits) VALUES (?, ?, ?)", "Charlie", ahkClassicId, 1205)

; ══════════════════════════════════════════════════════════════════════════════
; 3. Scalar Queries
; ══════════════════════════════════════════════════════════════════════════════

totalProjects := db.Scalar("SELECT COUNT(*) FROM projects")
totalStars := db.Scalar("SELECT SUM(stars) FROM projects")
topProject := db.Scalar("SELECT name FROM projects ORDER BY stars DESC LIMIT 1")
avgStars := db.Scalar("SELECT ROUND(AVG(stars), 0) FROM projects")

msg1 := "═══ SQLite Summary (sample data) ═══"
    . "`n▸ Projects:     " totalProjects
    . "`n▸ Total Stars:  " totalStars
    . "`n▸ Top Project:  " topProject
    . "`n▸ Avg Stars:    " avgStars

; ══════════════════════════════════════════════════════════════════════════════
; 4. Row Queries (JOIN)
; ══════════════════════════════════════════════════════════════════════════════

joinSql := "SELECT p.name, p.language, p.stars, COUNT(c.id) as contributors "
    . "FROM projects p LEFT JOIN contributors c ON c.project_id = p.id "
    . "GROUP BY p.id ORDER BY p.stars DESC"
rows := db.Query(joinSql)

msg2 := "`n`n═══ Project Table (sample stars) ═══"
for row in rows {
    msg2 .= "`n  " row["name"]
        . " (" row["language"] ")"
        . " — ★" row["stars"]
        . " — " row["contributors"] " contributors"
}

; ══════════════════════════════════════════════════════════════════════════════
; 5. Transactions (atomic batch insert)
; ══════════════════════════════════════════════════════════════════════════════

beforeCount := db.Scalar("SELECT COUNT(*) FROM projects")

txFn() {
    db.Execute("INSERT INTO projects (name, language, stars) VALUES (?, ?, ?)", "Rust", "Rust", 96000)
    db.Execute("INSERT INTO projects (name, language, stars) VALUES (?, ?, ?)", "Go", "Go", 123000)
    db.Execute("INSERT INTO projects (name, language, stars) VALUES (?, ?, ?)", "Zig", "Zig", 34000)
}
db.Transaction(txFn)

afterCount := db.Scalar("SELECT COUNT(*) FROM projects")

msg3 := "`n`n═══ Transaction ═══"
    . "`n  Before: " beforeCount " projects"
    . "`n  After:  " afterCount " projects (added 3 atomically)"

; ══════════════════════════════════════════════════════════════════════════════
; 6. Display All Results
; ══════════════════════════════════════════════════════════════════════════════

MsgBox(msg1 . msg2 . msg3, "AHK# — SQLite Database Demo", 0x40)

db.Close()
ExitApp()
