;; AHK# Example 16 — File Hasher & Analyzer
;; Drop any file path to get instant hashes, metadata, and hex preview.
;; Uses System.IO + System.Security.Cryptography — no DllCalls needed.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

class FileAnalyzer extends _CSModule {
    static CSharp := "
    (
        using System;
        using System.IO;
        using System.Security.Cryptography;
        using System.Text;
        using System.Linq;

        public static string Analyze(string path) {
            if (!File.Exists(path))
                return "ERR|File not found: " + path;

            var fi = new FileInfo(path);
            var sb = new StringBuilder();

            // Metadata
            sb.AppendLine("NAME|" + fi.Name);
            sb.AppendLine("DIR|" + fi.DirectoryName);
            sb.AppendLine("SIZE|" + fi.Length);
            sb.AppendLine("SIZEH|" + FormatSize(fi.Length));
            sb.AppendLine("EXT|" + fi.Extension);
            sb.AppendLine("CREATED|" + fi.CreationTime.ToString("yyyy-MM-dd HH:mm:ss"));
            sb.AppendLine("MODIFIED|" + fi.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"));
            sb.AppendLine("READONLY|" + fi.IsReadOnly);

            // Hashes
            byte[] data = File.ReadAllBytes(path);
            sb.AppendLine("MD5|" + HashBytes(MD5.Create(), data));
            sb.AppendLine("SHA1|" + HashBytes(SHA1.Create(), data));
            sb.AppendLine("SHA256|" + HashBytes(SHA256.Create(), data));

            // Hex preview (first 256 bytes)
            int previewLen = Math.Min(data.Length, 256);
            var hex = new StringBuilder();
            for (int i = 0; i < previewLen; i += 16) {
                hex.Append(i.ToString("X8") + "  ");
                int end = Math.Min(i + 16, previewLen);
                for (int j = i; j < end; j++)
                    hex.Append(data[j].ToString("X2") + " ");
                for (int j = end; j < i + 16; j++)
                    hex.Append("   ");
                hex.Append(" ");
                for (int j = i; j < end; j++) {
                    char c = (char)data[j];
                    hex.Append(c >= 32 && c < 127 ? c : '.');
                }
                hex.AppendLine();
            }
            sb.AppendLine("HEX|" + hex.ToString());

            // Text detection
            bool isText = data.Length > 0 && data.Take(Math.Min(data.Length, 8192))
                .All(b => b == 9 || b == 10 || b == 13 || (b >= 32 && b < 127) || b > 127);
            sb.AppendLine("ISTEXT|" + isText);

            if (isText && data.Length < 100000) {
                string content = Encoding.UTF8.GetString(data);
                int lines = content.Split('\n').Length;
                int chars = content.Length;
                sb.AppendLine("LINES|" + lines);
                sb.AppendLine("CHARS|" + chars);
            }

            return sb.ToString();
        }

        static string HashBytes(HashAlgorithm ha, byte[] data) {
            return BitConverter.ToString(ha.ComputeHash(data)).Replace("-", "").ToLower();
        }

        static string FormatSize(long bytes) {
            string[] units = { "B", "KB", "MB", "GB", "TB" };
            double size = bytes;
            int unit = 0;
            while (size >= 1024 && unit < units.Length - 1) { size /= 1024; unit++; }
            return size.ToString("F1") + " " + units[unit];
        }
    )"
}

; ── GUI ───────────────────────────────────────────────────────────────────────

g := Gui("+Resize", "AHK# — File Hasher & Analyzer")
g.SetFont("s10", "Segoe UI")
g.BackColor := "0x1e1e2e"
g.SetFont("cCDD6F4")

g.Add("Text", "x10 y10", "File:")
pathEdit := g.Add("Edit", "x50 y8 w370 h24 Background0x313244 cCDD6F4"
    , A_ScriptFullPath)
btnBrowse := g.Add("Button", "x425 y7 w30 h26", "...")
btnAnalyze := g.Add("Button", "x460 y7 w35 h26", "▶")

g.SetFont("s9", "Cascadia Mono")
resultEdit := g.Add("Edit", "x10 y40 w485 h420 Multi ReadOnly Background0x181825 cA6E3A1")

btnBrowse.OnEvent("Click", (*) => DoBrowse())
btnAnalyze.OnEvent("Click", (*) => DoAnalyze())

DoBrowse() {
    f := FileSelect(1,, "Select a file to analyze")
    if (f != "") {
        pathEdit.Value := f
        DoAnalyze()
    }
}

DoAnalyze() {
    path := pathEdit.Value
    if (path == "")
        return

    resultEdit.Value := "Analyzing..."
    t := A_TickCount
    raw := FileAnalyzer.Analyze(path)

    if (SubStr(raw, 1, 3) == "ERR") {
        resultEdit.Value := StrReplace(raw, "ERR|", "Error: ")
        return
    }

    ; Parse the structured output
    data := Map()
    hexBlock := ""
    inHex := false
    Loop Parse, raw, "`n", "`r" {
        if (A_LoopField == "")
            continue
        if inHex {
            hexBlock .= A_LoopField "`n"
            continue
        }
        parts := StrSplit(A_LoopField, "|",, 2)
        if (parts.Length >= 2) {
            if (parts[1] == "HEX") {
                hexBlock := parts[2] "`n"
                inHex := true
            } else {
                data[parts[1]] := parts[2]
            }
        }
    }

    elapsed := A_TickCount - t

    out := "═══ FILE ANALYSIS ═══`n`n"
        . "  Name:     " (data.Has("NAME") ? data["NAME"] : "?") "`n"
        . "  Dir:      " (data.Has("DIR") ? data["DIR"] : "?") "`n"
        . "  Size:     " (data.Has("SIZEH") ? data["SIZEH"] : "?")
        . " (" (data.Has("SIZE") ? data["SIZE"] : "?") " bytes)`n"
        . "  Type:     " (data.Has("EXT") ? data["EXT"] : "?")
        . (data.Has("ISTEXT") && data["ISTEXT"] == "True" ? " (text)" : " (binary)") "`n"
        . "  Created:  " (data.Has("CREATED") ? data["CREATED"] : "?") "`n"
        . "  Modified: " (data.Has("MODIFIED") ? data["MODIFIED"] : "?") "`n"

    if (data.Has("LINES"))
        out .= "  Lines:    " data["LINES"] "  |  Chars: " data["CHARS"] "`n"

    out .= "`n─── HASHES ───`n"
        . "  MD5:    " (data.Has("MD5") ? data["MD5"] : "?") "`n"
        . "  SHA1:   " (data.Has("SHA1") ? data["SHA1"] : "?") "`n"
        . "  SHA256: " (data.Has("SHA256") ? data["SHA256"] : "?") "`n"

    out .= "`n─── HEX PREVIEW ───`n" hexBlock

    out .= "`n═══════════════════════════════════`n"
        . "  Analysis completed in " elapsed "ms"

    resultEdit.Value := out
}

DoAnalyze()
g.Show("w505 h470")
WinWaitClose(g.Hwnd)
ExitApp()
