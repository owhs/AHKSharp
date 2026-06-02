;; AHK# Example 36 — Windows Toast Notifications
;; AHK's TrayTip is ugly and limited. This creates real Windows 10/11
;; toast notifications via NotifyIcon — they appear in Action Center.
;;
;; Usage:
;;   Toast.Send("Title", "Body")
;;   Toast.Send("Warning!", "Disk full", "warning", 8000)
;;   Toast.Send("Error", "Build failed", "error")

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

; ── CSModule: Toast ───────────────────────────────────────────────────────────

class Toast extends _CSModule {
    static References := "System.Windows.Forms.dll;System.Drawing.dll"
    static CSharp := '
    (
        using System;
        using System.Drawing;
        using System.Threading;
        using System.Windows.Forms;
        using System.Collections.Generic;

        private static NotifyIcon _icon;
        private static Form _host;
        private static bool _ready = false;
        private static int _count = 0;
        private static List<string> _log = new List<string>();
        private static ManualResetEvent _initGate = new ManualResetEvent(false);

        private static void Boot() {
            if (_ready) return;

            Thread t = new Thread(() => {
                Application.EnableVisualStyles();
                _host = new Form();
                _host.ShowInTaskbar = false;
                _host.WindowState = FormWindowState.Minimized;
                _host.FormBorderStyle = FormBorderStyle.FixedToolWindow;
                _host.Opacity = 0;
                _host.Load += (s, e) => {
                    _host.Visible = false;
                    _icon = new NotifyIcon();
                    _icon.Icon = SystemIcons.Application;
                    _icon.Text = "AHK# Notifications";
                    _icon.Visible = true;
                    _ready = true;
                    _initGate.Set();
                };
                Application.Run(_host);
            });
            t.SetApartmentState(ApartmentState.STA);
            t.IsBackground = true;
            t.Start();
            _initGate.WaitOne(3000);
        }

        public static int Send(string title, string body, string iconType, int durationMs) {
            Boot();
            int id = Interlocked.Increment(ref _count);
            string ts = DateTime.Now.ToString("HH:mm:ss");
            _log.Add(string.Format("[{0}] {1}: {2} ({3})", ts, title, body, iconType));

            ToolTipIcon tip = ToolTipIcon.Info;
            if (iconType == "warning") tip = ToolTipIcon.Warning;
            else if (iconType == "error") tip = ToolTipIcon.Error;
            else if (iconType == "none") tip = ToolTipIcon.None;

            if (_host != null && _host.InvokeRequired) {
                _host.Invoke(new Action(() => {
                    _icon.ShowBalloonTip(durationMs, title, body, tip);
                }));
            } else if (_icon != null) {
                _icon.ShowBalloonTip(durationMs, title, body, tip);
            }
            return id;
        }

        public static void Schedule(string title, string body, string iconType, int delayMs) {
            Boot();
            var timer = new System.Threading.Timer((_) => {
                Send(title, body, iconType, 5000);
            }, null, delayMs, Timeout.Infinite);
        }

        public static string GetLog() {
            if (_log.Count == 0) return "(no notifications sent)";
            return string.Join("\n", _log);
        }

        public static int GetCount() {
            return _count;
        }

        public static void SetTooltip(string text) {
            Boot();
            if (_host != null && _host.InvokeRequired) {
                _host.Invoke(new Action(() => { _icon.Text = text; }));
            }
        }

        public static void Cleanup() {
            if (!_ready) return;
            try {
                _host.Invoke(new Action(() => {
                    _icon.Visible = false;
                    _icon.Dispose();
                    Application.ExitThread();
                }));
            } catch { }
            _ready = false;
        }
    )'
}

; ── Demo GUI ──────────────────────────────────────────────────────────────────

g := Gui("+Resize", "AHK# — Toast Notifications")
g.SetFont("s10", "Segoe UI")
g.BackColor := "0x1e1e2e"
g.SetFont("cCDD6F4")

; Header
g.SetFont("s13 cF38BA8 Bold")
g.Add("Text", "x20 y12 w440", Chr(0x1F514) " Toast Notification Center")
g.SetFont("s8 c585B70 Norm")
g.Add("Text", "x20 y36 w440", "Send real Windows Action Center notifications from AHK")

; ── Compose Section ───────────────────────────────────────────────────────────
g.SetFont("s10 cCDD6F4", "Segoe UI")
g.Add("GroupBox", "x12 y58 w456 h125 c585B70", " " Chr(0x270F) " Compose ")

g.Add("Text", "x25 y82 w50 Right", "Title:")
titleEdit := g.Add("Edit", "x80 y80 w375 h24 Background0x313244 cCDD6F4", "AHK# Alert")

g.Add("Text", "x25 y112 w50 Right", "Body:")
bodyEdit := g.Add("Edit", "x80 y110 w375 h24 Background0x313244 cCDD6F4", "Something happened!")

g.Add("Text", "x25 y142 w50 Right", "Type:")
iconDD := g.Add("DropDownList", "x80 y140 w100 Background0x313244 cCDD6F4", ["info", "warning", "error", "none"])
iconDD.Value := 1

g.Add("Text", "x195 y142 w55 Right c585B70", "Duration:")
durEdit := g.Add("Edit", "x255 y140 w70 h24 Background0x313244 cCDD6F4 Center", "5000")
g.SetFont("s8 c585B70")
g.Add("Text", "x328 y145", "ms")

; ── Action Buttons ────────────────────────────────────────────────────────────
g.SetFont("s10 cCDD6F4", "Segoe UI")
btnSend := g.Add("Button", "x12 y190 w110 h32", Chr(0x1F4E8) " Send Now")
btnSchedule := g.Add("Button", "x127 y190 w135 h32", Chr(0x23F0) " Schedule (3s)")

; Quick presets
g.SetFont("s9 c585B70")
g.Add("Text", "x275 y192 w5 h28", Chr(0x2502))
g.SetFont("s9 cCDD6F4", "Segoe UI")
btnSuccess := g.Add("Button", "x290 y190 w55 h32", Chr(0x2714))
btnWarn := g.Add("Button", "x350 y190 w55 h32", Chr(0x26A0))
btnError := g.Add("Button", "x410 y190 w55 h32", Chr(0x274C))

; ── Notification Log ──────────────────────────────────────────────────────────
g.SetFont("s10 cF38BA8")
g.Add("Text", "x12 y230", Chr(0x25CF) " Event Log")
g.SetFont("s9 c585B70")
countText := g.Add("Text", "x380 y232 w85 Right", "Sent: 0")

g.SetFont("s9", "Cascadia Mono")
logEdit := g.Add("Edit", "x12 y250 w456 h150 Multi ReadOnly Background0x181825 cA6E3A1 VScroll", "(no notifications sent)")

; ── Handlers ──────────────────────────────────────────────────────────────────

SendNotification() {
    title := titleEdit.Value
    body := bodyEdit.Value
    icon := iconDD.Text
    dur := Integer(durEdit.Value)
    Toast.Send(title, body, icon, dur)
    RefreshLog()
}

RefreshLog() {
    logEdit.Value := Toast.GetLog()
    countText.Value := "Sent: " Toast.GetCount()
}

btnSend.OnEvent("Click", (*) => SendNotification())
btnSchedule.OnEvent("Click", (*) => (
    Toast.Schedule(titleEdit.Value, bodyEdit.Value, iconDD.Text, 3000),
    logEdit.Value := Toast.GetLog() "`r`n(+1 scheduled in 3s)"
))
btnSuccess.OnEvent("Click", (*) => (
    Toast.Send("Success", "Operation completed!", "info", 4000),
    RefreshLog()
))
btnWarn.OnEvent("Click", (*) => (
    Toast.Send("Warning", "Disk space low on C:", "warning", 6000),
    RefreshLog()
))
btnError.OnEvent("Click", (*) => (
    Toast.Send("Error", "Build failed — 3 errors", "error", 8000),
    RefreshLog()
))

; Refresh log periodically (for scheduled notifications)
SetTimer(() => RefreshLog(), 1000)

g.OnEvent("Close", (*) => (Toast.Cleanup(), ExitApp()))
g.Show("w480 h412")

WinWaitClose(g.Hwnd)
ExitApp()

