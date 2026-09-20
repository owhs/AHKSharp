;; AHK# — CS.Import: Namespace Aliasing
;; Use CS.Import() to create short aliases for deeply-nested .NET namespaces.
;; This dramatically improves readability for repeated namespace access.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

; ── Without CS.Import (verbose) ──────────────────────────────────────────────
; CS.System.IO.File.WriteAllText("test.txt", "Hello")
; CS.System.IO.File.ReadAllText("test.txt")
; CS.System.IO.Directory.GetFiles("C:\", "*.txt")
; ... typing CS.System.IO every time gets old fast!

; ── With CS.Import (clean) ───────────────────────────────────────────────────
IO := CS.Import("System.IO")
Text := CS.Import("System.Text")
Crypto := CS.Import("System.Security.Cryptography")

; File operations with IO alias
tempFile := A_Temp "\ahk_import_test.txt"
IO.File.WriteAllText(tempFile, "Written by AHK# CS.Import at " A_Now)
content := IO.File.ReadAllText(tempFile)
MsgBox(content, "AHK# — IO.File")

; Check if file exists
exists := IO.File.Exists(tempFile)
info := IO.FileInfo(tempFile)
MsgBox("File exists: " exists "`nSize: " info.Length " bytes", "AHK# — IO.FileInfo")

; StringBuilder with Text alias
sb := Text.StringBuilder()
sb.Append("Hello")
sb.Append(" from ")
sb.Append("CS.Import!")
sb.AppendLine()
sb.Append("This is much cleaner.")
MsgBox(sb.ToString(), "AHK# — Text.StringBuilder")

; Encoding with Text alias
encoded := Text.Encoding.UTF8.GetBytes("AHK# v2.0")
MsgBox("UTF8 byte count: " encoded.Length, "AHK# — Text.Encoding")

; Hash with Crypto alias: SHA-256 of the same UTF-8 bytes
sha := Crypto.SHA256.Create()
hash := sha.ComputeHash(encoded)
hex := StrReplace(CS.System.BitConverter.ToString(hash), "-")
sha.Dispose()
MsgBox("SHA-256 of `"AHK# v2.0`":`n" hex, "AHK# — Crypto.SHA256")

msg := "Multiple namespace aliases, all clean and readable!"
MsgBox(msg, "AHK# — CS.Import Demo Complete", 0x40)

; Cleanup
IO.File.Delete(tempFile)

ExitApp()
