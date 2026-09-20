;; AHK# — Garbage Collection & Memory Management
;; Monitor managed heap usage and control garbage collection.
;; Useful for long-running scripts that process large amounts of data.
;;
;; Try it: "Allocate 10MB" keeps the memory alive (the heap grows and Force GC
;; can NOT free it), "Release held" drops the references so Force GC can.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

EVAL_COUNT := 8   ; every unique CS.Eval compiles an assembly, so keep this small
held := []        ; AHK-side references that keep .NET objects reachable

; ── GUI ───────────────────────────────────────────────────────────────────────
g := Gui("+Resize", "AHK# — Memory Manager")
g.SetFont("s10", "Segoe UI")
g.BackColor := "0x1e1e2e"
g.SetFont("cCDD6F4")

g.Add("Text", "x10 y10 w280", "Managed Heap Usage:")
memLabel := g.Add("Text", "x10 y30 w280 h24 cA6E3A1", "...")
g.Add("Text", "x10 y60 w280", "Module Cache (compiled DLLs on disk):")
cacheLabel := g.Add("Text", "x10 y80 w280 h24 cFAB387", "...")
g.Add("Text", "x10 y110 w280", "Held allocations:")
heldLabel := g.Add("Text", "x10 y130 w280 h24 cF9E2AF", "none")

btnGC := g.Add("Button", "x300 y10 w120 h30", "Force GC")
btnAllocate := g.Add("Button", "x300 y44 w120 h30", "Allocate 10MB")
btnRelease := g.Add("Button", "x300 y78 w120 h30", "Release held")
btnEval := g.Add("Button", "x300 y112 w120 h30", "Run " EVAL_COUNT " Evals")

g.SetFont("s9", "Cascadia Mono")
logEdit := g.Add("Edit", "x10 y160 w410 h200 Multi ReadOnly Background0x181825 cA6E3A1")

UpdateMemory() {
    bytes := CS.Memory()
    kb := Round(bytes / 1024)
    mb := Round(bytes / (1024 * 1024), 2)
    if (mb >= 1)
        memLabel.Value := mb " MB (" Format("{:,}", kb) " KB)"
    else
        memLabel.Value := Format("{:,}", kb) " KB"
}

; Compiled modules are cached as DLLs by the bridge; count them.
UpdateCache() {
    cacheDir := EnvGet("LocalAppData") "\AhkSharp\CompileCache"
    count := 0
    bytes := 0
    Loop Files cacheDir "\*.dll" {
        count++
        bytes += A_LoopFileSize
    }
    cacheLabel.Value := count " modules, " Format("{:,}", Round(bytes / 1024)) " KB"
}

UpdateHeld() {
    heldLabel.Value := held.Length ? held.Length " x 10 MB (still referenced)" : "none"
}

AddLog(text) {
    timestamp := FormatTime(A_Now, "HH:mm:ss")
    logEdit.Value := "[" timestamp "] " text "`r`n" logEdit.Value
}

; ── Handlers ──────────────────────────────────────────────────────────────────

btnGC.OnEvent("Click", (*) => DoGC())
btnAllocate.OnEvent("Click", (*) => DoAllocate())
btnRelease.OnEvent("Click", (*) => DoRelease())
btnEval.OnEvent("Click", (*) => DoManyEvals())

DoGC() {
    before := CS.Memory()
    CS.GC()
    after := CS.Memory()
    freed := before - after
    AddLog("GC: freed " Round(freed / 1024) " KB (before: " Round(before / 1024) " KB → after: " Round(after / 1024) " KB)")
    if (held.Length)
        AddLog("   " held.Length " x 10 MB are still referenced, so the GC must keep them")
    UpdateMemory()
}

DoAllocate() {
    before := CS.Memory()
    ; MemoryStream(capacity) allocates a 10 MB byte[]. Storing the proxy keeps the
    ; .NET object reachable, so the heap really grows and GC cannot reclaim it.
    held.Push(CS.System.IO.MemoryStream(10 * 1024 * 1024))
    after := CS.Memory()
    AddLog("Allocated 10 MB - delta: +" Round((after - before) / 1024) " KB")
    UpdateHeld()
    UpdateMemory()
}

DoRelease() {
    if (!held.Length) {
        AddLog("Nothing is held - press Allocate first")
        return
    }
    n := held.Length
    held.Length := 0            ; drop the AHK references...
    before := CS.Memory()
    CS.GC()                     ; ...so the collector is now free to reclaim them
    after := CS.Memory()
    AddLog("Released " n " x 10 MB, GC freed " Round((before - after) / 1024) " KB")
    UpdateHeld()
    UpdateMemory()
}

DoManyEvals() {
    AddLog("Running " EVAL_COUNT " unique CS.Eval expressions...")
    before := CS.Memory()
    t := A_TickCount
    Loop EVAL_COUNT {
        CS.Eval("Math.Pow(" A_Index ", 2) + Math.Sqrt(" A_Index ")")
    }
    elapsed := A_TickCount - t
    after := CS.Memory()
    AddLog("Done! " elapsed "ms, delta: +" Round((after - before) / 1024) " KB (run again: cached, much faster)")
    UpdateCache()
    UpdateMemory()
}

; ── Auto-refresh memory display ───────────────────────────────────────────────
UpdateMemory()
UpdateCache()
AddLog("Memory manager started")
AddLog("Initial heap: " Round(CS.Memory() / 1024) " KB")

SetTimer(UpdateMemory, 1000)

g.OnEvent("Close", (*) => ExitApp())
g.Show("w430 h370")

WinWaitClose(g.Hwnd)
ExitApp()
