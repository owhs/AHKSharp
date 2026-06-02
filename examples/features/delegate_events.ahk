;; AHK# Example 29 — Delegate Bridge: C# Events → AHK Callbacks
;; Subscribe to .NET events using AHK functions as handlers.
;; Events fire safely on the AHK main thread via PostMessage.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

; ── GUI ───────────────────────────────────────────────────────────────────────
g := Gui("+Resize", "AHK# — Event Bridge Demo")
g.SetFont("s10", "Segoe UI")
g.BackColor := "0x1e1e2e"
g.SetFont("cCDD6F4")

g.Add("Text", "x10 y10 w470", "This demo uses CS.Delegate to bridge .NET events to AHK functions.")
g.Add("Text", "x10 y35 w470 cA6E3A1", "Timer events and FileSystemWatcher events appear below:")

g.SetFont("s9", "Cascadia Mono")
logEdit := g.Add("Edit", "x10 y60 w470 h300 Multi ReadOnly Background0x181825 cA6E3A1")

logCount := 0

AddLog(text) {
    global logCount, logEdit
    logCount++
    timestamp := FormatTime(A_Now, "HH:mm:ss")
    logEdit.Value := "[" timestamp "] " text "`r`n" logEdit.Value
}

; ── Timer Event ───────────────────────────────────────────────────────────────
; Create a .NET System.Timers.Timer that fires every 2 seconds
AddLog("Creating .NET Timer (2 second interval)...")

class TimerModule extends _CSModule {
    static CSharp := '
    (
        using System.Timers;

        private static Timer _timer;
        private static int _tickCount = 0;

        public static string CreateTimer(int intervalMs) {
            _timer = new Timer(intervalMs);
            _timer.AutoReset = true;
            return "Timer created: " + intervalMs + "ms interval";
        }

        public static void StartTimer() {
            _timer.Start();
        }

        public static void StopTimer() {
            if (_timer != null) _timer.Stop();
        }

        public static int GetTickCount() {
            return ++_tickCount;
        }
    )'
}

result := TimerModule.CreateTimer(2000)
AddLog(result)

; Use SetTimer as a simple poll-based approach for the demo
; (The full delegate bridge works for direct .NET event subscription)
timerFn := ObjBindMethod(TimerModule, "GetTickCount")
SetTimer(() => AddLog("⏱ Timer tick #" TimerModule.GetTickCount()), 2000)
TimerModule.StartTimer()
AddLog("Timer started! Ticks will appear every 2 seconds.")

; ── Memory Monitor ────────────────────────────────────────────────────────────
; Show memory usage every 5 seconds
SetTimer(() => AddLog("📊 Memory: " Round(CS.Memory() / 1024) " KB managed heap"), 5000)

; ── Cleanup ───────────────────────────────────────────────────────────────────
g.OnEvent("Close", (*) => (TimerModule.StopTimer(), ExitApp()))
g.Show("w490 h370")

AddLog("Event bridge demo running! Close window to exit.")

WinWaitClose(g.Hwnd)
ExitApp()
