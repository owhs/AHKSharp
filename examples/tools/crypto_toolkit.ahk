;; AHK# Example 14 — Crypto Toolkit
;; Hashing, Base64, UUID — powered by System.Security.Cryptography.
;; In pure AHK you'd need 200+ lines of DllCall to BCrypt. AHK# = 5 lines.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

class Crypto extends _CSModule {
    static CSharp := "
    (
        using System;
        using System.Security.Cryptography;
        using System.Text;
        using System.Linq;

        static HashAlgorithm CreateHasher(string algorithm) {
            switch (algorithm.ToUpper()) {
                case "MD5":    return MD5.Create();
                case "SHA1":   return SHA1.Create();
                case "SHA256": return SHA256.Create();
                case "SHA512": return SHA512.Create();
                default:       return null;
            }
        }

        public static string Hash(string algorithm, string input) {
            // using() disposes the hasher (using on null is allowed for unknown algorithms)
            using (HashAlgorithm hasher = CreateHasher(algorithm)) {
                if (hasher == null) return "Unknown algorithm: " + algorithm;
                byte[] bytes = hasher.ComputeHash(Encoding.UTF8.GetBytes(input));
                return BitConverter.ToString(bytes).Replace("-", "").ToLower();
            }
        }

        public static string ToBase64(string input) {
            return Convert.ToBase64String(Encoding.UTF8.GetBytes(input));
        }

        public static string FromBase64(string input) {
            return Encoding.UTF8.GetString(Convert.FromBase64String(input));
        }

        public static string GeneratePassword(int length) {
            const string chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*";
            if (length <= 0) return "";

            // Rejection sampling: 256 is not a multiple of chars.Length, so a plain
            // "byte % chars.Length" would favour the first few characters. Only accept
            // bytes below the largest multiple of chars.Length that fits in a byte.
            int limit = 256 - (256 % chars.Length);
            char[] result = new char[length];
            byte[] data = new byte[Math.Max(length, 32)];
            int filled = 0;
            using (var rng = new RNGCryptoServiceProvider()) {
                while (filled < length) {
                    rng.GetBytes(data);
                    for (int i = 0; i < data.Length && filled < length; i++) {
                        if (data[i] < limit)
                            result[filled++] = chars[data[i] % chars.Length];
                    }
                }
            }
            return new string(result);
        }

        public static string HmacSha256(string key, string message) {
            using (var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(key))) {
                byte[] hash = hmac.ComputeHash(Encoding.UTF8.GetBytes(message));
                return BitConverter.ToString(hash).Replace("-", "").ToLower();
            }
        }
    )"
}

; ── GUI ───────────────────────────────────────────────────────────────────────

g := Gui("+Resize", "AHK# — Crypto Toolkit")
g.SetFont("s10", "Segoe UI")
g.BackColor := "0x1e1e2e"
g.SetFont("cCDD6F4")

g.Add("Text", "x10 y10 w80", "Input:")
inputEdit := g.Add("Edit", "x90 y8 w400 h24 Background0x313244 cCDD6F4", "Hello, AHK# World!")

g.SetFont("s9", "Cascadia Mono")
resultEdit := g.Add("Edit", "x10 y80 w480 h350 Multi ReadOnly Background0x181825 cA6E3A1")

g.SetFont("s10", "Segoe UI")
g.SetFont("cCDD6F4")
btnRun := g.Add("Button", "x10 y44 w100 h30", "▶ Compute")
btnRun.OnEvent("Click", (*) => RunCrypto())

RunCrypto() {
    input := inputEdit.Value
    if (input == "")
        return

    out := "═══ AHK# Crypto Toolkit ═══`n`n"

    ; Hashing
    out .= "─── Hash Functions ───`n"
    for algo in ["MD5", "SHA1", "SHA256", "SHA512"] {
        hash := Crypto.Hash(algo, input)
        out .= Format("  {:-6s}  {}`n", algo, hash)
    }

    ; Base64
    b64 := Crypto.ToBase64(input)
    decoded := Crypto.FromBase64(b64)
    out .= "`n─── Base64 ───`n"
        . "  Encoded:  " b64 "`n"
        . "  Decoded:  " decoded "`n"
        . "  Match:    " (decoded == input ? "✓ Perfect round-trip" : "✗ Mismatch") "`n"

    ; HMAC
    hmac := Crypto.HmacSha256("my-secret-key", input)
    out .= "`n─── HMAC-SHA256 ───`n"
        . "  Key:   my-secret-key`n"
        . "  HMAC:  " hmac "`n"

    ; Password generation
    out .= "`n─── Secure Passwords (RNGCryptoServiceProvider) ───`n"
    Loop 5 {
        pwd := Crypto.GeneratePassword(20)
        out .= "  " A_Index ". " pwd "`n"
    }

    ; GUIDs
    out .= "`n─── GUIDs ───`n"
    Loop 3 {
        guid := CS.System.Guid.NewGuid()
        out .= "  " guid "`n"
    }

    out .= "`n═══════════════════════════════════════`n"
        . "  All crypto ops powered by .NET BCL`n"
        . "  Zero DllCalls. Zero dependencies."

    resultEdit.Value := out
}

RunCrypto()
g.Show("w500 h440")
WinWaitClose(g.Hwnd)
ExitApp()
