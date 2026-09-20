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
                // Never delete an existing archive here: the AHK side asks the user first
                // (CreateFromDirectory throws if the target file already exists).
                if (File.Exists(zipFilePath))
                    return "ERR: " + zipFilePath + " already exists";

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

; "Zip It!" writes backup.zip NEXT TO the chosen folder (never inside it, or the archive
; would try to include itself). The extract box defaults to that same location.
DefaultZipPath(folder) {
    SplitPath(RTrim(folder, "\"), , &parent)
    return (parent != "" ? parent : A_MyDocuments) "\backup.zip"
}

lastZipPath := ""

g.Add("Text", "x10 y55", "Zip to Extract:")
txtZip := g.Add("Edit", "x110 y50 w260", DefaultZipPath(A_ScriptDir))
btnExtract := g.Add("Button", "x380 y49 w70", "Extract!")
btnExtract.OnEvent("Click", (*) => ExtractZip())

lblStatus := g.Add("Text", "x10 y90 w440 cBlue", "Ready")

g.Show("w460 h120")
g.OnEvent("Close", (*) => ExitApp())

ZipFolder() {
    global lastZipPath
    folder := RTrim(txtFolder.Value, "\")
    zipFile := DefaultZipPath(folder)

    if !DirExist(folder)
        return MsgBox("Target folder doesn't exist!")

    ; Never silently destroy an existing backup: ask first
    if FileExist(zipFile) {
        if (MsgBox(zipFile " already exists.`n`nOverwrite it?", "Zip It", "YesNo Icon?") != "Yes")
            return
        try FileDelete(zipFile)
        catch as err
            return MsgBox("Could not remove the existing archive:`n" err.Message, "Zip It", "Icon!")
    }

    lastZipPath := zipFile
    lblStatus.Value := "Compressing folder asynchronously..."

    ZipArchiver.Async.CompressFolder(folder, zipFile).Then(OnZipDone)
}

OnZipDone(result) {
    global lblStatus, txtZip, lastZipPath
    if (result == "SUCCESS") {
        txtZip.Value := lastZipPath        ; the Extract box now points at what was just written
        lblStatus.Value := "Successfully created " lastZipPath "!"
    } else
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
