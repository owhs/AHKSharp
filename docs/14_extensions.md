# Extensions

AHK# ships with built-in extensions for common tasks.

## SQLite (ext/ahk#.sqlite.ahk)
Zero-dependency SQLite via Windows' built-in winsqlite3.dll.
`utohotkey
#Include ..\ext\ahk#.sqlite.ahk
db := SQLite(':memory:')
db.Execute('CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)')
db.Execute('INSERT INTO users (name) VALUES (?)', 'Alice')
rows := db.Query('SELECT * FROM users')
`

## HTTP/JSON (ext/ahk#.http.ahk)
Built-in HTTP client and JSON parser.
`utohotkey
#Include ..\ext\ahk#.http.ahk
response := Http.Get('https://api.github.com/users/octocat')
name := Json.Query(response, 'login')
`

## IPC (ext/ahk#.ipc.ahk)
Memory-mapped file IPC for inter-process communication.
`utohotkey
#Include ..\ext\ahk#.ipc.ahk
sm := SharedMemory('MyChannel')
sm.Write('Hello from process A')
`

## Native UI (ext/ahk#.ui.ahk)
Embed .NET WinForms controls in AHK GUIs.
`utohotkey
#Include ..\ext\ahk#.ui.ahk
grid := NativeUI.DataGridView(g, 10, 10, 400, 300)
grid.AddColumn('Name', 'Name').AddColumn('Score', 'Score')
`

## UIAutomation (ext/ahk#.uia.ahk)
High-performance UI tree crawling.
`utohotkey
#Include ..\ext\ahk#.uia.ahk
tree := UIA2.CrawlTree(hwnd)
`
