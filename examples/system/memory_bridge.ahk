;; AHK# Example 38 — Process Memory Bridge
;; A mini Cheat Engine from AHK. Read/write any process memory,
;; list modules, scan for byte patterns (AOB), freeze values.
;;
;; Uses kernel32.dll P/Invoke: OpenProcess, ReadProcessMemory, WriteProcessMemory.
;;
;; Usage:
;;   pid := Memory.FindProcess("notepad")
;;   modules := Memory.ListModules(pid)
;;   value := Memory.ReadInt(pid, 0x12345678)
;;   Memory.WriteInt(pid, 0x12345678, 999)

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

; ── CSModule: Memory ──────────────────────────────────────────────────────────

class Memory extends _CSModule {
    static CSharp := '
    (
        using System;
        using System.Runtime.InteropServices;
        using System.Diagnostics;
        using System.Text;
        using System.Collections.Generic;
        
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr OpenProcess(int access, bool inherit, int pid);
        
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool ReadProcessMemory(IntPtr hProc, IntPtr addr,
            byte[] buf, int size, out int read);
        
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool WriteProcessMemory(IntPtr hProc, IntPtr addr,
            byte[] buf, int size, out int written);
        
        [DllImport("kernel32.dll")]
        private static extern bool CloseHandle(IntPtr handle);
        
        [DllImport("kernel32.dll")]
        private static extern int VirtualQueryEx(IntPtr hProc, IntPtr addr,
            out MEMORY_BASIC_INFORMATION mbi, int size);
        
        private const int PROCESS_VM_READ = 0x0010;
        private const int PROCESS_VM_WRITE = 0x0020;
        private const int PROCESS_VM_OPERATION = 0x0008;
        private const int PROCESS_QUERY_INFORMATION = 0x0400;
        private const int MEM_COMMIT = 0x1000;
        
        [StructLayout(LayoutKind.Sequential)]
        private struct MEMORY_BASIC_INFORMATION {
            public IntPtr BaseAddress;
            public IntPtr AllocationBase;
            public int AllocationProtect;
            public IntPtr RegionSize;
            public int State;
            public int Protect;
            public int Type;
        }
        
        public static string FindProcess(string name) {
            string clean = name.Replace(".exe", "");
            var procs = Process.GetProcessesByName(clean);
            if (procs.Length == 0) return "";
            var sb = new StringBuilder();
            foreach (var p in procs) {
                try {
                    sb.AppendLine(string.Format("{0}|{1}|{2}|{3}",
                        p.Id, p.ProcessName,
                        p.MainWindowTitle.Length > 0 ? p.MainWindowTitle : "(no window)",
                        FormatBytes(p.WorkingSet64)));
                } catch { }
            }
            return sb.ToString().TrimEnd();
        }
        
        public static string ListModules(int pid) {
            var sb = new StringBuilder();
            try {
                var proc = Process.GetProcessById(pid);
                sb.AppendLine(string.Format("{0,-16} {1,-18} {2,-12} {3}",
                    "Module", "Base Address", "Size", "Path"));
                sb.AppendLine(new string((char)0x2500, 80));
                foreach (ProcessModule m in proc.Modules) {
                    sb.AppendLine(string.Format("{0,-16} 0x{1:X8} {2,-12} {3}",
                        m.ModuleName.Length > 15 ? m.ModuleName.Substring(0, 15) : m.ModuleName,
                        m.BaseAddress.ToInt64(),
                        FormatBytes(m.ModuleMemorySize),
                        m.FileName));
                }
            } catch (Exception ex) {
                sb.AppendLine("Error: " + ex.Message);
            }
            return sb.ToString().TrimEnd();
        }
        
        public static int ReadInt(int pid, long address) {
            IntPtr h = OpenProcess(PROCESS_VM_READ, false, pid);
            if (h == IntPtr.Zero) return 0;
            try {
                byte[] buf = new byte[4];
                int read;
                ReadProcessMemory(h, new IntPtr(address), buf, 4, out read);
                return BitConverter.ToInt32(buf, 0);
            } finally { CloseHandle(h); }
        }
        
        public static float ReadFloat(int pid, long address) {
            IntPtr h = OpenProcess(PROCESS_VM_READ, false, pid);
            if (h == IntPtr.Zero) return 0;
            try {
                byte[] buf = new byte[4];
                int read;
                ReadProcessMemory(h, new IntPtr(address), buf, 4, out read);
                return BitConverter.ToSingle(buf, 0);
            } finally { CloseHandle(h); }
        }
        
        public static long ReadLong(int pid, long address) {
            IntPtr h = OpenProcess(PROCESS_VM_READ, false, pid);
            if (h == IntPtr.Zero) return 0;
            try {
                byte[] buf = new byte[8];
                int read;
                ReadProcessMemory(h, new IntPtr(address), buf, 8, out read);
                return BitConverter.ToInt64(buf, 0);
            } finally { CloseHandle(h); }
        }
        
        public static string ReadString(int pid, long address, int maxLen) {
            IntPtr h = OpenProcess(PROCESS_VM_READ, false, pid);
            if (h == IntPtr.Zero) return "";
            try {
                byte[] buf = new byte[maxLen];
                int read;
                ReadProcessMemory(h, new IntPtr(address), buf, maxLen, out read);
                int end = Array.IndexOf(buf, (byte)0);
                if (end < 0) end = read;
                return Encoding.ASCII.GetString(buf, 0, end);
            } finally { CloseHandle(h); }
        }
        
        public static string ReadBytes(int pid, long address, int count) {
            IntPtr h = OpenProcess(PROCESS_VM_READ, false, pid);
            if (h == IntPtr.Zero) return "";
            try {
                byte[] buf = new byte[count];
                int read;
                ReadProcessMemory(h, new IntPtr(address), buf, count, out read);
                return BitConverter.ToString(buf, 0, read);
            } finally { CloseHandle(h); }
        }
        
        public static bool WriteInt(int pid, long address, int value) {
            IntPtr h = OpenProcess(PROCESS_VM_WRITE | PROCESS_VM_OPERATION, false, pid);
            if (h == IntPtr.Zero) return false;
            try {
                byte[] buf = BitConverter.GetBytes(value);
                int written;
                return WriteProcessMemory(h, new IntPtr(address), buf, 4, out written);
            } finally { CloseHandle(h); }
        }
        
        public static bool WriteFloat(int pid, long address, float value) {
            IntPtr h = OpenProcess(PROCESS_VM_WRITE | PROCESS_VM_OPERATION, false, pid);
            if (h == IntPtr.Zero) return false;
            try {
                byte[] buf = BitConverter.GetBytes(value);
                int written;
                return WriteProcessMemory(h, new IntPtr(address), buf, 4, out written);
            } finally { CloseHandle(h); }
        }
        
        public static string ScanPattern(int pid, string hexPattern, long startAddr, long endAddr) {
            // AOB scan — search for byte pattern like "90 90 ?? FF"
            // ?? = wildcard byte
            string[] parts = hexPattern.Split(new char[] { (char)32 }, StringSplitOptions.RemoveEmptyEntries);
            byte[] pattern = new byte[parts.Length];
            bool[] mask = new bool[parts.Length];
            for (int i = 0; i < parts.Length; i++) {
                if (parts[i] == "??" || parts[i] == "?") {
                    mask[i] = true;
                    pattern[i] = 0;
                } else {
                    mask[i] = false;
                    pattern[i] = Convert.ToByte(parts[i], 16);
                }
            }
        
            IntPtr h = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, false, pid);
            if (h == IntPtr.Zero) return "Error: Cannot open process";
        
            try {
                var results = new List<string>();
                long addr = startAddr;
                MEMORY_BASIC_INFORMATION mbi;
        
                while (addr < endAddr && results.Count < 50) {
                    int ret = VirtualQueryEx(h, new IntPtr(addr), out mbi,
                        Marshal.SizeOf(typeof(MEMORY_BASIC_INFORMATION)));
                    if (ret == 0) break;
        
                    if (mbi.State == MEM_COMMIT && mbi.RegionSize.ToInt64() > 0) {
                        long regionSize = mbi.RegionSize.ToInt64();
                        if (regionSize > 0 && regionSize <= 64 * 1024 * 1024) {
                            byte[] buf = new byte[regionSize];
                            int read;
                            if (ReadProcessMemory(h, mbi.BaseAddress, buf, (int)regionSize, out read) && read > 0) {
                                for (int i = 0; i <= read - pattern.Length; i++) {
                                    bool match = true;
                                    for (int j = 0; j < pattern.Length; j++) {
                                        if (!mask[j] && buf[i + j] != pattern[j]) {
                                            match = false;
                                            break;
                                        }
                                    }
                                    if (match) {
                                        results.Add(string.Format("0x{0:X8}",
                                            mbi.BaseAddress.ToInt64() + i));
                                        if (results.Count >= 50) break;
                                    }
                                }
                            }
                        }
                    }
        
                    addr = mbi.BaseAddress.ToInt64() + mbi.RegionSize.ToInt64();
                    if (addr <= mbi.BaseAddress.ToInt64()) break;
                }
        
                if (results.Count == 0) return "No matches found";
                return string.Join("\n", results);
            } finally { CloseHandle(h); }
        }
        
        public static string GetMemoryMap(int pid) {
            IntPtr h = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, false, pid);
            if (h == IntPtr.Zero) return "Error: Cannot open process";
        
            try {
                var sb = new StringBuilder();
                sb.AppendLine(string.Format("{0,-18} {1,-12} {2,-10} {3}",
                    "Address", "Size", "State", "Protect"));
                sb.AppendLine(new string((char)0x2500, 55));
        
                long addr = 0;
                MEMORY_BASIC_INFORMATION mbi;
                int count = 0;
        
                while (count < 200) {
                    int ret = VirtualQueryEx(h, new IntPtr(addr), out mbi,
                        Marshal.SizeOf(typeof(MEMORY_BASIC_INFORMATION)));
                    if (ret == 0) break;
        
                    if (mbi.State == MEM_COMMIT) {
                        string protect = "---";
                        int p = mbi.Protect;
                        if ((p & 0x02) != 0) protect = "R--";
                        if ((p & 0x04) != 0) protect = "RW-";
                        if ((p & 0x10) != 0) protect = "--X";
                        if ((p & 0x20) != 0) protect = "R-X";
                        if ((p & 0x40) != 0) protect = "RWX";
        
                        sb.AppendLine(string.Format("0x{0:X8}  {1,-12} {2,-10} {3}",
                            mbi.BaseAddress.ToInt64(),
                            FormatBytes(mbi.RegionSize.ToInt64()),
                            "Commit", protect));
                    }
        
                    addr = mbi.BaseAddress.ToInt64() + mbi.RegionSize.ToInt64();
                    if (addr <= mbi.BaseAddress.ToInt64()) break;
                    count++;
                }
                return sb.ToString().TrimEnd();
            } finally { CloseHandle(h); }
        }
        
        private static string FormatBytes(long bytes) {
            if (bytes < 1024) return bytes + " B";
            if (bytes < 1024 * 1024) return (bytes / 1024.0).ToString("F1") + " KB";
            return (bytes / (1024.0 * 1024.0)).ToString("F1") + " MB";
        }
    )'
}

; ── Demo GUI ──────────────────────────────────────────────────────────────────

g := Gui("+Resize", "AHK# — Process Memory Bridge")
g.SetFont("s10", "Segoe UI")
g.BackColor := "0x1e1e2e"
g.SetFont("cCDD6F4")

; Header
g.SetFont("s13 cF38BA8 Bold")
g.Add("Text", "x20 y8 w540", Chr(0x1F50D) " Process Memory Bridge")
g.SetFont("s8 c585B70 Norm")
g.Add("Text", "x20 y32 w540", "Mini Cheat Engine — read/write process memory, AOB scan, module listing")

; Process selector
g.SetFont("s10 cCDD6F4", "Segoe UI")
g.Add("GroupBox", "x12 y50 w555 h55 c585B70", " " Chr(0x2699) " Target ")
g.Add("Text", "x25 y73", "Process:")
procEdit := g.Add("Edit", "x90 y71 w150 h24 Background0x313244 cCDD6F4", "notepad")
btnFind := g.Add("Button", "x245 y70 w70 h26", Chr(0x1F50E) " Find")
g.Add("Text", "x325 y73 c585B70", "PID:")
pidEdit := g.Add("Edit", "x355 y71 w80 h24 Background0x313244 cCDD6F4 ReadOnly Center")

; Tabs
tabs := g.Add("Tab3", "x10 y115 w555 h340 Background0x1e1e2e", ["Modules", "Read/Write", "AOB Scan", "Memory Map"])

; ── Tab 1: Modules ────────────────────────────────────────────────────────────
tabs.UseTab(1)
g.SetFont("s8", "Cascadia Mono")
modEdit := g.Add("Edit", "x15 y145 w540 h290 Multi ReadOnly Background0x181825 cA6E3A1 HScroll VScroll")

; ── Tab 2: Read/Write ─────────────────────────────────────────────────────────
tabs.UseTab(2)
g.SetFont("s10", "Segoe UI")
g.SetFont("cCDD6F4")
g.Add("Text", "x15 y145", "Address (hex):")
addrEdit := g.Add("Edit", "x120 y143 w160 h24 Background0x313244 cCDD6F4", "0x")

g.Add("Text", "x300 y145", "Type:")
typeDD := g.Add("DropDownList", "x340 y143 w90 Background0x313244 cCDD6F4", ["Int32", "Float", "Int64", "String", "Bytes"])
typeDD.Value := 1

btnRead := g.Add("Button", "x440 y142 w50 h26", "Read")
btnWrite := g.Add("Button", "x495 y142 w50 h26", "Write")

g.Add("Text", "x15 y175", "Value:")
valEdit := g.Add("Edit", "x120 y173 w425 h24 Background0x313244 cCDD6F4")

g.SetFont("s8", "Cascadia Mono")
g.Add("Text", "x15 y205 cF38BA8", Chr(0x25CF) " Hex Dump (32 bytes from address)")
hexEdit := g.Add("Edit", "x15 y225 w535 h130 Multi ReadOnly Background0x181825 c6C7086")

; ── Tab 3: AOB Scan ───────────────────────────────────────────────────────────
tabs.UseTab(3)
g.SetFont("s10", "Segoe UI")
g.SetFont("cCDD6F4")
g.Add("Text", "x15 y145", "Pattern:")
patternEdit := g.Add("Edit", "x80 y143 w330 h24 Background0x313244 cCDD6F4", "90 90 ?? FF")
btnScan := g.Add("Button", "x420 y142 w125 h26", Chr(0x1F50E) " Scan")

g.SetFont("s8 c585B70")
g.Add("Text", "x15 y173", "Use ?? for wildcard bytes. Example: 48 8B ?? 48 89")

g.SetFont("s8", "Cascadia Mono")
scanEdit := g.Add("Edit", "x15 y195 w535 h160 Multi ReadOnly Background0x181825 cA6E3A1")

; ── Tab 4: Memory Map ─────────────────────────────────────────────────────────
tabs.UseTab(4)
g.SetFont("s8", "Cascadia Mono")
mapEdit := g.Add("Edit", "x15 y145 w535 h290 Multi ReadOnly Background0x181825 c6C7086")

tabs.UseTab()

; ── Handlers ──────────────────────────────────────────────────────────────────

currentPid := 0

btnFind.OnEvent("Click", (*) => FindProc())
FindProc() {
    global currentPid
    result := Memory.FindProcess(procEdit.Value)
    if (result == "") {
        pidEdit.Value := "N/A"
        modEdit.Value := "Process not found: " procEdit.Value
        return
    }
    ; Take first match
    parts := StrSplit(StrSplit(result, "`n")[1], "|")
    currentPid := Integer(parts[1])
    pidEdit.Value := currentPid
    modEdit.Value := Memory.ListModules(currentPid)
    mapEdit.Value := Memory.GetMemoryMap(currentPid)
}

btnRead.OnEvent("Click", (*) => DoRead())
DoRead() {
    global currentPid
    if (currentPid == 0)
        return
    addr := addrEdit.Value
    if (SubStr(addr, 1, 2) == "0x")
        addr := "0x" SubStr(addr, 3)
    addrNum := Integer(addr)
    type := typeDD.Text

    if (type == "Int32")
        valEdit.Value := Memory.ReadInt(currentPid, addrNum)
    else if (type == "Float")
        valEdit.Value := Memory.ReadFloat(currentPid, addrNum)
    else if (type == "Int64")
        valEdit.Value := Memory.ReadLong(currentPid, addrNum)
    else if (type == "String")
        valEdit.Value := Memory.ReadString(currentPid, addrNum, 128)
    else if (type == "Bytes")
        valEdit.Value := Memory.ReadBytes(currentPid, addrNum, 16)

    hexEdit.Value := Memory.ReadBytes(currentPid, addrNum, 32)
}

btnWrite.OnEvent("Click", (*) => DoWrite())
DoWrite() {
    global currentPid
    if (currentPid == 0)
        return
    addrNum := Integer(addrEdit.Value)
    type := typeDD.Text
    val := valEdit.Value

    if (type == "Int32")
        Memory.WriteInt(currentPid, addrNum, Integer(val))
    else if (type == "Float")
        Memory.WriteFloat(currentPid, addrNum, Float(val))
}

btnScan.OnEvent("Click", (*) => DoScan())
DoScan() {
    global currentPid
    if (currentPid == 0)
        return
    scanEdit.Value := "Scanning... (this may take a moment)"
    result := Memory.ScanPattern(currentPid, patternEdit.Value, 0, 0x7FFFFFFF)
    scanEdit.Value := result
}

g.OnEvent("Close", (*) => ExitApp())
g.Show("w580 h470")

WinWaitClose(g.Hwnd)
ExitApp()