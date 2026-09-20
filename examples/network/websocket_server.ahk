;; AHK# — Native WebSocket Server
;; Allows external apps (Browser, OBS, StreamDeck) to instantly trigger AHK functions.
;; Several clients can be connected at once; multi-frame messages are reassembled.
;; Run this script, then open a browser console and type:
;; let ws = new WebSocket("ws://localhost:8181/"); ws.onmessage = e => console.log(e.data); ws.send("Hello AHK!");
;; Commands: BEEP, MOUSE, BROADCAST <text>. Anything else is echoed back.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

PORT := 8181   ; change this if the port is already in use

class WSServer extends _CSModule {
    static CSharp := '
    (
        using System.Collections.Concurrent;
        using System.IO;
        using System.Net;
        using System.Net.WebSockets;
        using System.Text;
        using System.Threading;
        using System;

        private static HttpListener _listener;
        private static readonly ConcurrentDictionary<int, WebSocket> _clients = new ConcurrentDictionary<int, WebSocket>();
        private static readonly BlockingCollection<string> _events = new BlockingCollection<string>();
        private static int _nextId = 0;

        // Events are queued as "KIND|clientId|payload" for AHK to pick up.
        private static void Post(string kind, int id, string payload) {
            try { _events.Add(kind + "|" + id + "|" + payload); }
            catch (InvalidOperationException) { /* shutting down */ }
        }

        public static void Start(string url) {
            _listener = new HttpListener();
            _listener.Prefixes.Add(url);
            _listener.Start();

            var accept = new Thread(AcceptLoop);
            accept.IsBackground = true;
            accept.Start();
        }

        private static void AcceptLoop() {
            while (true) {
                HttpListenerContext ctx;
                try { ctx = _listener.GetContext(); }
                catch (Exception) { return; }   // listener stopped

                if (!ctx.Request.IsWebSocketRequest) {
                    ctx.Response.StatusCode = 400;
                    ctx.Response.Close();
                    continue;
                }
                var client = new Thread(() => ClientLoop(ctx));
                client.IsBackground = true;
                client.Start();
            }
        }

        private static void ClientLoop(HttpListenerContext ctx) {
            int id = Interlocked.Increment(ref _nextId);
            WebSocket ws = null;
            try {
                ws = ctx.AcceptWebSocketAsync(null).Result.WebSocket;
                _clients[id] = ws;
                Post("CONNECT", id, "");

                byte[] buffer = new byte[4096];
                while (ws.State == WebSocketState.Open) {
                    // A message can arrive in several frames: keep reading until EndOfMessage
                    var message = new MemoryStream();
                    WebSocketReceiveResult r = null;
                    do {
                        r = ws.ReceiveAsync(new ArraySegment<byte>(buffer), CancellationToken.None).Result;
                        if (r.MessageType == WebSocketMessageType.Close) break;
                        message.Write(buffer, 0, r.Count);
                    } while (!r.EndOfMessage);

                    if (r.MessageType == WebSocketMessageType.Close) {
                        ws.CloseAsync(WebSocketCloseStatus.NormalClosure, "", CancellationToken.None).Wait();
                        break;
                    }
                    if (r.MessageType == WebSocketMessageType.Text)
                        Post("MSG", id, Encoding.UTF8.GetString(message.ToArray()));
                }
            } catch (Exception) {
                // the client dropped the connection
            }

            WebSocket removed;
            _clients.TryRemove(id, out removed);
            if (ws != null) ws.Dispose();
            Post("DISCONNECT", id, "");
        }

        // Blocks until something happens. Run it through .Async.
        public static string WaitForEvent() {
            try { return _events.Take(); }
            catch (InvalidOperationException) { return "STOPPED|0|"; }
        }

        public static void Send(int id, string msg) {
            WebSocket ws;
            if (!_clients.TryGetValue(id, out ws) || ws.State != WebSocketState.Open) return;
            try {
                byte[] buf = Encoding.UTF8.GetBytes(msg);
                ws.SendAsync(new ArraySegment<byte>(buf), WebSocketMessageType.Text, true, CancellationToken.None).Wait();
            } catch (Exception) { /* client is gone */ }
        }

        public static void Broadcast(string msg) {
            foreach (int id in _clients.Keys) Send(id, msg);
        }

        public static int ClientCount() {
            return _clients.Count;
        }

        public static void Stop() {
            _events.CompleteAdding();
            if (_listener != null) _listener.Close();
            foreach (var ws in _clients.Values) ws.Abort();
        }
    )'
}

; ── Start Server ──
; Do this before creating any UI so a busy port gives a clear message.
try {
    WSServer.Start("http://localhost:" PORT "/")
} catch as e {
    MsgBox("Could not start the WebSocket server on port " PORT ".`n`n"
        . "Another program (or another copy of this script) is probably using it. "
        . "Change PORT at the top of the script and run it again.`n`n"
        . "Details: " e.Message, "AHK# — WebSocket Server", 0x10)
    ExitApp()
}

OnExit((*) => WSServer.Stop())

; ── UI Setup ──
g := Gui("", "AHK# — WebSocket Server")
g.SetFont("s10", "Consolas")
g.Add("Text", "w400 cBlue", "Listening on ws://localhost:" PORT "/")
txtLog := g.Add("Edit", "w400 h200 ReadOnly", "")
g.Show()
g.OnEvent("Close", (*) => ExitApp())

AddLog(msg) {
    txtLog.Value := A_Hour ":" A_Min ":" A_Sec " - " msg "`r`n" txtLog.Value
}

AddLog("Server started. Awaiting connections...")

; ── Main Event Loop ──
Loop {
    ; Use AHK# Async to wait for events on a background thread without freezing the GUI!
    try {
        evt := WSServer.Async.WaitForEvent().Await()
    } catch {
        break
    }

    parts := StrSplit(evt, "|", , 3)   ; kind | client id | payload
    kind := parts[1]
    id := parts[2]
    msg := parts.Length >= 3 ? parts[3] : ""

    if (kind == "STOPPED")
        break

    if (kind == "CONNECT") {
        AddLog("Client #" id " connected (" WSServer.ClientCount() " online)")
        WSServer.Send(id, "Welcome! You are client #" id)
        continue
    }
    if (kind == "DISCONNECT") {
        AddLog("Client #" id " disconnected (" WSServer.ClientCount() " online)")
        continue
    }

    AddLog("Client #" id ": " msg)

    ; You can parse commands from the browser and trigger macros here!
    if (msg == "BEEP") {
        SoundBeep(750, 250)
        WSServer.Send(id, "Ahk beeped!")
    } else if (msg == "MOUSE") {
        MouseGetPos(&x, &y)
        WSServer.Send(id, "Mouse is at: " x ", " y)
    } else if (SubStr(msg, 1, 10) == "BROADCAST ") {
        WSServer.Broadcast("Client #" id " says: " SubStr(msg, 11))
    } else {
        WSServer.Send(id, "AHK received: " msg)
    }
}

ExitApp()
