;; AHK# Spatial Code Execution — OCR + AST combined
;; Monitor screen regions for text, parse as AHK2, compile and execute dynamically.

#Requires AutoHotkey v2.0

class Spatial {
    static _watchers := Map()
    static _nextId := 1

    ; Watch a screen region. When OCR detects valid AHK2 code, compile and execute it.
    ; Returns a watcher ID for stopping.
    static Watch(x, y, w, h, intervalMs, callback) {
        id := this._nextId++
        watcher := {
            id: id, x: x, y: y, w: w, h: h,
            interval: intervalMs, callback: callback,
            lastText: "", active: true
        }
        this._watchers[id] := watcher

        ; Set up polling timer
        fn := ObjBindMethod(this, "_Poll", id)
        SetTimer(fn, intervalMs)

        return id
    }

    ; Watch for a specific regex pattern in OCR text, then execute callback.
    static WatchFor(x, y, w, h, pattern, callback, intervalMs := 500) {
        id := this._nextId++
        watcher := {
            id: id, x: x, y: y, w: w, h: h,
            interval: intervalMs, callback: callback,
            pattern: pattern, lastText: "", active: true
        }
        this._watchers[id] := watcher

        fn := ObjBindMethod(this, "_PollPattern", id)
        SetTimer(fn, intervalMs)

        return id
    }

    ; Stop a watcher
    static Stop(id) {
        if this._watchers.Has(id) {
            watcher := this._watchers[id]
            watcher.active := false
            this._watchers.Delete(id)
        }
    }

    ; Stop all watchers
    static StopAll() {
        for id in this._watchers
            this.Stop(id)
    }

    ; ── Internal Polling ──────────────────────────────────────────────────

    static _Poll(id) {
        if !this._watchers.Has(id)
            return

        watcher := this._watchers[id]
        if !watcher.active {
            SetTimer(ObjBindMethod(this, "_Poll", id), 0)
            return
        }

        try {
            ; OCR the region
            text := OCR.Text(watcher.x, watcher.y, watcher.w, watcher.h)

            ; Skip if unchanged
            if (text == watcher.lastText || text == "")
                return
            watcher.lastText := text

            ; Try to parse as AHK2
            ast := ASTparse(text)
            errors := ASTgetErrors(ast)

            ; Execute if parseable (allow some errors — resilient)
            result := {text: text, ast: ast, errorCount: errors.Length}

            ; Call user callback
            watcher.callback(result)
        } catch as e {
            ; Silently continue on OCR/parse failures
        }
    }

    static _PollPattern(id) {
        if !this._watchers.Has(id)
            return

        watcher := this._watchers[id]
        if !watcher.active {
            SetTimer(ObjBindMethod(this, "_PollPattern", id), 0)
            return
        }

        try {
            text := OCR.Text(watcher.x, watcher.y, watcher.w, watcher.h)

            if (text == "" || text == watcher.lastText)
                return
            watcher.lastText := text

            ; Check pattern match
            if RegExMatch(text, watcher.pattern, &match) {
                watcher.callback({text: text, match: match})
            }
        }
    }
}
