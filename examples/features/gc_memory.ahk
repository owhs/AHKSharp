;; AHK# Example 35 — Garbage Collection & Memory Management
;; Monitor managed heap usage and control garbage collection.
;; Useful for long-running scripts that process large amounts of data.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

; ── GUI ───────────────────────────────────────────────────────────────────────
g := Gui("+Resize", "AHK# — Memory Manager")
g.SetFont("s10", "Segoe UI")
g.BackColor := "0x1e1e2e"
g.SetFont("cCDD6F4")

g.Add("Text", "x10 y10 w280", "Managed Heap Usage:")
memLabel := g.Add("Text", "x10 y30 w280 h24 cA6E3A1", "...")
g.Add("Text", "x10 y60 w280", "Module Cache:")
cacheLabel := g.Add("Text", "x10 y80 w280 h24 cFAB387", "...")

btnGC := g.Add("Button", "x300 y10 w120 h30", "Force GC")
btnAllocate := g.Add("Button", "x300 y50 w120 h30", "Allocate 10MB")
btnEval := g.Add("Button", "x300 y90 w120 h30", "Run 100 Evals")

g.SetFont("s9", "Cascadia Mono")
logEdit := g.Add("Edit", "x10 y110 w410 h200 Multi ReadOnly Background0x181825 cA6E3A1")

UpdateMemory() {
    bytes := CS.Memory()
    kb := Round(bytes / 1024)
    mb := Round(bytes / (1024 * 1024), 2)
    if (mb >= 1)
        memLabel.Value := mb " MB (" Format("{:,}", kb) " KB)"
    else
        memLabel.Value := Format("{:,}", kb) " KB"
}

AddLog(text) {
    timestamp := FormatTime(A_Now, "HH:mm:ss")
    logEdit.Value := "[" timestamp "] " text "`r`n" logEdit.Value
}

; ── Handlers ──────────────────────────────────────────────────────────────────

btnGC.OnEvent("Click", (*) => DoGC())
btnAllocate.OnEvent("Click", (*) => DoAllocate())
btnEval.OnEvent("Click", (*) => DoManyEvals())

DoGC() {
    before := CS.Memory()
    CS.GC()
    after := CS.Memory()
    freed := before - after
    AddLog("GC: freed " Round(freed / 1024) " KB (before: " Round(before / 1024) " KB → after: " Round(after / 1024) " KB)")
    UpdateMemory()
}

DoAllocate() {
    AddLog("Allocating 10MB string...")
    before := CS.Memory()
    ; Create a large string in .NET to simulate memory pressure
    CS.Eval("new string('x', 10 * 1024 * 1024).Length")
    after := CS.Memory()
    AddLog("Allocated! Delta: +" Round((after - before) / 1024) " KB")
    UpdateMemory()
}

DoManyEvals() {
    AddLog("Running 100 unique CS.Eval expressions...")
    before := CS.Memory()
    t := A_TickCount
    Loop 100 {
        CS.Eval("Math.Pow(" A_Index ", 2) + Math.Sqrt(" A_Index ")")
    }
    elapsed := A_TickCount - t
    after := CS.Memory()
    AddLog("Done! " elapsed "ms, delta: +" Round((after - before) / 1024) " KB")
    UpdateMemory()
}

; ── Auto-refresh memory display ───────────────────────────────────────────────
UpdateMemory()
AddLog("Memory manager started")
AddLog("Initial heap: " Round(CS.Memory() / 1024) " KB")

SetTimer(UpdateMemory, 1000)

g.OnEvent("Close", (*) => ExitApp())
g.Show("w430 h320")

WinWaitClose(g.Hwnd)
ExitApp()
