;; AHK# Example 26 — Native Zip Explorer
;; A full-blown Explorer interface to view, navigate, and extract files from a Zip!
;; Plus advanced options to create new Zips using System.IO.Compression.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

class ZipTool extends _CSModule {
    static References := "System.IO.Compression.dll;System.IO.Compression.FileSystem.dll"
    static CSharp := '
    (
        using System;
        using System.IO;
        using System.IO.Compression;
        using System.Collections.Generic;

        public static string[] GetZipContents(string zipPath) {
            try {
                var results = new List<string>();
                using (ZipArchive archive = ZipFile.OpenRead(zipPath)) {
                    foreach (ZipArchiveEntry entry in archive.Entries) {
                        results.Add(entry.FullName + "|" + entry.Length + "|" + entry.CompressedLength);
                    }
                }
                return results.ToArray();
            } catch (Exception ex) {
                return new string[] { "ERROR|" + ex.Message };
            }
        }

        public static string ExtractFile(string zipPath, string entryName, string outPath) {
            try {
                using (ZipArchive archive = ZipFile.OpenRead(zipPath)) {
                    var entry = archive.GetEntry(entryName);
                    if (entry != null) {
                        string dir = Path.GetDirectoryName(outPath);
                        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
                        entry.ExtractToFile(outPath, true);
                        return "SUCCESS";
                    }
                    return "Entry not found: " + entryName;
                }
            } catch (Exception ex) {
                return "ERROR: " + ex.Message;
            }
        }
        
        public static string CompressFolder(string folderPath, string zipFilePath, int level) {
            try {
                if (File.Exists(zipFilePath)) File.Delete(zipFilePath);
                CompressionLevel compLevel = (CompressionLevel)level; // 0=Optimal, 1=Fastest, 2=NoCompression
                ZipFile.CreateFromDirectory(folderPath, zipFilePath, compLevel, false);
                return "SUCCESS";
            } catch (Exception ex) {
                return "ERROR: " + ex.Message;
            }
        }
    )'
}

; ── UI Setup ──
g := Gui("+Resize", "AHK# — Native Zip Explorer")
g.SetFont("s10", "Segoe UI")

g.Add("Text", "x10 y15", "Zip File:")
txtZip := g.Add("Edit", "x70 y10 w400", "")
btnBrowse := g.Add("Button", "x480 y9 w70", "Browse")
btnBrowse.OnEvent("Click", BrowseAndLoad)

BrowseAndLoad(*) {
    file := FileSelect(3,, "Select a Zip File", "Zip Files (*.zip)")
    if file {
        txtZip.Value := file
        LoadZip()
    }
}

btnLoad := g.Add("Button", "x560 y9 w80", "Open Zip")
btnLoad.OnEvent("Click", LoadZip)

btnNew := g.Add("Button", "x650 y9 w140", "Create New Zip...")
btnNew.OnEvent("Click", CreateNewZip)

global tv := g.Add("TreeView", "x10 y50 w220 h400 -Lines")
tv.OnEvent("ItemSelect", OnTvSelect)

global lv := g.Add("ListView", "x240 y50 w550 h400", ["File Name", "Size", "Packed Size"])
lv.ModifyCol(1, 300)
lv.ModifyCol(2, 100)
lv.ModifyCol(3, 100)
lv.OnEvent("DoubleClick", ExtractSelected)

btnExtract := g.Add("Button", "x650 y460 w140 h30 Default", "Extract Selected")
btnExtract.OnEvent("Click", ExtractSelected)

global lblStatus := g.Add("Text", "x10 y465 w600 cBlue", "Ready.")

g.Show("w800 h500")
g.OnEvent("Close", (*) => ExitApp())

; ── Global State ──
global zipItems := []
global tvRootId := 0
global tvFolders := Map()

; ── Load Zip ──
LoadZip(*) {
    if !FileExist(txtZip.Value)
        return MsgBox("Zip file not found!")
    
    lblStatus.Value := "Parsing zip contents..."
    tv.Delete()
    lv.Delete()
    zipItems := []
    
    ZipTool.Async.GetZipContents(txtZip.Value).Then(OnLoadDone)
}

OnLoadDone(results) {
    global tvFolders, tvRootId, zipItems
    
    if InStr(results[1], "ERROR|") {
        lblStatus.Value := "Failed to read zip."
        MsgBox(StrSplit(results[1], "|")[2])
        return
    }
    
    tvFolders := Map()
    tvRootId := tv.Add("Root", 0, "Expand")
    tvFolders[""] := tvRootId
    
    for item in results {
        parts := StrSplit(item, "|")
        fullName := parts[1]
        size := parts[2]
        compSize := parts[3]
        
        isDir := SubStr(fullName, -1) == "/"
        if isDir
            fullName := SubStr(fullName, 1, -1)
            
        ZipSplitPath(fullName, &name, &dir)
        
        if (dir != "" && !tvFolders.Has(dir))
            EnsureDirInTV(dir)
            
        if isDir {
            EnsureDirInTV(fullName)
        } else {
            zipItems.Push({Name: name, Dir: dir, FullName: parts[1], Size: size, CompSize: compSize})
        }
    }
    
    lblStatus.Value := "Loaded " zipItems.Length " files."
    tv.Modify(tvRootId, "Select") ; Trigger initial render
}

ZipSplitPath(path, &name, &dir) {
    lastSlash := InStr(path, "/",, -1)
    if lastSlash {
        name := SubStr(path, lastSlash + 1)
        dir := SubStr(path, 1, lastSlash - 1)
    } else {
        name := path
        dir := ""
    }
}

EnsureDirInTV(dirPath) {
    if tvFolders.Has(dirPath)
        return tvFolders[dirPath]
        
    ZipSplitPath(dirPath, &name, &parentDir)
    
    parentId := tvFolders.Has(parentDir) ? tvFolders[parentDir] : EnsureDirInTV(parentDir)
    id := tv.Add(name, parentId)
    tvFolders[dirPath] := id
    return id
}

; ── Navigate ──
OnTvSelect(ctrl, item) {
    lv.Opt("-Redraw")
    lv.Delete()
    
    selectedDir := GetTvPath(item)
    for file in zipItems {
        if (file.Dir == selectedDir) {
            lv.Add("", file.Name, Round(file.Size/1024, 1) " KB", Round(file.CompSize/1024, 1) " KB")
        }
    }
    lv.Opt("+Redraw")
}

GetTvPath(itemId) {
    if (itemId == tvRootId)
        return ""
    path := tv.GetText(itemId)
    parent := tv.GetParent(itemId)
    while (parent && parent != tvRootId) {
        path := tv.GetText(parent) "/" path
        parent := tv.GetParent(parent)
    }
    return path
}

; ── Extract ──
ExtractSelected(*) {
    row := lv.GetNext(0)
    if !row
        return MsgBox("Select a file to extract first!")
        
    fileName := lv.GetText(row, 1)
    selectedDir := GetTvPath(tv.GetSelection())
    
    ; Find the exact FullName in our array
    fullName := ""
    for file in zipItems {
        if (file.Dir == selectedDir && file.Name == fileName) {
            fullName := file.FullName
            break
        }
    }
    
    outDir := DirSelect(, 3, "Select folder to extract to")
    if !outDir
        return
        
    outPath := outDir "\" fileName
    lblStatus.Value := "Extracting " fileName "..."
    
    OnExtractDone(res) {
        if (res == "SUCCESS") {
            lblStatus.Value := "Successfully extracted to " outPath
            Run("explorer.exe /select,`"" outPath "`"")
        } else {
            lblStatus.Value := res
        }
    }
    
    ZipTool.Async.ExtractFile(txtZip.Value, fullName, outPath).Then(OnExtractDone)
}

; ── Create New Zip ──
CreateNewZip(*) {
    folder := DirSelect(, 3, "Select folder to compress")
    if !folder
        return
        
    outZip := FileSelect("S 16", folder "\..\archive.zip", "Save Zip As", "Zip Files (*.zip)")
    if !outZip
        return
        
    ; Quick UI for compression level
    compLvl := MsgBox("Use Optimal Compression?`n(Yes = Optimal, No = Fastest, Cancel = No Compression)", "Compression Level", "YesNoCancel")
    levelId := (compLvl == "Yes") ? 0 : (compLvl == "No") ? 1 : 2
    
    lblStatus.Value := "Compressing folder..."
    
    OnCompressDone(res) {
        if (res == "SUCCESS") {
            lblStatus.Value := "Successfully created " outZip
            txtZip.Value := outZip
            LoadZip() ; auto load it
        } else {
            lblStatus.Value := res
        }
    }
    
    ZipTool.Async.CompressFolder(folder, outZip, levelId).Then(OnCompressDone)
}
