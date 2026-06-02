;; AHK# Example 21 — Native WebSocket Server
;; Allows external apps (Browser, OBS, StreamDeck) to instantly trigger AHK functions.
;; Run this script, then open a browser console and type:
;; let ws = new WebSocket("ws://localhost:8181/"); ws.onmessage = e => console.log(e.data); ws.send("Hello AHK!");

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

class WSServer extends _CSModule {
    static CSharp := '
    (
        using System.Net;
        using System.Net.WebSockets;
        using System.Threading;
        using System.Threading.Tasks;
        using System.Text;
        using System;

        private static HttpListener _listener;
        private static WebSocket _currentSocket;

        public static void Start(string url) {
            _listener = new HttpListener();
            _listener.Prefixes.Add(url);
            _listener.Start();
        }
        
        public static string WaitForMessage() {
            try {
                if (_currentSocket == null || _currentSocket.State != WebSocketState.Open) {
                    var ctx = _listener.GetContext(); 
                    if (ctx.Request.IsWebSocketRequest) {
                        var wsContext = ctx.AcceptWebSocketAsync(null).Result;
                        _currentSocket = wsContext.WebSocket;
                    } else {
                        ctx.Response.StatusCode = 400;
                        ctx.Response.Close();
                        return "HTTP_ERROR";
                    }
                }

                byte[] buffer = new byte[1024];
                var result = _currentSocket.ReceiveAsync(new ArraySegment<byte>(buffer), CancellationToken.None).Result;
                
                if (result.MessageType == WebSocketMessageType.Close) {
                    _currentSocket.CloseAsync(WebSocketCloseStatus.NormalClosure, "", CancellationToken.None).Wait();
                    _currentSocket = null;
                    return "CLIENT_DISCONNECTED";
                }
                
                return Encoding.UTF8.GetString(buffer, 0, result.Count);
            } catch (Exception ex) {
                return "ERR: " + ex.Message;
            }
        }

        public static void SendMessage(string msg) {
            if (_currentSocket != null && _currentSocket.State == WebSocketState.Open) {
                byte[] buf = Encoding.UTF8.GetBytes(msg);
                _currentSocket.SendAsync(new ArraySegment<byte>(buf), WebSocketMessageType.Text, true, CancellationToken.None).Wait();
            }
        }
        
        public static void Stop() {
            if (_listener != null) {
                _listener.Stop();
            }
        }
    )'
}

; ── UI Setup ──
g := Gui("", "AHK# — WebSocket Server")
g.SetFont("s10", "Consolas")
g.Add("Text", "w400 cBlue", "Listening on ws://localhost:8181/")
txtLog := g.Add("Edit", "w400 h200 ReadOnly", "")
g.Show()
g.OnEvent("Close", (*) => ExitApp())

Log(msg) {
    txtLog.Value := A_Hour ":" A_Min ":" A_Sec " - " msg "`r`n" txtLog.Value
}

; ── Start Server ──
WSServer.Start("http://localhost:8181/")
OnExit((*) => WSServer.Stop())

Log("Server started. Awaiting connections...")

; ── Main Event Loop ──
Loop {
    ; Use AHK# Async to wait for messages on a background thread without freezing GUI!
    promise := WSServer.Async.WaitForMessage()
    msg := promise.Await()
    
    if (msg == "CLIENT_DISCONNECTED") {
        Log("Client Disconnected. Waiting for new client...")
        continue
    }
    
    if (msg == "HTTP_ERROR")
        continue

    Log("Received: " msg)
    
    ; You can parse commands from the browser and trigger macros here!
    if (msg == "BEEP") {
        SoundBeep(750, 250)
        WSServer.SendMessage("Ahk beeped!")
    } else if (msg == "MOUSE") {
        MouseGetPos(&x, &y)
        WSServer.SendMessage("Mouse is at: " x ", " y)
    } else {
        WSServer.SendMessage("AHK received: " msg)
    }
}
