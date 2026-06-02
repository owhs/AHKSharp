;; AHK# Example 39 — FileSystemWatcher Live
;; AHK's only option for detecting file changes is polling loops. Pathetic.
;; .NET's FileSystemWatcher gives INSTANT events — create, modify, delete, rename.
;;
;; The watcher runs on a background thread. Events are buffered in a
;; ConcurrentQueue and polled safely from AHK's main thread via SetTimer.
;;
;; Usage:
;;   Watcher.Start("C:\MyFolder", "*.*", true)   ; path, filter, recursive
;;   events := Watcher.Poll()                     ; get new events
;;   Watcher.Stop()

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

; ── CSModule: Watcher ─────────────────────────────────────────────────────────

class Watcher extends _CSModule {
    static CSharp := '
    (
        using System;
        using System.IO;
        using System.Collections.Concurrent;
        using System.Text;

        private static FileSystemWatcher _watcher;
        private static ConcurrentQueue<string> _events = new ConcurrentQueue<string>();
        private static bool _running = false;
        private static int _totalEvents = 0;

        public static string Start(string path, string filter, bool recursive) {
            if (_running) Stop();
            if (!Directory.Exists(path))
                return "Error: Directory not found: " + path;

            _watcher = new FileSystemWatcher();
            _watcher.Path = path;
            _watcher.Filter = filter;
            _watcher.IncludeSubdirectories = recursive;
            _watcher.InternalBufferSize = 65536;
            _watcher.NotifyFilter = NotifyFilters.FileName
                | NotifyFilters.DirectoryName
                | NotifyFilters.LastWrite
                | NotifyFilters.Size
                | NotifyFilters.CreationTime;

            _watcher.Created += (s, e) => Enqueue("Created", e.FullPath);
            _watcher.Changed += (s, e) => Enqueue("Changed", e.FullPath);
            _watcher.Deleted += (s, e) => Enqueue("Deleted", e.FullPath);
            _watcher.Renamed += (s, e) => Enqueue("Renamed", e.OldFullPath + " -> " + e.FullPath);
            _watcher.Error += (s, e) => Enqueue("Error", e.GetException().Message);

            _watcher.EnableRaisingEvents = true;
            _running = true;
            return "Watching: " + path + " (" + filter + ")" + (recursive ? " [recursive]" : "");
        }

        public static void Stop() {
            if (_watcher != null) {
                _watcher.EnableRaisingEvents = false;
                _watcher.Dispose();
                _watcher = null;
            }
            _running = false;
        }

        public static string Poll() {
            var sb = new StringBuilder();
            string evt;
            while (_events.TryDequeue(out evt)) {
                sb.AppendLine(evt);
            }
            return sb.ToString();
        }

        public static int PendingCount() {
            return _events.Count;
        }

        public static int TotalCount() {
            return _totalEvents;
        }

        public static bool IsRunning() {
            return _running;
        }

        public static void SetFilter(string filter) {
            if (_watcher != null) {
                _watcher.Filter = filter;
            }
        }

        public static void Clear() {
            string dummy;
            while (_events.TryDequeue(out dummy)) { }
        }

        private static void Enqueue(string type, string detail) {
            string ts = DateTime.Now.ToString("HH:mm:ss.fff");
            _events.Enqueue(ts + "|" + type + "|" + detail);
            _totalEvents++;
        }
    )'
}

; ── Demo GUI ──────────────────────────────────────────────────────────────────

g := Gui("+Resize", "AHK# — FileSystemWatcher")
g.SetFont("s10", "Segoe UI")
g.BackColor := "0x1e1e2e"
g.SetFont("cCDD6F4")

; Header
g.SetFont("s13 cF38BA8 Bold")
g.Add("Text", "x20 y10 w440", Chr(0x1F4C2) " FileSystem Watcher")
g.SetFont("s8 c585B70 Norm")
g.Add("Text", "x20 y34 w440", "Instant file change events via .NET FileSystemWatcher — zero polling")

; ── Config ────────────────────────────────────────────────────────────────────
g.SetFont("s10 cCDD6F4", "Segoe UI")
g.Add("GroupBox", "x12 y55 w456 h85 c585B70", " " Chr(0x2699) " Configuration ")

g.Add("Text", "x25 y88 w55 Right", "Path:")
pathEdit := g.Add("Edit", "x85 y86 w310 h24 Background0x313244 cCDD6F4", A_Desktop)
btnBrowse := g.Add("Button", "x400 y85 w25 h26", "...")

g.Add("Text", "x25 y115 w55 Right", "Filter:")
filterEdit := g.Add("Edit", "x85 y113 w80 h24 Background0x313244 cCDD6F4", "*.*")
recurseChk := g.Add("Checkbox", "x175 y115 cCDD6F4", "Recursive")
recurseChk.Value := 1

btnStart := g.Add("Button", "x320 y110 w65 h28", Chr(0x25B6) " Start")
btnStop := g.Add("Button", "x390 y110 w65 h28", Chr(0x25A0) " Stop")
btnStop.Enabled := false

; Status bar
g.SetFont("s8 c585B70")
statusText := g.Add("Text", "x20 y147 w350 h16", "Not watching")
totalText := g.Add("Text", "x370 y147 w95 h16 Right", "Events: 0")

; Event log
g.SetFont("s10 cF38BA8")
g.Add("Text", "x20 y165", Chr(0x25CF) " Live Events")
g.SetFont("s9", "Cascadia Mono")
logEdit := g.Add("Edit", "x20 y185 w448 h250 Multi ReadOnly Background0x181825 cA6E3A1 VScroll")

; Event type icons
IconFor(type) {
    if (type == "Created")
        return Chr(0x2795) " "
    if (type == "Deleted")
        return Chr(0x274C) " "
    if (type == "Changed")
        return Chr(0x270F) " "
    if (type == "Renamed")
        return Chr(0x21C4) " "
    if (type == "Error")
        return Chr(0x26A0) " "
    return "  "
}

ColorFor(type) {
    if (type == "Created")
        return "A6E3A1"
    if (type == "Deleted")
        return "F38BA8"
    if (type == "Changed")
        return "FAB387"
    if (type == "Renamed")
        return "89B4FA"
    return "CDD6F4"
}

; ── Handlers ──────────────────────────────────────────────────────────────────

btnBrowse.OnEvent("Click", (*) => BrowseFolder())
BrowseFolder() {
    folder := DirSelect(, , "Select folder to watch")
    if (folder != "")
        pathEdit.Value := folder
}

btnStart.OnEvent("Click", (*) => StartWatch())
StartWatch() {
    result := Watcher.Start(pathEdit.Value, filterEdit.Value, recurseChk.Value)
    statusText.Value := result
    btnStart.Enabled := false
    btnStop.Enabled := true
    logEdit.Value := ""
}

btnStop.OnEvent("Click", (*) => StopWatch())
StopWatch() {
    Watcher.Stop()
    statusText.Value := "Stopped"
    btnStart.Enabled := true
    btnStop.Enabled := false
}

; Poll for events every 100ms
SetTimer(PollEvents, 100)
PollEvents() {
    if (!Watcher.IsRunning())
        return
    newEvents := Watcher.Poll()
    if (newEvents == "")
        return

    ; Parse and format events
    Loop Parse, newEvents, "`n", "`r"
    {
        if (A_LoopField == "")
            continue
        parts := StrSplit(A_LoopField, "|",, 3)
        if (parts.Length < 3)
            continue
        ts := parts[1]
        type := parts[2]
        detail := parts[3]
        ; Get just filename from path
        SplitPath(StrSplit(detail, " -> ")[1], &fn)
        icon := IconFor(type)
        line := "[" ts "] " icon type ": " fn
        if (InStr(detail, " -> ")) {
            SplitPath(StrSplit(detail, " -> ")[2], &fn2)
            line .= " -> " fn2
        }
        logEdit.Value := line "`r`n" logEdit.Value
    }
    totalText.Value := "Events: " Watcher.TotalCount()
}

; Clean up on exit
g.OnEvent("Close", (*) => (Watcher.Stop(), ExitApp()))
g.Show("w480 h448")

WinWaitClose(g.Hwnd)
ExitApp()
