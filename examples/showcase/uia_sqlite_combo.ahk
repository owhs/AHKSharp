;; AHK# — Power Combo: UIA + SQLite + CSModule
;; Crawl the UI tree of any window, store it in SQLite, and query it.
;; Demonstrates combining multiple AHK# extensions in a real workflow.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk
#Include ..\..\ext\ahk#.uia.ahk
#Include ..\..\ext\ahk#.sqlite.ahk

; ══════════════════════════════════════════════════════════════════════════════
; 1. Custom C# Module: Element Analyzer
; ══════════════════════════════════════════════════════════════════════════════

class ElementStats extends _CSModule {
    static CSharp := "
    (
        using System.Linq;

        // AHK arrays arrive as object[], so convert each element to an int here
        public static int MaxDepth(object[] depths) {
            if (depths == null || depths.Length == 0) return 0;
            return depths.Max(d => Convert.ToInt32(d));
        }

        public static double AvgDepth(object[] depths) {
            if (depths == null || depths.Length == 0) return 0;
            return depths.Average(d => Convert.ToInt32(d));
        }

        public static double TreeComplexity(int totalNodes, int maxDepth, int typeCount) {
            if (maxDepth == 0) return 0;
            return (double)totalNodes * typeCount / maxDepth;
        }
    )"
}

; ══════════════════════════════════════════════════════════════════════════════
; 2. SQLite: In-Memory Element Store
; ══════════════════════════════════════════════════════════════════════════════

; ":memory:" keeps the database in RAM for this run only; pass a file path
; (e.g. A_Temp "\ui_scan.db") instead if you want the scan to persist.
db := SQLite(":memory:")

db.Execute("CREATE TABLE ui_elements ("
    . "id INTEGER PRIMARY KEY AUTOINCREMENT,"
    . "name TEXT,"
    . "control_type TEXT,"
    . "automation_id TEXT,"
    . "class_name TEXT,"
    . "depth INTEGER,"
    . "x INTEGER, y INTEGER, w INTEGER, h INTEGER,"
    . "is_enabled INTEGER,"
    . "scan_time TEXT)")

db.Execute("CREATE TABLE scans ("
    . "id INTEGER PRIMARY KEY AUTOINCREMENT,"
    . "window_title TEXT,"
    . "hwnd INTEGER,"
    . "element_count INTEGER,"
    . "scan_time TEXT)")

; ══════════════════════════════════════════════════════════════════════════════
; 3. Crawl Active Window → Store in SQLite
; ══════════════════════════════════════════════════════════════════════════════

MsgBox("This demo will:`n"
    . "1. Crawl the UI tree of the NEXT active window`n"
    . "2. Store all elements in SQLite`n"
    . "3. Run analytics queries`n`n"
    . "After clicking OK, switch to any window within 3 seconds."
    , "AHK# — UIA + SQLite Combo", 0x40)

Sleep(3000)

try {
    hwnd := WinGetID("A")
    title := WinGetTitle("A")
} catch {
    MsgBox("No active window found. Using current script window.", "Info")
    hwnd := A_ScriptHwnd
    title := "AHK# Script"
}

scanTime := FormatTime(, "yyyy-MM-dd HH:mm:ss")

ToolTip("Crawling: " title "...")
try {
    elements := UIA2.CrawlTree(hwnd, 6)
} catch as e {
    ToolTip("")
    MsgBox("UIA Crawl failed: " e.Message "`n`nThis can happen if the window "
        . "doesn't support UI Automation. Try switching to a different window."
        , "AHK# — UIA Error", 0x10)
    db.Close()
    ExitApp()
}
ToolTip("")

; Insert scan record
db.Execute("INSERT INTO scans (window_title, hwnd, element_count, scan_time) VALUES (?, ?, ?, ?)"
    , title, hwnd, 0, scanTime)
scanId := db.LastId

; Insert all elements
count := 0
depths := []
for el in elements {   ; enumeration stops at the end of the array
    db.Execute("INSERT INTO ui_elements (name, control_type, automation_id, class_name, depth, x, y, w, h, is_enabled, scan_time) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        , el.Name, el.ControlType, el.AutomationId, el.ClassName
        , el.Depth, el.BoundingX, el.BoundingY, el.BoundingW, el.BoundingH
        , el.IsEnabled, scanTime)
    depths.Push(el.Depth)
    count++
}

; Update scan with real count
db.Execute("UPDATE scans SET element_count = ? WHERE id = ?", count, scanId)

if (count == 0) {
    MsgBox("No UI elements captured. The window may not support UIA crawling."
        , "AHK# — UIA + SQLite Combo", 0x30)
    db.Close()
    ExitApp()
}

; ══════════════════════════════════════════════════════════════════════════════
; 4. SQL Analytics on the Crawled UI
; ══════════════════════════════════════════════════════════════════════════════

msg := "═══ UIA + SQLite Analytics ═══"
    . "`nWindow: " title
    . "`nElements captured: " count
    . "`n"

; Type breakdown
typeRows := db.Query("SELECT control_type, COUNT(*) as cnt FROM ui_elements GROUP BY control_type ORDER BY cnt DESC LIMIT 10")
msg .= "`n─── Top Control Types ───"
for row in typeRows
    msg .= "`n  " row["control_type"] ": " row["cnt"]

; Depth stats (coerce to numbers — SQLite returns strings)
maxDepth := Integer(db.Scalar("SELECT MAX(depth) FROM ui_elements") || 0)
avgDepth := Float(db.Scalar("SELECT ROUND(AVG(depth), 1) FROM ui_elements") || 0)
msg .= "`n`n─── Depth Stats ───"
    . "`n  Max depth: " maxDepth
    . "`n  Avg depth: " avgDepth

; Largest elements by area
bigRows := db.Query("SELECT name, control_type, w * h as area, w, h FROM ui_elements WHERE w > 0 AND h > 0 ORDER BY area DESC LIMIT 5")
msg .= "`n`n─── Largest Elements (by area) ───"
for row in bigRows {
    name := row["name"] != "" ? row["name"] : "(unnamed)"
    msg .= "`n  " SubStr(name, 1, 25) " [" row["control_type"] "] " row["w"] "×" row["h"]
}

; Named elements
namedCount := Integer(db.Scalar("SELECT COUNT(*) FROM ui_elements WHERE name != ''") || 0)
msg .= "`n`n─── Named Elements ───"
    . "`n  " namedCount " of " count " elements have names (" Round(namedCount / Max(count, 1) * 100) "%)"

; C# depth analysis
if depths.Length > 0 {
    csMax := ElementStats.MaxDepth(depths)   ; AHK Array → object[] in C#
    csAvg := ElementStats.AvgDepth(depths)
    msg .= "`n`n─── C# Depth Analysis ───"
        . "`n  Max depth (C#): " csMax
        . "`n  Avg depth (C#): " Format("{:.1f}", csAvg)
}

; Complexity metric
typeCount := Integer(db.Scalar("SELECT COUNT(DISTINCT control_type) FROM ui_elements") || 0)
complexity := ElementStats.TreeComplexity(count, maxDepth, typeCount)
msg .= "`n`n─── Complexity Score ───"
    . "`n  " Format("{:.1f}", complexity) " (nodes × types / depth)"

MsgBox(msg, "AHK# — UIA Analytics", 0x40)

db.Close()
ExitApp()
