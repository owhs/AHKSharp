;; AHK# Spatial — watch a screen region and react when its text changes
;;
;;   Spatial.Reader := (x, y, w, h) => OCR.FromRect(x, y, w, h).Text     ; any function returning the region's text
;;   id := Spatial.Watch(0, 0, 400, 200, 500, (r) => ToolTip(r.text))      ; every 500 ms, when the text changed
;;   id2 := Spatial.WatchFor(0, 0, 400, 200, "i)error (\d+)", (r) => MsgBox("Code " r.match[1]), 250)
;;   Spatial.Stop(id)          ; stops that watcher's timer
;;   Spatial.StopAll()
;;
;; AHK# ships no OCR engine: you supply the Reader (Descolada's OCR library, a Tesseract call, an
;; accessibility read ... anything that turns a rectangle into text). If a class named OCR with a
;; Text(x, y, w, h) method is present it is used by default.
;; Optionally set Spatial.Parser := (text) => {ast: ..., errorCount: ...} (for example wrapping an AHK
;; parser) and its result is merged into the object passed to Watch callbacks.
;; Errors thrown by the Reader / Parser / callback go to Spatial.OnError(e, watcherId) — by default
;; OutputDebug — instead of disappearing.

#Requires AutoHotkey v2.0

class Spatial {
    static Reader := ""
    static Parser := ""
    static OnError := ""
    static _watchers := Map()
    static _nextId := 1

    ; Watch a region. callback({text, ...}) runs when the text is non-empty and different from last time.
    ; Returns a watcher id for Stop().
    static Watch(x, y, w, h, intervalMs, callback) {
        return this._Add(x, y, w, h, intervalMs, callback, "")
    }

    ; Like Watch, but only calls back when the text matches the regex: callback({text, match}).
    static WatchFor(x, y, w, h, pattern, callback, intervalMs := 500) {
        return this._Add(x, y, w, h, intervalMs, callback, pattern)
    }

    ; Stop one watcher (its timer is cancelled)
    static Stop(id) {
        if !this._watchers.Has(id)
            return
        w := this._watchers[id]
        SetTimer(w.timer, 0)
        this._watchers.Delete(id)
    }

    static StopAll() {
        ids := []
        for id in this._watchers
            ids.Push(id)
        for id in ids
            this.Stop(id)
    }

    ; number of active watchers
    static Count => this._watchers.Count

    ; ── internals ─────────────────────────────────────────────────────────

    static _Add(x, y, w, h, intervalMs, callback, pattern) {
        id := this._nextId++
        watcher := { id: id, x: x, y: y, w: w, h: h, callback: callback, pattern: pattern, lastText: "", busy: false }
        watcher.timer := ObjBindMethod(this, "_Poll", id)      ; kept, so Stop can cancel exactly this timer
        this._watchers[id] := watcher
        SetTimer(watcher.timer, intervalMs)
        return id
    }

    static _Read(w) {
        reader := this.Reader
        if reader
            return reader(w.x, w.y, w.w, w.h)
        if (IsSet(OCR) && HasMethod(OCR, "Text"))
            return OCR.Text(w.x, w.y, w.w, w.h)
        throw Error("Spatial has no Reader. Set Spatial.Reader := (x, y, w, h) => <text of that region> "
            . "(AHK# includes no OCR engine).")
    }

    static _Poll(id) {
        if !this._watchers.Has(id)
            return
        w := this._watchers[id]
        if (w.busy)                                              ; a slow reader must not pile up timer threads
            return
        w.busy := true
        try {
            text := this._Read(w)
            if (text == "" || text == w.lastText)
                return
            w.lastText := text

            ; a function stored in an object property is NOT a method: calling it as w.callback(x) would pass `w` first
            callback := w.callback
            if (w.pattern != "") {
                if RegExMatch(text, w.pattern, &m)
                    callback({ text: text, match: m })
                return
            }

            result := { text: text }
            if this.Parser {
                parser := this.Parser                                 ; (a function stored in a property is not a method: no implicit `this`)
                parsed := parser(text)
                for name in ObjOwnProps(parsed)
                    result.%name% := parsed.%name%
            }
            callback(result)
        } catch as e {
            this._Report(e, id)
        } finally
            w.busy := false
    }

    static _Report(e, id) {
        handler := this.OnError
        if handler
            handler(e, id)
        else
            OutputDebug("AHK# Spatial watcher " id ": " e.Message)
    }
}
