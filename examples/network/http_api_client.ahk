;; AHK# Example 15 — HTTP API Client
;; Fetch live data from public APIs using System.Net.WebClient.
;; In pure AHK: WinHttp COM, 50+ lines of boilerplate.
;; In AHK#: 3 lines per request.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

class HttpClient extends _CSModule {
    static CSharp := "
    (
        using System;
        using System.Net;
        using System.Text;

        static bool _init = Init();
        static bool Init() {
            ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072;
            return true;
        }

        public static string Get(string url) {
            using (var client = new WebClient()) {
                client.Encoding = Encoding.UTF8;
                client.Headers.Add("User-Agent", "AHK-Sharp/1.0");
                return client.DownloadString(url);
            }
        }

        public static string Post(string url, string jsonBody) {
            using (var client = new WebClient()) {
                client.Encoding = Encoding.UTF8;
                client.Headers.Add("Content-Type", "application/json");
                client.Headers.Add("User-Agent", "AHK-Sharp/1.0");
                return client.UploadString(url, jsonBody);
            }
        }

        public static string Head(string url) {
            var req = WebRequest.Create(url);
            req.Method = "HEAD";
            using (var resp = (HttpWebResponse)req.GetResponse()) {
                return (int)resp.StatusCode + "|" + resp.ContentType + "|" + resp.Server;
            }
        }
    )"
}

; Simple JSON value extractor (no external lib needed)
JsonVal(json, key) {
    pattern := '"' key '"\s*:\s*"?([^",}\]]+)"?'
    if RegExMatch(json, pattern, &m)
        return Trim(m[1])
    return "(not found)"
}

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
btnTime := g.Add("Button", "x145 y36 w80 h24", "UTC Time")
btnUuid := g.Add("Button", "x230 y36 w80 h24", "UUID")
btnHeaders := g.Add("Button", "x315 y36 w80 h24", "Headers")

g.SetFont("s9", "Cascadia Mono")
resultEdit := g.Add("Edit", "x10 y68 w480 h380 Multi ReadOnly Background0x181825 cA6E3A1")

; ── Handlers ──────────────────────────────────────────────────────────────────

DoFetch() {
    url := urlEdit.Value
    resultEdit.Value := "Fetching " url "..."
    try {
        t := A_TickCount
        body := HttpClient.Get(url)
        elapsed := A_TickCount - t
        resultEdit.Value := "GET " url " (" elapsed "ms)`n"
            . "───────────────────────────────`n"
            . body
    } catch as e {
        resultEdit.Value := "Error: " e.Message
    }
}

btnIp.OnEvent("Click", (*) => FetchApi("https://httpbin.org/ip", "origin"))
btnUuid.OnEvent("Click", (*) => FetchApi("https://httpbin.org/uuid", "uuid"))
btnHeaders.OnEvent("Click", (*) => DoHead())

btnTime.OnEvent("Click", (*) => DoUtcTime())

DoUtcTime() {
    resultEdit.Value := "Fetching UTC time..."
    try {
        t := A_TickCount
        body := HttpClient.Get("https://httpbin.org/get")
        elapsed := A_TickCount - t
        utc := CS.System.DateTime.UtcNow
        resultEdit.Value := "═══ UTC Time ═══`n`n"
            . "  UTC Now:  " utc "`n"
            . "  Source:   System.DateTime.UtcNow`n"
            . "  Latency:  " elapsed "ms (httpbin.org roundtrip)`n"
            . "`n─── httpbin.org /get ───`n" body
    } catch as e {
        resultEdit.Value := "Error: " e.Message
    }
}

FetchApi(url, key) {
    resultEdit.Value := "Fetching..."
    try {
        t := A_TickCount
        body := HttpClient.Get(url)
        elapsed := A_TickCount - t
        val := JsonVal(body, key)
        resultEdit.Value := "═══ API Result ═══`n`n"
            . "  URL:     " url "`n"
            . "  Key:     " key "`n"
            . "  Value:   " val "`n"
            . "  Latency: " elapsed "ms`n"
            . "`n─── Raw Response ───`n" body
    } catch as e {
        resultEdit.Value := "Error: " e.Message
    }
}

DoHead() {
    url := urlEdit.Value
    resultEdit.Value := "HEAD " url "..."
    try {
        raw := HttpClient.Head(url)
        parts := StrSplit(raw, "|")
        resultEdit.Value := "═══ HEAD Response ═══`n`n"
            . "  Status:  " parts[1] "`n"
            . "  Type:    " (parts.Length >= 2 ? parts[2] : "?") "`n"
            . "  Server:  " (parts.Length >= 3 ? parts[3] : "?")
    } catch as e {
        resultEdit.Value := "Error: " e.Message
    }
}

g.Show("w500 h460")
WinWaitClose(g.Hwnd)
ExitApp()
