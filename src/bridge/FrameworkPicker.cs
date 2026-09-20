// ═══════════════════════════════════════════════════════════════════════════════
// AHK# Bridge — FrameworkPicker: which NuGet target frameworks can this runtime load?
// (part of ahk#.bridge.dll; used by NuGetManager)
// ═══════════════════════════════════════════════════════════════════════════════
// The bridge runs on the .NET Framework 4.x CLR. A package folder such as lib/net8.0 or lib/netstandard2.1 holds
// assemblies that reference APIs this CLR does not have, so they must never be picked "because nothing else is there".
// Every target framework gets a rank (higher = better) or -1 (unusable here):
//   net4x up to the Framework installed on this machine  4000..4081
//   netstandard1.0 .. 2.0 (needs Framework 4.7.2+)        3510..3520
//   net20 .. net35                                        2000..3050

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

internal static class FrameworkPicker
{
    private static int _maxNet = -1;

    /// <summary>Newest .NET Framework 4.x on this machine as major*1000+minor*10+patch (4.8 → 4080, 4.7.2 → 4072).</summary>
    public static int MaxNet
    {
        get
        {
            if (_maxNet < 0) _maxNet = Detect();
            return _maxNet;
        }
    }

    public static bool NetStandardOk { get { return MaxNet >= 4072; } }

    private static int Detect()
    {
        int release = 0;
        try
        {
            using (Microsoft.Win32.RegistryKey k = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full"))
            {
                if (k != null)
                {
                    object v = k.GetValue("Release");
                    if (v != null) release = Convert.ToInt32(v);
                }
            }
        }
        catch { }
        if (release >= 533320) return 4081;
        if (release >= 528040) return 4080;
        if (release >= 461808) return 4072;
        if (release >= 461308) return 4071;
        if (release >= 460798) return 4070;
        if (release >= 394802) return 4062;
        if (release >= 394254) return 4061;
        if (release >= 393295) return 4060;
        if (release >= 379893) return 4052;
        if (release >= 378675) return 4051;
        if (release >= 378389) return 4050;
        return 4000;
    }

    /// <summary>".NETFramework4.8" / "net48-windows" / "netstandard2.0" → the short folder name ("net48", "netstandard2.0").</summary>
    public static string Normalize(string tfm)
    {
        if (string.IsNullOrEmpty(tfm)) return "any";
        string t = tfm.Trim().ToLowerInvariant();
        if (t.StartsWith("portable")) return "portable";
        if (t.StartsWith(".netframework")) return "net" + t.Substring(13).Replace(".", "");
        if (t.StartsWith(".netstandard")) return "netstandard" + t.Substring(12);
        if (t.StartsWith(".netcoreapp")) return "netcoreapp" + t.Substring(11);
        if (t.StartsWith(".netportable")) return "portable";
        int dash = t.IndexOf('-');
        if (dash > 0) t = t.Substring(0, dash);
        return t;
    }

    /// <summary>Preference for a target framework on this runtime; -1 when its assemblies cannot be loaded here.</summary>
    public static int Rank(string tfm)
    {
        string t = Normalize(tfm);
        if (t == "any") return 1000;
        if (t.StartsWith("netstandard"))
        {
            if (!NetStandardOk) return -1;
            string[] p = t.Substring(11).Split('.');
            int maj, min = 0;
            if (p.Length == 0 || !int.TryParse(p[0], out maj)) return -1;
            if (p.Length > 1 && !int.TryParse(p[1], out min)) return -1;
            if (maj > 2 || (maj == 2 && min > 0)) return -1;          // netstandard2.1 needs .NET Core 3+ / Mono
            return 3500 + maj * 10 + min;
        }
        if (t.Length > 3 && t.StartsWith("net") && char.IsDigit(t[3]))
        {
            string rest = t.Substring(3);
            if (rest.IndexOf('.') >= 0) return -1;                     // net5.0, net6.0, net8.0 ...
            foreach (char c in rest) if (!char.IsDigit(c)) return -1;
            int major = rest[0] - '0';
            int minor = rest.Length > 1 ? rest[1] - '0' : 0;
            int patch = rest.Length > 2 ? rest[2] - '0' : 0;
            int value = major * 1000 + minor * 10 + patch;
            if (major == 4) return value <= MaxNet ? value : -1;
            return major <= 3 ? value : -1;
        }
        return -1;
    }

    /// <summary>The best lib/ subfolder that holds DLLs this runtime can load, or null. `offered` lists what the package has.</summary>
    public static string PickLibDir(string libPath, List<string> offered)
    {
        string best = null;
        int bestRank = -1;
        foreach (string dir in Directory.GetDirectories(libPath))
        {
            if (Directory.GetFiles(dir, "*.dll").Length == 0) continue;
            string name = Path.GetFileName(dir);
            offered.Add(name);
            int r = Rank(name);
            if (r > bestRank) { bestRank = r; best = dir; }
        }
        if (best != null) return best;
        // legacy layout: DLLs straight in lib/ (valid for every framework)
        if (Directory.GetFiles(libPath, "*.dll").Length > 0 && offered.Count == 0) return libPath;
        return null;
    }

    /// <summary>Would a package whose nuspec lists these dependency-group frameworks have anything for this runtime?</summary>
    public static bool AnyUsable(IEnumerable<string> tfms)
    {
        bool any = false;
        foreach (string t in tfms)
        {
            any = true;
            if (Rank(t) >= 0) return true;
        }
        return !any;      // no groups at all: unknown, so give it a try
    }
}
