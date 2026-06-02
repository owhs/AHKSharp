;; AHK# Example 23 — Fast Parallel File Searcher
;; Searching 10,000+ files with Regex in AHK is incredibly slow due to single-threading.
;; C# can use Parallel.ForEach to instantly blast through thousands of files.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

class FileSearcher extends _CSModule {
    static CSharp := '
    (
        using System;
        using System.IO;
        using System.Text.RegularExpressions;
        using System.Collections.Concurrent;
        using System.Threading.Tasks;

        private static volatile bool _cancel = false;
        
        public static void Cancel() {
            _cancel = true;
        }

        private static IEnumerable<string> GetFilesSafe(string root, string pattern) {
            var pending = new Stack<string>();
            pending.Push(root);
            while (pending.Count > 0) {
                var path = pending.Pop();
                string[] next = null;
                try { next = Directory.GetFiles(path, pattern); } catch { }
                if (next != null) {
                    foreach (var file in next) yield return file;
                }
                try {
                    next = Directory.GetDirectories(path);
                    foreach (var subdir in next) pending.Push(subdir);
                } catch { }
            }
        }

        public static string[] Search(string dir, string extPattern, string regexQuery, bool namesOnly, string scope, int maxAgeDays) {
            _cancel = false;
            var results = new ConcurrentBag<string>();
            int filesSearched = 0;
            try {
                Regex rx = string.IsNullOrEmpty(regexQuery) ? null : new Regex(regexQuery, RegexOptions.IgnoreCase | RegexOptions.Compiled);
                DateTime minDate = maxAgeDays > 0 ? DateTime.Now.AddDays(-maxAgeDays) : DateTime.MinValue;
                
                Parallel.ForEach(GetFilesSafe(dir, extPattern), (file, state) => {
                    if (_cancel) state.Stop();
                    try {
                        System.Threading.Interlocked.Increment(ref filesSearched);
                        
                        if (maxAgeDays > 0 && File.GetLastWriteTime(file) < minDate) 
                            return;
                            
                        if (rx == null) {
                            results.Add(file);
                            return;
                        }
                        
                        if (namesOnly) {
                            if (rx.IsMatch(Path.GetFileName(file))) results.Add(file);
                            return;
                        }
                        
                        if (scope == "Full") {
                            string content = File.ReadAllText(file);
                            if (rx.IsMatch(content)) results.Add(file);
                        } else if (scope == "First100") {
                            foreach(var line in File.ReadLines(file).Take(100)) {
                                if (rx.IsMatch(line)) { results.Add(file); break; }
                            }
                        } else if (scope == "Last100") {
                            var allLines = File.ReadAllLines(file);
                            int start = Math.Max(0, allLines.Length - 100);
                            for(int i = start; i < allLines.Length; i++) {
                                if (rx.IsMatch(allLines[i])) { results.Add(file); break; }
                            }
                        }
                    } catch { } // Ignore locked files
                });
            } catch (Exception ex) {
                results.Add("Error: " + ex.Message);
            }
            
            var finalList = new System.Collections.Generic.List<string>();
            finalList.Add("STATUS:" + filesSearched + ":" + (_cancel ? "CANCELLED" : "DONE"));
            finalList.AddRange(results);
            return finalList.ToArray();
        }
    )'
}

; ── UI Setup ──
g := Gui("", "AHK# — Ultra Fast Parallel File Searcher")
g.SetFont("s10", "Segoe UI")
g.Add("Text", "x10 y15", "Search Directory:")
txtDir := g.Add("Edit", "x120 y10 w280", A_MyDocuments)
btnBrowse := g.Add("Button", "x410 y9 w70", "Browse")
btnBrowse.OnEvent("Click", (*) => txtDir.Value := DirSelect(txtDir.Value))

g.Add("Text", "x10 y45", "Regex Query:")
txtRegex := g.Add("Edit", "x120 y40 w280", "error|failed|exception")

g.Add("Text", "x10 y75", "File Pattern:")
txtExt := g.Add("Edit", "x120 y70 w70", "*.log")
chkNamesOnly := g.Add("Checkbox", "x200 y74", "Names Only")

g.Add("Text", "x10 y105", "Scope:")
ddlScope := g.Add("DropDownList", "x60 y100 w110", ["Full", "First100", "Last100"])
ddlScope.Choose(1)

g.Add("Text", "x180 y105", "Modified:")
ddlDate := g.Add("DropDownList", "x245 y100 w110", ["Any Time", "Last 24 Hours", "Last 7 Days", "Last 30 Days"])
ddlDate.Choose(1)

btnSearch := g.Add("Button", "x10 y135 w170 h25 Default", "Start Parallel Search")
btnSearch.OnEvent("Click", StartSearch)

btnCancel := g.Add("Button", "x190 y135 w70 h25 Disabled", "Stop")
btnCancel.OnEvent("Click", (*) => FileSearcher.Cancel())

lv := g.Add("ListView", "x10 y170 w470 h250", ["Matching Files"])
lv.ModifyCol(1, 440)
lblStatus := g.Add("Text", "x10 y430 w470 cBlue", "Ready")

g.Show("w490 h460")
g.OnEvent("Close", (*) => ExitApp())

StartSearch(*) {
    dir := txtDir.Value
    if !DirExist(dir)
        return MsgBox("Directory doesn't exist!")
        
    btnSearch.Enabled := false
    btnCancel.Enabled := true
    lv.Delete()
    lblStatus.Value := "Searching heavily on background threads..."
    
    global searchStartTick := A_TickCount
    
    maxAge := 0
    if (ddlDate.Text == "Last 24 Hours")
        maxAge := 1
    else if (ddlDate.Text == "Last 7 Days")
        maxAge := 7
    else if (ddlDate.Text == "Last 30 Days")
        maxAge := 30
    
    ; ── The Magic ──
    ; Dispatch the heavy search to C# ThreadPool!
    FileSearcher.Async.Search(dir, txtExt.Value, txtRegex.Value, chkNamesOnly.Value, ddlScope.Text, maxAge).Then(OnSearchDone)
}

OnSearchDone(results) {
    global searchStartTick
    elapsedMs := A_TickCount - searchStartTick
    
    ; The first element is at index 0 (C# array wrapper is 0-indexed!)
    statusData := StrSplit(results[0], ":")
    filesSearched := statusData[2]
    isCancelled := statusData[3] == "CANCELLED"
    
    lv.Opt("-Redraw")
    loop results.Length {
        if (A_Index == 1)
            continue ; Skip status string at index 0
        lv.Add("", results[A_Index - 1])
    }
    lv.Opt("+Redraw")
    
    matches := results.Length - 1
    
    if (isCancelled)
        lblStatus.Value := "Stopped. Searched " filesSearched " files. Found " matches " matches in " elapsedMs " ms."
    else
        lblStatus.Value := "Searched " filesSearched " files. Found " matches " matches in " elapsedMs " ms!"
        
    btnSearch.Enabled := true
    btnCancel.Enabled := false
}
