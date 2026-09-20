;; AHK# — Async Web API Server
;; Turns your AHK script into a non-blocking Web API!
;; Run this script, then open your browser to: http://localhost:8080/
;; It serves live data from AHK without freezing the AHK message loop.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk
#Include ..\..\ext\ahk#.http.ahk   ; for Json.Build

PORT := 8080   ; change this if the port is already in use

class WebAPI extends _CSModule {
    static CSharp := '
    (
        using System.Net;
        using System.Text;
        using System;

        private static HttpListener _listener;
        private static HttpListenerContext _currentContext;

        public static void Start(string prefix) {
            _listener = new HttpListener();
            _listener.Prefixes.Add(prefix);
            _listener.Start();
        }

        public static void WaitForRequest() {
            // Blocks this ThreadPool thread until a browser connects
            _currentContext = _listener.GetContext();
        }

        public static string Respond(string responsePayload) {
            if (_currentContext == null) return "";

            var ctx = _currentContext;
            _currentContext = null;
            string path = ctx.Request.Url.PathAndQuery;
            try {
                var res = ctx.Response;
                res.AppendHeader("Access-Control-Allow-Origin", "*");
                byte[] buf = Encoding.UTF8.GetBytes(responsePayload);
                res.ContentType = "application/json";
                res.ContentLength64 = buf.Length;
                res.OutputStream.Write(buf, 0, buf.Length);
                res.OutputStream.Close();
            } catch (Exception) {
                // The browser went away before we answered - nothing to do
            }
            return path;
        }

        public static void Stop() {
            if (_listener != null) {
                _listener.Close();
            }
        }
    )'
}

; ── Start the Web Server ──
; Do this before creating any UI so a busy port gives a clear message.
try {
    WebAPI.Start("http://localhost:" PORT "/")
} catch as e {
    MsgBox("Could not start the web server on port " PORT ".`n`n"
        . "Another program (or another copy of this script) is probably using it. "
        . "Change PORT at the top of the script and run it again.`n`n"
        . "Details: " e.Message, "AHK# — Local Web Server", 0x10)
    ExitApp()
}

OnExit((*) => WebAPI.Stop())

; ── Setup AHK GUI ──
g := Gui("", "AHK# — Local Web Server")
g.SetFont("s12 cBlue")
g.Add("Text", "w300 center", "Server is running on port " PORT "!")
g.SetFont("s10 cBlack")
lblData := g.Add("Text", "w300 center y+10", "Waiting for requests...")
g.OnEvent("Close", (*) => ExitApp())
g.Show("w320 h100")

; Report mouse coordinates in screen space (the default is relative to the active window)
CoordMode("Mouse", "Screen")

; ── Main Async Request Loop ──
Loop {
    ; 1. Dispatch the blocking wait to the .NET ThreadPool!
    promise := WebAPI.Async.WaitForRequest()

    ; 2. Wait for the promise to resolve (a browser has just connected).
    ;    Await keeps AHK responsive, so the window can still be moved and closed.
    try {
        promise.Await()
    } catch {
        break   ; the listener was stopped
    }

    ; 3. NOW gather the live AHK data (so it is fresh, not 1 reload behind)
    MouseGetPos(&mx, &my)
    sysTime := A_Hour ":" A_Min ":" A_Sec
    jsonResponse := Json.Build("time", sysTime, "mouse_x", mx, "mouse_y", my
        , "status", "AHK# is amazing!")

    ; 4. Instantly reply to the browser
    pathRequested := WebAPI.Respond(jsonResponse)

    ; Update our GUI to show we handled a request
    lblData.Value := "Served request to: " pathRequested " at " sysTime
}

ExitApp()
