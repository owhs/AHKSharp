;; AHK# — HTTP API Client
;; Fetch live data from public APIs using the built-in HTTP/JSON extension
;; (ext\ahk#.http.ahk): Http.Get / Http.Post / Http.Head and Json.Query / Json.Build.
;; Every request goes through .Async + .Then, so the GUI never blocks while the
;; download runs on a .NET ThreadPool thread.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk
#Include ..\..\ext\ahk#.http.ahk

; ── GUI ───────────────────────────────────────────────────────────────────────

g := Gui("+Resize", "AHK# — HTTP API Client")
g.SetFont("s10", "Segoe UI")
g.BackColor := "0x1e1e2e"
g.SetFont("cCDD6F4")

g.Add("Text", "x10 y10", "URL:")
urlEdit := g.Add("Edit", "x50 y8 w390 h24 Background0x313244 cCDD6F4"
    , "https://httpbin.org/get")

btnFetch := g.Add("Button", "x445 y7 w50 h26", "GET")
btnFetch.OnEvent("Click", (*) => DoFetch())

g.Add("Text", "x10 y38", "Quick:")
btnIp := g.Add("Button", "x60 y36 w80 h24", "My IP")
btnPost := g.Add("Button", "x145 y36 w80 h24", "POST")
btnUuid := g.Add("Button", "x230 y36 w80 h24", "UUID")
btnHeaders := g.Add("Button", "x315 y36 w80 h24", "Headers")

g.SetFont("s9", "Cascadia Mono")
resultEdit := g.Add("Edit", "x10 y68 w480 h380 Multi ReadOnly Background0x181825 cA6E3A1")

; ── Request plumbing ──────────────────────────────────────────────────────────

reqSeq := 0   ; id of the newest request; older responses are ignored

; `promise` comes from Http.Async.*; `render(body)` turns the raw response into text.
StartRequest(label, promise, render) {
    global reqSeq
    seq := ++reqSeq
    t0 := A_TickCount
    resultEdit.Value := label " ..."
    promise.Then((body) => OnDone(seq, t0, label, render, body))
           .Catch((err) => OnFail(seq, label, err))
}

OnDone(seq, t0, label, render, body) {
    if (seq != reqSeq)
        return
    try {
        resultEdit.Value := "═══ " label " (" (A_TickCount - t0) "ms) ═══`n`n" render(body)
    } catch as e {
        resultEdit.Value := label " — could not read response: " e.Message
    }
}

OnFail(seq, label, err) {
    if (seq != reqSeq)
        return
    resultEdit.Value := label " failed:`n" FriendlyError(err)
}

; .NET exception text carries a stack trace; keep only the innermost first line.
FriendlyError(err) {
    line := StrSplit(err.Message, "`n")[1]
    if (p := InStr(line, "---> ", false, -1))
        line := SubStr(line, p + 5)
    return Trim(line, "`r ")
}

; ── Handlers ──────────────────────────────────────────────────────────────────

DoFetch() {
    url := urlEdit.Value
    StartRequest("GET " url, Http.Async.Get(url), (body) => body)
}

DoIp() {
    StartRequest("My IP", Http.Async.Get("https://httpbin.org/ip")
        , (body) => "  Origin:  " Json.Query(body, "origin") "`n`n─── Raw Response ───`n" body)
}

DoUuid() {
    StartRequest("UUID", Http.Async.Get("https://httpbin.org/uuid")
        , (body) => "  UUID:  " Json.Query(body, "uuid") "`n`n─── Raw Response ───`n" body)
}

DoPost() {
    ; Json.Build takes key/value pairs and returns a JSON string
    payload := Json.Build("name", "AHK#", "language", "AutoHotkey v2")
    StartRequest("POST https://httpbin.org/post"
        , Http.Async.Post("https://httpbin.org/post", payload)
        , (body) => "  Sent:         " payload "`n"
            . "  Echoed name:  " Json.Query(body, "json.name") "`n`n"
            . "─── Raw Response ───`n" body)
}

DoHead() {
    url := urlEdit.Value
    StartRequest("HEAD " url, Http.Async.Head(url), RenderHead)
}

; Http.Head returns "status|content-type|server"
RenderHead(raw) {
    parts := StrSplit(raw, "|")
    return "  Status:  " parts[1] "`n"
        . "  Type:    " (parts.Length >= 2 ? parts[2] : "?") "`n"
        . "  Server:  " (parts.Length >= 3 ? parts[3] : "?")
}

btnIp.OnEvent("Click", (*) => DoIp())
btnPost.OnEvent("Click", (*) => DoPost())
btnUuid.OnEvent("Click", (*) => DoUuid())
btnHeaders.OnEvent("Click", (*) => DoHead())

g.Show("w500 h460")
WinWaitClose(g.Hwnd)
ExitApp()
