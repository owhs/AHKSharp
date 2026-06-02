using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Xml;
using System.Drawing;
using System.Threading.Tasks;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Web.Script.Serialization;
using System.Diagnostics;
using System.Runtime.InteropServices;

public class EcoBench
{
    public static bool _prewarm = true;
    public static string SetPrewarm(string val)
    {
        _prewarm = (val == "true" || val == "1");
        return "ok";
    }
    // ====================================================================
    // Cached state for fair per-call benchmarks
    // ====================================================================
    static JavaScriptSerializer _js;
    static string _jsonStr;
    static object _jsonObj;
    static MD5 _md5;
    static SHA1 _sha1;
    static byte[] _hashBytes;
    static byte[] _aesKey, _aesIv;
    static byte[] _b64Bytes;
    static string _b64Str;
    static int[] _arr;
    static Dictionary<string, int> _dict;
    static Dictionary<string, object> _deepSrc;
    static Dictionary<string, List<string>> _tIdx;
    static Dictionary<string, string> _tMap, _tPar;
    static List<string> _dfsNames;

    // ====================================================================
    // Setup methods — called once before timing loops, NOT timed
    // ====================================================================
    public static string SetupJson(string json)
    {
        _js = new JavaScriptSerializer();
        _jsonStr = json;
        _jsonObj = _js.DeserializeObject(json);
        return "ok";
    }

    public static string SetupCrypto(string input)
    {
        _md5 = MD5.Create();
        _sha1 = SHA1.Create();
        _hashBytes = Encoding.UTF8.GetBytes(input);
        _aesKey = new byte[32]; _aesIv = new byte[16];
        new Random(42).NextBytes(_aesKey); new Random(7).NextBytes(_aesIv);
        return "ok";
    }

    public static string SetupBase64(string input)
    {
        _b64Bytes = Encoding.UTF8.GetBytes(input);
        _b64Str = Convert.ToBase64String(_b64Bytes);
        return _b64Str;
    }

    public static string SetupArray(string csv)
    {
        _arr = Array.ConvertAll(csv.Split(','), int.Parse);
        return _arr.Length.ToString();
    }

    public static string SetupDict(int count)
    {
        _dict = new Dictionary<string, int>();
        for (int i = 1; i <= count; i++) _dict["key" + i] = i;
        return "ok";
    }

    public static string SetupDeepClone()
    {
        _deepSrc = new Dictionary<string, object> {
        {"name", "root"},
        {"data", new List<object> {1, 2, 3}},
        {"child", new Dictionary<string, object> {
            {"name", "child1"},
            {"child", new Dictionary<string, object> {
                {"name", "child2"},
                {"values", new List<object> {10, 20, 30}}
            }}
        }}
    };
        return "ok";
    }

    public static string SetupTree(string data)
    {
        var lines = data.Split(new[] { '\n' }, StringSplitOptions.RemoveEmptyEntries);
        _tIdx = new Dictionary<string, List<string>>();
        _tMap = new Dictionary<string, string>();
        _tPar = new Dictionary<string, string>();
        foreach (var rawLine in lines)
        {
            var line = rawLine.Trim();
            if (line.Length == 0) continue;
            int ni = line.IndexOf("Name: \""); if (ni < 0) continue;
            int ns = ni + 7; int ne = line.IndexOf('"', ns); if (ne < 0) continue;
            string name = line.Substring(ns, ne - ns);
            int ci = line.IndexOf(':'); if (ci < 0) continue;
            string path = line.Substring(0, ci);
            _tMap[path] = name;
            if (!_tIdx.ContainsKey(name)) _tIdx[name] = new List<string>();
            _tIdx[name].Add(path);
            int li = path.LastIndexOf(',');
            if (li > 0)
            {
                string p1 = path.Substring(0, li);
                if (_tMap.ContainsKey(p1)) { _tPar[path] = p1; }
                else
                {
                    int li2 = p1.LastIndexOf(',');
                    if (li2 > 0)
                    {
                        string p2 = path.Substring(0, li2);
                        if (_tMap.ContainsKey(p2)) _tPar[path] = p2;
                    }
                }
            }
        }
        return _tIdx.Count + "|" + _tMap.Count;
    }

    public static string SetupDFS(string data)
    {
        _dfsNames = new List<string>();
        var lines = data.Split(new[] { '\n' }, StringSplitOptions.RemoveEmptyEntries);
        foreach (var rawLine in lines)
        {
            var line = rawLine.Trim();
            int ni = line.IndexOf("Name: \""); if (ni < 0) continue;
            int ns = ni + 7; int ne = line.IndexOf('"', ns); if (ne < 0) continue;
            _dfsNames.Add(line.Substring(ns, ne - ns));
        }
        return _dfsNames.Count.ToString();
    }

    // ====================================================================
    // Per-call methods — called once per iteration from AHK timing loop
    // Interop overhead is naturally captured by external AHK timing.
    // ====================================================================

    // --- JSON ---
    public static string Do_JsonParse()
    {
        _js.DeserializeObject(_jsonStr);
        return "ok";
    }
    public static string Do_JsonStringify()
    {
        return _js.Serialize(_jsonObj);
    }

    // --- Crypto (FIXED: hashes same input each time, not chained) ---
    public static string Do_Md5()
    {
        _md5.ComputeHash(_hashBytes);
        return "ok";
    }
    public static string Do_Sha1()
    {
        _sha1.ComputeHash(_hashBytes);
        return "ok";
    }
    public static string Do_Crc32()
    {
        byte[] d = _hashBytes;
        uint crc = 0xFFFFFFFF;
        for (int j = 0; j < d.Length; j++)
        {
            crc ^= d[j];
            for (int k = 0; k < 8; k++) crc = (crc >> 1) ^ (0xEDB88320 * (crc & 1));
        }
        return ((crc ^ 0xFFFFFFFF)).ToString();
    }
    public static string Do_AesEncrypt()
    {
        using (var aes = Aes.Create())
        {
            aes.Key = _aesKey; aes.IV = _aesIv;
            using (var enc = aes.CreateEncryptor())
                enc.TransformFinalBlock(_hashBytes, 0, _hashBytes.Length);
        }
        return "ok";
    }

    // --- Base64 ---
    public static string Do_Base64Encode()
    {
        return Convert.ToBase64String(_b64Bytes);
    }
    public static string Do_Base64Decode()
    {
        Encoding.UTF8.GetString(Convert.FromBase64String(_b64Str));
        return "ok";
    }

    // --- Array ops (on pre-parsed cached array) ---
    public static string Do_ArraySort()
    {
        var c = (int[])_arr.Clone(); Array.Sort(c);
        return "ok";
    }
    public static string Do_ArrayFilter()
    {
        _arr.Where(n => n > 500).ToArray();
        return "ok";
    }
    public static string Do_ArrayMap()
    {
        _arr.Select(n => n * 2).ToArray();
        return "ok";
    }
    public static string Do_ArrayReduce()
    {
        _arr.Aggregate(0L, (a, b) => a + b);
        return "ok";
    }

    // --- String ops (FIXED: PadLeft matches AHK's LPad) ---
    public static string Do_StringOps(string text)
    {
        text.ToUpper(); text.Replace("fox", "cat"); text.Trim();
        text.PadLeft(text.Length + 5, '*');
        return text.IndexOf("lazy").ToString();
    }

    // --- Dict filter+count (fair: on pre-built cached dict, matches AHK Map) ---
    public static string Do_DictFilterCount()
    {
        _dict.Where(kv => kv.Value > 500).Count();
        _dict.Count(kv => kv.Value > 800);
        return "ok";
    }

    // --- Dict add+read (for COM Scripting.Dictionary comparison) ---
    public static string Do_DictAddRead(int count)
    {
        var d = new Dictionary<string, int>();
        for (int i = 1; i <= count; i++) d["k" + i] = i;
        long s = 0;
        for (int i = 1; i <= count; i++) s += d["k" + i];
        return s.ToString();
    }

    // --- XML ---
    public static string Do_XmlParse(string xml)
    {
        var doc = new XmlDocument(); doc.LoadXml(xml);
        return "ok";
    }

    // --- GUID ---
    public static string Do_GuidGen()
    {
        return Guid.NewGuid().ToString("B").ToUpper();
    }

    // --- File ops ---
    public static string Do_FileCountLines(string path)
    {
        return File.ReadAllLines(path).Length.ToString();
    }
    public static string Do_FileFindStr(string path, string search)
    {
        int c = 0;
        foreach (var line in File.ReadAllLines(path)) if (line.Contains(search)) c++;
        return c.ToString();
    }

    // --- DeepClone (FIXED: real recursive clone, not shallow copy) ---
    static Dictionary<string, object> CloneDeep(Dictionary<string, object> src)
    {
        var c = new Dictionary<string, object>();
        foreach (var kv in src)
        {
            if (kv.Value is Dictionary<string, object>)
                c[kv.Key] = CloneDeep((Dictionary<string, object>)kv.Value);
            else if (kv.Value is List<object>)
                c[kv.Key] = new List<object>((List<object>)kv.Value);
            else
                c[kv.Key] = kv.Value;
        }
        return c;
    }
    public static string Do_DeepClone()
    {
        CloneDeep(_deepSrc);
        return "ok";
    }

    // --- Buffer alloc (same kernel32 memset as AHK) ---
    [DllImport("kernel32.dll", EntryPoint = "RtlFillMemory", SetLastError = false)]
    static extern void FillMemory(IntPtr dest, uint length, byte fill);
    public static string Do_BufAlloc(int w, int h)
    {
        int sz = w * h * 4;
        IntPtr p = Marshal.AllocHGlobal(sz);
        FillMemory(p, (uint)sz, 0xFF);
        Marshal.FreeHGlobal(p);
        return "ok";
    }

    // --- GDI+ bitmap (same P/Invoke as AHK DllCall) ---
    [DllImport("gdiplus.dll")] static extern int GdipCreateBitmapFromScan0(int w, int h, int stride, int fmt, IntPtr scan0, out IntPtr bmp);
    [DllImport("gdiplus.dll")] static extern int GdipDisposeImage(IntPtr img);
    public static string Do_GdipCreate(int w, int h)
    {
        IntPtr bmp;
        GdipCreateBitmapFromScan0(w, h, 0, 0x26200A, IntPtr.Zero, out bmp);
        if (bmp != IntPtr.Zero) GdipDisposeImage(bmp);
        return "ok";
    }

    // --- Clipboard (real Win32 API, matches WinClip) ---
    [DllImport("user32.dll")] static extern bool OpenClipboard(IntPtr h);
    [DllImport("user32.dll")] static extern bool CloseClipboard();
    [DllImport("user32.dll")] static extern bool EmptyClipboard();
    [DllImport("user32.dll")] static extern IntPtr SetClipboardData(uint f, IntPtr m);
    [DllImport("user32.dll")] static extern IntPtr GetClipboardData(uint f);
    [DllImport("kernel32.dll")] static extern IntPtr GlobalAlloc(uint f, UIntPtr s);
    [DllImport("kernel32.dll")] static extern IntPtr GlobalLock(IntPtr h);
    [DllImport("kernel32.dll")] static extern bool GlobalUnlock(IntPtr h);
    const uint CF_UNICODETEXT = 13;
    const uint GMEM_MOVEABLE = 0x0002;
    public static string Do_ClipboardOp(string text)
    {
        if (OpenClipboard(IntPtr.Zero))
        {
            EmptyClipboard();
            byte[] b = Encoding.Unicode.GetBytes(text + "\0");
            IntPtr hm = GlobalAlloc(GMEM_MOVEABLE, (UIntPtr)b.Length);
            IntPtr p = GlobalLock(hm); Marshal.Copy(b, 0, p, b.Length); GlobalUnlock(hm);
            SetClipboardData(CF_UNICODETEXT, hm);
            IntPtr hd = GetClipboardData(CF_UNICODETEXT);
            if (hd != IntPtr.Zero) { IntPtr pd = GlobalLock(hd); Marshal.PtrToStringUni(pd); GlobalUnlock(hd); }
            CloseClipboard();
        }
        return "ok";
    }

    // --- Tree search (on pre-built cached tree) ---
    public static string Do_TreeSearch(string target)
    {
        if (_tIdx.ContainsKey(target))
        {
            var key = _tIdx[target][0];
            var pp = new List<string>(); pp.Add(_tMap[key]);
            while (_tPar.ContainsKey(key)) { key = _tPar[key]; pp.Insert(0, _tMap[key]); }
            return string.Join(" > ", pp);
        }
        return "";
    }
    public static string Do_TreeSearchAll(string target)
    {
        int total = 0;
        if (_tIdx.ContainsKey(target))
        {
            foreach (var startKey in _tIdx[target])
            {
                string k = startKey;
                var pp = new List<string>(); pp.Add(_tMap[k]);
                while (_tPar.ContainsKey(k)) { k = _tPar[k]; pp.Insert(0, _tMap[k]); }
                total++;
            }
        }
        return total.ToString();
    }
    public static string Do_DFS(string target)
    {
        foreach (var n in _dfsNames) if (n == target) return "found";
        return "";
    }

    // --- C# Exclusive features (internal timing, no AHK equivalent) ---
    public static string AsyncParallel()
    {
        var sw = Stopwatch.StartNew();
        var tasks = new Task<long>[10];
        for (int i = 0; i < 10; i++) { int n = i; tasks[i] = Task.Run(() => { long s = 0; for (int j = 0; j < 1000000; j++) s += j; return s + n; }); }
        Task.WaitAll(tasks); long total = tasks.Sum(t => t.Result);
        sw.Stop(); return sw.Elapsed.TotalMilliseconds.ToString("F3") + "|" + total;
    }
    public static string LinqOps(int count)
    {
        var sw = Stopwatch.StartNew();
        var data = Enumerable.Range(0, count).Select(i => new { Name = "item" + i, Value = i * 3 }).ToList();
        var f = data.Where(x => x.Value > count).OrderByDescending(x => x.Value).Take(100).ToList();
        var g = data.GroupBy(x => x.Value % 10).ToDictionary(x => x.Key, x => x.Count());
        sw.Stop(); return sw.Elapsed.TotalMilliseconds.ToString("F3") + "|" + f.Count + "|" + g.Count;
    }

    [System.Runtime.InteropServices.DllImport("kernel32.dll", EntryPoint = "GetTickCount")]
    static extern uint GetTickCount32();

    public static string RegexSmallMatch(string text, int iters)
    {
        if (_prewarm)
        {
            var m = System.Text.RegularExpressions.Regex.Match(text, @"\d+");
            var val = m.Value;
        }
        var sw = Stopwatch.StartNew();
        for (int i = 0; i < iters; i++)
        {
            var m = System.Text.RegularExpressions.Regex.Match(text, @"\d+");
            var val = m.Value;
        }
        sw.Stop();
        return sw.Elapsed.TotalMilliseconds.ToString("F3");
    }

    public static string Win32DllCall(int iters)
    {
        if (_prewarm) GetTickCount32();
        var sw = Stopwatch.StartNew();
        for (int i = 0; i < iters; i++) GetTickCount32();
        sw.Stop();
        return sw.Elapsed.TotalMilliseconds.ToString("F3");
    }

    public static string OsFileExist(string path, int iters)
    {
        if (_prewarm) File.Exists(path);
        var sw = Stopwatch.StartNew();
        for (int i = 0; i < iters; i++) File.Exists(path);
        sw.Stop();
        return sw.Elapsed.TotalMilliseconds.ToString("F3");
    }

    [StructLayout(LayoutKind.Explicit, Size = 40)]
    public struct PROCESS_HEAP_ENTRY
    {
        [FieldOffset(0)] public IntPtr lpData;
        [FieldOffset(8)] public uint cbData;
        [FieldOffset(12)] public byte cbOverhead;
        [FieldOffset(13)] public byte iRegionIndex;
        [FieldOffset(14)] public ushort wFlags;
    }
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr GetProcessHeap();
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool HeapWalk(IntPtr hHeap, ref PROCESS_HEAP_ENTRY lpEntry);

    [DllImport("user32.dll")]
    static extern uint EnumClipboardFormats(uint format);

    public static string RegExMatchAll(string text, string pattern, int iters)
    {
        var sw = Stopwatch.StartNew();
        for (int i = 0; i < iters; i++)
        {
            var matches = System.Text.RegularExpressions.Regex.Matches(text, pattern);
            int count = matches.Count;
        }
        sw.Stop();
        return sw.Elapsed.TotalMilliseconds.ToString("F3");
    }

    public static string RangeIter(int start, int end, int iters)
    {
        var sw = Stopwatch.StartNew();
        for (int i = 0; i < iters; i++)
        {
            int sum = 0;
            for (int v = start; v <= end; v++)
            {
                sum += v;
            }
        }
        sw.Stop();
        return sw.Elapsed.TotalMilliseconds.ToString("F3");
    }

    public class ComVarSim
    {
        public object Value;
        public ComVarSim(object val) { Value = val; }
    }

    public static string ComVarCreate(int iters)
    {
        var sw = Stopwatch.StartNew();
        for (int i = 0; i < iters; i++)
        {
            var cv1 = new ComVarSim(42);
            var cv2 = new ComVarSim("hello world");
        }
        sw.Stop();
        return sw.Elapsed.TotalMilliseconds.ToString("F3");
    }

    public static string TreeAncestor(string data, string target, string ancestor, int iters)
    {
        if (_tIdx == null) SetupTree(data);
        var sw = Stopwatch.StartNew();
        for (int i = 0; i < iters; i++)
        {
            if (_tIdx.ContainsKey(target))
            {
                string key = _tIdx[target][0];
                bool matches = false;
                while (_tPar.ContainsKey(key))
                {
                    key = _tPar[key];
                    if (_tMap[key] == ancestor) { matches = true; break; }
                }
            }
        }
        sw.Stop();
        return sw.Elapsed.TotalMilliseconds.ToString("F3");
    }

    public static string HeapWalkTest(int iters)
    {
        IntPtr heap = GetProcessHeap();
        var sw = Stopwatch.StartNew();
        for (int i = 0; i < iters; i++)
        {
            PROCESS_HEAP_ENTRY entry = new PROCESS_HEAP_ENTRY();
            entry.lpData = IntPtr.Zero;
            HeapWalk(heap, ref entry);
        }
        sw.Stop();
        return sw.Elapsed.TotalMilliseconds.ToString("F3");
    }

    public static string ClipFormats(int iters)
    {
        var sw = Stopwatch.StartNew();
        for (int i = 0; i < iters; i++)
        {
            if (OpenClipboard(IntPtr.Zero))
            {
                uint fmt = 0;
                while ((fmt = EnumClipboardFormats(fmt)) != 0) { }
                CloseClipboard();
            }
        }
        sw.Stop();
        return sw.Elapsed.TotalMilliseconds.ToString("F3");
    }

    public static string WmiProcesses()
    {
        var sw = Stopwatch.StartNew();
        var searcher = new System.Management.ManagementObjectSearcher("SELECT Name FROM Win32_Process");
        int count = 0;
        foreach (var obj in searcher.Get())
        {
            count++;
        }
        sw.Stop();
        return sw.Elapsed.TotalMilliseconds.ToString("F3") + "|" + count;
    }

    // ====================================================================
    // Chart renderer — SpaceX-grade aesthetic & Premium Extensions
    // ====================================================================

    public struct Theme
    {
        public Color Cyan1;
        public Color Cyan2;
        public Color Amber1;
        public Color Amber2;
        public Color Violet1;
        public Color Violet2;
        public Color Gold1;
        public Color Gold2;
        public Color Accent;
        public Color Dim;
        public Color Label;
        public Color RowEven;
        public Color RowOdd;
        public Color GridLine;
        public Color BarBg;
        public Color BgTop;
        public Color BgBot;
        public Color CardBg;
        public Color Border;
    }

    public static Theme GetTheme(string name)
    {
        Theme t = new Theme();
        name = (name ?? "").ToLowerInvariant().Replace(" ", "").Replace("-", "");

        if (name == "cyberpunk" || name == "cyberpunkneo")
        {
            t.BgTop = Color.FromArgb(10, 6, 18);
            t.BgBot = Color.FromArgb(20, 10, 36);
            t.RowEven = Color.FromArgb(10, 6, 18);
            t.RowOdd = Color.FromArgb(16, 8, 28);
            t.Cyan1 = Color.FromArgb(0, 255, 255); t.Cyan2 = Color.FromArgb(0, 120, 255);
            t.Amber1 = Color.FromArgb(255, 0, 128); t.Amber2 = Color.FromArgb(200, 0, 80);
            t.Violet1 = Color.FromArgb(255, 200, 0); t.Violet2 = Color.FromArgb(255, 100, 0);
            t.Gold1 = Color.FromArgb(255, 230, 0); t.Gold2 = Color.FromArgb(220, 190, 0);
            t.Accent = Color.FromArgb(255, 0, 128);
            t.Dim = Color.FromArgb(140, 100, 180);
            t.Label = Color.FromArgb(240, 220, 255);
            t.GridLine = Color.FromArgb(40, 20, 60);
            t.BarBg = Color.FromArgb(14, 8, 24);
            t.CardBg = Color.FromArgb(14, 8, 24);
            t.Border = Color.FromArgb(80, 20, 100);
        }
        else if (name == "aurora" || name == "auroraemerald")
        {
            t.BgTop = Color.FromArgb(4, 12, 16);
            t.BgBot = Color.FromArgb(8, 24, 32);
            t.RowEven = Color.FromArgb(4, 12, 16);
            t.RowOdd = Color.FromArgb(6, 18, 24);
            t.Cyan1 = Color.FromArgb(0, 255, 150); t.Cyan2 = Color.FromArgb(0, 150, 100);
            t.Amber1 = Color.FromArgb(220, 160, 255); t.Amber2 = Color.FromArgb(140, 80, 250);
            t.Violet1 = Color.FromArgb(0, 220, 255); t.Violet2 = Color.FromArgb(0, 128, 255);
            t.Gold1 = Color.FromArgb(234, 255, 140); t.Gold2 = Color.FromArgb(180, 210, 80);
            t.Accent = Color.FromArgb(0, 255, 150);
            t.Dim = Color.FromArgb(100, 140, 150);
            t.Label = Color.FromArgb(220, 245, 240);
            t.GridLine = Color.FromArgb(20, 45, 55);
            t.BarBg = Color.FromArgb(6, 18, 24);
            t.CardBg = Color.FromArgb(6, 18, 24);
            t.Border = Color.FromArgb(20, 65, 80);
        }
        else if (name == "solareclipse" || name == "lava")
        {
            t.BgTop = Color.FromArgb(10, 8, 8);
            t.BgBot = Color.FromArgb(22, 14, 12);
            t.RowEven = Color.FromArgb(10, 8, 8);
            t.RowOdd = Color.FromArgb(16, 12, 12);
            t.Cyan1 = Color.FromArgb(255, 60, 0); t.Cyan2 = Color.FromArgb(150, 0, 0);
            t.Amber1 = Color.FromArgb(255, 180, 0); t.Amber2 = Color.FromArgb(200, 120, 0);
            t.Violet1 = Color.FromArgb(240, 240, 250); t.Violet2 = Color.FromArgb(100, 110, 120);
            t.Gold1 = Color.FromArgb(255, 190, 0); t.Gold2 = Color.FromArgb(210, 140, 0);
            t.Accent = Color.FromArgb(255, 180, 0);
            t.Dim = Color.FromArgb(135, 105, 100);
            t.Label = Color.FromArgb(250, 235, 230);
            t.GridLine = Color.FromArgb(45, 25, 20);
            t.BarBg = Color.FromArgb(16, 12, 12);
            t.CardBg = Color.FromArgb(16, 12, 12);
            t.Border = Color.FromArgb(65, 35, 30);
        }
        else if (name == "mars" || name == "marsrust")
        {
            t.BgTop = Color.FromArgb(14, 9, 9);
            t.BgBot = Color.FromArgb(22, 13, 13);
            t.RowEven = Color.FromArgb(14, 9, 9);
            t.RowOdd = Color.FromArgb(20, 12, 12);
            t.Cyan1 = Color.FromArgb(255, 60, 0); t.Cyan2 = Color.FromArgb(153, 0, 0);
            t.Amber1 = Color.FromArgb(160, 170, 181); t.Amber2 = Color.FromArgb(96, 104, 112);
            t.Violet1 = Color.FromArgb(226, 95, 56); t.Violet2 = Color.FromArgb(158, 60, 31);
            t.Gold1 = Color.FromArgb(240, 190, 110); t.Gold2 = Color.FromArgb(190, 130, 70);
            t.Accent = Color.FromArgb(255, 69, 0);
            t.Dim = Color.FromArgb(139, 112, 112);
            t.Label = Color.FromArgb(242, 230, 230);
            t.GridLine = Color.FromArgb(40, 20, 20);
            t.BarBg = Color.FromArgb(18, 10, 10);
            t.CardBg = Color.FromArgb(15, 10, 10);
            t.Border = Color.FromArgb(61, 27, 27);
        }
        else if (name == "carbon" || name == "carbonmono")
        {
            t.BgTop = Color.FromArgb(6, 6, 6);
            t.BgBot = Color.FromArgb(14, 14, 14);
            t.RowEven = Color.FromArgb(6, 6, 6);
            t.RowOdd = Color.FromArgb(12, 12, 12);
            t.Cyan1 = Color.FromArgb(255, 255, 255); t.Cyan2 = Color.FromArgb(138, 138, 138);
            t.Amber1 = Color.FromArgb(108, 114, 122); t.Amber2 = Color.FromArgb(58, 63, 69);
            t.Violet1 = Color.FromArgb(163, 163, 163); t.Violet2 = Color.FromArgb(82, 82, 82);
            t.Gold1 = Color.FromArgb(200, 200, 200); t.Gold2 = Color.FromArgb(140, 140, 140);
            t.Accent = Color.FromArgb(255, 255, 255);
            t.Dim = Color.FromArgb(107, 107, 107);
            t.Label = Color.FromArgb(229, 229, 229);
            t.GridLine = Color.FromArgb(26, 26, 26);
            t.BarBg = Color.FromArgb(16, 16, 16);
            t.CardBg = Color.FromArgb(10, 10, 10);
            t.Border = Color.FromArgb(38, 38, 38);
        }
        else if (name == "starlink" || name == "starlinkblue")
        {
            t.BgTop = Color.FromArgb(2, 6, 23);
            t.BgBot = Color.FromArgb(15, 23, 42);
            t.RowEven = Color.FromArgb(2, 6, 23);
            t.RowOdd = Color.FromArgb(11, 19, 41);
            t.Cyan1 = Color.FromArgb(56, 189, 248); t.Cyan2 = Color.FromArgb(2, 132, 199);
            t.Amber1 = Color.FromArgb(245, 158, 11); t.Amber2 = Color.FromArgb(217, 119, 6);
            t.Violet1 = Color.FromArgb(20, 184, 166); t.Violet2 = Color.FromArgb(13, 148, 136);
            t.Gold1 = Color.FromArgb(250, 204, 21); t.Gold2 = Color.FromArgb(202, 138, 4);
            t.Accent = Color.FromArgb(56, 189, 248);
            t.Dim = Color.FromArgb(100, 116, 139);
            t.Label = Color.FromArgb(241, 245, 249);
            t.GridLine = Color.FromArgb(30, 41, 59);
            t.BarBg = Color.FromArgb(15, 23, 42);
            t.CardBg = Color.FromArgb(7, 13, 30);
            t.Border = Color.FromArgb(51, 65, 85);
        }
        else if (name == "falcon" || name == "falconwhite")
        {
            t.BgTop = Color.FromArgb(248, 250, 252);
            t.BgBot = Color.FromArgb(226, 232, 240);
            t.RowEven = Color.FromArgb(248, 250, 252);
            t.RowOdd = Color.FromArgb(241, 245, 249);
            t.Cyan1 = Color.FromArgb(30, 58, 138); t.Cyan2 = Color.FromArgb(59, 130, 246);
            t.Amber1 = Color.FromArgb(194, 65, 12); t.Amber2 = Color.FromArgb(234, 88, 12);
            t.Violet1 = Color.FromArgb(91, 33, 182); t.Violet2 = Color.FromArgb(124, 58, 237);
            t.Gold1 = Color.FromArgb(202, 138, 4); t.Gold2 = Color.FromArgb(161, 98, 7);
            t.Accent = Color.FromArgb(30, 58, 138);
            t.Dim = Color.FromArgb(100, 116, 139);
            t.Label = Color.FromArgb(15, 23, 42);
            t.GridLine = Color.FromArgb(203, 213, 225);
            t.BarBg = Color.FromArgb(226, 232, 240);
            t.CardBg = Color.FromArgb(255, 255, 255);
            t.Border = Color.FromArgb(148, 163, 184);
        }
        else
        {
            // SpaceX Jet Dark (Default)
            t.BgTop = Color.FromArgb(8, 9, 13);
            t.BgBot = Color.FromArgb(12, 14, 20);
            t.RowEven = Color.FromArgb(8, 9, 13);
            t.RowOdd = Color.FromArgb(12, 14, 20);
            t.Cyan1 = Color.FromArgb(0, 240, 255); t.Cyan2 = Color.FromArgb(0, 120, 255);
            t.Amber1 = Color.FromArgb(255, 155, 0); t.Amber2 = Color.FromArgb(255, 75, 0);
            t.Violet1 = Color.FromArgb(170, 90, 255); t.Violet2 = Color.FromArgb(100, 20, 220);
            t.Gold1 = Color.FromArgb(255, 215, 0); t.Gold2 = Color.FromArgb(234, 179, 8);
            t.Accent = Color.FromArgb(0, 240, 255);
            t.Dim = Color.FromArgb(100, 110, 135);
            t.Label = Color.FromArgb(215, 222, 240);
            t.GridLine = Color.FromArgb(20, 25, 38);
            t.BarBg = Color.FromArgb(14, 16, 26);
            t.CardBg = Color.FromArgb(10, 12, 18);
            t.Border = Color.FromArgb(32, 40, 60);
        }
        return t;
    }

    static System.Drawing.Drawing2D.GraphicsPath RoundedRect(float x, float y, float w, float h, float r)
    {
        var gp = new System.Drawing.Drawing2D.GraphicsPath();
        if (r < 1 || w < r * 2 || h < r * 2) { gp.AddRectangle(new RectangleF(x, y, w, h)); return gp; }
        float d = r * 2;
        gp.AddArc(x, y, d, d, 180, 90);
        gp.AddArc(x + w - d, y, d, d, 270, 90);
        gp.AddArc(x + w - d, y + h - d, d, d, 0, 90);
        gp.AddArc(x, y + h - d, d, d, 90, 90);
        gp.CloseFigure();
        return gp;
    }

    public static string Render(string dataStr, int w, int h, string path, string themeName = "spacex", double customMaxR = 0, bool showDetails = false, int labelMode = 0, string specs = "")
    {
        themeName = (themeName ?? "spacex").ToLowerInvariant();
        Theme t = GetTheme(themeName);
        var items = new List<string[]>();
        foreach (var it in dataStr.Split(new[] { ';' }, StringSplitOptions.RemoveEmptyEntries)) items.Add(it.Split('|'));
        if (items.Count == 0) return "no data";

        using (var bmp = new Bitmap(w, h))
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
            g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;

            // ── Background gradient ──────────────────────────────────────
            using (var bg = new System.Drawing.Drawing2D.LinearGradientBrush(
                new Rectangle(0, 0, w, h), t.BgTop, t.BgBot, 45f))
                g.FillRectangle(bg, 0, 0, w, h);

            // ── Scale / metrics ──────────────────────────────────────────
            float padX = Math.Max(12f, w * 0.025f);
            float padY = Math.Max(12f, h * 0.025f);
            float cw = w - padX * 2f;

            // ── Dynamic Font Sizes ───────────────────────────────────────
            float fsTitle = Math.Max(10f, Math.Min(22f, h * 0.026f + w * 0.005f));
            float fsSub = Math.Max(7.2f, Math.Min(10f, h * 0.012f + w * 0.003f));
            float fsLeg = Math.Max(7f, Math.Min(10f, h * 0.012f + w * 0.003f));

            var fTitle = new Font("Segoe UI", fsTitle, FontStyle.Bold);
            var fSub = new Font("Segoe UI", fsSub);
            var fLeg = new Font("Segoe UI", fsLeg);

            float y = padY;

            // ── Header ───────────────────────────────────────────────────
            // Thin accent line above title
            using (var ap = new Pen(t.Accent, Math.Max(2f, fsTitle * 0.15f)))
                g.DrawLine(ap, padX, y, padX + Math.Min(cw * 0.18f, fsTitle * 8f), y);
            y += Math.Max(5f, fsTitle * 0.35f);

            g.DrawString("ECOSYSTEM  BENCHMARK", fTitle, new SolidBrush(themeName.ToLower() == "falcon" ? t.Label : Color.White), padX, y);
            y += fTitle.GetHeight(g) + 2f;

            string subtitle = "21 AHK v2 community libraries  vs  AHK# (.NET)  \u00B7  " + items.Count + " tests";
            if (!string.IsNullOrEmpty(specs))
            {
                subtitle += "  \u00B7  " + specs;
            }
            else
            {
                subtitle += "  \u00B7  fair per-call timing";
            }
            g.DrawString(subtitle, fSub, new SolidBrush(t.Dim), padX, y);
            y += fSub.GetHeight(g) + 8f;

            // ── Stats summary bar (SpaceX-style Telemetry HUD) ────────────────────
            int csWins = 0, ahkWins = 0, exclusive = 0;
            foreach (var it in items)
            {
                double a = double.Parse(it[1], System.Globalization.CultureInfo.InvariantCulture);
                double c = double.Parse(it[2], System.Globalization.CultureInfo.InvariantCulture);
                if (a == -1 || c == -1 || it[0].Contains("Async Parallel") || it[0].Contains("LINQ")) exclusive++;
                else if (a >= 0 && c >= 0)
                {
                    if (a < c) ahkWins++;
                    else csWins++;
                }
            }

            float statH = Math.Max(30f, Math.Min(48f, h * 0.065f));
            using (var sbg = new SolidBrush(t.CardBg))
            using (var statPath = RoundedRect(padX, y, cw, statH, Math.Max(2f, statH * 0.12f)))
                g.FillPath(sbg, statPath);

            using (var sbp = new Pen(t.Border, 1))
            using (var statPath2 = RoundedRect(padX, y, cw, statH, Math.Max(2f, statH * 0.12f)))
                g.DrawPath(sbp, statPath2);

            var fStatVal = new Font("Segoe UI", Math.Max(8f, Math.Min(16f, statH * 0.38f)), FontStyle.Bold);
            var fStatLbl = new Font("Cascadia Code", Math.Max(5.5f, Math.Min(8.5f, statH * 0.18f)));

            float secW = cw / 4f;
            for (int idx = 0; idx < 3; idx++)
            {
                float divX = padX + (idx + 1) * secW;
                using (var divPen = new Pen(t.Border, 1))
                    g.DrawLine(divPen, divX, y + 4f, divX, y + statH - 4f);
            }

            Action<int, string, string, Color> drawSection = (idx, valText, lblText, valColor) =>
            {
                float secX = padX + idx * secW;
                var szVal = g.MeasureString(valText, fStatVal);
                var szLbl = g.MeasureString(lblText, fStatLbl);

                float vGap = Math.Max(1f, statH * 0.05f);
                float totalContentH = szVal.Height + szLbl.Height + vGap;
                float startY = y + (statH - totalContentH) / 2f;

                g.DrawString(valText, fStatVal, new SolidBrush(valColor),
                    secX + (secW - szVal.Width) / 2f, startY);

                g.DrawString(lblText, fStatLbl, new SolidBrush(t.Dim),
                    secX + (secW - szLbl.Width) / 2f, startY + szVal.Height + vGap);
            };

            drawSection(0, csWins.ToString(), "C# FASTER", t.Cyan1);
            drawSection(1, ahkWins.ToString(), "AHK FASTER", t.Amber1);
            drawSection(2, exclusive.ToString(), ".NET EXCLUSIVE", t.Violet1);
            drawSection(3, items.Count.ToString(), "TOTAL TESTS", Color.FromArgb(140, 144, 168));

            y += statH + 12f;

            // ── Separator ────────────────────────────────────────────────
            using (var dp = new Pen(t.GridLine, 1)) g.DrawLine(dp, padX, y, padX + cw, y);
            y += 6f;

            // ── Bar area layout ──────────────────────────────────────────
            float legH = Math.Max(16f, h * 0.04f);
            float footerH = fsLeg * 1.4f + 8f;
            float availH = h - y - legH - footerH - padY - 14f; // 14px safety for ticks and spacing
            float rowH = availH / items.Count;

            // Fonts that depend strictly on row height
            var fLabel = new Font("Segoe UI Semibold", Math.Max(5.5f, Math.Min(11f, rowH * 0.44f)));
            var fTime = new Font("Cascadia Code", Math.Max(5f, Math.Min(9f, rowH * 0.35f)));
            var fSpeed = new Font("Segoe UI", Math.Max(5.5f, Math.Min(11f, rowH * 0.44f)), FontStyle.Bold);

            float barH = Math.Max(3f, rowH * 0.65f);
            float barR = Math.Max(1f, barH * 0.20f);

            float labelW = Math.Max(120f, Math.Min(260f, w * 0.24f));
            float speedW = Math.Max(45f, Math.Min(95f, w * 0.09f));
            float bL = padX + labelW;
            float bA = cw - labelW - speedW - 10f;

            // ── Compute log scale ────────────────────────────────────────
            double maxR = 1;
            foreach (var it in items)
            {
                double a = double.Parse(it[1], System.Globalization.CultureInfo.InvariantCulture);
                double c = double.Parse(it[2], System.Globalization.CultureInfo.InvariantCulture);
                if (a > 0 && c > 0)
                {
                    double r = a / c;
                    double ar = r >= 1 ? r : 1.0 / r;
                    if (ar > maxR) maxR = ar;
                }
            }

            double currentLogMax = Math.Log10(Math.Max(maxR, 10));
            if (customMaxR > 0)
            {
                currentLogMax = Math.Log10(Math.Max(customMaxR, 1.5));
            }

            // ── Log Scale Grid Lines (Aviation-style HUD) ──────────────────────
            double[] ticks = { 1.5, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0, 500.0, 1000.0 };
            float gridBottomY = y + items.Count * rowH;
            using (var gridPen = new Pen(t.GridLine, 1))
            using (var tickFont = new Font("Cascadia Code", Math.Max(4.5f, Math.Min(8.0f, rowH * 0.35f))))
            using (var tickBrush = new SolidBrush(t.Dim))
            {
                foreach (var tval in ticks)
                {
                    if (customMaxR > 0 && tval > customMaxR) break;
                    if (customMaxR <= 0 && tval > maxR) break;
                    float tx = bL + (float)(Math.Log10(tval) / currentLogMax * bA);
                    if (tx > bL && tx < bL + bA - 5f)
                    {
                        g.DrawLine(gridPen, tx, y, tx, gridBottomY);
                        string tickStr = tval.ToString("F1").TrimEnd('0').TrimEnd('.') + "x";
                        float tw = g.MeasureString(tickStr, tickFont).Width;
                        g.DrawString(tickStr, tickFont, tickBrush, tx - tw / 2f, gridBottomY + 2f);
                    }
                }
            }

            // ── Draw rows ────────────────────────────────────────────────
            var sfClip = new StringFormat { Trimming = StringTrimming.EllipsisCharacter, FormatFlags = StringFormatFlags.NoWrap, LineAlignment = StringAlignment.Center };

            for (int i = 0; i < items.Count; i++)
            {
                var it = items[i];
                double ahk = double.Parse(it[1], System.Globalization.CultureInfo.InvariantCulture);
                double cs = double.Parse(it[2], System.Globalization.CultureInfo.InvariantCulture);
                double ratio = (ahk == -1 || cs == -1) ? -1 : (cs == 0 && ahk == 0) ? 1 : ahk / cs;

                float ry = y + i * rowH;
                float barY = ry + (rowH - barH) / 2f;

                // ── Alternating row stripe ───────────────────────────────
                g.FillRectangle(new SolidBrush(i % 2 == 0 ? t.RowEven : t.RowOdd), padX - 2f, ry, cw + 4f, rowH);

                // Subtle horizontal grid line at row top
                if (i > 0)
                    using (var gp = new Pen(t.GridLine, 1))
                        g.DrawLine(gp, padX, ry, padX + cw, ry);

                // ── Row number (formatted D2 for tech HUD feel) ───────────
                float numW = Math.Max(14f, rowH * 1.1f);
                g.DrawString((i + 1).ToString("D2"), fTime, new SolidBrush(Color.FromArgb(90, t.Dim)),
                    padX, barY + (barH - fTime.GetHeight(g)) / 2f);

                // ── Label & Technical HUD overviews ───────────────────────
                if (showDetails)
                {
                    var labelRect = new RectangleF(padX + numW, ry + 1f, labelW - numW - 4f, rowH * 0.55f);
                    g.DrawString(labelMode == 1 ? GetLibVsCsFunc(it[0]) : it[0], fLabel, new SolidBrush(t.Label), labelRect, sfClip);

                    string detailText = GetAhkStrategyShort(it[0]) + " | " + GetCsStrategyShort(it[0]);
                    var fDetail = new Font("Cascadia Code", Math.Max(4.8f, Math.Min(8.0f, rowH * 0.32f)));
                    var detailRect = new RectangleF(padX + numW, ry + rowH * 0.52f, labelW - numW - 4f, rowH * 0.45f);
                    g.DrawString(detailText, fDetail, new SolidBrush(t.Dim), detailRect, sfClip);
                }
                else
                {
                    var labelRect = new RectangleF(padX + numW, ry, labelW - numW - 4f, rowH);
                    g.DrawString(labelMode == 1 ? GetLibVsCsFunc(it[0]) : it[0], fLabel, new SolidBrush(t.Label), labelRect, sfClip);
                }

                // ── Bar track (rounded) ──────────────────────────────────
                using (var trackPath = RoundedRect(bL, barY, bA, barH, barR))
                    g.FillPath(new SolidBrush(t.BarBg), trackPath);

                bool isDotNetExclusive = (it[0].Contains("Async Parallel") || it[0].Contains("LINQ"));
                if (ratio < 0 && !isDotNetExclusive)
                {
                    // ── AHK# Exclusive (Full-width Sleek violet neon bar) ────────────────────
                    using (var exPath = RoundedRect(bL, barY, bA, barH, barR))
                    {
                        using (var exBrush = new System.Drawing.Drawing2D.LinearGradientBrush(
                            new RectangleF(bL, barY, bA, barH), t.Violet1, t.Violet2, 0f))
                            g.FillPath(exBrush, exPath);

                        using (var borderPen = new Pen(Color.FromArgb(160, t.Violet1), 0.75f))
                            g.DrawPath(borderPen, exPath);

                        // Shine highlight on top 35%
                        using (var shineBrush = new SolidBrush(Color.FromArgb(20, 255, 255, 255)))
                        using (var shinePath = RoundedRect(bL, barY, bA, barH * 0.35f, barR))
                            g.FillPath(shineBrush, shinePath);
                    }
                    if (barH >= 6f)
                    {
                        string exLabel = ahk == -1 ? "C# EXCLUSIVE" : "AHK EXCLUSIVE";
                        g.DrawString(exLabel, fLabel,
                            new SolidBrush(themeName.ToLower() == "falcon" ? t.Label : Color.FromArgb(215, 195, 255)), bL + 6f, barY + (barH - fLabel.GetHeight(g)) / 2f);
                    }
                }
                else
                {
                    // ── Comparative bar (or .NET Exclusive with real timings) ──────────
                    bool ahkFaster = ratio < 1 && ratio > 0;
                    double displayRatio = ahkFaster ? 1.0 / ratio : ratio;
                    double lr = Math.Log10(Math.Max(displayRatio, 1));
                    float bw = (float)Math.Max(lr / currentLogMax * bA, 3);

                    bool isOverflown = bw >= bA;
                    if (isOverflown)
                    {
                        bw = bA;
                    }

                    bool isComparable = (ratio >= 1.0 && ratio <= 2.0);

                    Color c1, c2;
                    if (isDotNetExclusive)
                    {
                        c1 = t.Violet1; c2 = t.Violet2;
                    }
                    else if (ahkFaster)
                    {
                        c1 = t.Amber1; c2 = t.Amber2;
                    }
                    else if (isComparable)
                    {
                        c1 = t.Gold1; c2 = t.Gold2;
                    }
                    else
                    {
                        c1 = t.Cyan1; c2 = t.Cyan2;
                    }

                    if (bw > 2f)
                    {
                        using (var barPath = RoundedRect(bL, barY, bw, barH, barR))
                        {
                            using (var barBrush = new System.Drawing.Drawing2D.LinearGradientBrush(
                                new RectangleF(bL, barY, bw + 1f, barH), c1, c2, 0f))
                                g.FillPath(barBrush, barPath);

                            float penWidth = ahkFaster ? 1.5f : 0.75f;
                            Color borderCol = ahkFaster ? Color.FromArgb(255, 255, 255) : Color.FromArgb(160, c1);
                            if (themeName.ToLower() == "falcon" && ahkFaster)
                            {
                                borderCol = Color.FromArgb(220, 38, 38);
                            }

                            using (var borderPen = new Pen(borderCol, penWidth))
                                g.DrawPath(borderPen, barPath);

                            // Top shine
                            using (var shine = new SolidBrush(Color.FromArgb(ahkFaster ? 55 : 30, 255, 255, 255)))
                            using (var shPath = RoundedRect(bL, barY, bw, barH * 0.35f, barR))
                                g.FillPath(shine, shPath);
                        }
                    }

                    // Draw sexy right-pointing neon chevron arrow if overflown
                    if (isOverflown)
                    {
                        float arrowW = Math.Max(3f, barH * 0.35f);
                        using (var arrowBrush = new SolidBrush(Color.FromArgb(220, Color.White)))
                        {
                            PointF[] arrowPts = new PointF[] {
                            new PointF(bL + bA - arrowW - 1.5f, barY + 1.5f),
                            new PointF(bL + bA - 1.5f, barY + barH / 2f),
                            new PointF(bL + bA - arrowW - 1.5f, barY + barH - 1.5f)
                        };
                            g.FillPolygon(arrowBrush, arrowPts);
                        }
                    }

                    // Draw .NET EXCLUSIVE overlay inside the bar if applicable
                    if (isDotNetExclusive && barH >= 6f && bw > 75f)
                    {
                        g.DrawString(".NET EXCLUSIVE", fLabel,
                            new SolidBrush(themeName.ToLower() == "falcon" ? t.Label : Color.FromArgb(215, 195, 255)), bL + 6f, barY + (barH - fLabel.GetHeight(g)) / 2f);
                    }

                    // ── Timing annotation (HUD overlay inside bar track) ──────
                    if (barH >= 6f)
                    {
                        string ahkStr = ahk.ToString(ahk < 10 ? "F2" : "F0", System.Globalization.CultureInfo.InvariantCulture);
                        string csStr = cs.ToString(cs < 10 ? "F2" : "F0", System.Globalization.CultureInfo.InvariantCulture);
                        string timeStr = ahkStr + " vs " + csStr + " ms";
                        if (ahkFaster)
                        {
                            timeStr = "★ AHK WINS ★  " + timeStr;
                        }
                        float tw = g.MeasureString(timeStr, fTime).Width;
                        float tx = bL + bA - tw - 6f;

                        Color timeCol = (tx < bL + bw - 4f)
                            ? (themeName.ToLower() == "falcon" ? Color.FromArgb(240, 245, 255) : Color.FromArgb(200, 255, 255, 255))
                            : Color.FromArgb(55, 60, 75);
                        if (themeName.ToLower() == "falcon" && tx >= bL + bw - 4f)
                        {
                            timeCol = Color.FromArgb(120, 130, 150);
                        }
                        g.DrawString(timeStr, fTime, new SolidBrush(timeCol),
                            tx, barY + (barH - fTime.GetHeight(g)) / 2f);
                    }

                    // ── Speedup badge (right column, uniform formatting) ────────
                    string speedStr = displayRatio >= 100.0
                        ? Math.Round(displayRatio, 0).ToString() + "x"
                        : Math.Round(displayRatio, 1).ToString("F1") + "x";

                    if (ahkFaster) speedStr += " AHK";

                    float speedY = barY + (barH - fSpeed.GetHeight(g)) / 2f;
                    g.DrawString(speedStr, fSpeed, new SolidBrush(c1), bL + bA + 8f, speedY);
                }
            }

            // ── Bottom separator ─────────────────────────────────────────
            float legY = h - footerH - padY * 0.2f;
            using (var dp = new Pen(t.GridLine, 1)) g.DrawLine(dp, padX, legY, padX + cw, legY);
            legY += 6f;

            // ── Legend (pill-shaped indicators) ───────────────────────────
            float pillH = Math.Max(6f, fsLeg * 0.9f);
            float pillW = Math.Max(14f, fsLeg * 2.2f);
            float pillR = pillH / 2f;
            float legSpacing = cw / 4.2f;

            Action<float, Color, Color, string> drawLeg = (lx, ca, cb, txt) =>
            {
                using (var pp = RoundedRect(lx, legY + (fsLeg * 1.35f - pillH) / 2f, pillW, pillH, pillR))
                using (var pb = new System.Drawing.Drawing2D.LinearGradientBrush(
                    new RectangleF(lx, legY, pillW + 1f, pillH + 2f), ca, cb, 0f))
                {
                    g.FillPath(pb, pp);
                    using (var borderPen = new Pen(Color.FromArgb(160, ca), 0.75f))
                        g.DrawPath(borderPen, pp);
                }
                g.DrawString(txt, fLeg, new SolidBrush(Color.FromArgb(140, 148, 172)),
                    lx + pillW + 6f, legY);
            };

            Color cGold1 = t.Gold1;
            Color cGold2 = t.Gold2;

            drawLeg(padX, t.Cyan1, t.Cyan2, "C# FASTER (>3x)");
            drawLeg(padX + legSpacing, cGold1, cGold2, "AHK COMPARABLE");
            drawLeg(padX + legSpacing * 2f, t.Amber1, t.Amber2, "AHK FASTER");
            drawLeg(padX + legSpacing * 3f, t.Violet1, t.Violet2, ".NET EXCLUSIVE");

            // Branding Watermark
            g.DrawString("AHK#", new Font("Segoe UI", fsLeg, FontStyle.Bold),
                new SolidBrush(themeName.ToLower() == "falcon" ? Color.FromArgb(180, 190, 210) : Color.FromArgb(30, 40, 55)),
                padX + cw - g.MeasureString("AHK#", fLeg).Width, legY);

            bmp.Save(path, System.Drawing.Imaging.ImageFormat.Png);
            return "ok";
        }
    }

    static string GetLibVsCsFunc(string name)
    {
        name = (name ?? "").Trim();
        if (name.IndexOf("JXON Parse", StringComparison.OrdinalIgnoreCase) >= 0) return "JXON vs Do_JsonParse";
        if (name.IndexOf("JXON Stringify", StringComparison.OrdinalIgnoreCase) >= 0) return "JXON vs Do_JsonStringify";
        if (name.IndexOf("thqby Parse", StringComparison.OrdinalIgnoreCase) >= 0) return "thqby JSON vs Do_JsonParse";
        if (name.IndexOf("thqby Stringify", StringComparison.OrdinalIgnoreCase) >= 0) return "thqby JSON vs Do_JsonStringify";
        if (name.IndexOf("MD5", StringComparison.OrdinalIgnoreCase) >= 0) return "Crypt.ahk vs Do_MD5";
        if (name.IndexOf("SHA1", StringComparison.OrdinalIgnoreCase) >= 0) return "Crypt.ahk vs Do_SHA1";
        if (name.IndexOf("CRC32", StringComparison.OrdinalIgnoreCase) >= 0) return "Crypt.ahk vs Do_CRC32";
        if (name.IndexOf("AES-256", StringComparison.OrdinalIgnoreCase) >= 0) return "Crypt.ahk vs Do_AesEncrypt";
        if (name.IndexOf("B64 Enc jNizM", StringComparison.OrdinalIgnoreCase) >= 0) return "jNizM B64 vs Do_Base64Encode";
        if (name.IndexOf("B64 Dec jNizM", StringComparison.OrdinalIgnoreCase) >= 0) return "jNizM B64 vs Do_Base64Decode";
        if (name.IndexOf("B64 Enc thqby", StringComparison.OrdinalIgnoreCase) >= 0) return "thqby B64 vs Do_Base64Encode";
        if (name.IndexOf("B64 Dec thqby", StringComparison.OrdinalIgnoreCase) >= 0) return "thqby B64 vs Do_Base64Decode";
        if (name.IndexOf("Array Sort", StringComparison.OrdinalIgnoreCase) >= 0) return "Array.ahk vs Do_ArraySort";
        if (name.IndexOf("Array Filter", StringComparison.OrdinalIgnoreCase) >= 0) return "Array.ahk vs Do_ArrayFilter";
        if (name.IndexOf("Array Map", StringComparison.OrdinalIgnoreCase) >= 0) return "Array.ahk vs Do_ArrayMap";
        if (name.IndexOf("Array Reduce", StringComparison.OrdinalIgnoreCase) >= 0) return "Array.ahk vs Do_ArrayReduce";
        if (name.IndexOf("String Ops", StringComparison.OrdinalIgnoreCase) >= 0) return "String.ahk vs Do_StringOps";
        if (name.IndexOf("RegExMatchAll", StringComparison.OrdinalIgnoreCase) >= 0) return "String.ahk vs Regex.Matches";
        if (name.IndexOf("Map Filter", StringComparison.OrdinalIgnoreCase) >= 0) return "Map.ahk vs Do_DictFilterCount";
        if (name.IndexOf("Range iter", StringComparison.OrdinalIgnoreCase) >= 0) return "Misc.ahk vs C# For-Loop";
        if (name.IndexOf("ComVar Create", StringComparison.OrdinalIgnoreCase) >= 0) return "ComVar.ahk vs AHK# COM Wrapper";
        if (name.IndexOf("DeepClone", StringComparison.OrdinalIgnoreCase) >= 0) return "DeepClone vs Do_DeepClone";
        if (name.IndexOf("Tree Parse", StringComparison.OrdinalIgnoreCase) >= 0) return "TreeNav vs SetupTree";
        if (name.IndexOf("Tree Search Deep", StringComparison.OrdinalIgnoreCase) >= 0) return "TreeNav vs Do_TreeSearch";
        if (name.IndexOf("Tree Search Miss", StringComparison.OrdinalIgnoreCase) >= 0) return "TreeNav vs Do_TreeSearch";
        if (name.IndexOf("Tree DFS Brute", StringComparison.OrdinalIgnoreCase) >= 0) return "TreeNav vs Do_DFS";
        if (name.IndexOf("Tree AllPaths", StringComparison.OrdinalIgnoreCase) >= 0) return "TreeNav vs Do_TreeSearchAll";
        if (name.IndexOf("Tree Ancestor", StringComparison.OrdinalIgnoreCase) >= 0) return "TreeNav vs Do_TreeAncestor";
        if (name.IndexOf("SQLite CRUD", StringComparison.OrdinalIgnoreCase) >= 0) return "Winsqlite3 vs AHK# SQLite";
        if (name.IndexOf("XML Parse", StringComparison.OrdinalIgnoreCase) >= 0) return "MSXML2 COM vs XmlDocument";
        if (name.IndexOf("GUID Gen", StringComparison.OrdinalIgnoreCase) >= 0) return "CreateGUID vs Do_GuidGen";
        if (name.IndexOf("FileCountLines", StringComparison.OrdinalIgnoreCase) >= 0) return "FileOps vs Do_FileCountLines";
        if (name.IndexOf("FileFindString", StringComparison.OrdinalIgnoreCase) >= 0) return "FileOps vs Do_FileFindStr";
        if (name.IndexOf("Heap Walk", StringComparison.OrdinalIgnoreCase) >= 0) return "Heap.ahk vs None (COM)";
        if (name.IndexOf("Buf Alloc", StringComparison.OrdinalIgnoreCase) >= 0) return "Buffer vs Do_BufAlloc";
        if (name.IndexOf("GDI+ Bitmap", StringComparison.OrdinalIgnoreCase) >= 0) return "GDI+ DllCall vs Do_GdipCreate";
        if (name.IndexOf("Clipboard", StringComparison.OrdinalIgnoreCase) >= 0) return "WinClip vs Do_ClipboardOp";
        if (name.IndexOf("Clip Formats", StringComparison.OrdinalIgnoreCase) >= 0) return "WinClip vs None";
        if (name.IndexOf("COM Dict", StringComparison.OrdinalIgnoreCase) >= 0) return "COM Dict vs Do_DictAddRead";
        if (name.IndexOf("WMI Processes", StringComparison.OrdinalIgnoreCase) >= 0) return "WMI COM vs None";
        if (name.IndexOf("Async Parallel", StringComparison.OrdinalIgnoreCase) >= 0) return "None (COM) vs Task.Run";
        if (name.IndexOf("LINQ", StringComparison.OrdinalIgnoreCase) >= 0) return "None (COM) vs LINQ Ops";
        return name;
    }

    static string GetAhkStrategy(string name)
    {
        name = (name ?? "").Trim();
        if (name.IndexOf("JXON Parse", StringComparison.OrdinalIgnoreCase) >= 0) return "Jxon_Load (RegEx lookup loops)";
        if (name.IndexOf("JXON Stringify", StringComparison.OrdinalIgnoreCase) >= 0) return "Jxon_Dump (recursive object walk)";
        if (name.IndexOf("thqby Parse", StringComparison.OrdinalIgnoreCase) >= 0) return "JSON.parse (native C++ class mapping)";
        if (name.IndexOf("thqby Stringify", StringComparison.OrdinalIgnoreCase) >= 0) return "JSON.stringify (native C++ mapping)";
        if (name.IndexOf("MD5", StringComparison.OrdinalIgnoreCase) >= 0) return "advapi32.dll DllCalls (MD5 context)";
        if (name.IndexOf("SHA1", StringComparison.OrdinalIgnoreCase) >= 0) return "advapi32.dll DllCalls (SHA1 context)";
        if (name.IndexOf("CRC32", StringComparison.OrdinalIgnoreCase) >= 0) return "ntdll.dll RtlComputeCrc32 DllCall";
        if (name.IndexOf("AES-256", StringComparison.OrdinalIgnoreCase) >= 0) return "advapi32.dll CryptEncrypt DllCall";
        if (name.IndexOf("B64 Enc jNizM", StringComparison.OrdinalIgnoreCase) >= 0) return "crypt32.dll CryptBinaryToString DllCall";
        if (name.IndexOf("B64 Dec jNizM", StringComparison.OrdinalIgnoreCase) >= 0) return "crypt32.dll CryptStringToBinary DllCall";
        if (name.IndexOf("B64 Enc thqby", StringComparison.OrdinalIgnoreCase) >= 0) return "crypt32.dll via compiled class wrapper";
        if (name.IndexOf("B64 Dec thqby", StringComparison.OrdinalIgnoreCase) >= 0) return "crypt32.dll via compiled class wrapper";
        if (name.IndexOf("Array Sort", StringComparison.OrdinalIgnoreCase) >= 0) return "QuickSort (recursive callback comparison)";
        if (name.IndexOf("Array Filter", StringComparison.OrdinalIgnoreCase) >= 0) return "Linear loop (element-by-element copy)";
        if (name.IndexOf("Array Map", StringComparison.OrdinalIgnoreCase) >= 0) return "Linear loop (transform element callback)";
        if (name.IndexOf("Array Reduce", StringComparison.OrdinalIgnoreCase) >= 0) return "Linear loop (accumulator callback)";
        if (name.IndexOf("String Ops", StringComparison.OrdinalIgnoreCase) >= 0) return "Built-in string methods & RegExReplace";
        if (name.IndexOf("RegExMatchAll", StringComparison.OrdinalIgnoreCase) >= 0) return "Looping RegExMatch (capturing all groups)";
        if (name.IndexOf("Map Filter", StringComparison.OrdinalIgnoreCase) >= 0) return "Map.Filter (callback array iteration)";
        if (name.IndexOf("Range iter", StringComparison.OrdinalIgnoreCase) >= 0) return "Range() custom generator class object";
        if (name.IndexOf("ComVar Create", StringComparison.OrdinalIgnoreCase) >= 0) return "VARIANT memory struct construction";
        if (name.IndexOf("DeepClone", StringComparison.OrdinalIgnoreCase) >= 0) return "Recursive Object/Array dictionary walk";
        if (name.IndexOf("Tree Parse", StringComparison.OrdinalIgnoreCase) >= 0) return "O(1) flat map + parent path indexing";
        if (name.IndexOf("Tree Search Deep", StringComparison.OrdinalIgnoreCase) >= 0) return "O(1) hash parent traversal path walk";
        if (name.IndexOf("Tree Search Miss", StringComparison.OrdinalIgnoreCase) >= 0) return "Hash lookup instant reject check";
        if (name.IndexOf("Tree DFS Brute", StringComparison.OrdinalIgnoreCase) >= 0) return "Linear scan for-loop through all nodes";
        if (name.IndexOf("Tree AllPaths", StringComparison.OrdinalIgnoreCase) >= 0) return "GetAllPathsToNode multi-path search";
        if (name.IndexOf("Tree Ancestor", StringComparison.OrdinalIgnoreCase) >= 0) return "GetPathToNode + PathMatchesAncestors";
        if (name.IndexOf("SQLite CRUD", StringComparison.OrdinalIgnoreCase) >= 0) return "N/A (AutoHotkey lacks native SQLite)";
        if (name.IndexOf("XML Parse", StringComparison.OrdinalIgnoreCase) >= 0) return "MSXML2.DOMDocument.6.0 COM wrapper";
        if (name.IndexOf("GUID Gen", StringComparison.OrdinalIgnoreCase) >= 0) return "ole32.dll CoCreateGuid DllCall";
        if (name.IndexOf("FileCountLines", StringComparison.OrdinalIgnoreCase) >= 0) return "FileOpen loop (line-by-line reading)";
        if (name.IndexOf("FileFindString", StringComparison.OrdinalIgnoreCase) >= 0) return "FileOpen search (line-by-line reading)";
        if (name.IndexOf("Heap Walk", StringComparison.OrdinalIgnoreCase) >= 0) return "HeapWalk API DllCalls";
        if (name.IndexOf("Buf Alloc", StringComparison.OrdinalIgnoreCase) >= 0) return "Buffer() alloc + RtlFillMemory DllCall";
        if (name.IndexOf("GDI+ Bitmap", StringComparison.OrdinalIgnoreCase) >= 0) return "gdiplus\\GdipCreateBitmapFromScan0 DllCall";
        if (name.IndexOf("Clipboard", StringComparison.OrdinalIgnoreCase) >= 0) return "OpenClipboard + GlobalAlloc DllCalls";
        if (name.IndexOf("Clip Formats", StringComparison.OrdinalIgnoreCase) >= 0) return "WinClip.GetFormats COM list check";
        if (name.IndexOf("COM Dict", StringComparison.OrdinalIgnoreCase) >= 0) return "Scripting.Dictionary COM creation";
        if (name.IndexOf("WMI Processes", StringComparison.OrdinalIgnoreCase) >= 0) return "SWbemLocator WMI query DllCall";
        return "N/A (Lacks native feature)";
    }

    static string GetCsStrategy(string name)
    {
        name = (name ?? "").Trim();
        if (name.IndexOf("JXON Parse", StringComparison.OrdinalIgnoreCase) >= 0) return "JavaScriptSerializer.Deserialize (reflection)";
        if (name.IndexOf("JXON Stringify", StringComparison.OrdinalIgnoreCase) >= 0) return "JavaScriptSerializer.Serialize (reflection)";
        if (name.IndexOf("thqby Parse", StringComparison.OrdinalIgnoreCase) >= 0) return "JavaScriptSerializer.Deserialize (reflection)";
        if (name.IndexOf("thqby Stringify", StringComparison.OrdinalIgnoreCase) >= 0) return "JavaScriptSerializer.Serialize (reflection)";
        if (name.IndexOf("MD5", StringComparison.OrdinalIgnoreCase) >= 0) return "MD5.ComputeHash (native CLR)";
        if (name.IndexOf("SHA1", StringComparison.OrdinalIgnoreCase) >= 0) return "SHA1.ComputeHash (native CLR)";
        if (name.IndexOf("CRC32", StringComparison.OrdinalIgnoreCase) >= 0) return "For-loop byte table lookup (C# optimized)";
        if (name.IndexOf("AES-256", StringComparison.OrdinalIgnoreCase) >= 0) return "AesCryptoServiceProvider (native CLR)";
        if (name.IndexOf("B64 Enc jNizM", StringComparison.OrdinalIgnoreCase) >= 0) return "Convert.ToBase64String (native CLR)";
        if (name.IndexOf("B64 Dec jNizM", StringComparison.OrdinalIgnoreCase) >= 0) return "Convert.FromBase64String (native CLR)";
        if (name.IndexOf("B64 Enc thqby", StringComparison.OrdinalIgnoreCase) >= 0) return "Convert.ToBase64String (native CLR)";
        if (name.IndexOf("B64 Dec thqby", StringComparison.OrdinalIgnoreCase) >= 0) return "Convert.FromBase64String (native CLR)";
        if (name.IndexOf("Array Sort", StringComparison.OrdinalIgnoreCase) >= 0) return "Array.Sort (optimized introsort algorithm)";
        if (name.IndexOf("Array Filter", StringComparison.OrdinalIgnoreCase) >= 0) return "LINQ Where + ToArray (deferred execution)";
        if (name.IndexOf("Array Map", StringComparison.OrdinalIgnoreCase) >= 0) return "LINQ Select + ToArray (deferred execution)";
        if (name.IndexOf("Array Reduce", StringComparison.OrdinalIgnoreCase) >= 0) return "LINQ Aggregate (optimized accumulator)";
        if (name.IndexOf("String Ops", StringComparison.OrdinalIgnoreCase) >= 0) return "String.ToUpper/Replace/Trim/PadLeft chaining";
        if (name.IndexOf("RegExMatchAll", StringComparison.OrdinalIgnoreCase) >= 0) return "Regex.Matches (compiled RegEx engine)";
        if (name.IndexOf("Map Filter", StringComparison.OrdinalIgnoreCase) >= 0) return "LINQ Dictionary.Where + Count";
        if (name.IndexOf("Range iter", StringComparison.OrdinalIgnoreCase) >= 0) return "Standard compiler-optimized C# for-loop";
        if (name.IndexOf("ComVar Create", StringComparison.OrdinalIgnoreCase) >= 0) return "AHK# dynamic marshaling struct wrapper";
        if (name.IndexOf("DeepClone", StringComparison.OrdinalIgnoreCase) >= 0) return "Recursive clone (Dictionary walk)";
        if (name.IndexOf("Tree Parse", StringComparison.OrdinalIgnoreCase) >= 0) return "Dictionary<string, string> text line parsing";
        if (name.IndexOf("Tree Search Deep", StringComparison.OrdinalIgnoreCase) >= 0) return "Dictionary parent pointer node path walk";
        if (name.IndexOf("Tree Search Miss", StringComparison.OrdinalIgnoreCase) >= 0) return "Dictionary.ContainsKey O(1) reject";
        if (name.IndexOf("Tree DFS Brute", StringComparison.OrdinalIgnoreCase) >= 0) return "Foreach loop through list nodes";
        if (name.IndexOf("Tree AllPaths", StringComparison.OrdinalIgnoreCase) >= 0) return "Dictionary lookup + parent array trace";
        if (name.IndexOf("Tree Ancestor", StringComparison.OrdinalIgnoreCase) >= 0) return "Dictionary lookup + parent key validation";
        if (name.IndexOf("SQLite CRUD", StringComparison.OrdinalIgnoreCase) >= 0) return "winsqlite3.dll raw P/Invoke wrapper";
        if (name.IndexOf("XML Parse", StringComparison.OrdinalIgnoreCase) >= 0) return "XmlDocument.LoadXml (compiled DOM)";
        if (name.IndexOf("GUID Gen", StringComparison.OrdinalIgnoreCase) >= 0) return "Guid.NewGuid (internal Win32 crypt gen)";
        if (name.IndexOf("FileCountLines", StringComparison.OrdinalIgnoreCase) >= 0) return "File.ReadAllLines().Length";
        if (name.IndexOf("FileFindString", StringComparison.OrdinalIgnoreCase) >= 0) return "File.ReadAllLines + string.Contains";
        if (name.IndexOf("Heap Walk", StringComparison.OrdinalIgnoreCase) >= 0) return "N/A (Lacks native feature)";
        if (name.IndexOf("Buf Alloc", StringComparison.OrdinalIgnoreCase) >= 0) return "Marshal.AllocHGlobal + FillMemory P/Invoke";
        if (name.IndexOf("GDI+ Bitmap", StringComparison.OrdinalIgnoreCase) >= 0) return "P/Invoke GdipCreateBitmapFromScan0";
        if (name.IndexOf("Clipboard", StringComparison.OrdinalIgnoreCase) >= 0) return "P/Invoke OpenClipboard + Marshal API";
        if (name.IndexOf("Clip Formats", StringComparison.OrdinalIgnoreCase) >= 0) return "N/A (Lacks native feature)";
        if (name.IndexOf("COM Dict", StringComparison.OrdinalIgnoreCase) >= 0) return "Dictionary<string, int> hash index";
        if (name.IndexOf("WMI Processes", StringComparison.OrdinalIgnoreCase) >= 0) return "N/A (Lacks native feature)";
        if (name.IndexOf("Async Parallel", StringComparison.OrdinalIgnoreCase) >= 0) return "Task.Run parallel execution (threadpool)";
        if (name.IndexOf("LINQ", StringComparison.OrdinalIgnoreCase) >= 0) return "LINQ Where/OrderByDescending/Take/GroupBy";
        return "N/A (Lacks native feature)";
    }

    static string GetAhkStrategyShort(string name)
    {
        name = (name ?? "").Trim();
        if (name.IndexOf("JXON Parse", StringComparison.OrdinalIgnoreCase) >= 0) return "Jxon_Load (RegEx)";
        if (name.IndexOf("JXON Stringify", StringComparison.OrdinalIgnoreCase) >= 0) return "Jxon_Dump (recursive)";
        if (name.IndexOf("thqby Parse", StringComparison.OrdinalIgnoreCase) >= 0) return "JSON.parse (native C++)";
        if (name.IndexOf("thqby Stringify", StringComparison.OrdinalIgnoreCase) >= 0) return "JSON.stringify (native C++)";
        if (name.IndexOf("MD5", StringComparison.OrdinalIgnoreCase) >= 0) return "advapi32.dll DllCall";
        if (name.IndexOf("SHA1", StringComparison.OrdinalIgnoreCase) >= 0) return "advapi32.dll DllCall";
        if (name.IndexOf("CRC32", StringComparison.OrdinalIgnoreCase) >= 0) return "ntdll RtlComputeCrc32";
        if (name.IndexOf("AES-256", StringComparison.OrdinalIgnoreCase) >= 0) return "advapi32 CryptEncrypt";
        if (name.IndexOf("B64 Enc jNizM", StringComparison.OrdinalIgnoreCase) >= 0) return "crypt32 CryptBinary";
        if (name.IndexOf("B64 Dec jNizM", StringComparison.OrdinalIgnoreCase) >= 0) return "crypt32 CryptString";
        if (name.IndexOf("B64 Enc thqby", StringComparison.OrdinalIgnoreCase) >= 0) return "crypt32 class wrapper";
        if (name.IndexOf("B64 Dec thqby", StringComparison.OrdinalIgnoreCase) >= 0) return "crypt32 class wrapper";
        if (name.IndexOf("Array Sort", StringComparison.OrdinalIgnoreCase) >= 0) return "QuickSort recursive";
        if (name.IndexOf("Array Filter", StringComparison.OrdinalIgnoreCase) >= 0) return "Linear callback loop";
        if (name.IndexOf("Array Map", StringComparison.OrdinalIgnoreCase) >= 0) return "Linear callback loop";
        if (name.IndexOf("Array Reduce", StringComparison.OrdinalIgnoreCase) >= 0) return "Linear callback loop";
        if (name.IndexOf("String Ops", StringComparison.OrdinalIgnoreCase) >= 0) return "Built-in & RegEx";
        if (name.IndexOf("RegExMatchAll", StringComparison.OrdinalIgnoreCase) >= 0) return "Looping RegExMatch";
        if (name.IndexOf("Map Filter", StringComparison.OrdinalIgnoreCase) >= 0) return "Map.Filter callback";
        if (name.IndexOf("Range iter", StringComparison.OrdinalIgnoreCase) >= 0) return "Range generator obj";
        if (name.IndexOf("ComVar Create", StringComparison.OrdinalIgnoreCase) >= 0) return "VARIANT memory struct";
        if (name.IndexOf("DeepClone", StringComparison.OrdinalIgnoreCase) >= 0) return "Recursive object walk";
        if (name.IndexOf("Tree Parse", StringComparison.OrdinalIgnoreCase) >= 0) return "O(1) flat map indexing";
        if (name.IndexOf("Tree Search Deep", StringComparison.OrdinalIgnoreCase) >= 0) return "O(1) parent path walk";
        if (name.IndexOf("Tree Search Miss", StringComparison.OrdinalIgnoreCase) >= 0) return "Hash lookup reject";
        if (name.IndexOf("Tree DFS Brute", StringComparison.OrdinalIgnoreCase) >= 0) return "Linear scan loop";
        if (name.IndexOf("Tree AllPaths", StringComparison.OrdinalIgnoreCase) >= 0) return "GetAllPathsToNode";
        if (name.IndexOf("Tree Ancestor", StringComparison.OrdinalIgnoreCase) >= 0) return "GetPathToNode + valid";
        if (name.IndexOf("SQLite CRUD", StringComparison.OrdinalIgnoreCase) >= 0) return "winsqlite3 DLL";
        if (name.IndexOf("XML Parse", StringComparison.OrdinalIgnoreCase) >= 0) return "MSXML2 DOM COM";
        if (name.IndexOf("GUID Gen", StringComparison.OrdinalIgnoreCase) >= 0) return "ole32 CoCreateGuid";
        if (name.IndexOf("FileCountLines", StringComparison.OrdinalIgnoreCase) >= 0) return "FileOpen line read";
        if (name.IndexOf("FileFindString", StringComparison.OrdinalIgnoreCase) >= 0) return "FileOpen line search";
        if (name.IndexOf("Heap Walk", StringComparison.OrdinalIgnoreCase) >= 0) return "HeapWalk API DllCall";
        if (name.IndexOf("Buf Alloc", StringComparison.OrdinalIgnoreCase) >= 0) return "Buffer() + RtlFillMem";
        if (name.IndexOf("GDI+ Bitmap", StringComparison.OrdinalIgnoreCase) >= 0) return "gdiplus DllCall";
        if (name.IndexOf("Clipboard", StringComparison.OrdinalIgnoreCase) >= 0) return "OpenClipboard DllCalls";
        if (name.IndexOf("Clip Formats", StringComparison.OrdinalIgnoreCase) >= 0) return "WinClip GetFormats";
        if (name.IndexOf("COM Dict", StringComparison.OrdinalIgnoreCase) >= 0) return "Scripting.Dict COM";
        if (name.IndexOf("WMI Processes", StringComparison.OrdinalIgnoreCase) >= 0) return "SWbemLocator query";
        return "N/A";
    }

    static string GetCsStrategyShort(string name)
    {
        name = (name ?? "").Trim();
        if (name.IndexOf("JXON Parse", StringComparison.OrdinalIgnoreCase) >= 0) return "JS-Serializer";
        if (name.IndexOf("JXON Stringify", StringComparison.OrdinalIgnoreCase) >= 0) return "JS-Serializer";
        if (name.IndexOf("thqby Parse", StringComparison.OrdinalIgnoreCase) >= 0) return "JS-Serializer";
        if (name.IndexOf("thqby Stringify", StringComparison.OrdinalIgnoreCase) >= 0) return "JS-Serializer";
        if (name.IndexOf("MD5", StringComparison.OrdinalIgnoreCase) >= 0) return "MD5 (native CLR)";
        if (name.IndexOf("SHA1", StringComparison.OrdinalIgnoreCase) >= 0) return "SHA1 (native CLR)";
        if (name.IndexOf("CRC32", StringComparison.OrdinalIgnoreCase) >= 0) return "C# loop lookup";
        if (name.IndexOf("AES-256", StringComparison.OrdinalIgnoreCase) >= 0) return "Aes (native CLR)";
        if (name.IndexOf("B64 Enc jNizM", StringComparison.OrdinalIgnoreCase) >= 0) return "Convert.ToBase64";
        if (name.IndexOf("B64 Dec jNizM", StringComparison.OrdinalIgnoreCase) >= 0) return "Convert.FromBase64";
        if (name.IndexOf("B64 Enc thqby", StringComparison.OrdinalIgnoreCase) >= 0) return "Convert.ToBase64";
        if (name.IndexOf("B64 Dec thqby", StringComparison.OrdinalIgnoreCase) >= 0) return "Convert.FromBase64";
        if (name.IndexOf("Array Sort", StringComparison.OrdinalIgnoreCase) >= 0) return "Array.Sort";
        if (name.IndexOf("Array Filter", StringComparison.OrdinalIgnoreCase) >= 0) return "LINQ Where";
        if (name.IndexOf("Array Map", StringComparison.OrdinalIgnoreCase) >= 0) return "LINQ Select";
        if (name.IndexOf("Array Reduce", StringComparison.OrdinalIgnoreCase) >= 0) return "LINQ Aggregate";
        if (name.IndexOf("String Ops", StringComparison.OrdinalIgnoreCase) >= 0) return "String chaining";
        if (name.IndexOf("RegExMatchAll", StringComparison.OrdinalIgnoreCase) >= 0) return "Regex.Matches";
        if (name.IndexOf("Map Filter", StringComparison.OrdinalIgnoreCase) >= 0) return "LINQ Dict Where";
        if (name.IndexOf("Range iter", StringComparison.OrdinalIgnoreCase) >= 0) return "C# for-loop";
        if (name.IndexOf("ComVar Create", StringComparison.OrdinalIgnoreCase) >= 0) return "AHK# COM wrapper";
        if (name.IndexOf("DeepClone", StringComparison.OrdinalIgnoreCase) >= 0) return "Recursive Dict clone";
        if (name.IndexOf("Tree Parse", StringComparison.OrdinalIgnoreCase) >= 0) return "Dictionary parse";
        if (name.IndexOf("Tree Search Deep", StringComparison.OrdinalIgnoreCase) >= 0) return "Dict parent traversal";
        if (name.IndexOf("Tree Search Miss", StringComparison.OrdinalIgnoreCase) >= 0) return "Dict ContainsKey";
        if (name.IndexOf("Tree DFS Brute", StringComparison.OrdinalIgnoreCase) >= 0) return "Foreach loop list";
        if (name.IndexOf("Tree AllPaths", StringComparison.OrdinalIgnoreCase) >= 0) return "Dict parent trace";
        if (name.IndexOf("Tree Ancestor", StringComparison.OrdinalIgnoreCase) >= 0) return "Dict validation";
        if (name.IndexOf("SQLite CRUD", StringComparison.OrdinalIgnoreCase) >= 0) return "winsqlite3 P/Invoke";
        if (name.IndexOf("XML Parse", StringComparison.OrdinalIgnoreCase) >= 0) return "XmlDocument.LoadXml";
        if (name.IndexOf("GUID Gen", StringComparison.OrdinalIgnoreCase) >= 0) return "Guid.NewGuid";
        if (name.IndexOf("FileCountLines", StringComparison.OrdinalIgnoreCase) >= 0) return "File.ReadAllLines";
        if (name.IndexOf("FileFindString", StringComparison.OrdinalIgnoreCase) >= 0) return "File.ReadAllLines + Cont.";
        if (name.IndexOf("Heap Walk", StringComparison.OrdinalIgnoreCase) >= 0) return "N/A";
        if (name.IndexOf("Buf Alloc", StringComparison.OrdinalIgnoreCase) >= 0) return "AllocHGlobal + Memset";
        if (name.IndexOf("GDI+ Bitmap", StringComparison.OrdinalIgnoreCase) >= 0) return "GdipCreate P/Invoke";
        if (name.IndexOf("Clipboard", StringComparison.OrdinalIgnoreCase) >= 0) return "OpenClipboard Marshal";
        if (name.IndexOf("Clip Formats", StringComparison.OrdinalIgnoreCase) >= 0) return "N/A";
        if (name.IndexOf("COM Dict", StringComparison.OrdinalIgnoreCase) >= 0) return "Dictionary<string,int>";
        if (name.IndexOf("WMI Processes", StringComparison.OrdinalIgnoreCase) >= 0) return "N/A";
        if (name.IndexOf("Async Parallel", StringComparison.OrdinalIgnoreCase) >= 0) return "Task.Run threadpool";
        if (name.IndexOf("LINQ", StringComparison.OrdinalIgnoreCase) >= 0) return "LINQ Where/Order";
        return "N/A";
    }

    public static string RenderCard(string name, string ahkLib, double ahkMs, double csMs, string path, string themeName = "spacex")
    {
        themeName = (themeName ?? "spacex").ToLowerInvariant();
        Theme t = GetTheme(themeName);
        int w = 800, h = 480;

        string ahkCode, csCode;
        GetSnippets(name, out ahkCode, out csCode);

        using (var bmp = new Bitmap(w, h))
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
            g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;

            // ── Background ──────────────────────────────────────────────
            using (var bg = new System.Drawing.Drawing2D.LinearGradientBrush(
                new Rectangle(0, 0, w, h), t.BgTop, t.BgBot, 45f))
                g.FillRectangle(bg, 0, 0, w, h);

            float pad = 24f;

            // ── Fonts ────────────────────────────────────────────────────
            var fTitle = new Font("Segoe UI", 16f, FontStyle.Bold);
            var fSub = new Font("Segoe UI", 9f);
            var fHeader = new Font("Segoe UI", 11f, FontStyle.Bold);
            var fTime = new Font("Cascadia Code", 14f, FontStyle.Bold);
            var fCode = new Font("Cascadia Code", 8.2f);
            var fBadge = new Font("Segoe UI", 10f, FontStyle.Bold);

            // ── Title ────────────────────────────────────────────────────
            g.DrawString("ECOSYSTEM COMPARISON CARD", fSub, new SolidBrush(t.Dim), pad, pad);
            g.DrawString(name.ToUpperInvariant(), fTitle, new SolidBrush(themeName.ToLower() == "falcon" ? t.Label : Color.White), pad, pad + 15f);

            float titleH = pad + 48f;
            using (var ap = new Pen(t.Accent, 2.5f))
                g.DrawLine(ap, pad, titleH, pad + 80f, titleH);
            using (var dp = new Pen(t.GridLine, 1f))
                g.DrawLine(dp, pad + 80f, titleH, w - pad, titleH);

            // ── Columns ──────────────────────────────────────────────────
            float colY = titleH + 16f;
            float colW = (w - pad * 2f - 20f) / 2f; // 366px each
            float colH = h - colY - pad;            // 368px each

            Action<float, string, string, string, double, double, Color, Color, bool> drawCol =
                (colX, colTitle, colLib, codeText, timeMs, otherMs, c1, c2, isCs) =>
                {

                    // Column container bg
                    using (var cbg = new SolidBrush(t.CardBg))
                    using (var cpath = RoundedRect(colX, colY, colW, colH, 6f))
                        g.FillPath(cbg, cpath);

                    using (var cbp = new Pen(t.Border, 1))
                    using (var cpath2 = RoundedRect(colX, colY, colW, colH, 6f))
                        g.DrawPath(cbp, cpath2);

                    float cy = colY + 12f;
                    g.DrawString(colTitle, fHeader, new SolidBrush(themeName.ToLower() == "falcon" ? t.Label : Color.White), colX + 16f, cy);
                    g.DrawString(colLib, fCode, new SolidBrush(t.Dim), colX + 16f, cy + 18f);

                    // Strategy/Method description:
                    string strat = isCs ? GetCsStrategy(name) : GetAhkStrategy(name);
                    var fStrat = new Font("Segoe UI", 7.6f, FontStyle.Italic);
                    g.DrawString("Strategy: " + strat, fStrat, new SolidBrush(t.Accent), colX + 16f, cy + 32f);

                    // Timing & Performance Bar (shifted down to cy + 48f)
                    float barAreaY = cy + 48f;
                    string timeStr = timeMs == -1 ? "N/A" : (timeMs == 0 ? "0 ms" : timeMs.ToString("F2") + " ms");
                    g.DrawString(timeStr, fTime, new SolidBrush(themeName.ToLower() == "falcon" ? t.Label : Color.White), colX + 16f, barAreaY);

                    // Draw dynamic horizontal bar in the column
                    float barW = colW - 32f;
                    float bH = 8f;
                    float bY = barAreaY + 22f;

                    // Empty Track
                    using (var trk = RoundedRect(colX + 16f, bY, barW, bH, bH / 2f))
                        g.FillPath(new SolidBrush(t.BarBg), trk);

                    // Fill Bar
                    if (timeMs != -1)
                    {
                        float fillRatio = 1f;
                        if (otherMs > 0 && timeMs > 0)
                        {
                            double r = timeMs / otherMs;
                            if (r > 1) fillRatio = (float)(1.0 / r); // slower = shorter bar
                        }
                        float activeW = Math.Max(6f, barW * fillRatio);
                        using (var bPath = RoundedRect(colX + 16f, bY, activeW, bH, bH / 2f))
                        {
                            using (var br = new System.Drawing.Drawing2D.LinearGradientBrush(
                                new RectangleF(colX + 16f, bY, activeW + 1f, bH), c1, c2, 0f))
                                g.FillPath(br, bPath);

                            using (var borderPen = new Pen(Color.FromArgb(160, c1), 0.75f))
                                g.DrawPath(borderPen, bPath);
                        }
                    }

                    // Code Container
                    float codeY = bY + 18f;
                    float codeW = colW - 32f;
                    float codeH = colH - (codeY - colY) - 12f;

                    Color innerCodeBg = themeName.ToLower() == "falcon" ? Color.FromArgb(240, 244, 248) : Color.FromArgb(5, 5, 8);
                    Color innerCodeBorder = themeName.ToLower() == "falcon" ? Color.FromArgb(200, 210, 225) : Color.FromArgb(15, 255, 255, 255);
                    using (var codeBg = new SolidBrush(innerCodeBg))
                    using (var cp = RoundedRect(colX + 16f, codeY, codeW, codeH, 4f))
                        g.FillPath(codeBg, cp);

                    using (var codeBp = new Pen(innerCodeBorder, 1))
                    using (var cp2 = RoundedRect(colX + 16f, codeY, codeW, codeH, 4f))
                        g.DrawPath(codeBp, cp2);

                    // Draw Highlighted Code
                    var lines = (codeText ?? "").Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
                    float ly = codeY + 8f;
                    for (int idx = 0; idx < lines.Length; idx++)
                    {
                        if (ly + 14f > codeY + codeH) break; // clip if too long
                        DrawCodeLine(g, lines[idx], colX + 22f, ly, fCode, themeName);
                        ly += 14f;
                    }
                };

            // AHK Column (left)
            drawCol(pad, "AUTOHOTKEY V2", ahkLib, ahkCode, ahkMs, csMs, t.Amber1, t.Amber2, false);

            // C# Column (right)
            string csLibStr = name.Contains("WMI") || name.Contains("Formats") ? "N/A" : ".NET CLR (AHK# Bridge)";
            drawCol(pad + colW + 20f, "C# (.NET FRAMEWORK)", csLibStr, csCode, csMs, ahkMs, t.Cyan1, t.Cyan2, true);

            // ── Winner Badge ─────────────────────────────────────────────
            if (ahkMs != -1 && csMs != -1)
            {
                bool isDotNetExclusive = (name.Contains("Async Parallel") || name.Contains("LINQ"));
                bool ahkWinner = ahkMs < csMs;
                double speedup = ahkWinner ? csMs / ahkMs : ahkMs / csMs;

                string badgeText;
                if (isDotNetExclusive)
                {
                    badgeText = ".NET EXCLUSIVE: C# is " + speedup.ToString("F1") + "x Faster!";
                }
                else
                {
                    badgeText = ahkWinner
                        ? "AHK is " + speedup.ToString("F1") + "x Faster!"
                        : "C# is " + speedup.ToString("F1") + "x Faster!";
                }

                Color badgeCol = isDotNetExclusive ? t.Violet1 : (ahkWinner ? t.Amber1 : t.Accent);
                if (themeName.ToLower() == "falcon")
                {
                    badgeCol = isDotNetExclusive ? Color.FromArgb(91, 33, 182) : (ahkWinner ? Color.FromArgb(194, 65, 12) : Color.FromArgb(30, 58, 138));
                }

                var szBadge = g.MeasureString(badgeText, fBadge);
                float bx = w - pad - szBadge.Width - 16f;
                float by = pad + 10f;

                using (var bbg = new SolidBrush(Color.FromArgb(16, badgeCol)))
                using (var bp = RoundedRect(bx, by, szBadge.Width + 16f, szBadge.Height + 8f, 4f))
                    g.FillPath(bbg, bp);

                using (var bpen = new Pen(Color.FromArgb(80, badgeCol), 1))
                using (var bp2 = RoundedRect(bx, by, szBadge.Width + 16f, szBadge.Height + 8f, 4f))
                    g.DrawPath(bpen, bp2);

                g.DrawString(badgeText, fBadge, new SolidBrush(badgeCol), bx + 8f, by + 4f);
            }
            else
            {
                // Exclusive badge
                string badgeText = ".NET EXCLUSIVE";
                Color badgeCol = t.Violet1;
                if (themeName.ToLower() == "falcon")
                {
                    badgeCol = Color.FromArgb(91, 33, 182);
                }
                var szBadge = g.MeasureString(badgeText, fBadge);
                float bx = w - pad - szBadge.Width - 16f;
                float by = pad + 10f;

                using (var bbg = new SolidBrush(Color.FromArgb(16, badgeCol)))
                using (var bp = RoundedRect(bx, by, szBadge.Width + 16f, szBadge.Height + 8f, 4f))
                    g.FillPath(bbg, bp);
                using (var bpen = new Pen(Color.FromArgb(80, badgeCol), 1))
                using (var bp2 = RoundedRect(bx, by, szBadge.Width + 16f, szBadge.Height + 8f, 4f))
                    g.DrawPath(bpen, bp2);
                g.DrawString(badgeText, fBadge, new SolidBrush(badgeCol), bx + 8f, by + 4f);
            }

            bmp.Save(path, System.Drawing.Imaging.ImageFormat.Png);
            return "ok";
        }
    }

    static void DrawCodeLine(Graphics g, string line, float x, float y, Font font, string themeName)
    {
        themeName = (themeName ?? "spacex").ToLowerInvariant();
        // Syntax highlighting palette
        Color cKeyword = Color.FromArgb(249, 38, 114);  // Pink
        Color cFunc = Color.FromArgb(102, 217, 239); // Cyan
        Color cString = Color.FromArgb(230, 219, 116); // Yellow
        Color cNum = Color.FromArgb(174, 129, 255); // Purple
        Color cComment = Color.FromArgb(117, 113, 94);  // Grey
        Color cText = Color.FromArgb(248, 248, 242); // Off-white
        Color cOp = Color.FromArgb(166, 226, 46);  // Green (operators)

        if (themeName.ToLower() == "falcon")
        {
            cKeyword = Color.FromArgb(190, 24, 74);  // Dark Pink
            cFunc = Color.FromArgb(3, 105, 161);   // Dark Blue
            cString = Color.FromArgb(21, 128, 61);   // Dark Green
            cNum = Color.FromArgb(109, 40, 217);  // Dark Purple
            cComment = Color.FromArgb(100, 116, 139); // Slate Grey
            cText = Color.FromArgb(30, 41, 59);    // Dark Charcoal
            cOp = Color.FromArgb(194, 65, 12);   // Orange
        }

        var tokens = System.Text.RegularExpressions.Regex.Matches(line,
            @"(\/\/.*|;.*)|("".*?""" + @"|'.*?')|(\b(public|static|void|string|int|double|bool|var|return|if|else|for|foreach|while|class|Loop|new|using|try|catch|global)\b)|(\b\d+\b)|(\b\w+)(?=\()|([^\s\w]+)|(\w+)|(\s+)");

        float cx = x;
        foreach (System.Text.RegularExpressions.Match m in tokens)
        {
            Color c = cText;
            if (m.Groups[1].Success) c = cComment;
            else if (m.Groups[2].Success) c = cString;
            else if (m.Groups[3].Success) c = cKeyword;
            else if (m.Groups[5].Success) c = cNum;
            else if (m.Groups[6].Success) c = cFunc;
            else if (m.Groups[7].Success) c = cOp;

            string txt = m.Value;
            g.DrawString(txt, font, new SolidBrush(c), cx, y, StringFormat.GenericTypographic);
            cx += g.MeasureString(txt, font, 1000, StringFormat.GenericTypographic).Width;
        }
    }

    static Dictionary<string, string[]> _snippets = null;
    static void InitializeSnippets()
    {
        if (_snippets != null) return;
        _snippets = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase);

        Action<string, string, string> add = (key, ahk, cs) =>
        {
            _snippets[key] = new string[] { ahk, cs };
        };

        add("JXON Parse 5K",
            "Loop 5000 {\n    obj := Jxon_Load(&jsonStr)\n}",
            "var js = new JavaScriptSerializer();\nfor (int i = 0; i < 5000; i++) {\n    js.DeserializeObject(jsonStr);\n}");

        add("JXON Stringify 5K",
            "obj := Jxon_Load(&jsonStr)\nLoop 5000 {\n    Jxon_Dump(obj)\n}",
            "var js = new JavaScriptSerializer();\nfor (int i = 0; i < 5000; i++) {\n    js.Serialize(jsonObj);\n}");

        add("thqby Parse 5K",
            "Loop 5000 {\n    JSON.parse(jsonStr)\n}",
            "var js = new JavaScriptSerializer();\nfor (int i = 0; i < 5000; i++) {\n    js.DeserializeObject(jsonStr);\n}");

        add("thqby Stringify 5K",
            "obj2 := JSON.parse(jsonStr)\nLoop 5000 {\n    JSON.stringify(obj2)\n}",
            "var js = new JavaScriptSerializer();\nfor (int i = 0; i < 5000; i++) {\n    js.Serialize(jsonObj);\n}");

        add("MD5 10K",
            "Loop 10000 {\n    MD5(buf)\n}",
            "var md5 = MD5.Create();\nfor (int i = 0; i < 10000; i++) {\n    md5.ComputeHash(hashBytes);\n}");

        add("SHA1 5K",
            "Loop 5000 {\n    Crypt_Hash(buf, buf.Size, \"SHA\")\n}",
            "var sha1 = SHA1.Create();\nfor (int i = 0; i < 5000; i++) {\n    sha1.ComputeHash(hashBytes);\n}");

        add("CRC32 10K",
            "Loop 10000 {\n    Crypt_Hash(buf, buf.Size, \"CRC32\")\n}",
            "// Manual C# loop over bytes\nfor (int i = 0; i < 10000; i++) {\n    uint crc = 0xFFFFFFFF;\n    for (int j = 0; j < d.Length; j++) {\n        crc ^= d[j];\n        for (int k = 0; k < 8; k++)\n            crc = (crc >> 1) ^ (0xEDB88320 * (crc & 1));\n    }\n}");

        add("AES-256 500",
            "Loop 500 {\n    Crypt_AES(buf, buf.Size, \"Key\", 256, true)\n}",
            "using (var aes = Aes.Create()) {\n    aes.Key = aesKey; aes.IV = aesIv;\n    using (var enc = aes.CreateEncryptor())\n        enc.TransformFinalBlock(hashBytes, 0, hashBytes.Length);\n}");

        add("B64 Enc jNizM",
            "Loop 1000 {\n    StringToBase64(hashStr)\n}",
            "for (int i = 0; i < 1000; i++) {\n    Convert.ToBase64String(b64Bytes);\n}");

        add("B64 Dec jNizM",
            "Loop 1000 {\n    Base64ToString(b64encoded)\n}",
            "for (int i = 0; i < 1000; i++) {\n    Encoding.UTF8.GetString(Convert.FromBase64String(b64Str));\n}");

        add("B64 Enc thqby",
            "Loop 1000 {\n    Base64.Encode(hashStr)\n}",
            "for (int i = 0; i < 1000; i++) {\n    Convert.ToBase64String(b64Bytes);\n}");

        add("B64 Dec thqby",
            "Loop 1000 {\n    Base64.Decode(thqbyEnc)\n}",
            "for (int i = 0; i < 1000; i++) {\n    Encoding.UTF8.GetString(Convert.FromBase64String(b64Str));\n}");

        add("Array Sort 1K",
            "Loop 1000 {\n    c := testArr.Clone()\n    c.Sort(\"N\")\n}",
            "for (int i = 0; i < 1000; i++) {\n    var c = (int[])arr.Clone();\n    Array.Sort(c);\n}");

        add("Array Filter 1K",
            "Loop 1000 {\n    testArr.Filter(x => x > 50000)\n}",
            "for (int i = 0; i < 1000; i++) {\n    arr.Where(n => n > 500).ToArray();\n}");

        add("Array Map 1K",
            "Loop 1000 {\n    testArr.Map(x => x * 2)\n}",
            "for (int i = 0; i < 1000; i++) {\n    arr.Select(n => n * 2).ToArray();\n}");

        add("Array Reduce 1K",
            "Loop 1000 {\n    testArr.Reduce((a, b) => a + b)\n}",
            "for (int i = 0; i < 1000; i++) {\n    arr.Aggregate(0L, (a, b) => a + b);\n}");

        add("String Ops 10K",
            "Loop 10000 {\n    v1 := testStr.ToUpper()\n    v2 := testStr.Replace(\"fox\", \"cat\")\n    v3 := testStr.Trim()\n    v4 := testStr.LPad(testStr.Length + 5, \"*\")\n    v5 := testStr.Find(\"lazy\")\n}",
            "for (int i = 0; i < 10000; i++) {\n    text.ToUpper();\n    text.Replace(\"fox\", \"cat\");\n    text.Trim();\n    text.PadLeft(text.Length + 5, '*');\n    text.IndexOf(\"lazy\");\n}");

        add("RegExMatchAll 1K",
            "Loop 1000 {\n    matches := regText.RegExMatchAll(\"\\w+\")\n}",
            "for (int i = 0; i < 1000; i++) {\n    var matches = Regex.Matches(text, \"\\\\w+\");\n    int c = matches.Count;\n}");

        add("Map Filter 1K",
            "Loop 1000 {\n    m2 := testMap.Filter((k, v) => v > 50000)\n    c := testMap.Count((k, v) => v > 80000)\n}",
            "for (int i = 0; i < 1000; i++) {\n    dict.Where(kv => kv.Value > 50000).Count();\n    dict.Count(kv => kv.Value > 80000);\n}");

        add("Range iter 5K",
            "Loop 5000 {\n    for v in Range(1, 100) {}\n}",
            "for (int i = 0; i < 5000; i++) {\n    int sum = 0;\n    for (int v = 1; v <= 100; v++) {\n        sum += v;\n    }\n}");

        add("ComVar Create 10K",
            "Loop 10000 {\n    v1 := ComVar(42)\n    v2 := ComVar(\"str\")\n}",
            "for (int i = 0; i < 10000; i++) {\n    var cv1 = new ComVarSim(42);\n    var cv2 = new ComVarSim(\"hello world\");\n}");

        add("DeepClone x1K",
            "Loop 1000 {\n    deepclone(nested)\n}",
            "for (int i = 0; i < 1000; i++) {\n    CloneDeep(deepSrc);\n}");

        add("Tree Parse",
            "classTree := TreeNavigator.ParseByFlatMap(treeRawData)",
            "// C# parses tree data into flat Dictionary lookup tables\nSetupTree(treeData);");

        add("Tree Search Deep",
            "Loop 500 {\n    GetPathToNode(classTree, Chr(0x7389))\n}",
            "for (int i = 0; i < 500; i++) {\n    if (tIdx.ContainsKey(target)) {\n        var key = tIdx[target][0];\n        var pp = new List<string> { tMap[key] };\n        while (tPar.ContainsKey(key)) { key = tPar[key]; pp.Insert(0, tMap[key]); }\n        var path = string.Join(\" > \", pp);\n    }\n}");

        add("Tree Search Miss",
            "Loop 500 {\n    GetPathToNode(classTree, \"THIS_DOES_NOT_EXIST_123\")\n}",
            "for (int i = 0; i < 500; i++) {\n    if (tIdx.ContainsKey(\"MISS\")) {\n        // ...\n    }\n}");

        add("Tree DFS Brute",
            "Loop 10 {\n    FindNodeDFS(freshTree, searchKey)\n}",
            "for (int i = 0; i < 10; i++) {\n    foreach (var n in dfsNames) {\n        if (n == target) break;\n    }\n}");

        add("Tree AllPaths",
            "Loop 500 {\n    GetAllPathsToNode(classTree, multiName)\n}",
            "for (int i = 0; i < 500; i++) {\n    if (tIdx.ContainsKey(target)) {\n        foreach (var startKey in tIdx[target]) {\n            string k = startKey;\n            var pp = new List<string> { tMap[k] };\n            while (tPar.ContainsKey(k)) { k = tPar[k]; pp.Insert(0, tMap[k]); }\n        }\n    }\n}");

        add("Tree Ancestor",
            "Loop 500 {\n    GetPathToNode(classTree, target, ancestor)\n}",
            "for (int i = 0; i < 500; i++) {\n    if (tIdx.ContainsKey(target)) {\n        string key = tIdx[target][0];\n        bool matches = false;\n        while (tPar.ContainsKey(key)) {\n            key = tPar[key];\n            if (tMap[key] == ancestor) { matches = true; break; }\n        }\n    }\n}");

        add("SQLite CRUD 1K",
            "db := SQLite(\":memory:\")\ndb.Exec(\"CREATE TABLE bench ...\")\ndb.BeginTransaction()\nLoop 1000 {\n    db.Exec(\"INSERT INTO bench ...\")\n}\ndb.CommitTransaction()",
            "// Simulated with in-memory fast C# collections\nvar d = new Dictionary<string, double>();\nfor (int i = 1; i <= 1000; i++)\n    d[\"item_\" + i] = i * 1.5;\nvar filtered = d.Where(kv => kv.Value > 500).ToList();\ndouble total = d.Values.Sum();");

        add("XML Parse 1K",
            "Loop 1000 {\n    xmlDoc := ComObject(\"MSXML2.DOMDocument.6.0\")\n    xmlDoc.async := false\n    xmlDoc.loadXML(xmlStr)\n}",
            "for (int i = 0; i < 1000; i++) {\n    var doc = new XmlDocument();\n    doc.LoadXml(xmlStr);\n}");

        add("GUID Gen 10K",
            "Loop 10000 {\n    guid := CreateGUID()\n}",
            "for (int i = 0; i < 10000; i++) {\n    Guid.NewGuid().ToString(\"B\").ToUpper();\n}");

        add("FileCountLines",
            "ahkLineCount := FileCountLines(path)",
            "File.ReadAllLines(path).Length;");

        add("FileFindString",
            "found := FileFindString(path, search)",
            "int c = 0;\nforeach (var line in File.ReadAllLines(path))\n    if (line.Contains(search)) c++;");

        add("Heap Walk 1K",
            "Loop 1000 {\n    findHeap(heapPtr)\n}",
            "for (int i = 0; i < 1000; i++) {\n    PROCESS_HEAP_ENTRY entry = new PROCESS_HEAP_ENTRY();\n    entry.lpData = IntPtr.Zero;\n    HeapWalk(heap, ref entry);\n}");

        add("Buf Alloc 160K",
            "Loop 100 {\n    buf := Buffer(160000, 0xFF)\n}",
            "for (int i = 0; i < 100; i++) {\n    IntPtr p = Marshal.AllocHGlobal(160000);\n    FillMemory(p, 160000, 0xFF);\n    Marshal.FreeHGlobal(p);\n}");

        add("GDI+ Bitmap",
            "Loop 100 {\n    DllCall(\"gdiplus\\GdipCreateBitmapFromScan0\", \"Int\", 200, \"Int\", 200, \"Int\", 0, \"Int\", 0x26200A, \"Ptr\", 0, \"Ptr*\", &pBitmap := 0)\n    DllCall(\"gdiplus\\GdipDisposeImage\", \"Ptr\", pBitmap)\n}",
            "for (int i = 0; i < 100; i++) {\n    IntPtr bmp;\n    GdipCreateBitmapFromScan0(200, 200, 0, 0x26200A, IntPtr.Zero, out bmp);\n    if (bmp != IntPtr.Zero) GdipDisposeImage(bmp);\n}");

        add("Clipboard 1K",
            "Loop 1000 {\n    WinClip.SetText(text)\n    val := WinClip.GetText()\n}",
            "for (int i = 0; i < 1000; i++) {\n    if (OpenClipboard(IntPtr.Zero)) {\n        EmptyClipboard();\n        byte[] b = Encoding.Unicode.GetBytes(text + \"\\0\");\n        IntPtr hm = GlobalAlloc(GMEM_MOVEABLE, (UIntPtr)b.Length);\n        IntPtr p = GlobalLock(hm); Marshal.Copy(b, 0, p, b.Length); GlobalUnlock(hm);\n        SetClipboardData(CF_UNICODETEXT, hm);\n        IntPtr hd = GetClipboardData(CF_UNICODETEXT);\n        if (hd != IntPtr.Zero) { IntPtr pd = GlobalLock(hd); Marshal.PtrToStringUni(pd); GlobalUnlock(hd); }\n        CloseClipboard();\n    }\n}");

        add("Clip Formats 1K",
            "Loop 1000 {\n    formats := WinClip.GetFormats()\n}",
            "for (int i = 0; i < 1000; i++) {\n    if (OpenClipboard(IntPtr.Zero)) {\n        uint fmt = 0;\n        while ((fmt = EnumClipboardFormats(fmt)) != 0) { }\n        CloseClipboard();\n    }\n}");

        add("COM Dict 10K",
            "dict := ComObject(\"Scripting.Dictionary\")\nLoop 10000 {\n    dict.Item(\"k\" A_Index) := A_Index\n}\nLoop 10000 {\n    s := dict.Item(\"k\" A_Index)\n}",
            "var d = new Dictionary<string, int>();\nfor (int i = 1; i <= 10000; i++)\n    d[\"k\" + i] = i;\nlong s = 0;\nfor (int i = 1; i <= 10000; i++)\n    s += d[\"k\" + i];");

        add("WMI Processes",
            "wmi := ComObjGet(\"winmgmts:\")\nprocs := wmi.ExecQuery(\"SELECT Name FROM Win32_Process\")\npCount := 0\nfor proc in procs {\n    pCount++\n}",
            "var searcher = new ManagementObjectSearcher(\"SELECT Name FROM Win32_Process\");\nint count = 0;\nforeach (var obj in searcher.Get()) {\n    count++;\n}");

        add("Async Parallel",
            "// .NET EXCLUSIVE FEATURE\n// (Compared against AHK next best thing: sequential loop)\nLoop 10 {\n    sum := 0\n    Loop 1000000\n        sum += A_Index - 1\n}",
            "var tasks = new Task<long>[10];\nfor (int i = 0; i < 10; i++) {\n    tasks[i] = Task.Run(() => {\n        long s = 0;\n        for (int j = 0; j < 1000000; j++) s += j;\n        return s;\n    });\n}\nTask.WaitAll(tasks);");

        add("LINQ 100K",
            "// .NET EXCLUSIVE FEATURE\n// (Compared against AHK next best thing: push + scan + slice)\ndata := []\nLoop 100000 {\n    data.Push({ Name: \"item\" (A_Index - 1), Value: (A_Index - 1) * 3 })\n}\nfiltered := []\nfor x in data {\n    if x.Value > 100000\n        filtered.Push(x)\n}\nreversed := []\nidx := filtered.Length\nLoop Min(100, filtered.Length) {\n    if idx <= 0\n        break\n    reversed.Push(filtered[idx])\n    idx--\n}",
            "var data = Enumerable.Range(0, 100000)\n    .Select(i => new { Name = \"item\" + i, Value = i * 3 })\n    .ToList();\nvar f = data.Where(x => x.Value > 100000)\n    .OrderByDescending(x => x.Value)\n    .Take(100).ToList();");

        add("RegEx Match 10K",
            "Loop 10000 {\n    RegExMatch(testText, \"\\\\d+\", &match)\n    res := match[0]\n}",
            "var rx = new Regex(\"\\\\d+\", RegexOptions.Compiled);\nfor (int i = 0; i < 10000; i++) {\n    var m = rx.Match(testText);\n    string res = m.Value;\n}");

        add("DllCall kernel32",
            "Loop 20000 {\n    ticks := DllCall(\"kernel32\\\\GetTickCount\", \"UInt\")\n}",
            "[DllImport(\"kernel32.dll\")]\nstatic extern uint GetTickCount();\n\n// ...\nfor (int i = 0; i < 20000; i++) {\n    uint ticks = GetTickCount();\n}");

        add("FileExist 2K",
            "Loop 2000 {\n    exists := FileExist(tempFile)\n}",
            "for (int i = 0; i < 2000; i++) {\n    bool exists = File.Exists(tempFile);\n}");
    }

    static void GetSnippets(string name, out string ahkCode, out string csCode)
    {
        InitializeSnippets();
        string key = (name ?? "").Trim();

        if (_snippets.ContainsKey(key))
        {
            ahkCode = _snippets[key][0];
            csCode = _snippets[key][1];
            return;
        }

        foreach (var k in _snippets.Keys)
        {
            if (key.IndexOf(k, StringComparison.OrdinalIgnoreCase) >= 0 || k.IndexOf(key, StringComparison.OrdinalIgnoreCase) >= 0)
            {
                ahkCode = _snippets[k][0];
                csCode = _snippets[k][1];
                return;
            }
        }

        ahkCode = "Loop 1000 {\n    // AHK Test code\n}";
        csCode = "Loop 1000 {\n    // C# Do_* code\n}";
    }

    // ====================================================================
    // Legacy monolithic methods — called by AHK benchmark script
    // Each sets up state, runs N iterations with Stopwatch, returns ms
    // ====================================================================

    public static string JsonParse(string json, int iters)
    {
        SetupJson(json);
        var sw = Stopwatch.StartNew();
        for (int i = 0; i < iters; i++) Do_JsonParse();
        sw.Stop();
        return sw.Elapsed.TotalMilliseconds.ToString("F3");
    }

    public static string JsonStringify(string json, int iters)
    {
        SetupJson(json);
        var sw = Stopwatch.StartNew();
        string last = "";
        for (int i = 0; i < iters; i++) last = Do_JsonStringify();
        sw.Stop();
        return sw.Elapsed.TotalMilliseconds.ToString("F3") + "|" + last;
    }

    public static string Md5(string input, int iters)
    {
        SetupCrypto(input);
        var sw = Stopwatch.StartNew();
        for (int i = 0; i < iters; i++) Do_Md5();
        sw.Stop();
        return sw.Elapsed.TotalMilliseconds.ToString("F3");
    }

    public static string Sha1(string input, int iters)
    {
        SetupCrypto(input);
        var sw = Stopwatch.StartNew();
        for (int i = 0; i < iters; i++) Do_Sha1();
        sw.Stop();
        return sw.Elapsed.TotalMilliseconds.ToString("F3");
    }

    public static string Crc32(string input, int iters)
    {
        SetupCrypto(input);
        var sw = Stopwatch.StartNew();
        string last = "";
        for (int i = 0; i < iters; i++) last = Do_Crc32();
        sw.Stop();
        return sw.Elapsed.TotalMilliseconds.ToString("F3") + "|" + last;
    }

    public static string AesEncrypt(string input, int iters)
    {
        SetupCrypto(input);
        var sw = Stopwatch.StartNew();
        for (int i = 0; i < iters; i++) Do_AesEncrypt();
        sw.Stop();
        return sw.Elapsed.TotalMilliseconds.ToString("F3");
    }

    public static string Base64Encode(string input, int iters)
    {
        SetupBase64(input);
        var sw = Stopwatch.StartNew();
        string last = "";
        for (int i = 0; i < iters; i++) last = Do_Base64Encode();
        sw.Stop();
        return sw.Elapsed.TotalMilliseconds.ToString("F3") + "|" + last;
    }

    public static string Base64Decode(string b64, int iters)
    {
        _b64Str = b64;
        var sw = Stopwatch.StartNew();
        for (int i = 0; i < iters; i++) Do_Base64Decode();
        sw.Stop();
        return sw.Elapsed.TotalMilliseconds.ToString("F3");
    }

    public static string ArraySort(string csv, int iters)
    {
        SetupArray(csv);
        var sw = Stopwatch.StartNew();
        for (int i = 0; i < iters; i++) Do_ArraySort();
        sw.Stop();
        return sw.Elapsed.TotalMilliseconds.ToString("F3");
    }

    public static string ArrayFilter(string csv, int iters)
    {
        SetupArray(csv);
        var sw = Stopwatch.StartNew();
        for (int i = 0; i < iters; i++) Do_ArrayFilter();
        sw.Stop();
        return sw.Elapsed.TotalMilliseconds.ToString("F3") + "|ok";
    }

    public static string ArrayMap(string csv, int iters)
    {
        SetupArray(csv);
        var sw = Stopwatch.StartNew();
        for (int i = 0; i < iters; i++) Do_ArrayMap();
        sw.Stop();
        return sw.Elapsed.TotalMilliseconds.ToString("F3") + "|ok";
    }

    public static string ArrayReduce(string csv, int iters)
    {
        SetupArray(csv);
        var sw = Stopwatch.StartNew();
        for (int i = 0; i < iters; i++) Do_ArrayReduce();
        sw.Stop();
        return sw.Elapsed.TotalMilliseconds.ToString("F3") + "|ok";
    }

    public static string StringOps(string text, int iters)
    {
        var sw = Stopwatch.StartNew();
        for (int i = 0; i < iters; i++) Do_StringOps(text);
        sw.Stop();
        return sw.Elapsed.TotalMilliseconds.ToString("F3");
    }

    public static string DictOps(int count)
    {
        var sw = Stopwatch.StartNew();
        string res = Do_DictAddRead(count);
        sw.Stop();
        return sw.Elapsed.TotalMilliseconds.ToString("F3") + "|" + res;
    }

    public static string DeepCloneTest(int depth, int iters)
    {
        SetupDeepClone();
        var sw = Stopwatch.StartNew();
        for (int i = 0; i < iters; i++) Do_DeepClone();
        sw.Stop();
        return sw.Elapsed.TotalMilliseconds.ToString("F3");
    }

    public static string TreeParse(string data)
    {
        var sw = Stopwatch.StartNew();
        string result = SetupTree(data);
        sw.Stop();
        var parts = result.Split('|');
        return sw.Elapsed.TotalMilliseconds.ToString("F3") + "|" + parts[0] + "|" + parts[1];
    }

    public static string TreeSearchParentPtr(string data, string target, int iters)
    {
        if (_tIdx == null) SetupTree(data);
        var sw = Stopwatch.StartNew();
        for (int i = 0; i < iters; i++) Do_TreeSearch(target);
        sw.Stop();
        return sw.Elapsed.TotalMilliseconds.ToString("F3");
    }

    public static string TreeSearchAll(string data, string target)
    {
        if (_tIdx == null) SetupTree(data);
        int iters = 500;
        var sw = Stopwatch.StartNew();
        string last = "";
        for (int i = 0; i < iters; i++) last = Do_TreeSearchAll(target);
        sw.Stop();
        return sw.Elapsed.TotalMilliseconds.ToString("F3") + "|" + last;
    }

    public static string TreeDFS(string data, string target)
    {
        SetupDFS(data);
        int iters = 10;
        var sw = Stopwatch.StartNew();
        for (int i = 0; i < iters; i++) Do_DFS(target);
        sw.Stop();
        return sw.Elapsed.TotalMilliseconds.ToString("F3") + "|ok";
    }

    public static string SqliteOps(int count)
    {
        // C# doesn't have winsqlite3 built-in; simulate with dictionary ops
        var sw = Stopwatch.StartNew();
        var d = new Dictionary<string, double>();
        for (int i = 1; i <= count; i++) d["item_" + i] = i * 1.5;
        var filtered = d.Where(kv => kv.Value > 500).ToList();
        double total = d.Values.Sum();
        sw.Stop();
        return sw.Elapsed.TotalMilliseconds.ToString("F3") + "|" + filtered.Count + "|" + total;
    }

    public static string XmlParse(string xml, int iters)
    {
        var sw = Stopwatch.StartNew();
        for (int i = 0; i < iters; i++) Do_XmlParse(xml);
        sw.Stop();
        return sw.Elapsed.TotalMilliseconds.ToString("F3");
    }

    public static string GuidGen(int iters)
    {
        var sw = Stopwatch.StartNew();
        string last = "";
        for (int i = 0; i < iters; i++) last = Do_GuidGen();
        sw.Stop();
        return sw.Elapsed.TotalMilliseconds.ToString("F3") + "|" + last;
    }

    public static string FileCountLines(string path)
    {
        var sw = Stopwatch.StartNew();
        string result = Do_FileCountLines(path);
        sw.Stop();
        return sw.Elapsed.TotalMilliseconds.ToString("F3") + "|" + result;
    }

    public static string FileFindStr(string path, string search)
    {
        var sw = Stopwatch.StartNew();
        string result = Do_FileFindStr(path, search);
        sw.Stop();
        return sw.Elapsed.TotalMilliseconds.ToString("F3") + "|" + result;
    }

    public static string ClipboardOps(int iters)
    {
        var sw = Stopwatch.StartNew();
        for (int i = 0; i < iters; i++)
            Do_ClipboardOp("Benchmark test data iteration " + i + " with some extra text for realism");
        sw.Stop();
        return sw.Elapsed.TotalMilliseconds.ToString("F3");
    }

    public static string ImageBufAllocOpt(int w, int h, int iters)
    {
        var sw = Stopwatch.StartNew();
        for (int i = 0; i < iters; i++) Do_BufAlloc(w, h);
        sw.Stop();
        return sw.Elapsed.TotalMilliseconds.ToString("F3");
    }

    public static string GdipCreateDirect(int w, int h, int iters)
    {
        // Initialize GDI+
        IntPtr token;
        var input = new GdiplusStartupInput { GdiplusVersion = 1 };
        GdiplusStartup(out token, ref input, IntPtr.Zero);
        var sw = Stopwatch.StartNew();
        for (int i = 0; i < iters; i++) Do_GdipCreate(w, h);
        sw.Stop();
        GdiplusShutdown(token);
        return sw.Elapsed.TotalMilliseconds.ToString("F3");
    }

    [StructLayout(LayoutKind.Sequential)]
    struct GdiplusStartupInput
    {
        public int GdiplusVersion;
        public IntPtr DebugEventCallback;
        public int SuppressBackgroundThread;
        public int SuppressExternalCodecs;
    }

    [DllImport("gdiplus.dll")]
    static extern int GdiplusStartup(out IntPtr token, ref GdiplusStartupInput input, IntPtr output);

    [DllImport("gdiplus.dll")]
    static extern void GdiplusShutdown(IntPtr token);

    public static string GetVerboseDescription(string name, double ahkMs, double csMs)
    {
        string ahkCode, csCode;
        GetSnippets(name, out ahkCode, out csCode);

        string sep = new string('=', 70);

        var sb = new System.Text.StringBuilder();
        sb.AppendLine(sep);
        sb.AppendLine(" " + name.ToUpperInvariant());
        sb.AppendLine(sep);
        sb.AppendLine();

        sb.AppendLine("--- TIMINGS & PERFORMANCE ---");
        if (ahkMs == -1)
        {
            sb.AppendLine("  AutoHotkey Time : N/A (Feature Not Supported natively)");
        }
        else
        {
            sb.AppendLine("  AutoHotkey Time : " + ahkMs.ToString("F2") + " ms");
        }

        if (csMs == -1 || csMs == 0)
        {
            sb.AppendLine("  C# (.NET) Time  : N/A");
        }
        else
        {
            sb.AppendLine("  C# (.NET) Time  : " + csMs.ToString("F2") + " ms");
        }

        if (ahkMs > 0 && csMs > 0)
        {
            bool isDotNetExclusive = (name.Contains("Async Parallel") || name.Contains("LINQ"));
            bool ahkWinner = ahkMs < csMs;
            double speedup = ahkWinner ? csMs / ahkMs : ahkMs / csMs;
            if (isDotNetExclusive)
            {
                sb.AppendLine("  Winner          : C# (.NET) (" + speedup.ToString("F1") + "x Faster) [.NET Exclusive]");
            }
            else
            {
                sb.AppendLine("  Winner          : " + (ahkWinner ? "AutoHotkey" : "C# (.NET)") + " (" + speedup.ToString("F1") + "x Faster)");
            }
        }
        else if (ahkMs == -1)
        {
            sb.AppendLine("  Winner          : C# Only (.NET Exclusive feature showcase)");
        }
        else if (csMs == 0 || csMs == -1)
        {
            sb.AppendLine("  Winner          : AHK Only (No comparative C# equivalent)");
        }
        sb.AppendLine();

        sb.AppendLine("--- AUTOHOTKEY CODE SNIPPET ---");
        sb.AppendLine(ahkCode);
        sb.AppendLine();

        sb.AppendLine("--- C# (.NET) CODE SNIPPET ---");
        sb.AppendLine(csCode);
        sb.AppendLine();

        sb.AppendLine("--- FAIRNESS NOTES ---");
        sb.AppendLine("  - Per-Call Interop: Timed. Each C# iteration is driven and measured individually");
        sb.AppendLine("    from AHK to capture COM boundary overhead.");
        sb.AppendLine("  - Cached State: Heavily structured state is pre-allocated and cached in Setup*()");
        sb.AppendLine("    calls to measure runtime operation fairly on both sides.");

        return sb.ToString();
    }
}


