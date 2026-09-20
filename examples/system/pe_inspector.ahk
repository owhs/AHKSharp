#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

; PE Inspector - lists the named exports of any PE32 / PE32+ DLL.
; Reads only the headers and export tables through a FileStream (never loads the whole
; image), validates every offset against the file length, and picks the optional-header
; data-directory offset from the Magic field (0x10B = PE32, 0x20B = PE32+).

class PEInspector extends _CSModule {
    static CSharp := '
(
        using System;
        using System.IO;
        using System.Text;
        using System.Collections.Generic;

        public class PEInspector {
            const int MaxNames = 2000000;

            static byte[] ReadAt(FileStream fs, long offset, int count) {
                if (offset < 0 || count < 0 || offset + count > fs.Length)
                    throw new InvalidDataException("Read outside file bounds (offset 0x" + offset.ToString("X") + ", " + count + " bytes)");
                byte[] buf = new byte[count];
                fs.Seek(offset, SeekOrigin.Begin);
                int done = 0;
                while (done < count) {
                    int n = fs.Read(buf, done, count - done);
                    if (n <= 0) throw new EndOfStreamException();
                    done += n;
                }
                return buf;
            }

            static int U16(FileStream fs, long offset) { return BitConverter.ToUInt16(ReadAt(fs, offset, 2), 0); }
            static long U32(FileStream fs, long offset) { return BitConverter.ToUInt32(ReadAt(fs, offset, 4), 0); }

            public static string GetExports(string dllPath) {
                try {
                    using (FileStream fs = new FileStream(dllPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite)) {
                        if (fs.Length < 0x40 || U16(fs, 0) != 0x5A4D)
                            return "ERROR: not a PE file (missing MZ header)";

                        long peHeader = U32(fs, 0x3C);
                        if (U32(fs, peHeader) != 0x00004550)
                            return "ERROR: not a PE file (missing PE signature)";

                        int numberOfSections = U16(fs, peHeader + 6);
                        int sizeOfOptionalHeader = U16(fs, peHeader + 20);
                        long optionalHeader = peHeader + 24;
                        int magic = U16(fs, optionalHeader);

                        // PE32 : data directories start at optional header + 96
                        // PE32+: data directories start at optional header + 112
                        long dataDirectory;
                        if (magic == 0x10B) dataDirectory = optionalHeader + 96;
                        else if (magic == 0x20B) dataDirectory = optionalHeader + 112;
                        else return "ERROR: unknown optional header magic 0x" + magic.ToString("X");

                        // NumberOfRvaAndSizes sits right before the directory table
                        long numberOfDirs = U32(fs, dataDirectory - 4);
                        if (numberOfDirs < 1) return "No exports found";
                        if (dataDirectory + 8 > optionalHeader + sizeOfOptionalHeader)
                            return "ERROR: optional header too small for an export directory entry";

                        long exportRva = U32(fs, dataDirectory);
                        if (exportRva == 0) return "No exports found";

                        // Section table
                        long sectionStart = optionalHeader + sizeOfOptionalHeader;
                        if (numberOfSections <= 0 || numberOfSections > 96)
                            return "ERROR: implausible section count " + numberOfSections;
                        byte[] sections = ReadAt(fs, sectionStart, numberOfSections * 40);

                        long exportOffset = RvaToOffset(exportRva, sections, numberOfSections, fs.Length);
                        if (exportOffset < 0) return "ERROR: could not map export directory RVA";

                        long numberOfNames = U32(fs, exportOffset + 24);
                        long addressOfNamesRva = U32(fs, exportOffset + 32);
                        if (numberOfNames == 0) return "No exports found";
                        if (numberOfNames > MaxNames) return "ERROR: implausible export name count " + numberOfNames;

                        long namesOffset = RvaToOffset(addressOfNamesRva, sections, numberOfSections, fs.Length);
                        if (namesOffset < 0) return "ERROR: could not map export name table";
                        byte[] nameRvas = ReadAt(fs, namesOffset, (int)numberOfNames * 4);

                        var names = new List<string>();
                        for (int i = 0; i < numberOfNames; i++) {
                            long nameRva = BitConverter.ToUInt32(nameRvas, i * 4);
                            long nameOffset = RvaToOffset(nameRva, sections, numberOfSections, fs.Length);
                            if (nameOffset < 0) continue;   // skip unmappable entries instead of crashing

                            // Read null-terminated ASCII string (capped, bounds-checked)
                            var sb = new StringBuilder();
                            fs.Seek(nameOffset, SeekOrigin.Begin);
                            for (int c = 0; c < 4096; c++) {
                                int b = fs.ReadByte();
                                if (b <= 0) break;
                                sb.Append((char)b);
                            }
                            names.Add(sb.ToString());
                        }

                        return string.Join("\n", names.ToArray());
                    }
                } catch (Exception ex) {
                    return "ERROR: " + ex.Message;
                }
            }

            // Returns the file offset for an RVA, or -1 when it is not inside any section
            // (or the mapped offset would fall outside the file).
            static long RvaToOffset(long rva, byte[] sections, int numberOfSections, long fileLength) {
                for (int i = 0; i < numberOfSections; i++) {
                    int hdr = i * 40;
                    long virtualSize = BitConverter.ToUInt32(sections, hdr + 8);
                    long virtualAddress = BitConverter.ToUInt32(sections, hdr + 12);
                    long rawSize = BitConverter.ToUInt32(sections, hdr + 16);
                    long rawPointer = BitConverter.ToUInt32(sections, hdr + 20);
                    long span = Math.Max(virtualSize, rawSize);

                    if (rva >= virtualAddress && rva < virtualAddress + span) {
                        long offset = rva - virtualAddress + rawPointer;
                        return (offset >= 0 && offset < fileLength) ? offset : -1;
                    }
                }
                return -1;
            }
        }
)'
}

dllPath := FileSelect(1, , "Select a DLL / EXE to inspect", "PE files (*.dll; *.exe; *.ocx; *.sys)")
if (dllPath = "")
    ExitApp()

exports := PEInspector.GetExports(dllPath)
if (SubStr(exports, 1, 6) = "ERROR:" || exports = "No exports found") {
    MsgBox(exports, "PE Inspector", exports = "No exports found" ? 0x40 : 0x10)
    ExitApp()
}

SplitPath(dllPath, , , , &baseName)
outPath := FileSelect("S16", A_ScriptDir "\" baseName "_exports.txt", "Save export list as", "Text files (*.txt)")
if (outPath = "")
    ExitApp()

f := FileOpen(outPath, "w", "UTF-8-RAW")
f.Write(exports)
f.Close()
count := StrSplit(exports, "`n").Length
MsgBox(count " exported names written to:`n" outPath, "PE Inspector", 0x40)
ExitApp()
