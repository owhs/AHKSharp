;; AHK# Example 22 — WMI Hardware Monitor
;; Querying WMI in native AHK via COM is slow, blocks the thread, and has ugly syntax.
;; C# can query WMI natively via System.Management extremely fast.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

class HardwareMonitor extends _CSModule {
    static References := "System.Management.dll"
    static CSharp := '
    (
        using System;
        using System.Management;
        using System.Collections.Generic;

        public static string[] GetHardwareStats() {
            var stats = new List<string>();
            
            try {
                // Get CPU Info
                using (var searcher = new ManagementObjectSearcher("SELECT Name, LoadPercentage FROM Win32_Processor")) {
                    foreach (ManagementObject obj in searcher.Get()) {
                        stats.Add("CPU: " + obj["Name"]);
                        stats.Add("CPU Load: " + obj["LoadPercentage"] + "%");
                    }
                }
                
                // Get Memory Info
                using (var searcher = new ManagementObjectSearcher("SELECT TotalVisibleMemorySize, FreePhysicalMemory FROM Win32_OperatingSystem")) {
                    foreach (ManagementObject obj in searcher.Get()) {
                        double total = Convert.ToDouble(obj["TotalVisibleMemorySize"]) / (1024 * 1024);
                        double free = Convert.ToDouble(obj["FreePhysicalMemory"]) / (1024 * 1024);
                        stats.Add("RAM Free: " + Math.Round(free, 2) + " GB / " + Math.Round(total, 2) + " GB");
                    }
                }
                
                // Get Disk Info
                using (var searcher = new ManagementObjectSearcher("SELECT Name, FreeSpace, Size FROM Win32_LogicalDisk WHERE DriveType=3")) {
                    foreach (ManagementObject obj in searcher.Get()) {
                        double free = Convert.ToDouble(obj["FreeSpace"]) / (1024 * 1024 * 1024);
                        double total = Convert.ToDouble(obj["Size"]) / (1024 * 1024 * 1024);
                        stats.Add("Drive " + obj["Name"] + " " + Math.Round(free, 1) + " GB Free");
                    }
                }
                
                // Get Temperatures (Requires Admin)
                try {
                    using (var searcher = new ManagementObjectSearcher("root\\WMI", "SELECT CurrentTemperature FROM MSAcpi_ThermalZoneTemperature")) {
                        foreach (ManagementObject obj in searcher.Get()) {
                            double kelvin = Convert.ToDouble(obj["CurrentTemperature"]);
                            double celcius = (kelvin / 10.0) - 273.15;
                            stats.Add("Temp: " + Math.Round(celcius, 1) + " °C");
                        }
                    }
                } catch {
                    stats.Add("Temp: (Run script as Admin to view)");
                }
            } catch (Exception ex) {
                stats.Add("Error: " + ex.Message);
            }
            
            return stats.ToArray();
        }
    )'
}

; ── UI Setup ──
g := Gui("", "AHK# — WMI Hardware Monitor")
g.SetFont("s11", "Segoe UI")
g.BackColor := "White"

lblStats := g.Add("Text", "w350 h200", "Loading hardware data...")
g.Show("w370")
g.OnEvent("Close", (*) => ExitApp())

UpdateStats() {
    ; Use AHK# Async so querying WMI doesn't lag the GUI dragging!
    HardwareMonitor.Async.GetHardwareStats().Then(OnDataReady)
}

OnDataReady(statsArray) {
    text := ""
    ; statsArray is returned from C# as a COM SafeArray, natively iterable in AHK!
    for item in statsArray {
        text .= "▪ " item "`r`n`r`n"
    }
    lblStats.Value := text
}

UpdateStats()
SetTimer(UpdateStats, 2000) ; Refresh every 2 seconds
