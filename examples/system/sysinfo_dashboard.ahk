;; AHK# Example 12 — Live System Dashboard
;; Real-time system monitoring powered by .NET — impossible in pure AHK.
;; Shows CPU cores, RAM, environment, drives, and running processes.
;; ~80 lines of AHK# vs ~500+ lines of raw DllCall/WMI equivalent.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

; ── All system data gathered by a single C# module ────────────────────────────

class SysInfo extends _CSModule {
    static CSharp := "
    (
        using System;
        using System.IO;
        using System.Diagnostics;
        using System.Linq;
        using System.Text;

        public static string Dashboard() {
            var sb = new StringBuilder();
            var env = Environment.MachineName;

            sb.AppendLine("MACHINE|" + Environment.MachineName);
            sb.AppendLine("USER|" + Environment.UserName);
            sb.AppendLine("OS|" + Environment.OSVersion.ToString());
            sb.AppendLine("CLR|" + Environment.Version.ToString());
            sb.AppendLine("CORES|" + Environment.ProcessorCount);
            sb.AppendLine("ARCH|" + (Environment.Is64BitOperatingSystem ? "64-bit" : "32-bit"));
            sb.AppendLine("UPTIME|" + (Environment.TickCount / 3600000.0).ToString("F1"));
            sb.AppendLine("SYSDIR|" + Environment.SystemDirectory);

            // Drives
            foreach (var d in DriveInfo.GetDrives().Where(d => d.IsReady)) {
                double totalGB = d.TotalSize / 1073741824.0;
                double freeGB  = d.AvailableFreeSpace / 1073741824.0;
                double usedPct = (1.0 - freeGB / totalGB) * 100;
                sb.AppendFormat("DRIVE|{0}|{1}|{2:F1}|{3:F1}|{4:F0}\n",
                    d.Name.TrimEnd('\\'), d.DriveFormat, totalGB, freeGB, usedPct);
            }

            // Top processes
            var procs = Process.GetProcesses()
                .OrderByDescending(p => { try { return p.WorkingSet64; } catch { return 0L; } })
                .Take(12);
            foreach (var p in procs) {
                double mb = 0;
                try { mb = p.WorkingSet64 / 1048576.0; } catch {}
                sb.AppendFormat("PROC|{0}|{1}|{2:F1}\n", p.ProcessName, p.Id, mb);
            }

            return sb.ToString();
        }
    )"
}

; ── Parse and format the dashboard ────────────────────────────────────────────

raw := SysInfo.Dashboard()
data := Map()
drives := []
procs := []

Loop Parse, raw, "`n", "`r" {
    if (A_LoopField == "")
        continue
    parts := StrSplit(A_LoopField, "|")
    key := parts[1]
    if (key == "DRIVE" && parts.Length >= 6)
        drives.Push(parts)
    else if (key == "PROC" && parts.Length >= 4)
        procs.Push(parts)
    else if (parts.Length >= 2)
        data[key] := parts[2]
}

; Build display
info := "═══════════════════════════════════════════════`n"
    . "          AHK#  SYSTEM  DASHBOARD`n"
    . "═══════════════════════════════════════════════"

info .= "`n`n  ◆ Machine:    " data["MACHINE"]
    . "`n  ◆ User:       " data["USER"]
    . "`n  ◆ OS:         " data["OS"]
    . "`n  ◆ CLR:        " data["CLR"]
    . "`n  ◆ Cores:      " data["CORES"] " (" data["ARCH"] ")"
    . "`n  ◆ Uptime:     " data["UPTIME"] " hours"
    . "`n  ◆ System Dir: " data["SYSDIR"]

; Drive table
Pad(s, w) => SubStr(s "                              ", 1, w)
PadR(s, w) => SubStr("                    " s, -w+1)

info .= "`n`n─── DISK DRIVES ──────────────────────────────"
info .= "`n  " Pad("Drive", 8) Pad("Format", 8) PadR("Total", 8) PadR("Free", 8) PadR("Used", 6)
for d in drives
    info .= "`n  " Pad(d[2], 8) Pad(d[3], 8) PadR(d[4] "GB", 8) PadR(d[5] "GB", 8) PadR(d[6] "%", 6)

; Process table
info .= "`n`n─── TOP PROCESSES (by RAM) ───────────────────"
info .= "`n  " Pad("Process", 28) PadR("PID", 8) PadR("RAM", 10)
for p in procs
    info .= "`n  " Pad(SubStr(p[2], 1, 26), 28) PadR(p[3], 8) PadR(p[4] " MB", 10)

info .= "`n`n═══════════════════════════════════════════════"
    . "`n  Rendered by AHK# — " FormatTime(, "yyyy-MM-dd HH:mm:ss")

g := Gui("+Resize", "AHK# — System Dashboard")
g.BackColor := "0x1e1e2e"
g.SetFont("s9 cCDD6F4", "Cascadia Mono")
g.Add("Edit", "w540 h600 ReadOnly -Border Background0x1e1e2e", info)
g.Show("w560 h620")

WinWaitClose(g.Hwnd)
ExitApp()
