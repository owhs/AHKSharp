;; AHK# — Hello .NET
;; Demonstrates basic CLR interop: static methods, constructors, fluid chaining.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

; ── Static Method Calls ──────────────────────────────────────────────────────
result := CS.System.Math.Pow(5, 3)
MsgBox("Math.Pow(5, 3) = " result, "AHK# — Static Method")

; ── String Builder — Constructor + Fluid Chaining ────────────────────────────
sb := CS.System.Text.StringBuilder()
sb.Append("Hello")
sb.Append(", ")
sb.Append("World from AHK#!")
MsgBox(sb.ToString(), "AHK# — StringBuilder")

; ── File I/O via .NET ────────────────────────────────────────────────────────
tempFile := A_Temp "\ahk_sharp_test.txt"
CS.System.IO.File.WriteAllText(tempFile, "Written by AHK# at " A_Now)
content := CS.System.IO.File.ReadAllText(tempFile)
MsgBox(content, "AHK# — File I/O")

; ── Environment Info ─────────────────────────────────────────────────────────
machineName := CS.System.Environment.MachineName
osVersion := CS.System.Environment.OSVersion.ToString()
processorCount := CS.System.Environment.ProcessorCount
MsgBox("Machine: " machineName "`nOS: " osVersion "`nCPUs: " processorCount
    , "AHK# — Environment")

; ── Regex via .NET ───────────────────────────────────────────────────────────
match := CS.System.Text.RegularExpressions.Regex.Match("Hello World 2025", "\d+")
MsgBox("Regex match: " match.Value, "AHK# — Regex")

; ── Guid Generation ──────────────────────────────────────────────────────────
guid := CS.System.Guid.NewGuid()
MsgBox("New GUID: " guid, "AHK# — Guid")

MsgBox("That's the basics: static calls, constructors, properties and regex, all straight from AHK.", "AHK# — Complete", 0x40)
ExitApp()
