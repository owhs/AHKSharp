# Extensions

AHK# ships with extensions in `ext\`. Include the library first, then the extension (adjust the relative paths for your script's folder; examples use `..\..\lib\` and `..\..\ext\`).

```autohotkey
#Include lib\ahk#.ahk
#Include ext\ahk#.sqlite.ahk
```

## SQLite (ext\ahk#.sqlite.ahk)

Zero-dependency SQLite via Windows' built-in `winsqlite3.dll`.

```autohotkey
db := SQLite(":memory:")                       ; or a file path
db.Execute("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)")
db.Execute("INSERT INTO users (name) VALUES (?)", "Alice")   ; ? parameters
rows := db.Query("SELECT * FROM users")        ; Array of Maps (column name → value)
MsgBox(rows[1]["name"])
n := db.Scalar("SELECT COUNT(*) FROM users")
id := db.LastId                                ; last inserted rowid
db.Transaction(() => db.Execute("UPDATE users SET name = ? WHERE id = ?", "Bob", 1))
db.Close()
```

`Execute` returns the number of rows affected. `Query` returns an Array of Maps (column name → value), the whole result set fetched through **one** bulk COM call. Query values and `Scalar` results are strings; SQL `NULL` comes back as `""`, and floats are formatted with the invariant culture (a `.` decimal separator whatever the locale). `Transaction(fn)` commits when `fn` returns and rolls back and rethrows if it throws.

Text is **UTF-8 in and out**: non-ASCII values and column names (`"héllo wörld 日本語 ✓"`, `"naïve"`) round-trip. Bound `?` parameters are copied by SQLite (`SQLITE_TRANSIENT`), so a value stays valid until the statement runs.

## HTTP/JSON (ext\ahk#.http.ahk)

```autohotkey
#Include ext\ahk#.http.ahk
response := Http.Get("https://api.github.com/users/octocat")
name := Json.Query(response, "login")
```

Full reference: [HTTP/JSON](08_http_json.md).

## IPC (ext\ahk#.ipc.ahk)

Memory-mapped file IPC between processes: a named channel with an 8-byte length header followed by data, guarded by a named mutex. A second process that creates a `SharedMemory` with the same name opens the same memory. There is no authentication ([Security](19_security.md)).

```autohotkey
#Include ext\ahk#.ipc.ahk
sm := SharedMemory("MyChannel", 4096)          ; name, capacity in bytes (default 1 MiB)
sm.Write("Hello from process A")               ; UTF-8 text
MsgBox(sm.Read())                              ; → "Hello from process A"
MsgBox(sm.Length " of " sm.Capacity " bytes")

; Raw bytes
buf := Buffer(4)
NumPut("UInt", 0xCAFEBABE, buf)
sm.WriteBytes(buf)                             ; an AHK Buffer (a byte[] proxy or a raw byte SafeArray also work)
data := sm.ReadBytes()                         ; → an AHK Buffer (not a byte[])
MsgBox(Format("{:X}", NumGet(data, 0, "UInt")))

; Offsets (scatter/gather): byte offsets into the data area, UTF-8 text
sm.WriteAt(0, "COMPUTE")
sm.WriteAt(20, "iterations=5000")
cmd := sm.ReadAt(0, 7)                         ; offset, length in bytes → "COMPUTE"

sm.OnChanged((text) => ToolTip("changed: " text), 50)   ; poll every 50 ms
sm.Clear()
sm.Close()
```

| Member | Description |
|--------|-------------|
| `SharedMemory(name, sizeBytes := 1048576)` | Create or open a named channel |
| `Write(text)` / `Read()` | Whole-channel UTF-8 text; `Read()` returns `""` when empty |
| `WriteBytes(data)` / `ReadBytes()` | Whole-channel bytes. `WriteBytes` accepts an AHK `Buffer`, a .NET `byte[]` proxy or a raw byte SafeArray; `ReadBytes()` returns an AHK `Buffer` |
| `WriteAt(offset, text)` / `ReadAt(offset, length)` | Text at a byte offset in the data area. `WriteAt` does not change the channel length that `Read()` uses |
| `Length` / `Capacity` | Current data length / capacity in bytes |
| `Clear()` | Sets the data length to 0 |
| `OnChanged(callback, intervalMs := 50)` | Polls with `SetTimer` and calls `callback(text)` when `Read()` changes |
| `Close()` | Releases the mapping |

`Write`, `WriteBytes`, `Clear`, `WriteAt` and `OnChanged` return the object, so calls chain.

## Native UI (ext\ahk#.ui.ahk)

Embed .NET WinForms controls in an AHK Gui (dark-styled). The controls live on the AHK thread.

```autohotkey
#Include ext\ahk#.ui.ahk
g := Gui("+Resize", "Grid demo")
g.Show("w600 h500")

grid := NativeUI.DataGridView(g, 10, 10, 560, 240)     ; gui (or hwnd), x, y, w, h
grid.AddColumn("Name", "Project Name").AddColumn("Stars", "Stars")   ; name, header text (optional)
grid.AddRow("AHK#", "1500")
grid.AddRow("Other", "42")
cell := grid.GetCell(0, 0)                             ; row, column (0-based) → "AHK#"
grid.Clear()                                           ; remove all rows

rtb := NativeUI.RichTextBox(g, 10, 260, 560, 200)
rtb.Text := "Hello from a .NET RichTextBox"
MsgBox(rtb.Text)
rtb.Resize(10, 260, 560, 220)                          ; x, y, w, h
rtb.BackColor := "#101020"                             ; other properties are set by reflection

panel := NativeUI.Panel(g, 0, 0, 100, 100)             ; a plain container
panel.Destroy()
```

| Member | Applies to | Description |
|--------|-----------|-------------|
| `NativeUI.DataGridView(gui, x, y, w, h)` | | Creates a DataGridView |
| `NativeUI.RichTextBox(gui, x, y, w, h)` | | Creates a RichTextBox |
| `NativeUI.Panel(gui, x, y, w, h)` | | Creates a Panel |
| `AddColumn(name, headerText := "")` | grid | Chainable |
| `AddRow(values*)` | grid | One value per column; chainable |
| `GetCell(row, col)` | grid | Cell text (0-based indexes) |
| `Clear()` | grid | Removes all rows; chainable |
| `Text` (get/set) | any control with text | The control's `Text` |
| `Resize(x, y, w, h)` | any | Moves/resizes; chainable |
| `Destroy()` | any | Disposes the control |
| `ctrl.Prop := value` | any | Sets a public WinForms property by reflection. Color-typed properties accept `"#RRGGBB"`, Font-typed ones a font family name; unknown names are ignored |

## UIAutomation (ext\ahk#.uia.ahk)

High-performance UI tree crawling: the whole walk runs in C# and comes back in **one bulk COM call** as plain rows, so reading a large tree does not cost one COM call per property.

```autohotkey
#Include ext\ahk#.uia.ahk
hwnd := WinGetID("A")
tree := UIA2.CrawlTree(hwnd, 5)                        ; hwnd (0 = desktop), max depth (default 50)
for el in tree                                         ; an ordinary 1-based Array of UIAElement
    MsgBox(el.Depth ": [" el.ControlType "] " el.Name)
buttons := UIA2.Find(hwnd, "ControlType=Button", 10)   ; condition, max depth
el := UIA2.FromPoint(500, 300)                         ; element under a screen point, or "" when there is none
f := UIA2.Focused()                                    ; the focused element, or ""
if (el != "" && f != "")
    MsgBox(el.Name " | " el.ControlType " | " f.AutomationId)
ok := UIA2.Invoke(hwnd, "btnSubmit")                   ; click via the Invoke pattern
ok := UIA2.SetValue(hwnd, "txtName", "Alice")          ; ValuePattern.SetValue
```

- `CrawlTree` and `Find` return an **AHK Array (1-based)** of `UIAElement` objects. Each element has plain AHK properties (no COM call to read them): `Name`, `AutomationId`, `ClassName`, `ControlType`, `LocalizedControlType`, `ProcessId`, `NativeWindowHandle`, `BoundingX`, `BoundingY`, `BoundingW`, `BoundingH`, `IsEnabled`, `IsOffscreen`, `Value`, `Depth`, `ChildCount`.
- **Breaking change:** these used to be a raw 0-based COM array that cost one COM call per property. Code that indexed `elements[A_Index - 1]` must use `for el in elements` (or 1-based indexes).
- `Find` conditions are `Property=value` with one of `Name` (substring, case-insensitive), `AutomationId`, `ClassName` or `ControlType` (exact, case-insensitive). An empty or unrecognised condition returns every element.
- `FromPoint(x, y)` and `Focused()` return one `UIAElement`, or `""` when there is no element.
- `Invoke` and `SetValue` locate the element by `AutomationId` under the window; they return `1` when the pattern was applied and `0` when the element or pattern was not found (or on error).

## Spatial (ext\ahk#.spatial.ahk)

Polls a screen region and calls your function when the text in it changes. It does not use the .NET bridge at all, and **AHK# ships no OCR engine**: you supply the function that turns a rectangle into text (`Spatial.Reader`), from any OCR library, a Tesseract call, an accessibility read, or anything else.

```autohotkey
#Include ext\ahk#.spatial.ahk

; 1. Tell Spatial how to read a region: any function (x, y, w, h) => text
Spatial.Reader := (x, y, w, h) => MyOcr.Read(x, y, w, h)      ; MyOcr is whatever you use

; 2. Watch: call back when the text is non-empty and different from last time, with {text}
id := Spatial.Watch(0, 0, 400, 200, 500, (r) => ToolTip(r.text))

; WatchFor: call back when the text matches a regex, with {text, match} (match is the RegExMatchInfo)
id2 := Spatial.WatchFor(0, 0, 400, 200, "i)error (\d+)", (r) => MsgBox("Code " r.match[1]), 250)

Spatial.Stop(id)          ; stop one watcher (its timer is cancelled)
Spatial.StopAll()         ; stop every watcher
MsgBox Spatial.Count      ; active watchers
```

If no `Spatial.Reader` is set but a class named `OCR` with a `Text(x, y, w, h)` method exists, that is used instead.

| Member | Description |
|--------|-------------|
| `Spatial.Reader` | `(x, y, w, h) => text`. Required (or an `OCR` class with `Text(x, y, w, h)`) |
| `Spatial.Parser` | Optional `(text) => {...}`. Its result's properties are merged into the object `Watch` passes to your callback (for example `{ast: ..., errorCount: ...}` from an AHK parser). Not used by `WatchFor` |
| `Spatial.OnError` | Optional `(e, watcherId) => ...`. Errors thrown by the Reader, Parser or your callback are passed here; by default they go to `OutputDebug`. They are never swallowed, and the watcher keeps running |
| `Spatial.Watch(x, y, w, h, intervalMs, callback)` | Every `intervalMs`, read the region; when the text is non-empty and changed, call `callback({text, ...})` (plus what `Parser` returned). Returns a watcher id |
| `Spatial.WatchFor(x, y, w, h, pattern, callback, intervalMs := 500)` | Same polling; calls `callback({text, match})` when `RegExMatch(text, pattern)` succeeds. Returns a watcher id |
| `Spatial.Stop(id)` / `Spatial.StopAll()` | Cancel the watcher's timer / every watcher's timer |
| `Spatial.Count` | Number of active watchers |

A slow Reader does not pile up: a poll that is still running makes the next tick skip. Nothing is executed unless **your callback** executes it; see [Security](19_security.md) before wiring a callback that runs what it reads. The behaviour is covered by `tests\test_spatial.ahk`, which uses a fake Reader.
