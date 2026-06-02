;; AHK# Example 41 — XInput Gamepad
;; Read Xbox/gamepad input in AHK without any external libraries.
;; P/Invoke to xinput1_4.dll (ships with Windows 10+).
;;
;; Usage:
;;   connected := Gamepad.IsConnected(0)          ; player 1
;;   state := Gamepad.GetState(0)                 ; "buttons|LX|LY|RX|RY|LT|RT"
;;   Gamepad.Vibrate(0, 32000, 32000)             ; rumble!
;;   buttons := Gamepad.GetPressedButtons(0)      ; "A, B, RightShoulder"

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

; ── CSModule: Gamepad ─────────────────────────────────────────────────────────

class Gamepad extends _CSModule {
    static CSharp := '
    (
        using System;
        using System.Runtime.InteropServices;
        using System.Text;
        using System.Collections.Generic;

        [DllImport("xinput1_4.dll")]
        private static extern int XInputGetState(int userIndex, out XINPUT_STATE state);

        [DllImport("xinput1_4.dll")]
        private static extern int XInputSetState(int userIndex, ref XINPUT_VIBRATION vibration);

        [DllImport("xinput1_4.dll")]
        private static extern int XInputGetBatteryInformation(int userIndex, byte devType,
            out XINPUT_BATTERY_INFORMATION battery);

        [StructLayout(LayoutKind.Sequential)]
        private struct XINPUT_STATE {
            public int PacketNumber;
            public XINPUT_GAMEPAD Gamepad;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct XINPUT_GAMEPAD {
            public ushort Buttons;
            public byte LeftTrigger;
            public byte RightTrigger;
            public short ThumbLX;
            public short ThumbLY;
            public short ThumbRX;
            public short ThumbRY;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct XINPUT_VIBRATION {
            public ushort LeftMotorSpeed;
            public ushort RightMotorSpeed;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct XINPUT_BATTERY_INFORMATION {
            public byte BatteryType;
            public byte BatteryLevel;
        }

        // Button flags
        private const int DPAD_UP = 0x0001;
        private const int DPAD_DOWN = 0x0002;
        private const int DPAD_LEFT = 0x0004;
        private const int DPAD_RIGHT = 0x0008;
        private const int START = 0x0010;
        private const int BACK = 0x0020;
        private const int LEFT_THUMB = 0x0040;
        private const int RIGHT_THUMB = 0x0080;
        private const int LEFT_SHOULDER = 0x0100;
        private const int RIGHT_SHOULDER = 0x0200;
        private const int A_BTN = 0x1000;
        private const int B_BTN = 0x2000;
        private const int X_BTN = 0x4000;
        private const int Y_BTN = 0x8000;

        public static bool IsConnected(int index) {
            XINPUT_STATE state;
            return XInputGetState(index, out state) == 0;
        }

        public static string GetState(int index) {
            XINPUT_STATE state;
            if (XInputGetState(index, out state) != 0)
                return "";
            var g = state.Gamepad;
            return string.Format("{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}",
                g.Buttons, g.ThumbLX, g.ThumbLY, g.ThumbRX, g.ThumbRY,
                g.LeftTrigger, g.RightTrigger, state.PacketNumber);
        }

        public static string GetPressedButtons(int index) {
            XINPUT_STATE state;
            if (XInputGetState(index, out state) != 0) return "";

            int b = state.Gamepad.Buttons;
            var names = new List<string>();
            if ((b & A_BTN) != 0) names.Add("A");
            if ((b & B_BTN) != 0) names.Add("B");
            if ((b & X_BTN) != 0) names.Add("X");
            if ((b & Y_BTN) != 0) names.Add("Y");
            if ((b & DPAD_UP) != 0) names.Add("Up");
            if ((b & DPAD_DOWN) != 0) names.Add("Down");
            if ((b & DPAD_LEFT) != 0) names.Add("Left");
            if ((b & DPAD_RIGHT) != 0) names.Add("Right");
            if ((b & LEFT_SHOULDER) != 0) names.Add("LB");
            if ((b & RIGHT_SHOULDER) != 0) names.Add("RB");
            if ((b & LEFT_THUMB) != 0) names.Add("LS");
            if ((b & RIGHT_THUMB) != 0) names.Add("RS");
            if ((b & START) != 0) names.Add("Start");
            if ((b & BACK) != 0) names.Add("Back");

            return names.Count > 0 ? string.Join(", ", names) : "(none)";
        }

        public static void Vibrate(int index, int leftMotor, int rightMotor) {
            var vib = new XINPUT_VIBRATION();
            vib.LeftMotorSpeed = (ushort)Math.Min(leftMotor, 65535);
            vib.RightMotorSpeed = (ushort)Math.Min(rightMotor, 65535);
            XInputSetState(index, ref vib);
        }

        public static void StopVibrate(int index) {
            var vib = new XINPUT_VIBRATION();
            vib.LeftMotorSpeed = 0;
            vib.RightMotorSpeed = 0;
            XInputSetState(index, ref vib);
        }

        public static string GetBattery(int index) {
            XINPUT_BATTERY_INFORMATION bat;
            if (XInputGetBatteryInformation(index, 0, out bat) != 0)
                return "Unknown";

            string type = "Unknown";
            if (bat.BatteryType == 0) type = "Disconnected";
            else if (bat.BatteryType == 1) type = "Wired";
            else if (bat.BatteryType == 2) type = "Alkaline";
            else if (bat.BatteryType == 3) type = "NiMH";

            string level = "Unknown";
            if (bat.BatteryLevel == 0) level = "Empty";
            else if (bat.BatteryLevel == 1) level = "Low";
            else if (bat.BatteryLevel == 2) level = "Medium";
            else if (bat.BatteryLevel == 3) level = "Full";

            return type + " (" + level + ")";
        }

        public static string ScanAll() {
            var sb = new StringBuilder();
            for (int i = 0; i < 4; i++) {
                XINPUT_STATE state;
                bool connected = XInputGetState(i, out state) == 0;
                sb.AppendLine(string.Format("Player {0}: {1}", i + 1,
                    connected ? "Connected" : "Not connected"));
            }
            return sb.ToString().TrimEnd();
        }

        // Normalized values: -1.0 to 1.0 for sticks, 0.0 to 1.0 for triggers
        public static string GetNormalized(int index) {
            XINPUT_STATE state;
            if (XInputGetState(index, out state) != 0) return "";
            var g = state.Gamepad;
            double lx = Math.Max(-1.0, g.ThumbLX / 32767.0);
            double ly = Math.Max(-1.0, g.ThumbLY / 32767.0);
            double rx = Math.Max(-1.0, g.ThumbRX / 32767.0);
            double ry = Math.Max(-1.0, g.ThumbRY / 32767.0);
            double lt = g.LeftTrigger / 255.0;
            double rt = g.RightTrigger / 255.0;
            return string.Format("{0:F3}|{1:F3}|{2:F3}|{3:F3}|{4:F3}|{5:F3}",
                lx, ly, rx, ry, lt, rt);
        }
    )'
}

; ── Demo GUI: Live Gamepad Visualizer ─────────────────────────────────────────

g := Gui("+AlwaysOnTop", "AHK# — XInput Gamepad")
g.SetFont("s10", "Segoe UI")
g.BackColor := "0x1e1e2e"
g.SetFont("cCDD6F4")

; Header
g.SetFont("s13 cF38BA8 Bold")
g.Add("Text", "x15 y8 w470", Chr(0x1F3AE) " XInput Gamepad")
g.SetFont("s8 c585B70 Norm")
g.Add("Text", "x15 y32 w470", "Live Xbox / XInput controller visualizer — P/Invoke to xinput1_4.dll")

; Connection status
g.SetFont("s9 cCDD6F4", "Segoe UI")
connText := g.Add("Text", "x15 y52 w300 c585B70", "Scanning controllers...")
battText := g.Add("Text", "x320 y52 w170 c585B70 Right", "")

; Player select
g.Add("Text", "x15 y75", "Player:")
playerDD := g.Add("DropDownList", "x65 y73 w70 Background0x313244 cCDD6F4", ["1", "2", "3", "4"])
playerDD.Value := 1

; Buttons display
g.SetFont("s10")
g.Add("Text", "x15 y105 cF38BA8", "Buttons:")
btnText := g.Add("Text", "x80 y105 w400 cA6E3A1", "(none)")

; Button grid
g.SetFont("s14")
btnA := g.Add("Text", "x180 y137 w30 h30 Center c6C7086 Background0x313244", "A")
btnB := g.Add("Text", "x215 y137 w30 h30 Center c6C7086 Background0x313244", "B")
btnX := g.Add("Text", "x145 y137 w30 h30 Center c6C7086 Background0x313244", "X")
btnY := g.Add("Text", "x180 y105 w30 h30 Center c6C7086 Background0x313244", "Y")

; D-Pad
g.SetFont("s12")
dUp := g.Add("Text", "x50 y127 w24 h24 Center c6C7086 Background0x313244", Chr(0x25B2))
dDown := g.Add("Text", "x50 y172 w24 h24 Center c6C7086 Background0x313244", Chr(0x25BC))
dLeft := g.Add("Text", "x25 y150 w24 h24 Center c6C7086 Background0x313244", Chr(0x25C0))
dRight := g.Add("Text", "x75 y150 w24 h24 Center c6C7086 Background0x313244", Chr(0x25B6))

; Shoulders and triggers
g.SetFont("s9")
lbText := g.Add("Text", "x15 y202 w60 h20 Center c6C7086 Background0x313244", "LB")
rbText := g.Add("Text", "x215 y202 w60 h20 Center c6C7086 Background0x313244", "RB")

g.SetFont("s10")
g.Add("Text", "x15 y227 c585B70", "LT:")
ltBar := g.Add("Progress", "x40 y229 w80 h14 Background0x313244 c89B4FA", 0)
g.Add("Text", "x195 y227 c585B70", "RT:")
rtBar := g.Add("Progress", "x220 y229 w80 h14 Background0x313244 cF38BA8", 0)

; Sticks (text-based position display)
g.SetFont("s9 cCDD6F4")
g.Add("Text", "x15 y257 cF38BA8", "Left Stick:")
lsText := g.Add("Text", "x15 y275 w130 c6C7086", "X: 0.000  Y: 0.000")

g.Add("Text", "x170 y257 cF38BA8", "Right Stick:")
rsText := g.Add("Text", "x170 y275 w130 c6C7086", "X: 0.000  Y: 0.000")

; Vibration controls
g.Add("Text", "x15 y307 cF38BA8", "Vibration Test:")
g.SetFont("s9")
btnVibeLight := g.Add("Button", "x15 y327 w80 h25", "Light")
btnVibeMed := g.Add("Button", "x100 y327 w80 h25", "Medium")
btnVibeHeavy := g.Add("Button", "x185 y327 w80 h25", "Heavy")
btnVibeStop := g.Add("Button", "x270 y327 w60 h25", "Stop")

; Raw data
g.SetFont("s8 c585B70")
rawText := g.Add("Text", "x15 y362 w470", "Raw: ...")

; ── Input Loop (60fps) ────────────────────────────────────────────────────────

lastPacket := 0

SetBtnColor(ctrl, active) {
    if (active) {
        ctrl.Opt("c11111B Background0xA6E3A1")
    } else {
        ctrl.Opt("c6C7086 Background0x313244")
    }
    ctrl.Redraw()
}

UpdateInput() {
    global lastPacket
    idx := playerDD.Value - 1

    if (!Gamepad.IsConnected(idx)) {
        connText.Value := Chr(0x274C) " Controller " (idx + 1) " not connected"
        battText.Value := ""
        return
    }

    state := Gamepad.GetState(idx)
    if (state == "")
        return

    parts := StrSplit(state, "|")
    if (parts.Length < 8)
        return

    ; Skip if packet unchanged (optimization)
    pkt := Integer(parts[8])
    if (pkt == lastPacket)
        return
    lastPacket := pkt

    connText.Value := Chr(0x2705) " Controller " (idx + 1) " connected"
    battText.Value := Chr(0x1F50B) " " Gamepad.GetBattery(idx)

    ; Buttons
    btns := Integer(parts[1])
    SetBtnColor(btnA, btns & 0x1000)
    SetBtnColor(btnB, btns & 0x2000)
    SetBtnColor(btnX, btns & 0x4000)
    SetBtnColor(btnY, btns & 0x8000)
    SetBtnColor(dUp, btns & 0x0001)
    SetBtnColor(dDown, btns & 0x0002)
    SetBtnColor(dLeft, btns & 0x0004)
    SetBtnColor(dRight, btns & 0x0008)
    SetBtnColor(lbText, btns & 0x0100)
    SetBtnColor(rbText, btns & 0x0200)

    btnText.Value := Gamepad.GetPressedButtons(idx)

    ; Triggers (0-255 → 0-100)
    lt := Integer(parts[6])
    rt := Integer(parts[7])
    ltBar.Value := Round(lt / 255 * 100)
    rtBar.Value := Round(rt / 255 * 100)

    ; Sticks (normalized)
    norm := Gamepad.GetNormalized(idx)
    if (norm != "") {
        np := StrSplit(norm, "|")
        lsText.Value := "X: " np[1] "  Y: " np[2]
        rsText.Value := "X: " np[3] "  Y: " np[4]
    }

    rawText.Value := "Raw: " state
}

; 60fps polling
SetTimer(UpdateInput, 16)

; Vibration buttons
playerIdx() => playerDD.Value - 1
btnVibeLight.OnEvent("Click", (*) => Gamepad.Vibrate(playerIdx(), 10000, 10000))
btnVibeMed.OnEvent("Click", (*) => Gamepad.Vibrate(playerIdx(), 32000, 32000))
btnVibeHeavy.OnEvent("Click", (*) => Gamepad.Vibrate(playerIdx(), 65535, 65535))
btnVibeStop.OnEvent("Click", (*) => Gamepad.StopVibrate(playerIdx()))

; Scan all on startup
connText.Value := Gamepad.ScanAll()

g.OnEvent("Close", (*) => (Gamepad.StopVibrate(0), ExitApp()))
g.Show("w500 h390")

WinWaitClose(g.Hwnd)
ExitApp()
