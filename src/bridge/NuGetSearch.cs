// ═══════════════════════════════════════════════════════════════════════════════
// AHK# Bridge — NuGet search that hides packages this runtime cannot load
// (part of ahk#.bridge.dll; partial class NuGetManager)
// ═══════════════════════════════════════════════════════════════════════════════

using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

internal static partial class NuGetManager
{
    private static string JsonUnescape(string s)
    {
        return Regex.Replace(s, @"\\(u[0-9a-fA-F]{4}|.)", m =>
        {
            string g = m.Groups[1].Value;
            if (g.Length == 5 && g[0] == 'u') return ((char)Convert.ToInt32(g.Substring(1), 16)).ToString();
            switch (g[0])
            {
                case 'n': return "\n";
                case 'r': return "";
                case 't': return " ";
                default: return g;
            }
        });
    }

    /// <summary>
    /// Searches nuget.org and returns "id|usableVersion|latestVersion|downloads|description" lines (description on
    /// one line). Unless includeIncompatible is set, packages with no version this runtime can use are left out, and
    /// a package whose newest release is too new is listed with the newest release that works.
    /// </summary>
    public static string Search(string query, int take, bool includeIncompatible)
    {
        if (take < 1) take = 20;
        if (take > 100) take = 100;
        _lastStatus = "Searching nuget.org for '" + query + "'...";
        string json = HttpGet("https://azuresearch-usnc.nuget.org/query?q=" + Uri.EscapeDataString(query ?? "")
            + "&take=" + (includeIncompatible ? take : Math.Min(100, take * 2)) + "&prerelease=false&semVerLevel=2.0.0");

        // each hit starts with {"@id":"https://api.nuget.org/v3/registration...
        string[] chunks = json.Split(new string[] { "{\"@id\":\"https://api.nuget.org/v3/registration" }, StringSplitOptions.None);
        List<string[]> hits = new List<string[]>();
        for (int i = 1; i < chunks.Length; i++)
        {
            string c = chunks[i];
            Match id = Regex.Match(c, "\"id\":\"([^\"]+)\"");
            Match ver = Regex.Match(c, "\"version\":\"([^\"]+)\"");
            Match dl = Regex.Match(c, "\"totalDownloads\":(\\d+)");
            Match desc = Regex.Match(c, "\"description\":\"((?:[^\"\\\\]|\\\\.)*)\"");
            if (!id.Success || !ver.Success) continue;
            string d = desc.Success ? JsonUnescape(desc.Groups[1].Value).Replace("\n", " ").Trim() : "";
            if (d.Length > 200) d = d.Substring(0, 197) + "...";
            hits.Add(new string[] { id.Groups[1].Value, ver.Groups[1].Value, dl.Success ? dl.Groups[1].Value : "0", d });
        }

        string[] usable = new string[hits.Count];
        if (includeIncompatible)
        {
            for (int i = 0; i < hits.Count; i++) usable[i] = hits[i][1];
        }
        else
        {
            Parallel.For(0, hits.Count, new ParallelOptions { MaxDegreeOfParallelism = 6 }, i =>
            {
                try
                {
                    if (NuspecUsable(hits[i][0], hits[i][1])) { usable[i] = hits[i][1]; return; }
                    List<string> stable = StableVersions(hits[i][0]);
                    for (int k = stable.Count - 1, n = 0; k >= 0 && n < 8; k--, n++)
                        if (NuspecUsable(hits[i][0], stable[k])) { usable[i] = stable[k]; return; }
                }
                catch { usable[i] = hits[i][1]; }      // could not check: show it rather than hide it
            });
        }

        StringBuilder sb = new StringBuilder();
        int shown = 0;
        for (int i = 0; i < hits.Count && shown < take; i++)
        {
            if (usable[i] == null) continue;
            if (shown++ > 0) sb.Append("\n");
            sb.Append(hits[i][0]).Append('|').Append(usable[i]).Append('|').Append(hits[i][1]).Append('|').Append(hits[i][2]).Append('|').Append(hits[i][3].Replace("|", "/"));
        }
        _lastStatus = "Search done: " + shown + " result(s).";
        return sb.ToString();
    }
}
