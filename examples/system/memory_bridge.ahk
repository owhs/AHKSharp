;; AHK# Example 38 — Cheat Engine Sharp
;; A full-featured Cheat Engine clone written in AutoHotkey and C#.
;; Features multi-tab process selection, fast block-based memory scanning,
;; address freezes, pointer paths, and standalone trainer script generation.
;;
;; Required library: ahk#.ahk
;;
;; DISCLAIMER: Use only on processes you own or are explicitly authorized to inspect
;; and modify (e.g. your own programs, memory_target_mock.ahk, or single-player
;; software you may legally debug). Reading/writing another program's memory can
;; crash it or corrupt its data, may violate a game's Terms of Service / EULA, and
;; will be flagged by anti-cheat systems (possible account bans). Never use it on
;; online or competitive games. You are responsible for how you use this tool.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

; Log unhandled errors to A_Temp for later inspection, but do NOT swallow them:
; returning 0 lets AutoHotkey show its normal error dialog.
OnError(LogUnhandledError)
LogUnhandledError(exception, mode) {
    try FileAppend("CRASH " A_Now ": " exception.Message "`n" exception.Extra "`n" exception.File ":" exception.Line "`n`n", A_Temp "\memory_bridge_crash.log")
    return 0
}

; ── CSModule: Memory ──────────────────────────────────────────────────────────

class Memory extends _CSModule {
}

Memory.CSharp := '
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
    
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool IsWow64Process(IntPtr hProcess, out bool wow64Process);
    
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint processId);
    
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool Module32First(IntPtr hSnapshot, ref MODULEENTRY32 lpme);
    
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool Module32Next(IntPtr hSnapshot, ref MODULEENTRY32 lpme);
    
    [StructLayout(LayoutKind.Sequential)]
    private struct MEMORY_BASIC_INFORMATION32 {
        public IntPtr BaseAddress;
        public IntPtr AllocationBase;
        public int AllocationProtect;
        public uint RegionSize;
        public int State;
        public int Protect;
        public int Type;
    }
    
    [StructLayout(LayoutKind.Sequential)]
    private struct MEMORY_BASIC_INFORMATION64 {
        public IntPtr BaseAddress;
        public IntPtr AllocationBase;
        public int AllocationProtect;
        public int __alignment1;
        public ulong RegionSize;
        public int State;
        public int Protect;
        public int Type;
        public int __alignment2;
    }
    
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    private struct MODULEENTRY32 {
        public uint dwSize;
        public uint th32ModuleID;
        public uint th32ProcessID;
        public uint GlblcntUsage;
        public uint ProccntUsage;
        public IntPtr modBaseAddr;
        public uint modBaseSize;
        public IntPtr hModule;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string szModule;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
        public string szExePath;
    }
    
    private struct UniversalMbi {
        public IntPtr BaseAddress;
        public ulong RegionSize;
        public int State;
        public int Protect;
    }
    
    [DllImport("kernel32.dll", EntryPoint = "VirtualQueryEx")]
    private static extern int VirtualQueryEx32(IntPtr hProc, IntPtr addr, out MEMORY_BASIC_INFORMATION32 mbi, int size);
    
    [DllImport("kernel32.dll", EntryPoint = "VirtualQueryEx")]
    private static extern int VirtualQueryEx64(IntPtr hProc, IntPtr addr, out MEMORY_BASIC_INFORMATION64 mbi, int size);
    
    private const int PROCESS_VM_READ = 0x0010;
    private const int PROCESS_VM_WRITE = 0x0020;
    private const int PROCESS_VM_OPERATION = 0x0008;
    private const int PROCESS_QUERY_INFORMATION = 0x0400;
    private const int MEM_COMMIT = 0x1000;
    
    private const uint TH32CS_SNAPMODULE = 0x00000008;
    private const uint TH32CS_SNAPMODULE32 = 0x00000010;
    
    private static bool QueryMemory(IntPtr hProc, IntPtr addr, out UniversalMbi uni) {
        uni = new UniversalMbi();
        if (IntPtr.Size == 8) {
            MEMORY_BASIC_INFORMATION64 mbi64;
            int ret = VirtualQueryEx64(hProc, addr, out mbi64, Marshal.SizeOf(typeof(MEMORY_BASIC_INFORMATION64)));
            if (ret == 0) return false;
            uni.BaseAddress = mbi64.BaseAddress;
            uni.RegionSize = mbi64.RegionSize;
            uni.State = mbi64.State;
            uni.Protect = mbi64.Protect;
            return true;
        } else {
            MEMORY_BASIC_INFORMATION32 mbi32;
            int ret = VirtualQueryEx32(hProc, addr, out mbi32, Marshal.SizeOf(typeof(MEMORY_BASIC_INFORMATION32)));
            if (ret == 0) return false;
            uni.BaseAddress = mbi32.BaseAddress;
            uni.RegionSize = mbi32.RegionSize;
            uni.State = mbi32.State;
            uni.Protect = mbi32.Protect;
            return true;
        }
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
    
    // Start time of a process (ticks), used to detect that a PID was recycled by another process.
    // Returns 0 when it cannot be determined (exited, or access denied).
    public static long GetProcessStartTicks(int pid) {
        try { return Process.GetProcessById(pid).StartTime.Ticks; } catch { return 0; }
    }

    public static string GetAllProcesses() {
        var sb = new StringBuilder();
        foreach (var p in Process.GetProcesses()) {
            try {
                string title = p.MainWindowTitle;
                sb.AppendLine(string.Format("{0}|{1}|{2}|{3}",
                    p.Id, p.ProcessName,
                    title.Length > 0 ? title.Replace("|", " ") : "",
                    FormatBytes(p.WorkingSet64)));
            } catch {}
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
        } catch {
            // Toolhelp fallback
            IntPtr snap = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, (uint)pid);
            if (snap != (IntPtr)(-1) && snap != IntPtr.Zero) {
                try {
                    var me = new MODULEENTRY32();
                    me.dwSize = (uint)Marshal.SizeOf(typeof(MODULEENTRY32));
                    sb.AppendLine(string.Format("{0,-16} {1,-18} {2,-12}", "Module", "Base Address", "Size"));
                    sb.AppendLine(new string((char)0x2500, 50));
                    if (Module32First(snap, ref me)) {
                        do {
                            sb.AppendLine(string.Format("{0,-16} 0x{1:X8} {2,-12}",
                                me.szModule.Length > 15 ? me.szModule.Substring(0, 15) : me.szModule,
                                me.modBaseAddr.ToInt64(),
                                FormatBytes(me.modBaseSize)));
                        } while (Module32Next(snap, ref me));
                    }
                } catch (Exception ex) {
                    sb.AppendLine("Error: " + ex.Message);
                } finally { CloseHandle(snap); }
            } else {
                sb.AppendLine("Error: Cannot list modules.");
            }
        }
        return sb.ToString().TrimEnd();
    }
    
    // ── Module Cache System ──────────────────────────────────────────────
    private static Dictionary<string, long> _moduleCache = new Dictionary<string, long>(StringComparer.OrdinalIgnoreCase);
    private static int _cachedPid = 0;
    
    private static bool? _is64Bit = null;
    private static int _archPid = 0;
    
    private static void ClearCacheIfPidChanged(int pid) {
        if (_cachedPid != pid) {
            _moduleCache.Clear();
            _cachedPid = pid;
        }
        if (_archPid != pid) {
            _is64Bit = null;
            _archPid = pid;
        }
    }
    
    public static long GetModuleBase(int pid, string moduleName) {
        lock (_moduleCache) {
            ClearCacheIfPidChanged(pid);
            if (_moduleCache.ContainsKey(moduleName)) {
                return _moduleCache[moduleName];
            }
            long baseAddr = GetModuleBaseInternal(pid, moduleName);
            if (baseAddr != 0) {
                _moduleCache[moduleName] = baseAddr;
            }
            return baseAddr;
        }
    }
    
    private static long GetModuleBaseInternal(int pid, string moduleName) {
        try {
            var proc = Process.GetProcessById(pid);
            foreach (ProcessModule m in proc.Modules) {
                if (m.ModuleName.Equals(moduleName, StringComparison.OrdinalIgnoreCase) || 
                    m.ModuleName.Replace(".exe", "").Equals(moduleName.Replace(".exe", ""), StringComparison.OrdinalIgnoreCase)) {
                    return m.BaseAddress.ToInt64();
                }
            }
        } catch {
            IntPtr snap = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, (uint)pid);
            if (snap != (IntPtr)(-1) && snap != IntPtr.Zero) {
                try {
                    var me = new MODULEENTRY32();
                    me.dwSize = (uint)Marshal.SizeOf(typeof(MODULEENTRY32));
                    if (Module32First(snap, ref me)) {
                        do {
                            if (me.szModule.Equals(moduleName, StringComparison.OrdinalIgnoreCase) ||
                                me.szModule.Replace(".exe", "").Equals(moduleName.Replace(".exe", ""), StringComparison.OrdinalIgnoreCase)) {
                                return me.modBaseAddr.ToInt64();
                            }
                        } while (Module32Next(snap, ref me));
                    }
                } catch {}
                finally { CloseHandle(snap); }
            }
        }
        return 0;
    }
    
    public static bool IsProcess64Bit(int pid) {
        lock (_moduleCache) {
            ClearCacheIfPidChanged(pid);
            if (_is64Bit.HasValue) {
                return _is64Bit.Value;
            }
            bool result = IsProcess64BitInternal(pid);
            _is64Bit = result;
            return result;
        }
    }
    
    private static bool IsProcess64BitInternal(int pid) {
        IntPtr h = OpenProcess(PROCESS_QUERY_INFORMATION, false, pid);
        if (h == IntPtr.Zero) return IntPtr.Size == 8;
        try {
            bool wow64;
            if (IsWow64Process(h, out wow64)) {
                return Environment.Is64BitOperatingSystem ? !wow64 : false;
            }
            return IntPtr.Size == 8;
        } finally { CloseHandle(h); }
    }
    
    public static long ResolvePointer(int pid, long baseAddress, long[] offsets, bool is64Bit) {
        IntPtr h = OpenProcess(PROCESS_VM_READ, false, pid);
        if (h == IntPtr.Zero) return 0;
        try {
            long currentAddr = baseAddress;
            int ptrSize = is64Bit ? 8 : 4;
            byte[] buf = new byte[ptrSize];
            
            for (int i = 0; i < offsets.Length; i++) {
                int read;
                if (!ReadProcessMemory(h, new IntPtr(currentAddr), buf, ptrSize, out read) || read != ptrSize) {
                    return 0;
                }
                currentAddr = is64Bit ? BitConverter.ToInt64(buf, 0) : BitConverter.ToUInt32(buf, 0);
                if (currentAddr == 0) return 0;
                currentAddr += offsets[i];
            }
            return currentAddr;
        } finally { CloseHandle(h); }
    }
    
    public static long ResolveAddressString(int pid, string addrStr) {
        addrStr = addrStr.Trim();
        if (addrStr.Length == 0) return 0;
        
        if (addrStr.StartsWith("[") && addrStr.EndsWith("]")) {
            string inner = addrStr.Substring(1, addrStr.Length - 2);
            string[] parts = inner.Split(',');
            if (parts.Length == 0) return 0;
            
            long baseAddr = ResolveSingleAddress(pid, parts[0]);
            if (baseAddr == 0) return 0;
            
            var offsets = new List<long>();
            for (int i = 1; i < parts.Length; i++) {
                offsets.Add(SafeParseHexOrDec(parts[i]));
            }
            
            return ResolvePointer(pid, baseAddr, offsets.ToArray(), IsProcess64Bit(pid));
        }
        
        return ResolveSingleAddress(pid, addrStr);
    }
    
    private static long ResolveSingleAddress(int pid, string s) {
        s = s.Trim();
        if (s.Length == 0) return 0;
        
        int plusIdx = s.IndexOf('+');
        if (plusIdx >= 0) {
            string modName = s.Substring(0, plusIdx).Trim();
            string offsetStr = s.Substring(plusIdx + 1).Trim();
            long baseAddr = GetModuleBase(pid, modName);
            if (baseAddr == 0) {
                try { return ParseHexOrDec(s); } catch { return 0; }
            }
            return baseAddr + SafeParseHexOrDec(offsetStr);
        }
        
        long modBase = GetModuleBase(pid, s);
        if (modBase != 0) return modBase;
        
        try { return ParseHexOrDec(s); } catch { return 0; }
    }
    
    private static long SafeParseHexOrDec(string s) {
        try { return ParseHexOrDec(s); } catch { return 0; }
    }
    
    private static long ParseHexOrDec(string s) {
        s = s.Trim();
        if (s.StartsWith("0x", StringComparison.OrdinalIgnoreCase)) {
            return Convert.ToInt64(s.Substring(2), 16);
        }
        try {
            return Convert.ToInt64(s, 10);
        } catch {
            return Convert.ToInt64(s, 16);
        }
    }
    
    public static string ReadValue(int pid, long address, string valType) {
        IntPtr h = OpenProcess(PROCESS_VM_READ, false, pid);
        if (h == IntPtr.Zero) return "??";
        try {
            if (valType == "String") {
                byte[] buf = new byte[128];
                int read;
                if (ReadProcessMemory(h, new IntPtr(address), buf, buf.Length, out read) && read > 0) {
                    int zeroIdx = Array.IndexOf(buf, (byte)0);
                    int len = zeroIdx >= 0 ? zeroIdx : read;
                    return Encoding.UTF8.GetString(buf, 0, len);
                }
                return "??";
            } else if (valType == "Array of Byte") {
                byte[] buf = new byte[16];
                int read;
                if (ReadProcessMemory(h, new IntPtr(address), buf, buf.Length, out read) && read > 0) {
                    return BitConverter.ToString(buf, 0, read).Replace("-", " ");
                }
                return "??";
            } else {
                int size = GetTypeSize(valType);
                byte[] buf = new byte[size];
                int read;
                if (ReadProcessMemory(h, new IntPtr(address), buf, size, out read) && read == size) {
                    string valStr;
                    DecodeToBits(buf, valType, out valStr);
                    return valStr;
                }
                return "??";
            }
        } finally { CloseHandle(h); }
    }
    
    public static bool WriteValue(int pid, long address, string valType, string valueStr) {
        IntPtr h = OpenProcess(PROCESS_VM_WRITE | PROCESS_VM_OPERATION, false, pid);
        if (h == IntPtr.Zero) return false;
        try {
            byte[] buf = null;
            if (valType == "Byte") buf = new byte[] { byte.Parse(valueStr) };
            else if (valType == "2 Bytes") buf = BitConverter.GetBytes(short.Parse(valueStr));
            else if (valType == "4 Bytes") buf = BitConverter.GetBytes(int.Parse(valueStr));
            else if (valType == "8 Bytes") buf = BitConverter.GetBytes(long.Parse(valueStr));
            else if (valType == "Float") buf = BitConverter.GetBytes(float.Parse(valueStr));
            else if (valType == "Double") buf = BitConverter.GetBytes(double.Parse(valueStr));
            else if (valType == "String") buf = Encoding.UTF8.GetBytes(valueStr);
            else if (valType == "Array of Byte") {
                string[] parts = valueStr.Split(new char[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
                buf = new byte[parts.Length];
                for (int i = 0; i < parts.Length; i++) {
                    buf[i] = Convert.ToByte(parts[i], 16);
                }
            }
            
            if (buf == null) return false;
            int written;
            return WriteProcessMemory(h, new IntPtr(address), buf, buf.Length, out written);
        } finally { CloseHandle(h); }
    }
    
    // ── High Performance Scanner (Thread Safe & Asynchronous) ──────────────────────
    
    public static List<long> Matches = new List<long>();
    public static List<long> Values = new List<long>();
    private static List<long[]> HistoryAddresses = new List<long[]>();
    private static List<long[]> HistoryValues = new List<long[]>();
    
    private static System.Threading.Thread _scanThread = null;
    private static volatile bool _isScanning = false;
    private static volatile int _scanProgress = 0;
    private static volatile string _scanError = "";
    private static volatile bool _cancelScan = false;
    
    // Regions larger than 64 MB are not scanned; the UI reports them after the scan.
    private static volatile int _skippedLargeRegions = 0;
    private static long _skippedLargeBytes = 0;
    public static int GetSkippedRegionCount() { return _skippedLargeRegions; }
    public static long GetSkippedRegionBytes() { return _skippedLargeBytes; }

    public static bool IsScanning() { return _isScanning; }
    public static int GetScanProgress() { return _scanProgress; }
    public static string GetScanError() { return _scanError; }
    public static void CancelScan() { _cancelScan = true; }
    
    public static void ClearScan() {
        lock (Matches) {
            Matches.Clear();
            Values.Clear();
            HistoryAddresses.Clear();
            HistoryValues.Clear();
        }
    }
    
    private static void SaveHistory() {
        HistoryAddresses.Add(Matches.ToArray());
        HistoryValues.Add(Values.ToArray());
        if (HistoryAddresses.Count > 5) {
            HistoryAddresses.RemoveAt(0);
            HistoryValues.RemoveAt(0);
        }
    }
    
    public static int UndoScan() {
        lock (Matches) {
            if (HistoryAddresses.Count > 0) {
                int lastIdx = HistoryAddresses.Count - 1;
                Matches = new List<long>(HistoryAddresses[lastIdx]);
                Values = new List<long>(HistoryValues[lastIdx]);
                HistoryAddresses.RemoveAt(lastIdx);
                HistoryValues.RemoveAt(lastIdx);
            }
            return Matches.Count;
        }
    }
    
    public static int GetFoundCount() {
        lock (Matches) {
            return Matches.Count;
        }
    }
    
    public static void StartFirstScan(int pid, string valStr, string valType, string scanType, long startAddr, long endAddr, bool writableOnly, bool executableOnly, bool useAlignment) {
        if (_isScanning) return;
        _isScanning = true;
        _skippedLargeRegions = 0;
        _skippedLargeBytes = 0;
        _scanProgress = 0;
        _scanError = "";
        _cancelScan = false;
        
        _scanThread = new System.Threading.Thread(() => {
            try {
                DoFirstScan(pid, valStr, valType, scanType, startAddr, endAddr, writableOnly, executableOnly, useAlignment);
            } catch (Exception ex) {
                _scanError = ex.Message;
            } finally {
                _isScanning = false;
            }
        });
        _scanThread.IsBackground = true;
        _scanThread.Start();
    }
    
    public static void StartNextScan(int pid, string valStr, string valType, string scanType) {
        if (_isScanning) return;
        _isScanning = true;
        _skippedLargeRegions = 0;   // only the first scan walks whole regions
        _skippedLargeBytes = 0;
        _scanProgress = 0;
        _scanError = "";
        _cancelScan = false;
        
        _scanThread = new System.Threading.Thread(() => {
            try {
                DoNextScan(pid, valStr, valType, scanType);
            } catch (Exception ex) {
                _scanError = ex.Message;
            } finally {
                _isScanning = false;
            }
        });
        _scanThread.IsBackground = true;
        _scanThread.Start();
    }
    
    private static void DoFirstScan(int pid, string valStr, string valType, string scanType, long startAddr, long endAddr, bool writableOnly, bool executableOnly, bool useAlignment) {
        ClearScan();
        
        var tempMatches = new List<long>();
        var tempValues = new List<long>();
        
        IntPtr h = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, false, pid);
        if (h == IntPtr.Zero) {
            _scanError = "Cannot open process (PID: " + pid + "). Try running as administrator.";
            return;
        }
        
        try {
            long targetInt = 0, targetIntMax = 0;
            double targetDouble = 0, targetDoubleMax = 0;
            
            bool isRange = scanType == "Value between...";
            bool isUnknown = scanType == "Unknown Initial Value";
            
            if (!isUnknown && valType != "String" && valType != "Array of Byte") {
                if (isRange) {
                    string[] parts = valStr.Split(',');
                    string p1 = parts[0].Trim();
                    string p2 = parts.Length > 1 ? parts[1].Trim() : p1;
                    
                    if (valType == "Byte" || valType == "2 Bytes" || valType == "4 Bytes" || valType == "8 Bytes") {
                        targetInt = SafeParseHexOrDec(p1);
                        targetIntMax = SafeParseHexOrDec(p2);
                    } else {
                        targetDouble = double.Parse(p1);
                        targetDoubleMax = double.Parse(p2);
                    }
                } else {
                    if (valType == "Byte" || valType == "2 Bytes" || valType == "4 Bytes" || valType == "8 Bytes") {
                        targetInt = SafeParseHexOrDec(valStr);
                    } else {
                        targetDouble = double.Parse(valStr);
                    }
                }
            }
            
            int typeSize = GetTypeSize(valType);
            int align = useAlignment ? typeSize : 1;
            
            byte[] aobPattern = null;
            bool[] aobMask = null;
            if (valType == "Array of Byte") {
                string[] parts = valStr.Split(new char[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
                aobPattern = new byte[parts.Length];
                aobMask = new bool[parts.Length];
                for (int i = 0; i < parts.Length; i++) {
                    if (parts[i] == "??" || parts[i] == "?") {
                        aobMask[i] = true;
                    } else {
                        aobMask[i] = false;
                        aobPattern[i] = Convert.ToByte(parts[i], 16);
                    }
                }
                typeSize = aobPattern.Length;
                align = 1;
            }
            
            byte[] strPattern = null;
            if (valType == "String") {
                strPattern = Encoding.UTF8.GetBytes(valStr);
                typeSize = strPattern.Length;
                align = 1;
            }
            
            long addr = startAddr;
            UniversalMbi mbi;
            
            long totalBytes = endAddr - startAddr;
            long bytesScanned = 0;
            
            while (addr < endAddr && tempMatches.Count < 5000000) {
                if (_cancelScan) break;
                if (!QueryMemory(h, new IntPtr(addr), out mbi)) break;
                
                if (mbi.State == MEM_COMMIT && mbi.RegionSize > 0) {
                    bool isReadable = (mbi.Protect & (0x02 | 0x04 | 0x20 | 0x40 | 0x08 | 0x80)) != 0;
                    bool isWritable = (mbi.Protect & (0x04 | 0x40 | 0x08 | 0x80)) != 0;
                    bool isExecutable = (mbi.Protect & (0x10 | 0x20 | 0x40 | 0x80)) != 0;
                    bool isGuard = (mbi.Protect & 0x100) != 0;   // PAGE_GUARD: touching it raises an exception in the target

                    bool matchOptions = isReadable && !isGuard;
                    if (writableOnly && !isWritable) matchOptions = false;
                    if (executableOnly && !isExecutable) matchOptions = false;

                    if (matchOptions) {
                        long regionSize = (long)mbi.RegionSize;
                        if (regionSize > 64 * 1024 * 1024) {
                            // Too large to buffer in one read - report it instead of silently skipping
                            _skippedLargeRegions++;
                            _skippedLargeBytes += regionSize;
                        }
                        if (regionSize > 0 && regionSize <= 64 * 1024 * 1024) {
                            byte[] buf = new byte[regionSize];
                            int read;
                            if (ReadProcessMemory(h, mbi.BaseAddress, buf, (int)regionSize, out read) && read > 0) {
                                long start = mbi.BaseAddress.ToInt64();
                                
                                if (valType == "Array of Byte") {
                                    for (int i = 0; i <= read - typeSize; i += align) {
                                        if (_cancelScan) break;
                                        bool matched = true;
                                        for (int j = 0; j < typeSize; j++) {
                                            if (!aobMask[j] && buf[i + j] != aobPattern[j]) {
                                                matched = false;
                                                break;
                                            }
                                        }
                                        if (matched) {
                                            tempMatches.Add(start + i);
                                            tempValues.Add(0);
                                            if (tempMatches.Count >= 5000000) break;
                                        }
                                    }
                                } else if (valType == "String") {
                                    for (int i = 0; i <= read - typeSize; i += align) {
                                        if (_cancelScan) break;
                                        bool matched = true;
                                        for (int j = 0; j < typeSize; j++) {
                                            if (buf[i + j] != strPattern[j]) {
                                                matched = false;
                                                break;
                                            }
                                        }
                                        if (matched) {
                                            tempMatches.Add(start + i);
                                            tempValues.Add(0);
                                            if (tempMatches.Count >= 5000000) break;
                                        }
                                    }
                                } else {
                                    for (int i = 0; i <= read - typeSize; i += align) {
                                        if (_cancelScan) break;
                                        long bits = 0;
                                        if (valType == "Byte") bits = buf[i];
                                        else if (valType == "2 Bytes") bits = BitConverter.ToInt16(buf, i);
                                        else if (valType == "4 Bytes") bits = BitConverter.ToInt32(buf, i);
                                        else if (valType == "8 Bytes") bits = BitConverter.ToInt64(buf, i);
                                        else if (valType == "Float") bits = BitConverter.ToInt32(BitConverter.GetBytes(BitConverter.ToSingle(buf, i)), 0);
                                        else if (valType == "Double") bits = BitConverter.DoubleToInt64Bits(BitConverter.ToDouble(buf, i));
                                        
                                        if (isUnknown || CompareValue(bits, valType, scanType, targetInt, targetIntMax, targetDouble, targetDoubleMax)) {
                                            tempMatches.Add(start + i);
                                            tempValues.Add(bits);
                                            if (tempMatches.Count >= 5000000) break;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                long currentRegionSize = (long)mbi.RegionSize;
                addr = mbi.BaseAddress.ToInt64() + currentRegionSize;
                bytesScanned += currentRegionSize;
                if (totalBytes > 0) {
                    _scanProgress = (int)((bytesScanned * 100) / totalBytes);
                    if (_scanProgress > 100) _scanProgress = 100;
                }
                if (addr <= mbi.BaseAddress.ToInt64()) break;
            }
        } finally { CloseHandle(h); }
        
        if (!_cancelScan) {
            lock (Matches) {
                Matches = tempMatches;
                Values = tempValues;
            }
            _scanProgress = 100;
        }
    }
    
    private static void DoNextScan(int pid, string valStr, string valType, string scanType) {
        var tempMatches = new List<long>();
        var tempValues = new List<long>();
        
        List<long> currentMatches;
        List<long> currentValues;
        lock (Matches) {
            currentMatches = new List<long>(Matches);
            currentValues = new List<long>(Values);
        }
        
        if (currentMatches.Count == 0) {
            lock (Matches) {
                Matches = tempMatches;
                Values = tempValues;
            }
            _scanProgress = 100;
            return;
        }
        
        IntPtr h = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, false, pid);
        if (h == IntPtr.Zero) {
            _scanError = "Cannot open process (PID: " + pid + ").";
            return;
        }
        
        try {
            long targetInt = 0;
            double targetDouble = 0;
            if (scanType == "Exact Value" || scanType == "Bigger than..." || scanType == "Smaller than..." || scanType == "Increased Value by..." || scanType == "Decreased Value by...") {
                if (valType == "Byte" || valType == "2 Bytes" || valType == "4 Bytes" || valType == "8 Bytes") {
                    targetInt = SafeParseHexOrDec(valStr);
                } else if (valType == "Float" || valType == "Double") {
                    targetDouble = double.Parse(valStr);
                }
            }
            
            int typeSize = GetTypeSize(valType);
            int total = currentMatches.Count;
            int scanned = 0;
            
            if (currentMatches.Count > 2000) {
                int matchCursor = 0;
                UniversalMbi mbi;
                
                while (matchCursor < currentMatches.Count) {
                    if (_cancelScan) break;
                    long targetAddr = currentMatches[matchCursor];
                    if (!QueryMemory(h, new IntPtr(targetAddr), out mbi)) {
                        matchCursor++;
                        scanned++;
                        _scanProgress = (int)((scanned * 100) / total);
                        continue;
                    }
                    
                    long start = mbi.BaseAddress.ToInt64();
                    long regionSize = (long)mbi.RegionSize;
                    long end = start + regionSize;
                    
                    if (mbi.State == MEM_COMMIT && regionSize > 0 && regionSize <= 128 * 1024 * 1024) {
                        byte[] buf = new byte[regionSize];
                        int read;
                        if (ReadProcessMemory(h, mbi.BaseAddress, buf, (int)regionSize, out read) && read > 0) {
                            long readEnd = start + read;
                            while (matchCursor < currentMatches.Count) {
                                if (_cancelScan) break;
                                long mAddr = currentMatches[matchCursor];
                                if (mAddr < start) {
                                    matchCursor++;
                                    scanned++;
                                    _scanProgress = (int)((scanned * 100) / total);
                                    continue;
                                }
                                if (mAddr > readEnd - typeSize) {
                                    break;
                                }
                                
                                int offset = (int)(mAddr - start);
                                long newBits = 0;
                                if (valType == "Byte") newBits = buf[offset];
                                else if (valType == "2 Bytes") newBits = BitConverter.ToInt16(buf, offset);
                                else if (valType == "4 Bytes") newBits = BitConverter.ToInt32(buf, offset);
                                else if (valType == "8 Bytes") newBits = BitConverter.ToInt64(buf, offset);
                                else if (valType == "Float") newBits = BitConverter.ToInt32(BitConverter.GetBytes(BitConverter.ToSingle(buf, offset)), 0);
                                else if (valType == "Double") newBits = BitConverter.DoubleToInt64Bits(BitConverter.ToDouble(buf, offset));
                                
                                long oldBits = currentValues[matchCursor];
                                if (CompareNextValue(oldBits, newBits, valType, scanType, targetInt, targetDouble)) {
                                    tempMatches.Add(mAddr);
                                    tempValues.Add(newBits);
                                }
                                matchCursor++;
                                scanned++;
                                _scanProgress = (int)((scanned * 100) / total);
                            }
                        } else {
                            while (matchCursor < currentMatches.Count && currentMatches[matchCursor] < end) {
                                matchCursor++;
                                scanned++;
                                _scanProgress = (int)((scanned * 100) / total);
                            }
                        }
                    } else {
                        while (matchCursor < currentMatches.Count && currentMatches[matchCursor] < end) {
                            matchCursor++;
                            scanned++;
                            _scanProgress = (int)((scanned * 100) / total);
                        }
                    }
                }
            } else {
                byte[] buf = new byte[8];
                for (int k = 0; k < currentMatches.Count; k++) {
                    if (_cancelScan) break;
                    long mAddr = currentMatches[k];
                    int read;
                    if (ReadProcessMemory(h, new IntPtr(mAddr), buf, typeSize, out read) && read == typeSize) {
                        long newBits = 0;
                        if (valType == "Byte") newBits = buf[0];
                        else if (valType == "2 Bytes") newBits = BitConverter.ToInt16(buf, 0);
                        else if (valType == "4 Bytes") newBits = BitConverter.ToInt32(buf, 0);
                        else if (valType == "8 Bytes") newBits = BitConverter.ToInt64(buf, 0);
                        else if (valType == "Float") newBits = BitConverter.ToInt32(BitConverter.GetBytes(BitConverter.ToSingle(buf, 0)), 0);
                        else if (valType == "Double") newBits = BitConverter.DoubleToInt64Bits(BitConverter.ToDouble(buf, 0));
                        
                        long oldBits = currentValues[k];
                        if (CompareNextValue(oldBits, newBits, valType, scanType, targetInt, targetDouble)) {
                            tempMatches.Add(mAddr);
                            tempValues.Add(newBits);
                        }
                    }
                    scanned++;
                    _scanProgress = (int)((scanned * 100) / total);
                }
            }
        } finally { CloseHandle(h); }
        
        if (!_cancelScan) {
            lock (Matches) {
                Matches = tempMatches;
                Values = tempValues;
            }
            _scanProgress = 100;
        }
    }
    
    public static string GetMatchesPage(int pid, int startIdx, int count, string valType) {
        lock (Matches) {
            if (Matches.Count == 0) return "";
            int end = Math.Min(startIdx + count, Matches.Count);
            var sb = new StringBuilder();
            IntPtr h = OpenProcess(PROCESS_VM_READ, false, pid);
            if (h == IntPtr.Zero) return "";
            try {
                int typeSize = GetTypeSize(valType);
                byte[] buf = new byte[Math.Max(32, typeSize)];
                
                for (int i = startIdx; i < end; i++) {
                    long addr = Matches[i];
                    long oldBits = i < Values.Count ? Values[i] : 0;
                    int read;
                    string currentValStr = "??";
                    
                    if (valType == "String") {
                        byte[] sbuf = new byte[32];
                        if (ReadProcessMemory(h, new IntPtr(addr), sbuf, sbuf.Length, out read) && read > 0) {
                            int zeroIdx = Array.IndexOf(sbuf, (byte)0);
                            int decodeLen = zeroIdx >= 0 ? zeroIdx : read;
                            currentValStr = Encoding.UTF8.GetString(sbuf, 0, decodeLen);
                        }
                    } else if (valType == "Array of Byte") {
                        byte[] abuf = new byte[16];
                        if (ReadProcessMemory(h, new IntPtr(addr), abuf, abuf.Length, out read) && read > 0) {
                            currentValStr = BitConverter.ToString(abuf, 0, read).Replace("-", " ");
                        }
                    } else {
                        if (ReadProcessMemory(h, new IntPtr(addr), buf, typeSize, out read) && read == typeSize) {
                            DecodeToBits(buf, valType, out currentValStr);
                        }
                    }
                    
                    string oldValStr = (valType == "String" || valType == "Array of Byte") ? "" : FormatBits(oldBits, valType);
                    sb.AppendLine(string.Format("0x{0:X8}|{1}|{2}", addr, currentValStr, oldValStr));
                }
            } finally { CloseHandle(h); }
            return sb.ToString().TrimEnd();
        }
    }
    
    private static int GetTypeSize(string valType) {
        switch (valType) {
            case "Byte": return 1;
            case "2 Bytes": return 2;
            case "4 Bytes": return 4;
            case "8 Bytes": return 8;
            case "Float": return 4;
            case "Double": return 8;
            default: return 4;
        }
    }
    
    private static bool CompareValue(long valBits, string valType, string scanType, long targetInt, long targetIntMax, double targetDouble, double targetDoubleMax) {
        if (valType == "Byte" || valType == "2 Bytes" || valType == "4 Bytes" || valType == "8 Bytes") {
            long val = valBits;
            switch (scanType) {
                case "Exact Value": return val == targetInt;
                case "Bigger than...": return val > targetInt;
                case "Smaller than...": return val < targetInt;
                case "Value between...": return val >= targetInt && val <= targetIntMax;
                default: return false;
            }
        } else if (valType == "Float") {
            float val = BitConverter.ToSingle(BitConverter.GetBytes((int)valBits), 0);
            switch (scanType) {
                case "Exact Value": return Math.Abs(val - targetDouble) < 0.0001;
                case "Bigger than...": return val > targetDouble;
                case "Smaller than...": return val < targetDouble;
                case "Value between...": return val >= targetDouble && val <= targetDoubleMax;
                default: return false;
            }
        } else if (valType == "Double") {
            double val = BitConverter.Int64BitsToDouble(valBits);
            switch (scanType) {
                case "Exact Value": return Math.Abs(val - targetDouble) < 0.000001;
                case "Bigger than...": return val > targetDouble;
                case "Smaller than...": return val < targetDouble;
                case "Value between...": return val >= targetDouble && val <= targetDoubleMax;
                default: return false;
            }
        }
        return false;
    }
    
    private static bool CompareNextValue(long oldBits, long newBits, string valType, string scanType, long targetInt, double targetDouble) {
        if (valType == "Byte" || valType == "2 Bytes" || valType == "4 Bytes" || valType == "8 Bytes") {
            long oldVal = oldBits;
            long newVal = newBits;
            switch (scanType) {
                case "Exact Value": return newVal == targetInt;
                case "Bigger than...": return newVal > targetInt;
                case "Smaller than...": return newVal < targetInt;
                case "Increased Value": return newVal > oldVal;
                case "Decreased Value": return newVal < oldVal;
                case "Changed Value": return newVal != oldVal;
                case "Unchanged Value": return newVal == oldVal;
                case "Increased Value by...": return newVal == oldVal + targetInt;
                case "Decreased Value by...": return newVal == oldVal - targetInt;
                default: return false;
            }
        } else if (valType == "Float") {
            float oldVal = BitConverter.ToSingle(BitConverter.GetBytes((int)oldBits), 0);
            float newVal = BitConverter.ToSingle(BitConverter.GetBytes((int)newBits), 0);
            switch (scanType) {
                case "Exact Value": return Math.Abs(newVal - targetDouble) < 0.0001;
                case "Bigger than...": return newVal > targetDouble;
                case "Smaller than...": return newVal < targetDouble;
                case "Increased Value": return newVal > oldVal;
                case "Decreased Value": return newVal < oldVal;
                case "Changed Value": return Math.Abs(newVal - oldVal) > 0.0001;
                case "Unchanged Value": return Math.Abs(newVal - oldVal) < 0.0001;
                case "Increased Value by...": return Math.Abs(newVal - (oldVal + targetDouble)) < 0.0001;
                case "Decreased Value by...": return Math.Abs(newVal - (oldVal - targetDouble)) < 0.0001;
                default: return false;
            }
        } else if (valType == "Double") {
            double oldVal = BitConverter.Int64BitsToDouble(oldBits);
            double newVal = BitConverter.Int64BitsToDouble(newBits);
            switch (scanType) {
                case "Exact Value": return Math.Abs(newVal - targetDouble) < 0.000001;
                case "Bigger than...": return newVal > targetDouble;
                case "Smaller than...": return newVal < targetDouble;
                case "Increased Value": return newVal > oldVal;
                case "Decreased Value": return newVal < oldVal;
                case "Changed Value": return Math.Abs(newVal - oldVal) > 0.000001;
                case "Unchanged Value": return Math.Abs(newVal - oldVal) < 0.000001;
                case "Increased Value by...": return Math.Abs(newVal - (oldVal + targetDouble)) < 0.000001;
                case "Decreased Value by...": return Math.Abs(newVal - (oldVal - targetDouble)) < 0.000001;
                default: return false;
            }
        }
        return false;
    }
    
    private static long DecodeToBits(byte[] buf, string valType, out string strVal) {
        strVal = "??";
        switch (valType) {
            case "Byte":
                strVal = buf[0].ToString();
                return buf[0];
            case "2 Bytes":
                short s = BitConverter.ToInt16(buf, 0);
                strVal = s.ToString();
                return s;
            case "4 Bytes":
                int i = BitConverter.ToInt32(buf, 0);
                strVal = i.ToString();
                return i;
            case "8 Bytes":
                long l = BitConverter.ToInt64(buf, 0);
                strVal = l.ToString();
                return l;
            case "Float":
                float f = BitConverter.ToSingle(buf, 0);
                strVal = f.ToString("F3");
                return BitConverter.ToInt32(BitConverter.GetBytes(f), 0);
            case "Double":
                double d = BitConverter.ToDouble(buf, 0);
                strVal = d.ToString("F6");
                return BitConverter.DoubleToInt64Bits(d);
            default:
                return 0;
        }
    }
    
    private static string FormatBits(long bits, string valType) {
        switch (valType) {
            case "Byte": return ((byte)bits).ToString();
            case "2 Bytes": return ((short)bits).ToString();
            case "4 Bytes": return ((int)bits).ToString();
            case "8 Bytes": return bits.ToString();
            case "Float": return BitConverter.ToSingle(BitConverter.GetBytes((int)bits), 0).ToString("F3");
            case "Double": return BitConverter.Int64BitsToDouble(bits).ToString("F6");
            default: return "";
        }
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
            UniversalMbi mbi;
            int count = 0;
            while (count < 200) {
                if (!QueryMemory(h, new IntPtr(addr), out mbi)) break;
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
                        FormatBytes((long)mbi.RegionSize),
                        "Commit", protect));
                }
                addr = mbi.BaseAddress.ToInt64() + (long)mbi.RegionSize;
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

Memory.__New()

; ── Global Variables & Main GUI Setup ─────────────────────────────────────────

currentPid := 0
currentPidStart := 0   ; start-time ticks of the attached process (detects PID reuse)
currentProcessName := "No Process Selected"
scannedCount := 0
global cheatTableEntries := []

; ── Theme & Design Tokens (Catppuccin Latte / Modern Light) ────────────────────
theme_bgColor := "0xf0f2f5"  ; Light grey base background
theme_cardColor := "0xffffff"  ; Pure white for lists/cards/edits
theme_textColor := "0x2d3748"  ; Slate-800 for text
theme_titleColor := "0x1a202c"  ; Charcoal for titles
theme_accent := "0x3182ce"  ; Steel blue for primary highlights/borders
theme_green := "0x38a169"  ; Green for success/attached status
theme_red := "0xe53e3e"  ; Red for error/detached status
theme_border := "0x718096"  ; GroupBox border color

g := Gui("+Resize", "Cheat Engine Sharp (Admin)")
g.SetFont("s10 c" theme_textColor, "Segoe UI")
g.BackColor := theme_bgColor

; Menu Bar Setup
mFile := Menu()
mFile.Add("&Open Table...`tCtrl+O", MenuOpenTable)
mFile.Add("&Save Table...`tCtrl+S", MenuSaveTable)
mFile.Add("&Clear Table", MenuClearTable)
mFile.Add()
mFile.Add("&Export as Standalone Trainer...`tCtrl+E", MenuExportTrainer)
mFile.Add()
mFile.Add("&Exit`tAlt+F4", (*) => ExitApp())

mHelp := Menu()
mHelp.Add("&About", (*) => MsgBox("Cheat Engine Sharp v1.0`n`nWritten using AHK# Native .NET CLR Bridge.`nFeatures ultra-fast C# block scanning and trainer compiler.", "About"))

mb := MenuBar()
mb.Add("&File", mFile)
mb.Add("&Help", mHelp)
g.MenuBar := mb

; ── Toolbar Section ───────────────────────────────────────────────────────────

btnProc := g.Add("Button", "x15 y10 w130 h30", "💻 Select Process")
btnProc.OnEvent("Click", (*) => ShowProcessList())

statusLabel := g.Add("Text", "x155 y17 w410 h20", "No Process Selected")
statusLabel.SetFont("c" theme_red " Bold")

; ── Main Body Split Panel ─────────────────────────────────────────────────────

; Left Pane: Scan Results
g.Add("Text", "x15 y55 w240 h20", "Found matches:")
foundLabel := g.Add("Text", "x15 y75 w240 h20 c" theme_green, "Found: 0")
foundLabel.SetFont("Bold")
resultsLV := g.Add("ListView", "x15 y100 w240 h290 +Grid -Multi Background" theme_cardColor " c" theme_textColor, ["Address", "Value", "Previous"])
resultsLV.OnEvent("DoubleClick", AddFoundToSaved)

; Right Pane: Scan Options
g.Add("Text", "x270 y102 w80 h20", "Value:")
valEdit := g.Add("Edit", "x355 y100 w210 h24 Background" theme_cardColor " c" theme_textColor)

g.Add("Text", "x270 y134 w80 h20", "Scan Type:")
scanTypeDD := g.Add("DropDownList", "x355 y132 w210 Background" theme_cardColor " c" theme_textColor, ["Exact Value", "Bigger than...", "Smaller than...", "Value between...", "Unknown Initial Value"])
scanTypeDD.Value := 1
scanTypeDD.OnEvent("Change", ScanTypeChanged)

g.Add("Text", "x270 y166 w80 h20", "Value Type:")
valTypeDD := g.Add("DropDownList", "x355 y164 w210 Background" theme_cardColor " c" theme_textColor, ["Byte", "2 Bytes", "4 Bytes", "8 Bytes", "Float", "Double", "String", "Array of Byte"])
valTypeDD.Value := 3 ; 4 Bytes (Int32)

; Range Options
g.Add("GroupBox", "x270 y195 w295 h95 c" theme_border, " Memory Scan Options ")
g.Add("Text", "x280 y220 w80 h20", "Start Address:")
startAddrEdit := g.Add("Edit", "x370 y218 w180 h22 Background" theme_cardColor " c" theme_textColor, "0x0000000000000000")
g.Add("Text", "x280 y250 w80 h20", "End Address:")
endAddrEdit := g.Add("Edit", "x370 y248 w180 h22 Background" theme_cardColor " c" theme_textColor, "0x7FFFFFFFFFFF")

; Scan Configuration Checkboxes
chkWritable := g.Add("Checkbox", "x275 y298 w145 h20 Checked", "Writable memory only")
chkExecutable := g.Add("Checkbox", "x425 y298 w145 h20", "Executable memory only")
chkAlign := g.Add("Checkbox", "x275 y320 w140 h20 Checked", "Alignment")

; Scan Control Buttons
btnFirst := g.Add("Button", "x270 y350 w90 h30 Default", "First Scan")
btnFirst.OnEvent("Click", (*) => ExecuteFirstScan())

btnNext := g.Add("Button", "x370 y350 w90 h30 Disabled", "Next Scan")
btnNext.OnEvent("Click", (*) => ExecuteNextScan())

btnUndo := g.Add("Button", "x470 y350 w95 h30 Disabled", "Undo Scan")
btnUndo.OnEvent("Click", (*) => ExecuteUndoScan())

scanProgress := g.Add("Progress", "x270 y383 w295 h6 -Smooth Backgroundffffff c3182ce Hidden", 0)

; ── Bottom Section: Saved Cheat Table ────────────────────────────────────────

g.Add("GroupBox", "x12 y395 w555 h205 c" theme_border, " Address Cheat Table ")

btnAddMan := g.Add("Button", "x25 y415 w140 h26", "➕ Add Address Manually")
btnAddMan.OnEvent("Click", (*) => ShowAddManualDialog())

savedLV := g.Add("ListView", "x25 y448 w350 h140 +Checked +Grid Background" theme_cardColor " c" theme_textColor, ["Active", "Description", "Address", "Type", "Value"])
savedLV.OnEvent("DoubleClick", SavedLVDoubleClick)
savedLV.OnEvent("ItemCheck", SavedLVItemCheck)
savedLV.OnEvent("ItemSelect", SavedLVItemSelect)

; Active Item Editor (Direct & Fluid Modification Panel)
g.Add("GroupBox", "x390 y412 w165 h170 c" theme_border, " Active Item Editor ")
activeItemLabel := g.Add("Text", "x400 y432 w145 h15", "Selected: None")
activeItemLabel.SetFont("c" theme_border " s8 Norm")
g.Add("Text", "x400 y450 w145 h15", "Value:")
valSetEdit := g.Add("Edit", "x400 y468 w145 h24 Background" theme_cardColor " c" theme_textColor " Disabled")
btnSetVal := g.Add("Button", "x400 y496 w145 h24 Disabled", "Set Value")
btnSetVal.OnEvent("Click", (*) => SetSelectedEntryValue())
g.Add("Text", "x400 y524 w145 h15", "Freeze State:")
freezeDD := g.Add("DropDownList", "x400 y542 w145 Background" theme_cardColor " c" theme_textColor " Disabled", ["Unfrozen", "Freeze", "Inc Only", "Dec Only"])
freezeDD.OnEvent("Change", (*) => ChangeSelectedEntryFreeze())

; ListView Context Menu
savedLVMenu := Menu()
savedLVMenu.Add("Change Value`tEnter", (*) => ChangeSelectedValue())
savedLVMenu.Add("Edit Selected Row", (*) => EditSelectedRow())
savedLVMenu.Add("Delete Selected Row(s)", (*) => DeleteSelectedRows())
savedLVMenu.Add("Clear Cheat Table", (*) => MenuClearTable())
savedLVMenu.Add()
savedLVMenu.Add("Freeze (Standard)", (*) => SetFreezeType("Standard"))
savedLVMenu.Add("Freeze (Allow Increase)", (*) => SetFreezeType("Allow Increase"))
savedLVMenu.Add("Freeze (Allow Decrease)", (*) => SetFreezeType("Allow Decrease"))
savedLVMenu.Add("Unfreeze", (*) => SetFreezeType("Unfreeze"))
savedLV.OnEvent("ContextMenu", ShowContextMenu)

ShowContextMenu(ctrl, item, isRightClick, x, y) {
    if (item > 0) {
        savedLVMenu.Show(x, y)
    }
}

; Layout Adjustment & View
g.OnEvent("Close", (*) => ExitApp())
g.Show("w580 h615")

; ── Background Value Refresher / Freeze Timer ─────────────────────────────────

SetTimer(RefreshFreezeTimer, 500)

; True while the attached process is still the one we attached to (guards against the
; process exiting and its PID being recycled by an unrelated process before we write).
AttachedProcessIsValid() {
    global currentPid, currentPidStart
    if (currentPid == 0 || !ProcessExist(currentPid))
        return false
    if (currentPidStart != 0 && Memory.GetProcessStartTicks(currentPid) != currentPidStart)
        return false
    return true
}

DetachDeadProcess() {
    global currentPid, currentPidStart, currentProcessName
    lost := currentProcessName
    currentPid := 0
    currentPidStart := 0
    statusLabel.Text := "Process exited: " lost " - select a process again"
    statusLabel.SetFont("c" theme_textColor " Norm")
}

; Ask before writing into another process' memory. Returns true if the user agrees.
ConfirmWrite(what, address, valType, newValue) {
    if (!AttachedProcessIsValid()) {
        if (currentPid != 0)
            DetachDeadProcess()
        MsgBox("The target process is no longer running.", "Write Cancelled", "Icon!")
        return false
    }
    msg := "Write to process memory?`n`n"
        . "Process: " currentProcessName " (PID " currentPid ")`n"
        . "Entry: " what "`n"
        . "Address: " address "`n"
        . "Type: " valType "`n"
        . "New value: " newValue "`n`n"
        . "Writing into a running program can crash it or corrupt its data."
    return MsgBox(msg, "Confirm Memory Write", "YesNo Icon?") == "Yes"
}

RefreshFreezeTimer() {
    global currentPid, cheatTableEntries, valSetEdit
    if (currentPid == 0)
        return
    if (!AttachedProcessIsValid()) {
        DetachDeadProcess()
        return
    }

    for index, entry in cheatTableEntries {
        ; Resolve address dynamically (handles modules, pointers, offsets)
        addr := Memory.ResolveAddressString(currentPid, entry.address)
        if (addr == 0) {
            entry.liveValue := "??"
            if (savedLV.GetText(index, 5) != "??")
                savedLV.Modify(index, "", savedLV.GetText(index, 1), entry.desc, entry.address, entry.type, "??")
            continue
        }

        ; Read live value from process memory
        liveVal := Memory.ReadValue(currentPid, addr, entry.type)

        ; Handle freeze logic
        if (entry.active && entry.freezeType != "") {
            shouldWrite := false
            if (entry.freezeType == "Freeze") {
                shouldWrite := true
            } else if (entry.freezeType == "Inc Only") {
                if (liveVal != "??" && CompareValues(liveVal, entry.value, entry.type) < 0) {
                    shouldWrite := true
                }
            } else if (entry.freezeType == "Dec Only") {
                if (liveVal != "??" && CompareValues(liveVal, entry.value, entry.type) > 0) {
                    shouldWrite := true
                }
            }

            if (shouldWrite) {
                ; Re-check right before writing: never write into a recycled PID
                if (!AttachedProcessIsValid()) {
                    DetachDeadProcess()
                    return
                }
                Memory.WriteValue(currentPid, addr, entry.type, entry.value)
                liveVal := entry.value
            }
        }

        entry.liveValue := liveVal

        ; Only modify the ListView cell if it is different, to prevent unnecessary redraw flickering!
        if (savedLV.GetText(index, 5) != liveVal) {
            savedLV.Modify(index, "", savedLV.GetText(index, 1), entry.desc, entry.address, entry.type, liveVal)
        }
    }

    ; Update active item editor panel dynamically if it's not being typed into
    selectedRow := savedLV.GetNext()
    if (selectedRow > 0 && selectedRow <= cheatTableEntries.Length) {
        ctrl := g.FocusedCtrl
        if (!ctrl || ctrl.Hwnd != valSetEdit.Hwnd) {
            valSetEdit.Value := cheatTableEntries[selectedRow].liveValue
        }
    }

    UpdateLiveResults()
}

CompareValues(val1, val2, valType) {
    try {
        if (valType == "Float" || valType == "Double") {
            v1 := Float(val1)
            v2 := Float(val2)
            return v1 > v2 ? 1 : (v1 < v2 ? -1 : 0)
        } else {
            v1 := Integer(val1)
            v2 := Integer(val2)
            return v1 > v2 ? 1 : (v1 < v2 ? -1 : 0)
        }
    } catch {
        return 0
    }
}

SetFreezeType(type) {
    global cheatTableEntries
    row := savedLV.GetNext()
    if (row == 0 || row > cheatTableEntries.Length)
        return

    if (type == "Unfreeze") {
        cheatTableEntries[row].freezeType := ""
        cheatTableEntries[row].active := false
        savedLV.Modify(row, "-Check", "")
    } else if (type == "Standard") {
        cheatTableEntries[row].freezeType := "Freeze"
        cheatTableEntries[row].active := true
        savedLV.Modify(row, "Check", "Freeze")
    } else if (type == "Allow Increase") {
        cheatTableEntries[row].freezeType := "Inc Only"
        cheatTableEntries[row].active := true
        savedLV.Modify(row, "Check", "Inc Only")
    } else if (type == "Allow Decrease") {
        cheatTableEntries[row].freezeType := "Dec Only"
        cheatTableEntries[row].active := true
        savedLV.Modify(row, "Check", "Dec Only")
    }
    UpdateEditorPanel(row)
}

ChangeSelectedValue() {
    global cheatTableEntries, currentPid
    row := savedLV.GetNext()
    if (row == 0 || row > cheatTableEntries.Length)
        return
    currentVal := cheatTableEntries[row].value

    ib := InputBox("Enter new value for cheat:", "Change Value", "w250 h130", currentVal)
    if (ib.Result == "OK") {
        if (currentPid != 0 && !ConfirmWrite(cheatTableEntries[row].desc, cheatTableEntries[row].address, cheatTableEntries[row].type, ib.Value))
            return
        cheatTableEntries[row].value := ib.Value
        cheatTableEntries[row].liveValue := ib.Value
        savedLV.Modify(row, "", savedLV.GetText(row, 1), cheatTableEntries[row].desc, cheatTableEntries[row].address, cheatTableEntries[row].type, ib.Value)

        if (savedLV.GetNext() == row) {
            UpdateEditorPanel(row)
        }

        if (currentPid != 0) {
            addr := Memory.ResolveAddressString(currentPid, cheatTableEntries[row].address)
            if (addr != 0) {
                Memory.WriteValue(currentPid, addr, cheatTableEntries[row].type, ib.Value)
            }
        }
    }
}

UpdateLiveResults() {
    global currentPid, scannedCount
    if (currentPid == 0 || scannedCount == 0 || resultsLV.GetCount() == 0 || Memory.IsScanning())
        return
    displayCount := Min(100, resultsLV.GetCount()) ; Only update first 100 items live to prevent UI lag
    pageData := Memory.GetMatchesPage(currentPid, 0, displayCount, valTypeDD.Text)
    if (pageData != "") {
        resultsLV.Opt("-Redraw")
        Loop parse, pageData, "`n", "`r" {
            if (A_LoopField == "")
                continue
            parts := StrSplit(A_LoopField, "|")
            if (parts.Length >= 2 && A_Index <= resultsLV.GetCount()) {
                if (resultsLV.GetText(A_Index, 2) != parts[2]) {
                    resultsLV.Modify(A_Index, "Col2", parts[2])
                }
            }
        }
        resultsLV.Opt("+Redraw")
    }
}

; ── Active Item Editor Handlers ────────────────────────────────────────────────

SavedLVItemSelect(ctrl, item, selected) {
    if (selected) {
        UpdateEditorPanel(item)
    } else {
        if (savedLV.GetNext() == 0) {
            ClearEditorPanel()
        }
    }
}

UpdateEditorPanel(item) {
    global cheatTableEntries, activeItemLabel, valSetEdit, btnSetVal, freezeDD
    if (item == 0 || item > cheatTableEntries.Length)
        return

    entry := cheatTableEntries[item]
    activeItemLabel.Text := "Selected: " entry.desc " (" entry.address ")"
    activeItemLabel.SetFont("c" theme_textColor " Bold s8")

    valSetEdit.Value := entry.liveValue
    valSetEdit.Enabled := true
    btnSetVal.Enabled := true
    freezeDD.Enabled := true

    if (entry.freezeType == "Freeze") {
        freezeDD.Value := 2
    } else if (entry.freezeType == "Inc Only") {
        freezeDD.Value := 3
    } else if (entry.freezeType == "Dec Only") {
        freezeDD.Value := 4
    } else {
        freezeDD.Value := 1
    }
}

ClearEditorPanel() {
    global activeItemLabel, valSetEdit, btnSetVal, freezeDD
    activeItemLabel.Text := "Selected: None"
    activeItemLabel.SetFont("c" theme_border " s8 Norm")
    valSetEdit.Value := ""
    valSetEdit.Enabled := false
    btnSetVal.Enabled := false
    freezeDD.Enabled := false
}

SetSelectedEntryValue() {
    global cheatTableEntries, currentPid, valSetEdit
    row := savedLV.GetNext()
    if (row == 0 || row > cheatTableEntries.Length)
        return

    newVal := valSetEdit.Value
    if (currentPid != 0 && !ConfirmWrite(cheatTableEntries[row].desc, cheatTableEntries[row].address, cheatTableEntries[row].type, newVal))
        return
    cheatTableEntries[row].value := newVal
    cheatTableEntries[row].liveValue := newVal
    savedLV.Modify(row, "", savedLV.GetText(row, 1), cheatTableEntries[row].desc, cheatTableEntries[row].address, cheatTableEntries[row].type, newVal)

    if (currentPid != 0) {
        addr := Memory.ResolveAddressString(currentPid, cheatTableEntries[row].address)
        if (addr != 0) {
            Memory.WriteValue(currentPid, addr, cheatTableEntries[row].type, newVal)
        }
    }
    SoundBeep(800, 50)
}

ChangeSelectedEntryFreeze() {
    global cheatTableEntries, freezeDD
    row := savedLV.GetNext()
    if (row == 0 || row > cheatTableEntries.Length)
        return

    sel := freezeDD.Text
    if (sel == "Unfrozen") {
        cheatTableEntries[row].freezeType := ""
        cheatTableEntries[row].active := false
        savedLV.Modify(row, "-Check", "")
    } else if (sel == "Freeze") {
        cheatTableEntries[row].freezeType := "Freeze"
        cheatTableEntries[row].active := true
        savedLV.Modify(row, "Check", "Freeze")
    } else if (sel == "Inc Only") {
        cheatTableEntries[row].freezeType := "Inc Only"
        cheatTableEntries[row].active := true
        savedLV.Modify(row, "Check", "Inc Only")
    } else if (sel == "Dec Only") {
        cheatTableEntries[row].freezeType := "Dec Only"
        cheatTableEntries[row].active := true
        savedLV.Modify(row, "Check", "Dec Only")
    }
}

AddCheat(active, freezeType, desc, address, type, value) {
    global cheatTableEntries
    entry := {
        active: active,
        freezeType: freezeType,
        desc: desc,
        address: address,
        type: type,
        value: value,
        liveValue: value
    }
    cheatTableEntries.Push(entry)
    chkOpt := active ? "Checked" : ""
    savedLV.Add(chkOpt, freezeType, desc, address, type, value)
}

; ── Scan Handlers ─────────────────────────────────────────────────────────────

ScanTypeChanged(*) {
    if (scanTypeDD.Text == "Unknown Initial Value") {
        valEdit.Enabled := false
    } else {
        valEdit.Enabled := true
    }
}

ExecuteFirstScan() {
    global currentPid, scannedCount, btnFirst, btnNext, btnUndo, btnProc, valTypeDD, scanTypeDD, scanProgress, valEdit
    if (currentPid == 0) {
        MsgBox("Please select a target process first!", "Scan Error", "Icon!")
        return
    }

    if (Memory.IsScanning()) {
        Memory.CancelScan()
        btnFirst.Text := "Cancelling..."
        btnFirst.Enabled := false
        return
    }

    val := valEdit.Value
    if (scanTypeDD.Text != "Unknown Initial Value" && val == "") {
        MsgBox("Please enter a scan value!", "Scan Error", "Icon!")
        return
    }

    valType := valTypeDD.Text
    scanType := scanTypeDD.Text

    try {
        startAddr := Integer(Trim(startAddrEdit.Value))
        endAddr := Integer(Trim(endAddrEdit.Value))
    } catch {
        MsgBox("Start/End address must be a number (decimal or 0x-prefixed hex).", "Scan Error", "Icon!")
        return
    }
    if (endAddr <= startAddr) {
        MsgBox("End address must be greater than the start address.", "Scan Error", "Icon!")
        return
    }

    writableOnly := chkWritable.Value
    executableOnly := chkExecutable.Value
    useAlign := chkAlign.Value

    btnNext.Enabled := false
    btnUndo.Enabled := false
    btnProc.Enabled := false
    valTypeDD.Enabled := false
    scanTypeDD.Enabled := false

    btnFirst.Text := "Cancel"
    scanProgress.Visible := true
    scanProgress.Value := 0

    resultsLV.Delete()

    Memory.StartFirstScan(currentPid, val, valType, scanType, startAddr, endAddr, writableOnly, executableOnly, useAlign)
    SetTimer(CheckScanProgressTimer, 100)
}

ExecuteNextScan() {
    global currentPid, scannedCount, btnFirst, btnNext, btnUndo, btnProc, valTypeDD, scanTypeDD, scanProgress, valEdit
    if (currentPid == 0)
        return

    if (Memory.IsScanning()) {
        Memory.CancelScan()
        btnNext.Text := "Cancelling..."
        btnNext.Enabled := false
        return
    }

    val := valEdit.Value
    if (scanTypeDD.Text != "Unknown Initial Value" && val == "") {
        MsgBox("Please enter a next-scan value!", "Scan Error", "Icon!")
        return
    }

    valType := valTypeDD.Text
    scanType := scanTypeDD.Text

    btnFirst.Enabled := false
    btnUndo.Enabled := false
    btnProc.Enabled := false
    valTypeDD.Enabled := false
    scanTypeDD.Enabled := false

    btnNext.Text := "Cancel"
    scanProgress.Visible := true
    scanProgress.Value := 0

    Memory.StartNextScan(currentPid, val, valType, scanType)
    SetTimer(CheckScanProgressTimer, 100)
}

CheckScanProgressTimer() {
    global scannedCount, btnFirst, btnNext, btnUndo, btnProc, valTypeDD, scanTypeDD, scanProgress
    if (Memory.IsScanning()) {
        prog := Memory.GetScanProgress()
        scanProgress.Value := prog
        return
    }

    SetTimer(CheckScanProgressTimer, 0)

    scanProgress.Visible := false
    btnProc.Enabled := true
    valTypeDD.Enabled := true
    scanTypeDD.Enabled := true

    err := Memory.GetScanError()
    if (err != "") {
        MsgBox("Scan error: " err, "Scan Failed", "Icon!")
        btnFirst.Text := (scannedCount > 0) ? "New Scan" : "First Scan"
        btnFirst.Enabled := true
        btnNext.Text := "Next Scan"
        btnNext.Enabled := (scannedCount > 0)
        btnUndo.Enabled := true
        return
    }

    scannedCount := Memory.GetFoundCount()
    btnFirst.Text := (scannedCount > 0) ? "New Scan" : "First Scan"
    btnFirst.Enabled := true
    btnNext.Text := "Next Scan"
    btnNext.Enabled := (scannedCount > 0)
    btnUndo.Enabled := true

    UpdateScanResults()

    ; Tell the user about memory that could not be scanned (single reads are capped at 64 MB)
    skippedCount := Memory.GetSkippedRegionCount()
    if (skippedCount > 0) {
        skippedMB := Round(Memory.GetSkippedRegionBytes() / 1048576, 1)
        MsgBox(skippedCount " memory region(s) larger than 64 MB (" skippedMB " MB total) were skipped, so values inside them are not in the results.",
            "Scan Incomplete", "Icon!")
    }
}

ExecuteUndoScan() {
    global scannedCount
    scannedCount := Memory.UndoScan()
    UpdateScanResults()
}

UpdateScanResults() {
    global scannedCount, currentPid, foundLabel, resultsLV, valTypeDD
    foundLabel.Text := "Found: " scannedCount
    resultsLV.Opt("-Redraw")
    resultsLV.Delete()

    if (scannedCount > 0) {
        pageData := Memory.GetMatchesPage(currentPid, 0, Min(1000, scannedCount), valTypeDD.Text)
        if (pageData != "") {
            Loop parse, pageData, "`n", "`r" {
                if (A_LoopField == "")
                    continue
                parts := StrSplit(A_LoopField, "|")
                resultsLV.Add("", parts[1], parts[2], parts[3])
            }
        }
    }
    resultsLV.Opt("+Redraw")
}

AddFoundToSaved(ctrl, row) {
    if (row == 0)
        return
    addr := resultsLV.GetText(row, 1)
    val := resultsLV.GetText(row, 2)
    valType := valTypeDD.Text

    AddCheat(false, "", "No Description", addr, valType, val)
}

; ── Process List Dialog ───────────────────────────────────────────────────────

ShowProcessList() {
    global currentPid, currentProcessName, g, scannedCount
    g.Opt("+Disabled")

    pListGui := Gui("+Owner" g.Hwnd, "Process List")
    pListGui.BackColor := theme_bgColor
    pListGui.SetFont("s9 c" theme_textColor, "Segoe UI")
    pListGui.OnEvent("Close", (*) => (g.Opt("-Disabled"), pListGui.Destroy()))

    tabs := pListGui.Add("Tab3", "x10 y10 w480 h360", ["Applications", "Processes", "Windows"])

    ; Load process list from C# reflection
    procString := Memory.GetAllProcesses()
    procRows := StrSplit(procString, "`n")

    ; Applications Tab
    tabs.UseTab(1)
    appLV := pListGui.Add("ListView", "x20 y45 w460 h310 +Grid -Multi Background" theme_cardColor " c" theme_textColor, ["PID", "Process Name", "Window Title"])

    ; Processes Tab
    tabs.UseTab(2)
    procLV := pListGui.Add("ListView", "x20 y45 w460 h310 +Grid -Multi Background" theme_cardColor " c" theme_textColor, ["PID", "Process Name", "Memory Working Set"])

    ; Windows Tab
    tabs.UseTab(3)
    winLV := pListGui.Add("ListView", "x20 y45 w460 h310 +Grid -Multi Background" theme_cardColor " c" theme_textColor, ["PID", "Process Name", "Window Class"])

    ; Populate ListViews based on process types
    appLV.Opt("-Redraw")
    procLV.Opt("-Redraw")
    winLV.Opt("-Redraw")

    Loop procRows.Length {
        if (procRows[A_Index] == "")
            continue
        parts := StrSplit(procRows[A_Index], "|")
        if (parts.Length < 4)
            continue
        pid := parts[1]
        pName := parts[2]
        title := parts[3]
        memUsage := parts[4]

        ; Add to processes
        procLV.Add("", pid, pName, memUsage)

        ; Add to applications/windows if title exists
        if (title != "" && title != "(no window)") {
            appLV.Add("", pid, pName, title)
            winLV.Add("", pid, pName, title)
        }
    }

    appLV.Opt("+Redraw")
    procLV.Opt("+Redraw")
    winLV.Opt("+Redraw")

    tabs.UseTab()

    btnOpen := pListGui.Add("Button", "x130 y380 w110 h28 Default", "Open")
    btnOpen.OnEvent("Click", OpenSelectedProc)

    btnCancel := pListGui.Add("Button", "x260 y380 w110 h28", "Cancel")
    btnCancel.OnEvent("Click", (*) => (g.Opt("-Disabled"), pListGui.Destroy()))

    appLV.OnEvent("DoubleClick", OpenSelectedProc)
    procLV.OnEvent("DoubleClick", OpenSelectedProc)
    winLV.OnEvent("DoubleClick", OpenSelectedProc)

    pListGui.Show("w500 h420")

    OpenSelectedProc(ctrl, *) {
        if (ctrl is Gui.ListView) {
            activeLV := ctrl
        } else {
            selTab := tabs.Value
            activeLV := (selTab == 1) ? appLV : (selTab == 2) ? procLV : winLV
        }
        row := activeLV.GetNext()
        if (row == 0) {
            MsgBox("Please select a process from the list!", "Selection Error", "Icon!")
            return
        }

        global currentPidStart
        try {
            currentPid := Integer(activeLV.GetText(row, 1))
        } catch {
            MsgBox("The selected row does not contain a valid PID.", "Selection Error", "Icon!")
            return
        }
        currentPidStart := Memory.GetProcessStartTicks(currentPid)
        currentProcessName := activeLV.GetText(row, 2)

        ; Set headers/status
        statusLabel.Text := "Attached PID: " currentPid " (" currentProcessName ")"
        statusLabel.SetFont("c" theme_green " Bold") ; Highlight active state

        g.Opt("-Disabled")
        pListGui.Destroy()

        ; Auto-detect process architecture (32/64 bit) and update range limits
        if (Memory.IsProcess64Bit(currentPid)) {
            startAddrEdit.Value := "0x0000000000000000"
            endAddrEdit.Value := "0x7FFFFFFFFFFF"
        } else {
            startAddrEdit.Value := "0x00000000"
            endAddrEdit.Value := "0x7FFFFFFF"
        }

        ; Clear old scan states
        Memory.ClearScan()
        scannedCount := 0
        foundLabel.Text := "Found: 0"
        resultsLV.Delete()

        ; Reset scan control buttons and progress
        btnFirst.Text := "First Scan"
        btnFirst.Enabled := true
        btnNext.Text := "Next Scan"
        btnNext.Enabled := false
        btnUndo.Enabled := false
        scanProgress.Visible := false
        scanProgress.Value := 0
    }
}

; ── Cheat Table Save/Load ─────────────────────────────────────────────────────

MenuOpenTable(*) {
    path := FileSelect(1, , "Open Cheat Table", "Cheat Table (*.ast; *.txt)")
    if (path == "")
        return

    savedLV.Delete()
    global cheatTableEntries
    cheatTableEntries := []

    fileContent := FileRead(path)
    Loop parse, fileContent, "`n", "`r" {
        if (A_LoopField == "")
            continue
        parts := StrSplit(A_LoopField, "|")
        if (parts.Length >= 5) {
            freezeType := parts[1]
            if (freezeType == "1" || freezeType == "Freeze") {
                freezeType := "Freeze"
            } else if (freezeType == "0" || freezeType == "") {
                freezeType := ""
            } else if (freezeType == "Inc Only" || freezeType == "Dec Only") {
                ; Keep as is
            } else {
                freezeType := ""
            }
            active := (freezeType != "")
            AddCheat(active, freezeType, parts[2], parts[3], parts[4], parts[5])
        } else if (parts.Length == 4) {
            AddCheat(false, "", parts[1], parts[2], parts[3], parts[4])
        }
    }
}

MenuSaveTable(*) {
    path := FileSelect(16, "table.ast", "Save Cheat Table", "Cheat Table (*.ast)")
    if (path == "")
        return

    outData := ""
    global cheatTableEntries
    for index, entry in cheatTableEntries {
        outData .= entry.freezeType "|" entry.desc "|" entry.address "|" entry.type "|" entry.value "`n"
    }

    if FileExist(path)
        FileDelete(path)
    FileAppend(outData, path)
}

MenuClearTable(*) {
    global cheatTableEntries
    cheatTableEntries := []
    savedLV.Delete()
    ClearEditorPanel()
}

; ── Bottom Address List Handlers ──────────────────────────────────────────────

ShowAddManualDialog() {
    global g
    g.Opt("+Disabled")
    dlg := Gui("+Owner" g.Hwnd, "Add Address Manually")
    dlg.BackColor := theme_bgColor
    dlg.SetFont("s9 c" theme_textColor, "Segoe UI")
    dlg.OnEvent("Close", (*) => (g.Opt("-Disabled"), dlg.Destroy()))

    dlg.Add("Text", "x15 y18 w100", "Description:")
    descEdit := dlg.Add("Edit", "x120 y15 w230 h24 Background" theme_cardColor " c" theme_textColor, "No Description")

    dlg.Add("Text", "x15 y50 w100", "Address:")
    addrEdit := dlg.Add("Edit", "x120 y47 w230 h24 Background" theme_cardColor " c" theme_textColor, "0x")

    dlg.Add("Text", "x15 y82 w100", "Value Type:")
    typeDD := dlg.Add("DropDownList", "x120 y79 w230 Background" theme_cardColor " c" theme_textColor, ["Byte", "2 Bytes", "4 Bytes", "8 Bytes", "Float", "Double", "String"])
    typeDD.Value := 3 ; 4 Bytes

    dlg.Add("Text", "x15 y114 w100", "Value:")
    valEdit2 := dlg.Add("Edit", "x120 y111 w230 h24 Background" theme_cardColor " c" theme_textColor, "0")

    btnAdd := dlg.Add("Button", "x90 y150 w110 h28 Default", "Add")
    btnAdd.OnEvent("Click", (*) => SaveManual())

    btnCancel := dlg.Add("Button", "x210 y150 w110 h28", "Cancel")
    btnCancel.OnEvent("Click", (*) => (g.Opt("-Disabled"), dlg.Destroy()))

    dlg.Show("w370 h195")

    SaveManual() {
        if (addrEdit.Value == "" || addrEdit.Value == "0x") {
            MsgBox("Please enter a valid memory address!", "Validation Error", "Icon!")
            return
        }

        AddCheat(false, "", descEdit.Value, addrEdit.Value, typeDD.Text, valEdit2.Value)
        g.Opt("-Disabled")
        dlg.Destroy()
    }
}

SavedLVDoubleClick(ctrl, row) {
    if (row == 0)
        return
    global valSetEdit
    valSetEdit.Focus()
    ControlSend("^a", valSetEdit)
}

SavedLVItemCheck(ctrl, item, checked) {
    global cheatTableEntries
    if (item == 0 || item > cheatTableEntries.Length)
        return

    if (checked) {
        if (cheatTableEntries[item].freezeType == "") {
            cheatTableEntries[item].freezeType := "Freeze"
            savedLV.Modify(item, "Col1", "Freeze")
        }
        cheatTableEntries[item].active := true
    } else {
        cheatTableEntries[item].freezeType := ""
        cheatTableEntries[item].active := false
        savedLV.Modify(item, "Col1", "")
    }

    if (savedLV.GetNext() == item) {
        UpdateEditorPanel(item)
    }
}

EditSelectedRow() {
    row := savedLV.GetNext()
    if (row != 0)
        EditRow(row)
}

DeleteSelectedRows() {
    global cheatTableEntries
    indices := []
    row := 0
    Loop {
        row := savedLV.GetNext(row)
        if (row == 0)
            break
        indices.Push(row)
    }

    if (indices.Length == 0)
        return

    Loop indices.Length {
        idx := indices[indices.Length - A_Index + 1]
        savedLV.Delete(idx)
        cheatTableEntries.RemoveAt(idx)
    }
    ClearEditorPanel()
}

EditRow(row) {
    global g, cheatTableEntries
    g.Opt("+Disabled")
    dlg := Gui("+Owner" g.Hwnd, "Edit Cheat Table Entry")
    dlg.BackColor := theme_bgColor
    dlg.SetFont("s9 c" theme_textColor, "Segoe UI")
    dlg.OnEvent("Close", (*) => (g.Opt("-Disabled"), dlg.Destroy()))

    dlg.Add("Text", "x15 y18 w100", "Description:")
    descEdit := dlg.Add("Edit", "x120 y15 w230 h24 Background" theme_cardColor " c" theme_textColor, cheatTableEntries[row].desc)

    dlg.Add("Text", "x15 y50 w100", "Address:")
    addrEdit := dlg.Add("Edit", "x120 y47 w230 h24 Background" theme_cardColor " c" theme_textColor, cheatTableEntries[row].address)

    dlg.Add("Text", "x15 y82 w100", "Value Type:")
    typeDD := dlg.Add("DropDownList", "x120 y79 w230 Background" theme_cardColor " c" theme_textColor, ["Byte", "2 Bytes", "4 Bytes", "8 Bytes", "Float", "Double", "String"])

    currentType := cheatTableEntries[row].type
    types := ["Byte", "2 Bytes", "4 Bytes", "8 Bytes", "Float", "Double", "String"]
    Loop types.Length {
        if (types[A_Index] == currentType) {
            typeDD.Value := A_Index
            break
        }
    }

    dlg.Add("Text", "x15 y114 w100", "Value:")
    valEdit2 := dlg.Add("Edit", "x120 y111 w230 h24 Background" theme_cardColor " c" theme_textColor, cheatTableEntries[row].value)

    btnSave := dlg.Add("Button", "x90 y150 w110 h28 Default", "Save")
    btnSave.OnEvent("Click", (*) => SaveEdit())

    btnCancel := dlg.Add("Button", "x210 y150 w110 h28", "Cancel")
    btnCancel.OnEvent("Click", (*) => (g.Opt("-Disabled"), dlg.Destroy()))

    dlg.Show("w370 h195")

    SaveEdit() {
        desc := descEdit.Value
        addrStr := addrEdit.Value
        valType := typeDD.Text
        valVal := valEdit2.Value

        cheatTableEntries[row].desc := desc
        cheatTableEntries[row].address := addrStr
        cheatTableEntries[row].type := valType
        cheatTableEntries[row].value := valVal

        savedLV.Modify(row, "", savedLV.GetText(row, 1), desc, addrStr, valType, valVal)

        global currentPid
        if (currentPid != 0) {
            addr := Memory.ResolveAddressString(currentPid, addrStr)
            if (addr != 0 && ConfirmWrite(desc, addrStr, valType, valVal)) {
                Memory.WriteValue(currentPid, addr, valType, valVal)
            }
        }

        g.Opt("-Disabled")
        dlg.Destroy()

        if (savedLV.GetNext() == row) {
            UpdateEditorPanel(row)
        }
    }
}

; ── Standalone Trainer Generator ──────────────────────────────────────────────

MenuExportTrainer(*) {
    if (savedLV.GetCount() == 0) {
        MsgBox("Your cheat table is empty! Please add some addresses before exporting a trainer.", "Export Error", "Icon!")
        return
    }

    ShowTrainerExporter()
}

ShowTrainerExporter() {
    global currentProcessName, g
    g.Opt("+Disabled")

    exportGui := Gui("+Owner" g.Hwnd, "Trainer Standalone Exporter")
    exportGui.BackColor := theme_bgColor
    exportGui.SetFont("s9 c" theme_textColor, "Segoe UI")
    exportGui.OnEvent("Close", (*) => (g.Opt("-Disabled"), exportGui.Destroy()))

    exportGui.Add("Text", "x15 y18 w120", "Trainer Title:")
    titleEdit := exportGui.Add("Edit", "x150 y15 w230 h24 Background" theme_cardColor " c" theme_textColor, "My Custom Game Trainer")

    exportGui.Add("Text", "x15 y50 w120", "Target Process:")
    procEdit := exportGui.Add("Edit", "x150 y47 w230 h24 Background" theme_cardColor " c" theme_textColor, currentProcessName != "No Process Selected" ? currentProcessName : "notepad.exe")

    exportGui.Add("Text", "x15 y82 w120", "Author Name:")
    authorEdit := exportGui.Add("Edit", "x150 y79 w230 h24 Background" theme_cardColor " c" theme_textColor, "Cheat Engine Sharp user")

    exportGui.Add("Text", "x15 y114 w120", "Visual Theme:")
    themeDD := exportGui.Add("DropDownList", "x150 y111 w230 Background" theme_cardColor " c" theme_textColor, ["Modern Light (Clean Blue)", "Classic CE (Light + Bold)", "Teal Breeze (Teal + Light)"])
    themeDD.Value := 1

    exportGui.Add("GroupBox", "x15 y145 w365 h170 c" theme_border, " Cheat Hotkeys ")

    ; Display included cheats list to configure hotkeys
    cheatLV := exportGui.Add("ListView", "x25 y165 w345 h140 +Checked +Grid Background" theme_cardColor " c" theme_textColor, ["Use", "Description", "Hotkey"])
    cheatLV.Opt("-Redraw")

    Loop savedLV.GetCount() {
        row := A_Index
        desc := savedLV.GetText(row, 2)
        defaultHotkey := "Numpad" row
        cheatLV.Add("Checked", "", desc, defaultHotkey)
    }
    cheatLV.Opt("+Redraw")
    cheatLV.OnEvent("DoubleClick", EditHotkey)

    btnGenerate := exportGui.Add("Button", "x80 y330 w110 h30 Default", "Export Script")
    btnGenerate.OnEvent("Click", (*) => RunExporter())

    btnCancel := exportGui.Add("Button", "x210 y330 w110 h30", "Close")
    btnCancel.OnEvent("Click", (*) => (g.Opt("-Disabled"), exportGui.Destroy()))

    exportGui.Show("w395 h375")

    EditHotkey(ctrl, row) {
        if (row == 0)
            return
        exportGui.Opt("+Disabled")
        hDlg := Gui("+Owner" exportGui.Hwnd, "Change Hotkey")
        hDlg.BackColor := theme_bgColor
        hDlg.SetFont("s9 c" theme_textColor, "Segoe UI")
        hDlg.OnEvent("Close", (*) => (exportGui.Opt("-Disabled"), hDlg.Destroy()))

        hDlg.Add("Text", "x15 y18 w80", "Hotkey:")
        hkEdit := hDlg.Add("Edit", "x100 y15 w180 h24 Background" theme_cardColor " c" theme_textColor, cheatLV.GetText(row, 3))

        hDlg.Add("Text", "x15 y48 w280 c" theme_border " s8", "Use standard AHK hotkey keys (e.g. Numpad1, F1, ^F1)")

        btnSaveHk := hDlg.Add("Button", "x60 y80 w90 h26 Default", "Set")
        btnSaveHk.OnEvent("Click", (*) => SaveHk())

        btnCancelHk := hDlg.Add("Button", "x160 y80 w90 h26", "Cancel")
        btnCancelHk.OnEvent("Click", (*) => (exportGui.Opt("-Disabled"), hDlg.Destroy()))

        hDlg.Show("w300 h115")

        SaveHk() {
            cheatLV.Modify(row, "Col3", hkEdit.Value)
            exportGui.Opt("-Disabled")
            hDlg.Destroy()
        }
    }

    RunExporter() {
        if (MsgBox("The exported trainer will WRITE to the memory of '" procEdit.Value "' while running.`n`n"
            . "Only export trainers for programs you own or are authorized to modify. Trainers for online or "
            . "anti-cheat protected games can violate their Terms of Service and get accounts banned.`n`n"
            . "Continue?", "Confirm Trainer Export", "YesNo Icon?") != "Yes")
            return

        exportPath := FileSelect("S16", "trainer.ahk","Save Trainer Script", "AutoHotkey Script (*.ahk)")
        if (exportPath == "")
            return

        trainerTitle := titleEdit.Value
        targetProc := procEdit.Value
        author := authorEdit.Value
        themeSelected := themeDD.Text

        ; Read included cheats
        cheats := []
        Loop cheatLV.GetCount() {
            row := A_Index
            isChecked := (cheatLV.GetNext(row - 1, "C") == row)
            if (isChecked) {
                ; Gather variables from main cheat table
                desc := savedLV.GetText(row, 2)
                addrStr := savedLV.GetText(row, 3)
                valType := savedLV.GetText(row, 4)
                valStr := savedLV.GetText(row, 5)
                hotkey := cheatLV.GetText(row, 3)

                cheats.Push({
                    desc: desc,
                    address: addrStr,
                    type: valType,
                    value: valStr,
                    hotkey: hotkey
                })
            }
        }

        if (cheats.Length == 0) {
            MsgBox("Please check at least one cheat option to export!", "Export Error", "Icon!")
            return
        }

        ; Create Trainer script file content
        scriptText := GenerateTrainerScriptText(trainerTitle, targetProc, author, themeSelected, cheats)

        if FileExist(exportPath)
            FileDelete(exportPath)
        FileAppend(scriptText, exportPath)

        MsgBox("Standalone trainer script successfully generated and exported at:`n`n" exportPath "`n`nRun it with AutoHotkey v2. It #Includes the AHK# library from its current location, so keep that path valid (or edit the #Include line).", "Export Success", "Iconi")
        g.Opt("-Disabled")
        exportGui.Destroy()
    }
}
GenerateTrainerScriptText(trainerTitle, targetProc, author, themeSelected, cheats) {
    bgColor := "0xf0f2f5"      ; Default: Latte
    accentColor := "3182ce"     ; Accent color: blue
    textColor := "2d3748"       ; Slate text
    mutedColor := "718096"      ; Muted text/borders

    if (themeSelected == "Classic CE (Light + Bold)") {
        bgColor := "0xf0f0f0"
        accentColor := "000080"
        textColor := "000000"
        mutedColor := "505050"
    } else if (themeSelected == "Teal Breeze (Teal + Light)") {
        bgColor := "0xe6fffa"
        accentColor := "0d9488"
        textColor := "115e59"
        mutedColor := "0f766e"
    }

    ; Build cheat entries initialization
    cheatArrStr := ""
    hotkeyBindingsCode := ""
    cheatsGuiControls := ""

    Loop cheats.Length {
        ch := cheats[A_Index]

        ; Sanitize strings
        desc := StrReplace(ch.desc, "'", "''")
        addr := StrReplace(ch.address, "'", "''")
        type := ch.type
        val := ch.value
        hk := ch.hotkey

        cheatArrStr .= "    cheats.Push({desc: '" desc "', address: '" addr "', type: '" type "', value: '" val "', hotkey: '" hk "', active: false})`n"

        ; Hotkey bind line
        hotkeyBindingsCode .= "Hotkey('~" hk "', ToggleCheat" A_Index ")`n"

        ; Toggle Function for this specific cheat
        hotkeyBindingsCode .= "ToggleCheat" A_Index "(*) {`n"
        hotkeyBindingsCode .= "    ToggleCheatState(" A_Index ")`n"
        hotkeyBindingsCode .= "}`n`n"

        ; GUI controls
        yPos := 75 + (A_Index - 1) * 32
        cheatsGuiControls .= "chk" A_Index " := tGui.Add('Checkbox', 'x20 y" yPos " w360 h24', ' [" hk "]  " desc " (Val: " val ")')`n"
        cheatsGuiControls .= "chk" A_Index ".OnEvent('Click', (*) => SetCheatState(" A_Index ", chk" A_Index ".Value))`n"
        cheatsGuiControls .= "checkboxes.Push(chk" A_Index ")`n`n"
    }

    code := "
    (
        #Requires AutoHotkey v2.0
        #SingleInstance Force
        ; The AHK# library is #Included from the path it had when this trainer was generated
        ; (no embedded copy that can drift). Edit this line if you move the library.
        #Include __LIBPATH__

        ; ══════════════════════════════════════════════════════════════════════════════
        ; Standalone Game Trainer
        ; Only use this against processes you own or are authorized to modify. Writing to
        ; another program's memory may violate its ToS/anti-cheat rules and can crash it.
        ; Title: {1}
        ; Process: {2}
        ; Author: {3}
        ; Generated by Cheat Engine Sharp
        ; ══════════════════════════════════════════════════════════════════════════════
        
        class Memory extends _CSModule {
        }
        
        Memory.CSharp := '
        __LPAREN__
            using System;
            using System.Runtime.InteropServices;
            using System.Diagnostics;
            using System.Text;
            using System.Collections.Generic;
        
            public class Memory {
                [DllImport(""kernel32.dll"", SetLastError = true)]
                private static extern IntPtr OpenProcess(int access, bool inherit, int pid);
                
                [DllImport(""kernel32.dll"", SetLastError = true)]
                private static extern bool ReadProcessMemory(IntPtr hProc, IntPtr addr, byte[] buf, int size, out int read);
                
                [DllImport(""kernel32.dll"", SetLastError = true)]
                private static extern bool WriteProcessMemory(IntPtr hProc, IntPtr addr, byte[] buf, int size, out int written);
                
                [DllImport(""kernel32.dll"")]
                private static extern bool CloseHandle(IntPtr handle);
                
                [DllImport(""kernel32.dll"", SetLastError = true)]
                private static extern bool IsWow64Process(IntPtr hProcess, out bool wow64Process);
        
                [DllImport(""kernel32.dll"", SetLastError = true)]
                private static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint processId);
                
                [DllImport(""kernel32.dll"", SetLastError = true)]
                private static extern bool Module32First(IntPtr hSnapshot, ref MODULEENTRY32 lpme);
                
                [DllImport(""kernel32.dll"", SetLastError = true)]
                private static extern bool Module32Next(IntPtr hSnapshot, ref MODULEENTRY32 lpme);
        
                [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
                private struct MODULEENTRY32 {
                    public uint dwSize;
                    public uint th32ModuleID;
                    public uint th32ProcessID;
                    public uint GlblcntUsage;
                    public uint ProccntUsage;
                    public IntPtr modBaseAddr;
                    public uint modBaseSize;
                    public IntPtr hModule;
                    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
                    public string szModule;
                    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
                    public string szExePath;
                }
        
                private const int PROCESS_VM_READ = 0x0010;
                private const int PROCESS_VM_WRITE = 0x0020;
                private const int PROCESS_VM_OPERATION = 0x0008;
                private const int PROCESS_QUERY_INFORMATION = 0x0400;
                
                private const uint TH32CS_SNAPMODULE = 0x00000008;
                private const uint TH32CS_SNAPMODULE32 = 0x00000010;
        
                public static string FindProcess(string name) {
                    string clean = name.Replace("".exe"", """");
                    var procs = Process.GetProcessesByName(clean);
                    if (procs.Length == 0) return """";
                    return procs[0].Id.ToString();
                }
        
                                // Cache System for Trainer Modules
                private static Dictionary<string, long> _moduleCache = new Dictionary<string, long>(StringComparer.OrdinalIgnoreCase);
                private static int _cachedPid = 0;
                private static bool? _is64Bit = null;
                private static int _archPid = 0;
        
                private static void ClearCacheIfPidChanged(int pid) {
                    if (_cachedPid != pid) {
                        _moduleCache.Clear();
                        _cachedPid = pid;
                    }
                    if (_archPid != pid) {
                        _is64Bit = null;
                        _archPid = pid;
                    }
                }
        
                public static long GetModuleBase(int pid, string moduleName) {
                    lock (_moduleCache) {
                        ClearCacheIfPidChanged(pid);
                        if (_moduleCache.ContainsKey(moduleName)) {
                            return _moduleCache[moduleName];
                        }
                        long baseAddr = GetModuleBaseInternal(pid, moduleName);
                        if (baseAddr != 0) {
                            _moduleCache[moduleName] = baseAddr;
                        }
                        return baseAddr;
                    }
                }
        
                private static long GetModuleBaseInternal(int pid, string moduleName) {
                    try {
                        var proc = Process.GetProcessById(pid);
                        foreach (ProcessModule m in proc.Modules) {
                            if (m.ModuleName.Equals(moduleName, StringComparison.OrdinalIgnoreCase)) {
                                return m.BaseAddress.ToInt64();
                            }
                        }
                    } catch {
                        IntPtr snap = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, (uint)pid);
                        if (snap != (IntPtr)(-1) && snap != IntPtr.Zero) {
                            try {
                                var me = new MODULEENTRY32();
                                me.dwSize = (uint)Marshal.SizeOf(typeof(MODULEENTRY32));
                                if (Module32First(snap, ref me)) {
                                    do {
                                        if (me.szModule.Equals(moduleName, StringComparison.OrdinalIgnoreCase)) {
                                            return me.modBaseAddr.ToInt64();
                                        }
                                    } while (Module32Next(snap, ref me));
                                }
                            } catch { }
                            finally { CloseHandle(snap); }
                        }
                    }
                    return 0;
                }
        
                public static bool IsProcess64Bit(int pid) {
                    lock (_moduleCache) {
                        ClearCacheIfPidChanged(pid);
                        if (_is64Bit.HasValue) {
                            return _is64Bit.Value;
                        }
                        bool result = IsProcess64BitInternal(pid);
                        _is64Bit = result;
                        return result;
                    }
                }
        
                private static bool IsProcess64BitInternal(int pid) {
                    IntPtr h = OpenProcess(PROCESS_QUERY_INFORMATION, false, pid);
                    if (h == IntPtr.Zero) return IntPtr.Size == 8;
                    try {
                        bool wow64;
                        if (IsWow64Process(h, out wow64)) {
                            return Environment.Is64BitOperatingSystem ? !wow64 : false;
                        }
                        return IntPtr.Size == 8;
                    } finally { CloseHandle(h); }
                }
        
                public static long ResolvePointer(int pid, long baseAddress, long[] offsets, bool is64Bit) {
                    IntPtr h = OpenProcess(PROCESS_VM_READ, false, pid);
                    if (h == IntPtr.Zero) return 0;
                    try {
                        long currentAddr = baseAddress;
                        int ptrSize = is64Bit ? 8 : 4;
                        byte[] buf = new byte[ptrSize];
                        for (int i = 0; i < offsets.Length; i++) {
                            int read;
                            if (!ReadProcessMemory(h, new IntPtr(currentAddr), buf, ptrSize, out read) || read != ptrSize) {
                                return 0;
                            }
                            currentAddr = is64Bit ? BitConverter.ToInt64(buf, 0) : BitConverter.ToUInt32(buf, 0);
                            if (currentAddr == 0) return 0;
                            currentAddr += offsets[i];
                        }
                        return currentAddr;
                    } finally { CloseHandle(h); }
                }
        
                public static long ResolveAddressString(int pid, string addrStr) {
                    addrStr = addrStr.Trim();
                    if (addrStr.Length == 0) return 0;
                    if (addrStr.StartsWith(""["") && addrStr.EndsWith(""]"")) {
                        string inner = addrStr.Substring(1, addrStr.Length - 2);
                        string[] parts = inner.Split(',');
                        if (parts.Length == 0) return 0;
                        long baseAddr = ResolveSingleAddress(pid, parts[0]);
                        if (baseAddr == 0) return 0;
                        var offsets = new List<long>();
                        for (int i = 1; i < parts.Length; i++) {
                            offsets.Add(ParseHexOrDec(parts[i]));
                        }
                        return ResolvePointer(pid, baseAddr, offsets.ToArray(), IsProcess64Bit(pid));
                    }
                    return ResolveSingleAddress(pid, addrStr);
                }
        
                private static long ResolveSingleAddress(int pid, string s) {
                    s = s.Trim();
                    if (s.Length == 0) return 0;
                    int plusIdx = s.IndexOf('+');
                    if (plusIdx >= 0) {
                        string modName = s.Substring(0, plusIdx).Trim();
                        string offsetStr = s.Substring(plusIdx + 1).Trim();
                        long baseAddr = GetModuleBase(pid, modName);
                        if (baseAddr == 0) {
                            try { return ParseHexOrDec(s); } catch { return 0; }
                        }
                        return baseAddr + ParseHexOrDec(offsetStr);
                    }
                    long modBase = GetModuleBase(pid, s);
                    if (modBase != 0) return modBase;
                    try { return ParseHexOrDec(s); } catch { return 0; }
                }
        
                private static long ParseHexOrDec(string s) {
                    s = s.Trim();
                    if (s.StartsWith(""0x"", StringComparison.OrdinalIgnoreCase)) {
                        return Convert.ToInt64(s.Substring(2), 16);
                    }
                    try { return Convert.ToInt64(s, 10); }
                    catch { return Convert.ToInt64(s, 16); }
                }
        
                public static string ReadValue(int pid, long address, string valType) {
                    IntPtr h = OpenProcess(PROCESS_VM_READ, false, pid);
                    if (h == IntPtr.Zero) return ""??"";
                    try {
                        int size = valType == ""Byte"" ? 1 : valType == ""2 Bytes"" ? 2 : valType == ""4 Bytes"" ? 4 : valType == ""8 Bytes"" ? 8 : valType == ""Float"" ? 4 : valType == ""Double"" ? 8 : 4;
                        byte[] buf = new byte[size];
                        int read;
                        if (ReadProcessMemory(h, new IntPtr(address), buf, size, out read) && read == size) {
                            if (valType == ""Byte"") return buf[0].ToString();
                            if (valType == ""2 Bytes"") return BitConverter.ToInt16(buf, 0).ToString();
                            if (valType == ""4 Bytes"") return BitConverter.ToInt32(buf, 0).ToString();
                            if (valType == ""8 Bytes"") return BitConverter.ToInt64(buf, 0).ToString();
                            if (valType == ""Float"") return BitConverter.ToSingle(buf, 0).ToString(""F2"");
                            if (valType == ""Double"") return BitConverter.ToDouble(buf, 0).ToString(""F4"");
                        }
                        return ""??"";
                    } finally { CloseHandle(h); }
                }
        
                public static bool WriteValue(int pid, long address, string valType, string valueStr) {
                    IntPtr h = OpenProcess(PROCESS_VM_WRITE | PROCESS_VM_OPERATION, false, pid);
                    if (h == IntPtr.Zero) return false;
                    try {
                        byte[] buf = null;
                        if (valType == ""Byte"") buf = new byte[] { byte.Parse(valueStr) };
                        else if (valType == ""2 Bytes"") buf = BitConverter.GetBytes(short.Parse(valueStr));
                        else if (valType == ""4 Bytes"") buf = BitConverter.GetBytes(int.Parse(valueStr));
                        else if (valType == ""8 Bytes"") buf = BitConverter.GetBytes(long.Parse(valueStr));
                        else if (valType == ""Float"") buf = BitConverter.GetBytes(float.Parse(valueStr));
                        else if (valType == ""Double"") buf = BitConverter.GetBytes(double.Parse(valueStr));
                        if (buf == null) return false;
                        int written;
                        return WriteProcessMemory(h, new IntPtr(address), buf, buf.Length, out written);
                    } finally { CloseHandle(h); }
                }
            }
        __RPAREN__'
        
        Memory.__New()
        
        ; ── Global Core ───────────────────────────────────────────────────────────────
        
        targetProcess := ""{2}""
        currentPid := 0
        cheats := []
        
        ; Load cheats list
        {4}
        
        ; GUI Layout
        tGui := Gui(""+AlwaysOnTop -MaximizeBox -MinimizeBox"", ""{1}"")
        tGui.BackColor := ""{5}""
        tGui.SetFont(""s10 c{6}"", ""Segoe UI"")
        
        tGui.SetFont(""s14 c{7} Bold"")
        tGui.Add(""Text"", ""x10 y10 w380 Center"", ""{1}"")
        tGui.SetFont(""s9 c{8} Norm"")
        statusText := tGui.Add(""Text"", ""x10 y42 w380 Center"", ""Searching for process "" targetProcess ""..."")
        
        checkboxes := []
        
        ; Draw Cheats
        {9}
        
        tGui.Add(""GroupBox"", ""x10 y325 w380 h60 c{8}"", "" Info "")
        tGui.SetFont(""s8 c{8}"")
        tGui.Add(""Text"", ""x20 y345 w360 Center"", ""Standalone game trainer built with Cheat Engine Sharp. Author: {3}"")
        
        tGui.OnEvent(""Close"", (*) => ExitApp())
        tGui.Show(""w400 h400"")
        
        ; Set up Hotkeys
        {10}
        
        ; Check for process thread
        SetTimer(ProcessMonitorThread, 1000)
        
        ; Freeze writes thread
        SetTimer(FreezeThread, 500)
        
        ProcessMonitorThread() {
            global currentPid, targetProcess
            
            if (currentPid == 0) {
                pidStr := Memory.FindProcess(targetProcess)
                if (pidStr != """") {
                    currentPid := Integer(pidStr)
                    statusText.Text := ""🎮 Process Active (PID: "" currentPid "") 🎮""
                    statusText.SetFont(""c00FF00 Bold"")
                } else {
                    statusText.Text := ""❌ Waiting for "" targetProcess ""... ❌""
                    statusText.SetFont(""cFF0000 Bold"")
                }
            } else {
                if !ProcessExist(currentPid) {
                    currentPid := 0
                    statusText.Text := ""❌ Process Closed! Waiting... ❌""
                    statusText.SetFont(""cFF0000 Bold"")
                }
            }
        }
        
        FreezeThread() {
            global currentPid, cheats
            if (currentPid == 0)
                return
                
            if !ProcessExist(currentPid) {
                currentPid := 0
                return
            }
            for index, ch in cheats {
                if (ch.active) {
                    addr := Memory.ResolveAddressString(currentPid, ch.address)
                    if (addr != 0) {
                        Memory.WriteValue(currentPid, addr, ch.type, ch.value)
                    }
                }
            }
        }
        
        ToggleCheatState(index) {
            global cheats, checkboxes
            if (index > cheats.Length) return
            
            val := !cheats[index].active
            cheats[index].active := val
            checkboxes[index].Value := val
            SoundBeep(val ? 1000 : 500, 100)
        }
        
        SetCheatState(index, val) {
            global cheats
            if (index > cheats.Length) return
            cheats[index].active := val
            SoundBeep(val ? 1000 : 500, 100)
        }
        
        
    )"

    ; Replace placeholders
    outText := Format(code, trainerTitle, targetProc, author, cheatArrStr, bgColor, textColor, accentColor, mutedColor, cheatsGuiControls, hotkeyBindingsCode)
    outText := StrReplace(outText, "__LPAREN__", "(")
    outText := StrReplace(outText, "__RPAREN__", ")")

    ; Resolve the AHK# library path now (normalized) so the trainer #Includes it instead of embedding a copy
    libPath := A_ScriptDir "\..\..\lib\ahk#.ahk"
    fullBuf := Buffer(1040)
    if (DllCall("GetFullPathNameW", "WStr", libPath, "UInt", 520, "Ptr", fullBuf, "Ptr", 0, "UInt"))
        libPath := StrGet(fullBuf, "UTF-16")
    outText := StrReplace(outText, "__LIBPATH__", libPath)
    return outText
}

#HotIf WinActive("ahk_id " g.Hwnd)
$Enter:: {
    ctrl := g.FocusedCtrl
    if (ctrl) {
        if (ctrl.Hwnd == valSetEdit.Hwnd) {
            SetSelectedEntryValue()
            return
        } else if (ctrl.Hwnd == savedLV.Hwnd) {
            ChangeSelectedValue()
            return
        }
    }
    Send("{Enter}")
}
#HotIf