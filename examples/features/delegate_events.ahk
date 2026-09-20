;; AHK# — Delegate Bridge: C# Events → AHK Callbacks
;; proxy.On("EventName", fn) subscribes an AHK function to a .NET event.
;; The event fires on a .NET thread, is marshalled to the AHK main thread via
;; PostMessage, and your function receives the event args object.
;;
;; Two sources are wired up below:
;;   - System.Timers.Timer          ("Elapsed" every 2 seconds)
;;   - System.IO.FileSystemWatcher  ("Created" / "Deleted" in a folder under A_Temp)

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

; ── GUI ───────────────────────────────────────────────────────────────────────
g := Gui("+Resize", "AHK# — Event Bridge Demo")
g.SetFont("s10", "Segoe UI")
g.BackColor := "0x1e1e2e"
g.SetFont("cCDD6F4")

g.Add("Text", "x10 y10 w470", "proxy.On(`"Event`", fn) bridges .NET events to AHK functions.")
g.Add("Text", "x10 y35 w470 cA6E3A1", "Timer ticks and file-system events appear below:")

g.SetFont("s9", "Cascadia Mono")
logEdit := g.Add("Edit", "x10 y60 w470 h300 Multi ReadOnly Background0x181825 cA6E3A1")

g.SetFont("s10", "Segoe UI")
btnDrop := g.Add("Button", "x10 y370 w150 h28", "Drop a test file")
btnClear := g.Add("Button", "x170 y370 w150 h28", "Delete test files")

AddLog(text) {
    timestamp := FormatTime(A_Now, "HH:mm:ss")
    logEdit.Value := "[" timestamp "] " text "`r`n" logEdit.Value
}

; ── Timer event ───────────────────────────────────────────────────────────────
; A real .NET timer; its Elapsed event calls straight into AHK.
tickCount := 0

OnTick(*) {
    global tickCount
    tickCount++
    AddLog("Timer tick #" tickCount)
}

timer := CS.System.Timers.Timer(2000)
timer.On("Elapsed", OnTick)
timer.Start()
AddLog("Timer started - Elapsed fires every 2 seconds.")

; ── FileSystemWatcher events ──────────────────────────────────────────────────
; The handler receives the FileSystemEventArgs object (Name, FullPath, ChangeType).
watchDir := A_Temp "\AHKSharp_EventDemo"
DirCreate(watchDir)

watcher := CS.System.IO.FileSystemWatcher(watchDir)
watcher.On("Created", (e) => AddLog("Created: " e.Name))
watcher.On("Deleted", (e) => AddLog("Deleted: " e.Name))
watcher.EnableRaisingEvents := true
AddLog("Watching " watchDir)

btnDrop.OnEvent("Click", DropFile)
btnClear.OnEvent("Click", ClearFiles)

DropFile(*) {
    FileAppend("hello from AHK#", watchDir "\test_" A_TickCount ".txt")
}

ClearFiles(*) {
    Loop Files watchDir "\*.txt"
        FileDelete(A_LoopFileFullPath)
}

; ── Clean shutdown ────────────────────────────────────────────────────────────
; Stopping and disposing the .NET objects ends the events, so nothing keeps
; posting messages to a script that is going away.
Cleanup(*) {
    try timer.Stop()
    try timer.Dispose()
    try {
        watcher.EnableRaisingEvents := false
        watcher.Dispose()
    }
    try DirDelete(watchDir, true)
}

OnExit(Cleanup)
g.OnEvent("Close", (*) => ExitApp())
g.Show("w490 h410")

AddLog("Event bridge demo running! Close the window to exit.")

WinWaitClose(g.Hwnd)
ExitApp()
