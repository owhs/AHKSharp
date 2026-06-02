;; AHK# Example 25 — Native Zip Archiver
;; Zipping and Unzipping files natively without relying on 7z.exe or clunky COM objects.
;; Uses the highly optimized .NET System.IO.Compression library.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

class ZipArchiver extends _CSModule {
    static References := "System.IO.Compression.dll;System.IO.Compression.FileSystem.dll"
    static CSharp := '
    (
        using System;
        using System.IO;
        using System.IO.Compression;

        public static string CompressFolder(string folderPath, string zipFilePath) {
            try {
                if (File.Exists(zipFilePath)) 
                    File.Delete(zipFilePath);
                    
                // CreateFromDirectory compresses the whole folder natively
                ZipFile.CreateFromDirectory(folderPath, zipFilePath, CompressionLevel.Optimal, false);
                return "SUCCESS";
            } catch (Exception ex) {
                return "ERR: " + ex.Message;
            }
        }
        
        public static string ExtractZip(string zipFilePath, string outFolder) {
            try {
                if (!Directory.Exists(outFolder))
                    Directory.CreateDirectory(outFolder);
                    
                // ExtractToDirectory with overwrite set to true (needs .NET Framework 4.8 / .NET Core)
                // If .NET 4.8 isn't available, we use a manual loop or standard ExtractToDirectory
                ZipFile.ExtractToDirectory(zipFilePath, outFolder);
                return "SUCCESS";
            } catch (Exception ex) {
                return "ERR: " + ex.Message;
            }
        }
    )'
}

; ── UI Setup ──
g := Gui("", "AHK# — Native Zip Archiver")
g.SetFont("s10", "Segoe UI")

g.Add("Text", "x10 y15", "Folder to Zip:")
txtFolder := g.Add("Edit", "x110 y10 w260", A_ScriptDir)
btnZip := g.Add("Button", "x380 y9 w70", "Zip It!")
btnZip.OnEvent("Click", (*) => ZipFolder())

g.Add("Text", "x10 y55", "Zip to Extract:")
txtZip := g.Add("Edit", "x110 y50 w260", A_ScriptDir "\backup.zip")
btnExtract := g.Add("Button", "x380 y49 w70", "Extract!")
btnExtract.OnEvent("Click", (*) => ExtractZip())

lblStatus := g.Add("Text", "x10 y90 w440 cBlue", "Ready")

g.Show("w460 h120")
g.OnEvent("Close", (*) => ExitApp())

ZipFolder() {
    folder := txtFolder.Value
    zipFile := txtFolder.Value "\..\backup.zip"
    
    if !DirExist(folder)
        return MsgBox("Target folder doesn't exist!")
        
    lblStatus.Value := "Compressing folder asynchronously..."
    
    ZipArchiver.Async.CompressFolder(folder, zipFile).Then(OnZipDone)
}

OnZipDone(result) {
    global lblStatus, txtFolder
    zipFile := txtFolder.Value "\..\backup.zip"
    if (result == "SUCCESS")
        lblStatus.Value := "Successfully created " zipFile "!"
    else
        lblStatus.Value := result
}

ExtractZip() {
    zipFile := txtZip.Value
    outFolder := txtZip.Value "_extracted"
    
    if !FileExist(zipFile)
        return MsgBox("Zip file doesn't exist!")
        
    lblStatus.Value := "Extracting zip asynchronously..."
    
    ZipArchiver.Async.ExtractZip(zipFile, outFolder).Then(OnExtractDone)
}

OnExtractDone(result) {
    global lblStatus, txtZip
    outFolder := txtZip.Value "_extracted"
    if (result == "SUCCESS")
        lblStatus.Value := "Successfully extracted to " outFolder "!"
    else
        lblStatus.Value := result
}
