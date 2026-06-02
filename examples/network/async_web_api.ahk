;; AHK# Example 09 — Async Web API Server
;; Turns your AHK script into a non-blocking Web API!
;; Run this script, then open your browser to: http://localhost:8080/
;; It serves live data from AHK without freezing the AHK message loop.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

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
            // This blocks the thread until a browser connects
            _currentContext = _listener.GetContext(); 
        }

        public static string Respond(string responsePayload) {
            if (_currentContext == null) return "";
            
            var res = _currentContext.Response;
            res.AppendHeader("Access-Control-Allow-Origin", "*");
            byte[] buf = Encoding.UTF8.GetBytes(responsePayload);
            res.ContentType = "application/json";
            res.ContentLength64 = buf.Length;
            
            res.OutputStream.Write(buf, 0, buf.Length);
            res.OutputStream.Close();
            
            string path = _currentContext.Request.Url.PathAndQuery;
            _currentContext = null;
            return path;
        }
        
        public static void Stop() { 
            if (_listener != null) {
                _listener.Stop(); 
            }
        }
    )'
}

; ── Setup AHK GUI ──
g := Gui("", "AHK# — Local Web Server")
g.SetFont("s12 cBlue")
g.Add("Text", "w300 center", "Server is running on port 8080!")
g.SetFont("s10 cBlack")
lblData := g.Add("Text", "w300 center y+10", "Waiting for requests...")
g.OnEvent("Close", (*) => ExitApp())
g.Show("w320 h100")

CoordMode("Mouse", "Screen")
#DllLoad "user32.dll" ; Preloads for speed, though often optional in v2
SetRegView(64)       ; Ensures registry/system calls align on 64-bit systems

; ── Start the Web Server ──
WebAPI.Start("http://localhost:8080/")

OnExit((*) => WebAPI.Stop())

; ── Main Async Request Loop ──
Loop {
    ; 1. Dispatch the blocking wait to the .NET ThreadPool!
    promise := WebAPI.Async.WaitForRequest()

    ; 2. Wait for the promise to resolve (A browser has just connected!)
    promise.Await()

    ; 3. NOW gather the live AHK data (So it's fresh, not 1 reload behind)
    MouseGetPos(&mx, &my)
    sysTime := A_Hour ":" A_Min ":" A_Sec
    jsonResponse := "{ `"time`": `"" sysTime "`", `"mouse_x`": " mx ", `"mouse_y`": " my ", `"status`": `"AHK# is amazing!`" }"

    ; 4. Instantly reply to the browser
    pathRequested := WebAPI.Respond(jsonResponse)

    ; Update our GUI to show we handled a request
    lblData.Value := "Served request to: " pathRequested " at " sysTime
}