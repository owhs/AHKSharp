;; AHK# Example 40 — COM-Free Excel Reader/Writer
;; "How do I read Excel without Excel installed?" — the #1 AHK FAQ.
;; XLSX files are just ZIP archives containing XML. .NET's System.IO.Packaging
;; opens them natively. Zero COM, zero Excel, zero dependencies.
;;
;; Usage:
;;   sheets := Excel.ListSheets("data.xlsx")
;;   data := Excel.ReadSheet("data.xlsx", "Sheet1", 500)   ; max rows, 0 = all rows
;;   cell := Excel.ReadCell("data.xlsx", "Sheet1", "B3")
;;   Excel.CreateWorkbook("output.xlsx")
;;   Excel.WriteCell("output.xlsx", "Sheet1", "A1", "Hello")

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

; ── CSModule: Excel ───────────────────────────────────────────────────────────

; System.IO.Packaging lives in WindowsBase.dll, which sits in the WPF folder of the .NET
; Framework (not on the compiler's default search path). Build the path from A_WinDir.
ExcelWindowsBaseRef() {
    p := A_WinDir "\Microsoft.NET\Framework64\v4.0.30319\WPF\WindowsBase.dll"
    return FileExist(p) ? p : "WindowsBase.dll"
}

class Excel extends _CSModule {
    static References := ExcelWindowsBaseRef()
    static CSharp := '
    (
        using System;
        using System.IO;
        using System.IO.Packaging;
        using System.Xml;
        using System.Collections.Generic;
        using System.Text;
        using System.Linq;

        private static readonly string _nsMain = "http://schemas.openxmlformats.org/spreadsheetml/2006/main";
        private static readonly string _nsRel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";
        private static readonly string _nsContentTypes = "http://schemas.openxmlformats.org/package/2006/content-types";

        public static string ListSheets(string path) {
            using (var pkg = Package.Open(path, FileMode.Open, FileAccess.Read)) {
                var wbPart = pkg.GetPart(new Uri("/xl/workbook.xml", UriKind.Relative));
                var doc = LoadXml(wbPart);
                var nsMgr = MakeNs(doc, "s", _nsMain);
                var sheets = doc.SelectNodes("//s:sheet", nsMgr);
                var sb = new StringBuilder();
                foreach (XmlNode sheet in sheets) {
                    sb.AppendLine(sheet.Attributes["name"].Value);
                }
                return sb.ToString().TrimEnd();
            }
        }

        // maxRows <= 0 means "no limit". When rows are cut off, the last line says so.
        public static string ReadSheet(string path, string sheetName, int maxRows) {
            using (var pkg = Package.Open(path, FileMode.Open, FileAccess.Read)) {
                int sheetIndex = GetSheetIndex(pkg, sheetName);
                if (sheetIndex < 0) return "Error: Sheet not found: " + sheetName;

                var strings = LoadSharedStrings(pkg);
                var sheetPart = GetSheetPart(pkg, sheetIndex);
                if (sheetPart == null) return "Error: Sheet data not found";

                var doc = LoadXml(sheetPart);
                var nsMgr = MakeNs(doc, "s", _nsMain);
                var rows = doc.SelectNodes("//s:sheetData/s:row", nsMgr);

                var sb = new StringBuilder();
                int maxCol = 0;
                var data = new Dictionary<string, string>();

                foreach (XmlNode row in rows) {
                    var cells = row.SelectNodes("s:c", nsMgr);
                    foreach (XmlNode cell in cells) {
                        string cellRef = cell.Attributes["r"].Value;
                        string cellType = cell.Attributes["t"] != null ? cell.Attributes["t"].Value : "";
                        var valNode = cell.SelectSingleNode("s:v", nsMgr);
                        string val = valNode != null ? valNode.InnerText : "";

                        if (cellType == "s" && strings != null) {
                            int idx;
                            if (int.TryParse(val, out idx) && idx < strings.Count)
                                val = strings[idx];
                        }
                        data[cellRef] = val;
                        int col = ColIndex(cellRef);
                        if (col > maxCol) maxCol = col;
                    }
                }

                // Build tab-separated output
                int maxRow = 0;
                foreach (var key in data.Keys) {
                    int r = RowIndex(key);
                    if (r > maxRow) maxRow = r;
                }

                int lastRow = (maxRows > 0 && maxRows < maxRow) ? maxRows : maxRow;
                for (int r = 1; r <= lastRow; r++) {
                    var cols = new List<string>();
                    for (int c = 1; c <= maxCol; c++) {
                        string key = ColName(c) + r.ToString();
                        string v;
                        cols.Add(data.TryGetValue(key, out v) ? v : "");
                    }
                    sb.AppendLine(string.Join("\t", cols.ToArray()));
                }
                if (lastRow < maxRow)
                    sb.AppendLine("... [truncated: showing " + lastRow + " of " + maxRow + " rows - raise Max rows (0 = all) to see more]");
                return sb.ToString().TrimEnd();
            }
        }

        public static string ReadCell(string path, string sheetName, string cellRef) {
            using (var pkg = Package.Open(path, FileMode.Open, FileAccess.Read)) {
                int sheetIndex = GetSheetIndex(pkg, sheetName);
                if (sheetIndex < 0) return "";
                var strings = LoadSharedStrings(pkg);
                var sheetPart = GetSheetPart(pkg, sheetIndex);
                if (sheetPart == null) return "";

                var doc = LoadXml(sheetPart);
                var nsMgr = MakeNs(doc, "s", _nsMain);
                var cell = doc.SelectSingleNode(
                    string.Format("//s:sheetData/s:row/s:c[@r=" + (char)39 + "{0}" + (char)39 + "]", cellRef.ToUpper()),
                    nsMgr);
                if (cell == null) return "";

                string cellType = cell.Attributes["t"] != null ? cell.Attributes["t"].Value : "";
                var valNode = cell.SelectSingleNode("s:v", nsMgr);
                string val = valNode != null ? valNode.InnerText : "";

                if (cellType == "s" && strings != null) {
                    int idx;
                    if (int.TryParse(val, out idx) && idx < strings.Count)
                        val = strings[idx];
                }
                return val;
            }
        }

        public static string GetHeaders(string path, string sheetName) {
            string sheet = ReadSheet(path, sheetName, 1);
            if (sheet.StartsWith("Error:")) return sheet;
            int nl = sheet.IndexOf((char)10);
            return nl > 0 ? sheet.Substring(0, nl).TrimEnd() : sheet;
        }

        public static string GetSheetInfo(string path) {
            var sb = new StringBuilder();
            var fi = new FileInfo(path);
            sb.AppendLine("File: " + fi.Name);
            sb.AppendLine("Size: " + (fi.Length / 1024.0).ToString("F1") + " KB");
            sb.AppendLine("Modified: " + fi.LastWriteTime.ToString("yyyy-MM-dd HH:mm"));
            sb.AppendLine("Sheets: " + ListSheets(path));
            return sb.ToString();
        }

        // ── Write Operations ─────────────────────────────────────────────
        public static void CreateWorkbook(string path) {
            if (File.Exists(path)) File.Delete(path);
            using (var pkg = Package.Open(path, FileMode.Create)) {
                // Content Types
                var ctPart = pkg.CreatePart(
                    new Uri("/[Content_Types].xml", UriKind.Relative),
                    "application/xml");
                WriteXml(ctPart, "<?xml version=" + (char)34 + "1.0" + (char)34 +
                    " encoding=" + (char)34 + "UTF-8" + (char)34 + "?>" +
                    "<Types xmlns=" + (char)34 + _nsContentTypes + (char)34 + ">" +
                    "<Default Extension=" + (char)34 + "rels" + (char)34 +
                    " ContentType=" + (char)34 + "application/vnd.openxmlformats-package.relationships+xml" + (char)34 + "/>" +
                    "<Default Extension=" + (char)34 + "xml" + (char)34 +
                    " ContentType=" + (char)34 + "application/xml" + (char)34 + "/>" +
                    "<Override PartName=" + (char)34 + "/xl/workbook.xml" + (char)34 +
                    " ContentType=" + (char)34 + "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml" + (char)34 + "/>" +
                    "<Override PartName=" + (char)34 + "/xl/worksheets/sheet1.xml" + (char)34 +
                    " ContentType=" + (char)34 + "application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml" + (char)34 + "/>" +
                    "</Types>");

                // Workbook
                var wbPart = pkg.CreatePart(
                    new Uri("/xl/workbook.xml", UriKind.Relative),
                    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml");
                pkg.CreateRelationship(wbPart.Uri, TargetMode.Internal,
                    "http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument");

                WriteXml(wbPart, "<?xml version=" + (char)34 + "1.0" + (char)34 + "?>" +
                    "<workbook xmlns=" + (char)34 + _nsMain + (char)34 +
                    " xmlns:r=" + (char)34 + _nsRel + (char)34 + ">" +
                    "<sheets><sheet name=" + (char)34 + "Sheet1" + (char)34 +
                    " sheetId=" + (char)34 + "1" + (char)34 +
                    " r:id=" + (char)34 + "rId1" + (char)34 + "/></sheets></workbook>");

                // Sheet relationship
                wbPart.CreateRelationship(
                    new Uri("/xl/worksheets/sheet1.xml", UriKind.Relative),
                    TargetMode.Internal,
                    "http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet",
                    "rId1");

                // Empty sheet
                var shPart = pkg.CreatePart(
                    new Uri("/xl/worksheets/sheet1.xml", UriKind.Relative),
                    "application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml");
                WriteXml(shPart, "<?xml version=" + (char)34 + "1.0" + (char)34 + "?>" +
                    "<worksheet xmlns=" + (char)34 + _nsMain + (char)34 + ">" +
                    "<sheetData/></worksheet>");
            }
        }

        public static void WriteCell(string path, string sheetName, string cellRef, string value) {
            cellRef = cellRef.ToUpper();
            int row = RowIndex(cellRef);

            using (var pkg = Package.Open(path, FileMode.Open, FileAccess.ReadWrite)) {
                int sheetIndex = GetSheetIndex(pkg, sheetName);
                if (sheetIndex < 0) return;
                var sheetPart = GetSheetPart(pkg, sheetIndex);
                if (sheetPart == null) return;

                var doc = LoadXml(sheetPart);
                var nsMgr = MakeNs(doc, "s", _nsMain);
                var sheetData = doc.SelectSingleNode("//s:sheetData", nsMgr);

                // Find or create row
                var rowNode = doc.SelectSingleNode(
                    string.Format("//s:sheetData/s:row[@r=" + (char)39 + "{0}" + (char)39 + "]", row),
                    nsMgr);
                if (rowNode == null) {
                    rowNode = doc.CreateElement("row", _nsMain);
                    var rAttr = doc.CreateAttribute("r");
                    rAttr.Value = row.ToString();
                    rowNode.Attributes.Append(rAttr);
                    sheetData.AppendChild(rowNode);
                }

                // Find or create cell
                var cellNode = doc.SelectSingleNode(
                    string.Format("//s:sheetData/s:row/s:c[@r=" + (char)39 + "{0}" + (char)39 + "]", cellRef),
                    nsMgr);
                if (cellNode == null) {
                    cellNode = doc.CreateElement("c", _nsMain);
                    var rAttr = doc.CreateAttribute("r");
                    rAttr.Value = cellRef;
                    cellNode.Attributes.Append(rAttr);
                    rowNode.AppendChild(cellNode);
                }

                // Set value (inline string)
                cellNode.InnerXml = "";
                var tAttr = cellNode.Attributes["t"];
                if (tAttr == null) {
                    tAttr = doc.CreateAttribute("t");
                    cellNode.Attributes.Append(tAttr);
                }
                tAttr.Value = "inlineStr";
                var isNode = doc.CreateElement("is", _nsMain);
                var tNode = doc.CreateElement("t", _nsMain);
                tNode.InnerText = value;
                isNode.AppendChild(tNode);
                cellNode.AppendChild(isNode);

                // Save back
                using (var stream = sheetPart.GetStream(FileMode.Create)) {
                    doc.Save(stream);
                }
            }
        }

        // ── Helpers ──────────────────────────────────────────────────────
        private static int GetSheetIndex(Package pkg, string sheetName) {
            var wbPart = pkg.GetPart(new Uri("/xl/workbook.xml", UriKind.Relative));
            var doc = LoadXml(wbPart);
            var nsMgr = MakeNs(doc, "s", _nsMain);
            var sheets = doc.SelectNodes("//s:sheet", nsMgr);
            for (int i = 0; i < sheets.Count; i++) {
                if (sheets[i].Attributes["name"].Value.Equals(sheetName, StringComparison.OrdinalIgnoreCase))
                    return i + 1;
            }
            return -1;
        }

        private static PackagePart GetSheetPart(Package pkg, int index) {
            var uri = new Uri("/xl/worksheets/sheet" + index + ".xml", UriKind.Relative);
            try { return pkg.GetPart(uri); }
            catch { return null; }
        }

        private static List<string> LoadSharedStrings(Package pkg) {
            var uri = new Uri("/xl/sharedStrings.xml", UriKind.Relative);
            try {
                var part = pkg.GetPart(uri);
                var doc = LoadXml(part);
                var nsMgr = MakeNs(doc, "s", _nsMain);
                var items = doc.SelectNodes("//s:si", nsMgr);
                var list = new List<string>();
                foreach (XmlNode item in items) {
                    var t = item.SelectSingleNode(".//s:t", nsMgr);
                    list.Add(t != null ? t.InnerText : "");
                }
                return list;
            } catch {
                return new List<string>();
            }
        }

        private static XmlDocument LoadXml(PackagePart part) {
            var doc = new XmlDocument();
            using (var stream = part.GetStream(FileMode.Open, FileAccess.Read)) {
                doc.Load(stream);
            }
            return doc;
        }

        private static XmlNamespaceManager MakeNs(XmlDocument doc, string prefix, string uri) {
            var nsMgr = new XmlNamespaceManager(doc.NameTable);
            nsMgr.AddNamespace(prefix, uri);
            return nsMgr;
        }

        private static void WriteXml(PackagePart part, string xml) {
            using (var sw = new StreamWriter(part.GetStream(FileMode.Create))) {
                sw.Write(xml);
            }
        }

        private static int ColIndex(string cellRef) {
            int col = 0;
            foreach (char c in cellRef) {
                if (c >= (char)65 && c <= (char)90)
                    col = col * 26 + (c - (char)65 + 1);
                else if (c >= (char)97 && c <= (char)122)
                    col = col * 26 + (c - (char)97 + 1);
                else break;
            }
            return col;
        }

        private static int RowIndex(string cellRef) {
            string num = "";
            foreach (char c in cellRef) {
                if (c >= (char)48 && c <= (char)57)
                    num += c;
            }
            int r;
            return int.TryParse(num, out r) ? r : 0;
        }

        private static string ColName(int col) {
            string name = "";
            while (col > 0) {
                col--;
                name = (char)((char)65 + (col % 26)) + name;
                col /= 26;
            }
            return name;
        }
    )'
}

; ── Demo GUI ──────────────────────────────────────────────────────────────────

g := Gui("+Resize", "AHK# — Excel Reader (No COM, No Excel)")
g.SetFont("s10", "Segoe UI")
g.BackColor := "0x1e1e2e"
g.SetFont("cCDD6F4")

; Header
g.SetFont("s13 cF38BA8 Bold")
g.Add("Text", "x20 y10 w470", Chr(0x1F4CA) " COM-Free Excel")
g.SetFont("s8 c585B70 Norm")
g.Add("Text", "x20 y34 w470", "Read/write .xlsx files — zero Excel installation required (System.IO.Packaging)")

; File picker
g.SetFont("s10 cCDD6F4", "Segoe UI")
g.Add("Text", "x15 y58", "File:")
fileEdit := g.Add("Edit", "x50 y56 w370 h24 Background0x313244 cCDD6F4")
btnOpen := g.Add("Button", "x425 y55 w70 h26", "Open...")

; Sheet selector
g.Add("Text", "x15 y88", "Sheet:")
sheetDD := g.Add("DropDownList", "x60 y86 w150 Background0x313244 cCDD6F4")
btnLoad := g.Add("Button", "x220 y85 w80 h26", "Load Sheet")

; Info
g.SetFont("s8 c585B70")
infoText := g.Add("Text", "x310 y90 w185", "")

; Cell read
g.SetFont("s10 cCDD6F4", "Segoe UI")
g.Add("Text", "x15 y118", "Cell:")
cellEdit := g.Add("Edit", "x52 y116 w50 h24 Background0x313244 cCDD6F4", "A1")
btnReadCell := g.Add("Button", "x107 y115 w50 h26", "Read")
cellResult := g.Add("Edit", "x162 y116 w170 h24 ReadOnly Background0x181825 cFAB387")

; Write
g.Add("Text", "x340 y118 c585B70", "Write:")
writeVal := g.Add("Edit", "x382 y116 w70 h24 Background0x313244 cCDD6F4")
btnWrite := g.Add("Button", "x457 y115 w38 h26", Chr(0x270F))

; Data view
g.SetFont("s10 cF38BA8")
g.Add("Text", "x15 y148", Chr(0x25CF) " Sheet Data")
g.SetFont("s9 cCDD6F4", "Segoe UI")
g.Add("Text", "x290 y148", "Max rows:")
maxRowsEdit := g.Add("Edit", "x352 y145 w60 h22 Number Background0x313244 cCDD6F4", "500")
g.Add("Text", "x418 y148 c585B70", "(0 = all)")
g.SetFont("s8", "Cascadia Mono")
dataEdit := g.Add("Edit", "x15 y168 w480 h230 Multi ReadOnly Background0x181825 cA6E3A1 HScroll VScroll")

; Create new workbook
g.SetFont("s10 cCDD6F4", "Segoe UI")
btnCreate := g.Add("Button", "x15 y408 w130 h28", Chr(0x2795) " New Workbook")

; ── Handlers ──────────────────────────────────────────────────────────────────

currentFile := ""

btnOpen.OnEvent("Click", (*) => OpenFile())
OpenFile() {
    global currentFile
    f := FileSelect(, , "Open Excel File", "Excel Files (*.xlsx)")
    if (f == "")
        return
    currentFile := f
    fileEdit.Value := f
    ; Load sheet list
    sheets := Excel.ListSheets(f)
    sheetDD.Delete()
    Loop Parse, sheets, "`n", "`r"
    {
        if (A_LoopField != "")
            sheetDD.Add([A_LoopField])
    }
    if (sheetDD.Value == 0)
        sheetDD.Value := 1
    infoText.Value := Excel.GetSheetInfo(f)
}

btnLoad.OnEvent("Click", (*) => LoadSheet())
LoadSheet() {
    global currentFile
    if (currentFile == "" || sheetDD.Text == "")
        return
    ; Row limit is a visible setting (0 = read every row); the reader appends a
    ; "[truncated: showing N of M rows]" line when it cuts the sheet off.
    try
        maxRows := Max(0, Integer(maxRowsEdit.Value))
    catch
        maxRows := 500
    data := Excel.ReadSheet(currentFile, sheetDD.Text, maxRows)
    dataEdit.Value := data
}

btnReadCell.OnEvent("Click", (*) => ReadCell())
ReadCell() {
    global currentFile
    if (currentFile == "" || sheetDD.Text == "")
        return
    cellResult.Value := Excel.ReadCell(currentFile, sheetDD.Text, cellEdit.Value)
}

btnWrite.OnEvent("Click", (*) => WriteCell())
WriteCell() {
    global currentFile
    if (currentFile == "" || sheetDD.Text == "")
        return

    ; Writing rewrites the sheet XML inside the .xlsx in place: offer a backup copy first
    ; (asked once per file per session).
    static backupDecided := Map()
    if !backupDecided.Has(currentFile) {
        answer := MsgBox("Write changes directly into this workbook?`n`n" currentFile
            . "`n`nYes = make a backup copy first (recommended)`nNo = write without a backup`nCancel = do nothing",
            "Backup before writing", "YesNoCancel Icon?")
        if (answer == "Cancel")
            return
        if (answer == "Yes") {
            bak := currentFile ".bak"
            if FileExist(bak)
                bak := currentFile "." A_Now ".bak"      ; never overwrite an older backup
            try FileCopy(currentFile, bak)
            catch as err
                return MsgBox("Could not create the backup, nothing was written:`n" err.Message, "Backup failed", "Icon!")
            cellResult.Value := "Backup: " bak
        }
        backupDecided[currentFile] := true
    }

    Excel.WriteCell(currentFile, sheetDD.Text, cellEdit.Value, writeVal.Value)
    cellResult.Value := "Written: " writeVal.Value
    LoadSheet() ; Refresh view
}

btnCreate.OnEvent("Click", (*) => CreateNew())
CreateNew() {
    global currentFile
    f := FileSelect("S", , "Create New Workbook", "Excel Files (*.xlsx)")
    if (f == "")
        return
    if (!InStr(f, ".xlsx"))
        f .= ".xlsx"
    Excel.CreateWorkbook(f)
    currentFile := f
    fileEdit.Value := f
    sheetDD.Delete()
    sheetDD.Add(["Sheet1"])
    sheetDD.Value := 1
    dataEdit.Value := "(empty workbook created)"
    infoText.Value := "New workbook: " f
}

g.OnEvent("Close", (*) => ExitApp())
g.Show("w510 h450")

WinWaitClose(g.Hwnd)
ExitApp()
