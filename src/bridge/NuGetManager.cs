// ═══════════════════════════════════════════════════════════════════════════════
// AHK# Bridge — NuGetManager: download, extract and cache NuGet packages
// (part of ahk#.bridge.dll; see AhkSharpBridge.cs for the COM entry point)
// ═══════════════════════════════════════════════════════════════════════════════

using System;
using System.CodeDom.Compiler;
using System.Collections;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Linq.Expressions;
using System.Net;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Runtime.ExceptionServices;
using Microsoft.CSharp;

// ─────────────────────────────────────────────────────────────────────────────
// NuGet Package Manager — Download, extract, cache packages from nuget.org
// ─────────────────────────────────────────────────────────────────────────────
// .nupkg files are ZIP archives. DLLs live in lib/{framework}/ folders.
// Framework choice: see FrameworkPicker.cs (net4x up to the installed Framework > netstandard1.0-2.0 > net35; never net5.0+)
// Cache dir: %LocalAppData%\AhkSharp\Packages\{id}\{version}\

internal static partial class NuGetManager
{
    private static readonly string _packagesDir;
    private static string _lastStatus = "";

    public static string LastStatus { get { return _lastStatus; } }

    /// <summary>Verify downloads against nuget.org's published SHA-512 (default true).</summary>
    public static bool VerifyDownloads = true;
    /// <summary>Treat a package whose hash cannot be fetched as a failure (default false: warn and continue).</summary>
    public static bool StrictVerification = false;

    private static string HttpGet(string url)
    {
        HttpWebRequest req = (HttpWebRequest)WebRequest.Create(url);
        req.UserAgent = "AHK-Sharp/1.0";
        req.AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate;
        req.Timeout = 30000;
        using (WebResponse resp = req.GetResponse())
        using (StreamReader sr = new StreamReader(resp.GetResponseStream(), Encoding.UTF8))
            return sr.ReadToEnd();
    }

    /// <summary>"verified sha512", "mismatch: ...", "unverifiable: ...", or "verification off".</summary>
    public static string Verify(string packageId, string version, string nupkgPath)
    {
        if (!VerifyDownloads) return "verification off";
        string expected, algorithm;
        try
        {
            // registration leaf → catalog entry → packageHash
            string leaf = HttpGet("https://api.nuget.org/v3/registration5-gz-semver2/"
                + packageId.ToLowerInvariant() + "/" + version.ToLowerInvariant() + ".json");
            System.Text.RegularExpressions.Match ce = System.Text.RegularExpressions.Regex.Match(leaf, "\"catalogEntry\"\\s*:\\s*\"([^\"]+)\"");
            if (!ce.Success) return "unverifiable: no catalog entry";
            string entry = HttpGet(ce.Groups[1].Value);
            System.Text.RegularExpressions.Match h = System.Text.RegularExpressions.Regex.Match(entry, "\"packageHash\"\\s*:\\s*\"([^\"]+)\"");
            System.Text.RegularExpressions.Match a = System.Text.RegularExpressions.Regex.Match(entry, "\"packageHashAlgorithm\"\\s*:\\s*\"([^\"]+)\"");
            if (!h.Success) return "unverifiable: no packageHash";
            expected = h.Groups[1].Value;
            algorithm = a.Success ? a.Groups[1].Value : "SHA512";
        }
        catch (Exception ex)
        {
            return "unverifiable: " + ex.Message;
        }

        if (!string.Equals(algorithm, "SHA512", StringComparison.OrdinalIgnoreCase))
            return "unverifiable: unsupported hash algorithm " + algorithm;

        string actual;
        using (SHA512 sha = SHA512.Create())
        using (FileStream fs = File.OpenRead(nupkgPath))
            actual = Convert.ToBase64String(sha.ComputeHash(fs));

        return actual == expected ? "verified sha512" : "mismatch: expected " + expected.Substring(0, 12) + "... but the download hashes to " + actual.Substring(0, 12) + "...";
    }

    static NuGetManager()
    {
        _packagesDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "AhkSharp", "Packages");
        if (!Directory.Exists(_packagesDir))
            Directory.CreateDirectory(_packagesDir);

        // Force TLS 1.2 for NuGet API
        ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072;
    }

    /// <summary>
    /// Downloads and extracts a NuGet package. Returns the package install directory.
    /// If version is empty, resolves the latest stable version.
    /// </summary>
    public static string Install(string packageId, string version)
    {
        return Install(packageId, version, new HashSet<string>(StringComparer.OrdinalIgnoreCase));
    }

    private static string Install(string packageId, string version, HashSet<string> visited)
    {
        if (string.IsNullOrEmpty(version))
            version = ResolveLatestVersion(packageId);

        string pkgDir = Path.Combine(_packagesDir, packageId.ToLowerInvariant(), version);
        string libDir = Path.Combine(pkgDir, "lib");

        // Guard against dependency cycles
        if (!visited.Add(packageId.ToLowerInvariant() + "|" + version))
            return pkgDir;

        // Already installed?
        if (Directory.Exists(libDir) && Directory.GetFiles(libDir, "*.dll", SearchOption.AllDirectories).Length > 0)
        {
            _lastStatus = "Already installed: " + packageId + " " + version;
            return pkgDir;
        }

        // Download the .nupkg
        _lastStatus = "Downloading " + packageId + " " + version + "...";
        string nupkgUrl = string.Format(
            "https://api.nuget.org/v3-flatcontainer/{0}/{1}/{0}.{1}.nupkg",
            packageId.ToLowerInvariant(), version);

        string nupkgPath = Path.Combine(pkgDir, packageId + "." + version + ".nupkg");
        if (!Directory.Exists(pkgDir))
            Directory.CreateDirectory(pkgDir);

        using (var client = new WebClient())
        {
            client.Headers.Add("User-Agent", "AHK-Sharp/1.0");
            client.DownloadFile(nupkgUrl, nupkgPath);
        }

        // Integrity: compare against the SHA-512 nuget.org publishes for this exact package version
        string verdict = Verify(packageId, version, nupkgPath);
        if (verdict.StartsWith("mismatch"))
        {
            try { File.Delete(nupkgPath); } catch { }
            throw new InvalidDataException("NuGet package " + packageId + " " + version + " failed integrity verification: " + verdict);
        }
        if (verdict.StartsWith("unverifiable") && StrictVerification)
        {
            try { File.Delete(nupkgPath); } catch { }
            throw new InvalidDataException("NuGet package " + packageId + " " + version + " could not be verified (" + verdict + ") and strict verification is on.");
        }
        _lastStatus = "Downloaded " + packageId + " " + version + " (" + verdict + ")";

        // Extract
        _lastStatus = "Extracting " + packageId + "...";
        string extractDir = Path.Combine(pkgDir, "_extract");
        if (Directory.Exists(extractDir))
            Directory.Delete(extractDir, true);

        ZipFile.ExtractToDirectory(nupkgPath, extractDir);

        // Find best framework target
        string extractLib = Path.Combine(extractDir, "lib");
        if (Directory.Exists(extractLib))
        {
            List<string> offered = new List<string>();
            string bestFx = FrameworkPicker.PickLibDir(extractLib, offered);
            if (bestFx != null)
            {
                if (!Directory.Exists(libDir))
                    Directory.CreateDirectory(libDir);

                foreach (string file in Directory.GetFiles(bestFx))
                {
                    string dest = Path.Combine(libDir, Path.GetFileName(file));
                    File.Copy(file, dest, true);
                }
            }
            else if (offered.Count > 0)
            {
                // assemblies exist, but none for a framework this CLR can load: say so instead of loading a wrong one
                try { Directory.Delete(pkgDir, true); } catch { }
                throw new NotSupportedException(packageId + " " + version + " has no assemblies this runtime can load. It offers: "
                    + string.Join(", ", offered.ToArray()) + ". AHK# runs on .NET Framework 4.x (this machine: "
                    + FrameworkPicker.MaxNet + ", netstandard " + (FrameworkPicker.NetStandardOk ? "up to 2.0 is usable" : "needs Framework 4.7.2+")
                    + "), so it can load net20-net4x and netstandard1.0-2.0 builds, not net5.0+. Try an older version of the package.");
            }
        }

        // Also copy any native runtimes (for packages like SQLitePCLRaw)
        string runtimesDir = Path.Combine(extractDir, "runtimes");
        if (Directory.Exists(runtimesDir))
        {
            string destRuntimes = Path.Combine(pkgDir, "runtimes");
            CopyDirectory(runtimesDir, destRuntimes);
        }

        // Also check for tools (some packages like Roslyn put csc.exe in tools/) and MSBuild tasks (the newer Roslyn toolset: tasks/net472/csc.exe)
        string toolsDir = Path.Combine(extractDir, "tools");
        if (Directory.Exists(toolsDir))
        {
            string destTools = Path.Combine(pkgDir, "tools");
            CopyDirectory(toolsDir, destTools);
        }
        string tasksDir = Path.Combine(extractDir, "tasks", "net472");
        if (Directory.Exists(tasksDir))
            CopyDirectory(tasksDir, Path.Combine(pkgDir, "tasks", "net472"));

        // Dependencies (best effort): recorded in deps.txt so GetReferences can include them
        try { InstallDependencies(extractDir, pkgDir, visited); }
        catch (Exception ex) { _lastStatus = "Dependency warning for " + packageId + ": " + ex.Message; }

        // Cleanup
        try { Directory.Delete(extractDir, true); } catch { }
        try { File.Delete(nupkgPath); } catch { }

        _lastStatus = "Installed: " + packageId + " " + version;
        return pkgDir;
    }

    // Packages that are pure metadata on .NET Framework (no DLLs) — never worth downloading
    private static readonly HashSet<string> _metaPackages = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        "NETStandard.Library", "Microsoft.NETCore.Platforms", "Microsoft.NETCore.Targets"
    };

    private static void InstallDependencies(string extractDir, string pkgDir, HashSet<string> visited)
    {
        string[] nuspecs = Directory.GetFiles(extractDir, "*.nuspec", SearchOption.TopDirectoryOnly);
        if (nuspecs.Length == 0) return;

        System.Xml.Linq.XDocument doc = System.Xml.Linq.XDocument.Load(nuspecs[0]);
        var deps = doc.Descendants().Where(e => e.Name.LocalName == "dependencies").FirstOrDefault();
        if (deps == null) return;

        // Pick the dependency group whose framework ranks highest on this runtime
        var groups = deps.Elements().Where(e => e.Name.LocalName == "group").ToList();
        IEnumerable<System.Xml.Linq.XElement> chosen;
        if (groups.Count == 0)
        {
            chosen = deps.Elements().Where(e => e.Name.LocalName == "dependency");
        }
        else
        {
            System.Xml.Linq.XElement group = null;
            int bestRank = -1;
            foreach (var g in groups)
            {
                int r = FrameworkPicker.Rank((string)g.Attribute("targetFramework"));
                if (r > bestRank) { bestRank = r; group = g; }
            }
            if (group == null) return;
            chosen = group.Elements().Where(e => e.Name.LocalName == "dependency");
        }

        List<string> recorded = new List<string>();
        foreach (var dep in chosen.ToList())
        {
            string id = (string)dep.Attribute("id");
            string range = (string)dep.Attribute("version") ?? "";
            if (string.IsNullOrEmpty(id) || _metaPackages.Contains(id)) continue;

            // Use the minimum version of the range ("[1.2.3,)" → 1.2.3)
            System.Text.RegularExpressions.Match m =
                System.Text.RegularExpressions.Regex.Match(range, @"[0-9][0-9A-Za-z\.\-\+]*");
            if (!m.Success) continue;
            string depVersion = m.Value;

            try
            {
                Install(id, depVersion, visited);
                recorded.Add(id + "|" + depVersion);
            }
            catch (Exception ex)
            {
                _lastStatus = "Dependency " + id + " " + depVersion + " failed: " + ex.Message;
            }
        }
        if (recorded.Count > 0)
            File.WriteAllLines(Path.Combine(pkgDir, "deps.txt"), recorded.ToArray());
    }

    /// <summary>Returns semicolon-separated paths to all DLLs for a package and its dependencies.</summary>
    public static string GetReferences(string packageId, string version)
    {
        if (string.IsNullOrEmpty(version))
            version = ResolveLatestVersion(packageId);

        List<string> dlls = new List<string>();
        CollectReferences(packageId, version, dlls, new HashSet<string>(StringComparer.OrdinalIgnoreCase));
        return string.Join(";", dlls.Distinct(StringComparer.OrdinalIgnoreCase).ToArray());
    }

    private static void CollectReferences(string packageId, string version, List<string> dlls, HashSet<string> seen)
    {
        if (!seen.Add(packageId + "|" + version)) return;

        string pkgDir = Path.Combine(_packagesDir, packageId.ToLowerInvariant(), version);
        string libDir = Path.Combine(pkgDir, "lib");
        if (Directory.Exists(libDir))
            dlls.AddRange(Directory.GetFiles(libDir, "*.dll", SearchOption.TopDirectoryOnly));

        string depsFile = Path.Combine(pkgDir, "deps.txt");
        if (File.Exists(depsFile))
        {
            foreach (string line in File.ReadAllLines(depsFile))
            {
                string[] parts = line.Split('|');
                if (parts.Length == 2)
                    CollectReferences(parts[0], parts[1], dlls, seen);
            }
        }
    }

    /// <summary>Checks if a package is already cached.</summary>
    public static bool IsInstalled(string packageId, string version)
    {
        if (string.IsNullOrEmpty(version))
        {
            // Check if any version exists
            string pkgRoot = Path.Combine(_packagesDir, packageId.ToLowerInvariant());
            return Directory.Exists(pkgRoot) && Directory.GetDirectories(pkgRoot).Length > 0;
        }

        string libDir = Path.Combine(_packagesDir, packageId.ToLowerInvariant(), version, "lib");
        return Directory.Exists(libDir) && Directory.GetFiles(libDir, "*.dll", SearchOption.AllDirectories).Length > 0;
    }

    /// <summary>Uninstalls and removes a NuGet package directory.</summary>
    public static bool Uninstall(string packageId, string version)
    {
        if (string.IsNullOrEmpty(packageId))
            return false;

        string pkgDir = Path.Combine(_packagesDir, packageId.ToLowerInvariant());
        if (!Directory.Exists(pkgDir))
        {
            _lastStatus = "Package " + packageId + " not found.";
            return false;
        }

        try
        {
            if (string.IsNullOrEmpty(version) || version == "*" || version.ToLowerInvariant() == "all")
            {
                Directory.Delete(pkgDir, true);
                _lastStatus = "Successfully removed package: " + packageId;
                return true;
            }
            else
            {
                string verDir = Path.Combine(pkgDir, version);
                if (Directory.Exists(verDir))
                {
                    Directory.Delete(verDir, true);

                    // If no other versions remain, delete parent package folder
                    if (Directory.GetDirectories(pkgDir).Length == 0 && Directory.GetFiles(pkgDir).Length == 0)
                    {
                        Directory.Delete(pkgDir, true);
                    }

                    _lastStatus = "Successfully removed " + packageId + " " + version;
                    return true;
                }
                else
                {
                    _lastStatus = "Version " + version + " of " + packageId + " not found.";
                    return false;
                }
            }
        }
        catch (Exception ex)
        {
            _lastStatus = "Failed to uninstall " + packageId + ": " + ex.Message;
            return false;
        }
    }

    /// <summary>All stable versions of a package, oldest first (NuGet v3 flat container).</summary>
    public static List<string> StableVersions(string packageId)
    {
        string url = string.Format("https://api.nuget.org/v3-flatcontainer/{0}/index.json", packageId.ToLowerInvariant());
        string json;
        using (var client = new WebClient())
        {
            client.Headers.Add("User-Agent", "AHK-Sharp/1.0");
            json = client.DownloadString(url);
        }

        List<string> all = new List<string>();
        int open = json.IndexOf("[");
        int close = json.IndexOf("]");
        if (open >= 0 && close > open)
        {
            foreach (string v in json.Substring(open + 1, close - open - 1).Split(','))
            {
                string clean = v.Trim().Trim('"');
                if (!string.IsNullOrEmpty(clean)) all.Add(clean);
            }
        }
        List<string> stable = all.Where(v => !v.Contains("-")).ToList();
        return stable.Count > 0 ? stable : all;
    }

    /// <summary>
    /// The nuspec's dependency groups say which frameworks a version was built for. A version whose groups are all
    /// net5.0+ / netstandard2.1 / netcoreapp has nothing this runtime can load. (No groups: unknown, so "usable".)
    /// </summary>
    public static bool NuspecUsable(string packageId, string version)
    {
        try
        {
            string nuspec = HttpGet(string.Format("https://api.nuget.org/v3-flatcontainer/{0}/{1}/{0}.nuspec",
                packageId.ToLowerInvariant(), version.ToLowerInvariant()));
            System.Xml.Linq.XDocument doc = System.Xml.Linq.XDocument.Parse(nuspec.TrimStart('﻿'));
            var groups = doc.Descendants().Where(e => e.Name.LocalName == "group" && e.Parent != null && e.Parent.Name.LocalName == "dependencies");
            return FrameworkPicker.AnyUsable(groups.Select(g => (string)g.Attribute("targetFramework")).ToList());
        }
        catch { return true; }
    }

    /// <summary>
    /// The newest stable version this runtime can use: newer releases that only target net5.0+ are skipped
    /// (looking at the newest 12), so "latest" means "latest that works here".
    /// </summary>
    public static string ResolveLatestVersion(string packageId)
    {
        _lastStatus = "Resolving latest version of " + packageId + "...";
        List<string> stable = StableVersions(packageId);
        if (stable.Count == 0) throw new InvalidOperationException("Could not resolve version for: " + packageId);

        string newest = stable[stable.Count - 1];
        int tried = 0;
        for (int i = stable.Count - 1; i >= 0 && tried < 12; i--, tried++)
        {
            if (!NuspecUsable(packageId, stable[i])) continue;
            if (i != stable.Count - 1)
                _lastStatus = packageId + " " + newest + " targets only frameworks newer than this runtime; using " + stable[i] + ".";
            return stable[i];
        }
        return newest;      // nothing usable found: Install explains what the package offers
    }

    /// <summary>
    /// Ensures the Roslyn compiler for a C# language version is available (downloaded once). Returns the folder with csc.exe.
    /// C# up to 10 uses microsoft.net.compilers 4.0.1; 11, 12 and "latest" use Microsoft.Net.Compilers.Toolset 4.8.0
    /// (csc.exe for .NET Framework 4.7.2+).
    /// </summary>
    public static string EnsureRoslyn(string langVersion)
    {
        bool modern = false;
        string lv = (langVersion ?? "").Trim().ToLowerInvariant();
        if (lv == "latest" || lv == "preview" || lv == "latestmajor") modern = true;
        else
        {
            double n;
            if (double.TryParse(lv, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out n) && n >= 11) modern = true;
        }

        if (modern && FrameworkPicker.MaxNet < 4072)
            throw new NotSupportedException("C# " + langVersion + " needs the newer Roslyn compiler, which runs on .NET Framework 4.7.2 or later; this machine has "
                + FrameworkPicker.MaxNet + ". Use CSVersion up to \"10.0\" here.");

        string pkgId = modern ? "microsoft.net.compilers.toolset" : "microsoft.net.compilers";
        string pkgVersion = modern ? "4.8.0" : "4.0.1";
        string sub = modern ? Path.Combine("tasks", "net472") : "tools";
        string dir = Path.Combine(_packagesDir, pkgId, pkgVersion, sub);
        if (File.Exists(Path.Combine(dir, "csc.exe")))
            return dir;

        _lastStatus = "Installing the Roslyn compiler (one-time setup)...";
        Install(pkgId, pkgVersion);

        if (File.Exists(Path.Combine(dir, "csc.exe")))
            return dir;

        throw new InvalidOperationException("Failed to install the Roslyn compiler. Check the network connection.");
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    private static void CopyDirectory(string src, string dest)
    {
        if (!Directory.Exists(dest))
            Directory.CreateDirectory(dest);

        foreach (string file in Directory.GetFiles(src))
            File.Copy(file, Path.Combine(dest, Path.GetFileName(file)), true);

        foreach (string dir in Directory.GetDirectories(src))
            CopyDirectory(dir, Path.Combine(dest, Path.GetFileName(dir)));
    }
}

