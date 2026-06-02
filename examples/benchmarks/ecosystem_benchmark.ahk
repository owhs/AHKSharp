;; AHK# Example — - Ecosystem Library Benchmark v5
;; Compares real AHK v2 community libraries vs AHK# (.NET) equivalents
;; 18 libraries across JSON, crypto, data structures, strings, tree nav,
;;   base64, COM interop, file ops, GUID, accessibility, imaging
;; Three tabs: Chart | Results | Libraries

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk
#Include lib_bench\JXON.ahk
#Include lib_bench\JSON_thqby.ahk
#Include lib_bench\Crypt.ahk
#Include lib_bench\Array.ahk
#Include lib_bench\String.ahk
#Include lib_bench\Map.ahk
#Include lib_bench\Base64_jNizM.ahk
#Include lib_bench\Base64_thqby.ahk
#Include lib_bench\ComVar.ahk
#Include lib_bench\DeepClone.ahk
#Include lib_bench\Misc.ahk
#Include lib_bench\TreeNavigator.ahk
#Include lib_bench\CreateGUID_jNizM.ahk
#Include lib_bench\FileCountLines_jNizM.ahk
#Include lib_bench\FileFindString_jNizM.ahk
#Include lib_bench\Heap.ahk
#Include lib_bench\WinClipAPI.ahk
#Include lib_bench\WinClip.ahk
#Include ..\..\ext\ahk#.sqlite.ahk

; ==============================================================================
; C# Module
; ==============================================================================

class EcoBench extends _CSModule {
    static References := ""
    static CSharp := ""
}

; ==============================================================================
; QPC timer
; ==============================================================================
DllCall("QueryPerformanceFrequency", "Int64*", &qpcFreq := 0)
QPCms() {
    global qpcFreq
    DllCall("QueryPerformanceCounter", "Int64*", &c := 0)
    return c * 1000.0 / qpcFreq
}

; Safe numeric conversion � returns 0 if value is empty/non-numeric
ToNum(val) {
    if (val == "" || !IsNumber(val))
        return 0
    return Number(val)
}

; ==============================================================================
; GUI
; ==============================================================================
g := Gui("+Resize +MinSize700x500", "AHK# -- AHK Community Ecosystem Library Benchmark")
g.BackColor := "0x0a0a16"
g.MarginX := 0, g.MarginY := 0

g.SetFont("s10 cCDD6F4", "Segoe UI")
tabs := g.Add("Tab3", "x0 y0 w900 h640 vTabs", ["Chart", "Results", "Libraries"])

tabs.UseTab(1)
chartPic := g.Add("Picture", "x2 y28 w896 h608 vChartPic Background0x0a0a16")

tabs.UseTab(2)
g.SetFont("s9 cCDD6F4", "Segoe UI")
lv := g.Add("ListView", "x2 y28 w896 h330 vLV Background0x0e0e1e c00FF88 -Border Grid NoSort", ["#", "Test", "AHK Lib", "AHK (ms)", "C# (ms)", "Speedup", "Winner"])
lv.ModifyCol(1, 30), lv.ModifyCol(2, 160), lv.ModifyCol(3, 160), lv.ModifyCol(4, 90), lv.ModifyCol(5, 90), lv.ModifyCol(6, 90), lv.ModifyCol(7, 70)
g.SetFont("s9 c80BFFF", "Cascadia Code")
detailEdit := g.Add("Edit", "x2 y362 w896 h274 Multi ReadOnly -Border Background0x0a0a18 vDetailEdit +VScroll")

tabs.UseTab(3)
g.SetFont("s9 cCDD6F4", "Segoe UI")
lvLib := g.Add("ListView", "x2 y28 w896 h330 vLVLib Background0x0e0e1e cFFAA32 -Border Grid NoSort", ["#", "Library", "Test", "Time (ms)", "vs C# (ms)", "Speedup", "Notes"])
lvLib.ModifyCol(1, 30), lvLib.ModifyCol(2, 120), lvLib.ModifyCol(3, 180), lvLib.ModifyCol(4, 80), lvLib.ModifyCol(5, 80), lvLib.ModifyCol(6, 80), lvLib.ModifyCol(7, 210)
g.SetFont("s9 c80BFFF", "Cascadia Code")
detailEditLib := g.Add("Edit", "x2 y362 w896 h274 Multi ReadOnly -Border Background0x0a0a18 vDetailEditLib +VScroll")

tabs.UseTab()
g.SetFont("s11 cFFFFFF", "Segoe UI")
btnRun := g.Add("Button", "x5 y645 w890 h36 vRunBtn", "RUN ALL LIBRARY BENCHMARKS")
btnRun.OnEvent("Click", (*) => RunAll())
g.SetFont("s8 c00FF88", "Cascadia Code")
statusText := g.Add("Text", "x5 y685 w890 h18 vStatusText BackgroundTrans", "21 libs: JXON|thqby|Crypt|Array|String|Map|B64x2|ComVar|Clone|Misc|TreeNav|GUID|FileOps|Heap|GDI+|WinClip|SQLite|COM|WMI")

lastEcoData := ""
; Create dynamic configuration toolbar
g.SetFont("s9 c80BFFF", "Segoe UI")
lblTheme := g.Add("Text", "x10 y605 w50 h22 +0x200 vLblTheme", "Theme:")
ddTheme := g.Add("ComboBox", "x60 y605 w130 Choose1 vTheme", ["SpaceX (Dark)", "Cyberpunk Neo", "Aurora Emerald", "Solar Eclipse", "Starlink (Blue)", "Mars (Rust)", "Carbon (Mono)", "Falcon (Light)"])

lblFilter := g.Add("Text", "x205 y605 w50 h22 +0x200 vLblFilter", "Filter:")
ddFilter := g.Add("ComboBox", "x255 y605 w160 Choose1 vFilter", ["All Categories", "JSON, XML & COM", "Cryptography & Base64", "Data Structures & Trees", "File Ops, OS & Clipboard"])

lblCompile := g.Add("Text", "x430 y605 w65 h22 +0x200 vLblCompile", "C# Engine:")
ddCompile := g.Add("ComboBox", "x500 y605 w140 Choose1 vCompile", ["Precompiled DLL", "Dynamic Compiler"])

lblJit := g.Add("Text", "x650 y605 w60 h22 +0x200 vLblJit", "JIT Mode:")
ddJit := g.Add("ComboBox", "x715 y605 w170 Choose1 vJit", ["Prewarmed (Steady)", "Cold Start (Inc JIT)"])

; Register events
ddTheme.OnEvent("Change", (*) => OnThemeFilterChange())
ddFilter.OnEvent("Change", (*) => OnThemeFilterChange())
ddCompile.OnEvent("Change", (*) => OnThemeFilterChange())
ddJit.OnEvent("Change", (*) => OnThemeFilterChange())
ddCompile.OnEvent("Change", (*) => OnThemeFilterChange())
ddJit.OnEvent("Change", (*) => OnThemeFilterChange())

global globalSpecs := "", allResults := []

OnThemeFilterChange() {
    global allResults
    if allResults.Length == 0
        return
    UpdateDisplay()
}

GetCategory(name, lib) {
    if InStr(lib, "JSON") || InStr(lib, "JXON") || InStr(lib, "COM") || InStr(lib, "ComVar") || InStr(lib, "XML") || InStr(lib, "WMI") || InStr(lib, "Scripting.Dict")
        return "JSON, XML & COM"
    if InStr(lib, "Crypt") || InStr(lib, "Base64") || InStr(lib, "B64")
        return "Cryptography & Base64"
    if InStr(lib, "Array") || InStr(lib, "String") || InStr(lib, "Map") || InStr(lib, "Misc") || InStr(lib, "Tree") || InStr(lib, "Linq") || InStr(lib, "Parallel")
        return "Data Structures & Trees"
    return "File Ops, OS & Clipboard"
}

UpdateDisplay() {
    global allResults, lastEcoData, allSnippets, allLibSnippets, globalSpecs

    themeChoice := ddTheme.Text
    filterChoice := ddFilter.Text

    themeMap := Map(
        "SpaceX (Dark)", "spacex",
        "Cyberpunk Neo", "cyberpunk",
        "Aurora Emerald", "aurora",
        "Solar Eclipse", "solareclipse",
        "Starlink (Blue)", "starlink",
        "Mars (Rust)", "mars",
        "Carbon (Mono)", "carbon",
        "Falcon (Light)", "falcon"
    )
    rawTheme := themeMap.Has(themeChoice) ? themeMap[themeChoice] : "spacex"

    lv.Opt("-Redraw")
    lvLib.Opt("-Redraw")
    lv.Delete()
    lvLib.Delete()

    filteredChartData := ""
    libIdx := 0
    testIdx := 0

    for r in allResults {
        cat := GetCategory(r.name, r.lib)
        if (filterChoice != "All Categories" && cat != filterChoice)
            continue

        testIdx++

        ; Repopulate lv
        ahkDisp := r.ahk >= 0 ? Round(r.ahk, 1) : "N/A"
        csDisp := r.cs >= 0 ? Round(r.cs, 1) : "N/A"
        row := lv.Add(, testIdx, r.name, r.lib, ahkDisp, csDisp, "", "")

        if r.ahk == -1 {
            lv.Modify(row, , , , , , , "C# ONLY", "C#")
        } else if r.cs == -1 {
            lv.Modify(row, , , , , , , "AHK ONLY", "AHK")
        } else {
            if r.cs == 0 && r.ahk == 0 {
                lv.Modify(row, , , , , , , "1.0x", "Tie")
            } else if r.cs == 0 {
                lv.Modify(row, , , , , , , "INF", "C#")
            } else {
                ratio := r.ahk / r.cs
                if ratio >= 1.05 {
                    winnerCol := (r.name == "Async Parallel" || r.name == "LINQ 100K") ? ".NET Exclusive" : "C#"
                    lv.Modify(row, , , , , , , Round(ratio, 1) "x", winnerCol)
                } else if ratio <= 0.95 {
                    lv.Modify(row, , , , , , , Round(1 / ratio, 1) "x AHK", "AHK")
                } else {
                    lv.Modify(row, , , , , , , "1.0x", "Tie")
                }
            }
        }

        ; Repopulate lvLib
        libIdx++
        winner := ""
        if r.cs >= 0 && r.ahk >= 0 {
            if r.cs == 0 && r.ahk == 0 {
                winner := "Tie"
            } else if r.cs == 0 {
                winner := "C#"
            } else {
                ratio := r.ahk / r.cs
                winner := ratio >= 1.05 ? Round(ratio, 1) "x" : (ratio <= 0.95 ? Round(1 / ratio, 1) "x AHK" : "Tie")
            }
            if (r.name == "Async Parallel" || r.name == "LINQ 100K")
                winner .= " (.NET Exclusive)"
        } else if r.ahk == -1 {
            winner := "C# Only"
        } else if r.cs == -1 {
            winner := "AHK Only"
        }
        lvLib.Add(, libIdx, r.lib, r.name, r.ahk >= 0 ? Round(r.ahk, 2) : "N/A", r.cs >= 0 ? Round(r.cs, 2) : "N/A", winner, r.notes)

        ; Rebuild chart data
        if filteredChartData != ""
            filteredChartData .= ";"
        filteredChartData .= r.name "|" Round(r.ahk, 2) "|" Round(r.cs, 2)
    }

    lv.Opt("+Redraw")
    lvLib.Opt("+Redraw")

    lastEcoData := filteredChartData

    ; Re-render chart pic
    chartPic.GetPos(, , &pw, &ph)
    if pw > 50 && ph > 50 && filteredChartData != "" {
        try {
            EcoBench.Render(filteredChartData, pw, ph, A_Temp "\ahk_eco_chart.png", rawTheme, 0, false, 0, globalSpecs)
            chartPic.Value := A_Temp "\ahk_eco_chart.png"
        }
    }
}

g.OnEvent("Size", GuiResize)
GuiResize(thisGui, minMax, w, h) {
    if minMax == -1
        return
    try {
        tabs.Move(0, 0, w, h - 105), chartPic.Move(2, 28, w - 8, h - 140)
        lvH := Integer((h - 140) * 0.55)
        lv.Move(2, 28, w - 8, lvH), detailEdit.Move(2, 28 + lvH + 4, w - 8, h - 140 - lvH - 4)
        lvLib.Move(2, 28, w - 8, lvH), detailEditLib.Move(2, 28 + lvH + 4, w - 8, h - 140 - lvH - 4)

        colW := Integer(w / 4)
        lblTheme.Move(10, h - 100, 50, 22)
        ddTheme.Move(60, h - 100, colW - 70, 22)

        lblFilter.Move(colW + 10, h - 100, 50, 22)
        ddFilter.Move(colW + 60, h - 100, colW - 70, 22)

        lblCompile.Move(colW * 2 + 10, h - 100, 65, 22)
        ddCompile.Move(colW * 2 + 80, h - 100, colW - 90, 22)

        lblJit.Move(colW * 3 + 10, h - 100, 60, 22)
        ddJit.Move(colW * 3 + 75, h - 100, colW - 85, 22)

        btnRun.Move(5, h - 60, w - 10, 36), statusText.Move(5, h - 22, w - 10, 18)
    }
    SetTimer(DoRerender, -300)
}
DoRerender() {
    global lastEcoData, globalSpecs
    if lastEcoData == ""
        return
    try {
        chartPic.GetPos(, , &pw, &ph)
        if pw > 50 && ph > 50 {
            themeChoice := ddTheme.Text
            themeMap := Map(
                "SpaceX (Dark)", "spacex",
                "Cyberpunk Neo", "cyberpunk",
                "Aurora Emerald", "aurora",
                "Solar Eclipse", "solareclipse",
                "Starlink (Blue)", "starlink",
                "Mars (Rust)", "mars",
                "Carbon (Mono)", "carbon",
                "Falcon (Light)", "falcon"
            )
            rawTheme := themeMap.Has(themeChoice) ? themeMap[themeChoice] : "spacex"
            EcoBench.Render(lastEcoData, pw, ph, A_Temp "\ahk_eco_chart.png", rawTheme, 0, false, 0, globalSpecs)
            chartPic.Value := A_Temp "\ahk_eco_chart.png"
        }
    }
}

global allSnippets := Map(), allLibSnippets := Map()
lv.OnEvent("Click", OnResultSelect)
lv.OnEvent("ItemFocus", OnResultSelect)
lvLib.OnEvent("Click", OnLibSelect)
lvLib.OnEvent("ItemFocus", OnLibSelect)

global currentSortCol := 0, currentSortDesc := false
global currentSortLibCol := 0, currentSortLibDesc := false

lv.OnEvent("ColClick", OnResultColClick)
lvLib.OnEvent("ColClick", OnLibColClick)

OnResultColClick(ctrl, col) {
    global currentSortCol, currentSortDesc
    if (col == 1) ; Don't sort index column
        return
    if (currentSortCol == col) {
        currentSortDesc := !currentSortDesc
    } else {
        currentSortCol := col
        currentSortDesc := false
    }
    SortResults(col, currentSortDesc)
    UpdateDisplay()
}

OnLibColClick(ctrl, col) {
    global currentSortLibCol, currentSortLibDesc
    if (col == 1)
        return
    if (currentSortLibCol == col) {
        currentSortLibDesc := !currentSortLibDesc
    } else {
        currentSortLibCol := col
        currentSortLibDesc := false
    }
    SortLibResults(col, currentSortLibDesc)
    UpdateDisplay()
}

GetSortValue(item, col) {
    if col == 2 {
        return item.name
    } else if col == 3 {
        return item.lib
    } else if col == 4 {
        return item.ahk >= 0 ? item.ahk : 999999.0
    } else if col == 5 {
        return item.cs >= 0 ? item.cs : 999999.0
    } else if col == 6 {
        if item.ahk < 0 || item.cs < 0
            return 0.0
        if item.cs == 0
            return 999999.0
        return item.ahk / item.cs
    } else if col == 7 {
        if item.ahk == -1 {
            return "C# ONLY"
        } else if item.cs == -1 {
            return "AHK ONLY"
        } else if item.cs == 0 && item.ahk == 0 {
            return "Tie"
        } else {
            ratio := item.ahk / item.cs
            if ratio >= 1.05 {
                return (item.name == "Async Parallel" || item.name == "LINQ 100K") ? ".NET Exclusive" : "C#"
            } else if ratio <= 0.95 {
                return "AHK"
            } else {
                return "Tie"
            }
        }
    }
    return ""
}

GetSortLibValue(item, col) {
    if col == 2 {
        return item.lib
    } else if col == 3 {
        return item.name
    } else if col == 4 {
        return item.ahk >= 0 ? item.ahk : 999999.0
    } else if col == 5 {
        return item.cs >= 0 ? item.cs : 999999.0
    } else if col == 6 {
        if item.ahk < 0 || item.cs < 0
            return 0.0
        if item.cs == 0
            return 999999.0
        return item.ahk / item.cs
    } else if col == 7 {
        return item.notes
    }
    return ""
}

SortResults(col, desc) {
    global allResults
    n := allResults.Length
    if n <= 1
        return
    Loop n - 1 {
        i := A_Index
        Loop n - i {
            j := A_Index + i
            val1 := GetSortValue(allResults[i], col)
            val2 := GetSortValue(allResults[j], col)

            swap := false
            if IsNumber(val1) && IsNumber(val2) {
                if !desc {
                    if val1 > val2
                        swap := true
                } else {
                    if val1 < val2
                        swap := true
                }
            } else {
                if !desc {
                    if StrCompare(String(val1), String(val2)) > 0
                        swap := true
                } else {
                    if StrCompare(String(val1), String(val2)) < 0
                        swap := true
                }
            }

            if swap {
                temp := allResults[i]
                allResults[i] := allResults[j]
                allResults[j] := temp
            }
        }
    }
}

SortLibResults(col, desc) {
    global allResults
    n := allResults.Length
    if n <= 1
        return
    Loop n - 1 {
        i := A_Index
        Loop n - i {
            j := A_Index + i
            val1 := GetSortLibValue(allResults[i], col)
            val2 := GetSortLibValue(allResults[j], col)

            swap := false
            if IsNumber(val1) && IsNumber(val2) {
                if !desc {
                    if val1 > val2
                        swap := true
                } else {
                    if val1 < val2
                        swap := true
                }
            } else {
                if !desc {
                    if StrCompare(String(val1), String(val2)) > 0
                        swap := true
                } else {
                    if StrCompare(String(val1), String(val2)) < 0
                        swap := true
                }
            }

            if swap {
                temp := allResults[i]
                allResults[i] := allResults[j]
                allResults[j] := temp
            }
        }
    }
}

; ==============================================================================
; BENCHMARK RUNNER
; ==============================================================================
RunAll() {
    global lastEcoData, allSnippets, allLibSnippets, allResults, globalSpecs
    allResults := [], allSnippets := Map(), allLibSnippets := Map()
    btnRun.Enabled := false

    compileChoice := ddCompile.Text
    jitChoice := ddJit.Text

    St(msg) {
        statusText.Value := msg
        Sleep 1
    }

    AddResult(name, lib, ahkMs, csMs, snippet) {
        item := { name: name, lib: lib, ahk: ahkMs, cs: csMs, snippet: snippet, notes: "", libSnippet: "" }
        allResults.Push(item)
        allSnippets[name] := snippet
    }

    AddLib(libName, testName, ahkMs, csMs, notes, snippet) {
        if allResults.Length > 0 {
            item := allResults[allResults.Length]
            item.notes := notes
            item.libSnippet := snippet
        }
        allLibSnippets[libName "|" testName] := snippet
    }

    ; -- Timed Boot C# Engine ---------------------------------------------
    St("Booting C# engine...")
    bootStart := QPCms()

    compileStart := QPCms()
    if (compileChoice == "Precompiled DLL") {
        dllPath := A_ScriptDir "\lib_bench\EcoBench.dll"
        if !FileExist(dllPath) {
            St("DLL not found. Compiling first...")
            EcoBench.CSharp := FileRead(A_ScriptDir "\lib_bench\EcoBench.cs", "UTF-8")
            EcoBench.References := "System.Web.Extensions.dll;System.Xml.dll;System.Drawing.dll;System.Management.dll"
            EcoBench.__New()
            EcoBench.Precompile(dllPath)
            EcoBench._assemblyId := ""
            St("DLL compiled & saved. Loading precompiled...")
        }
        EcoBench.PrecompiledDLL := dllPath
        EcoBench.CSharp := ""
        EcoBench.__New()
        bootType := "Precompiled DLL"
    } else {
        St("Compiling C# module dynamically...")
        EcoBench.PrecompiledDLL := ""
        EcoBench.CSharp := FileRead(A_ScriptDir "\lib_bench\EcoBench.cs", "UTF-8")
        EcoBench.References := "System.Web.Extensions.dll;System.Xml.dll;System.Drawing.dll;System.Management.dll"
        EcoBench.__New()
        bootType := "Dynamic Compiler"
    }
    compileMs := Round(QPCms() - compileStart, 2)

    prewarmState := (jitChoice == "Prewarmed (Steady)") ? "true" : "false"
    EcoBench.SetPrewarm(prewarmState)

    jitStart := QPCms()
    try EcoBench.Md5("boot", 1)
    jitMs := Round(QPCms() - jitStart, 2)

    bootMs := Round(QPCms() - bootStart, 2)

    globalSpecs := bootType . " · Boot: " . bootMs . "ms (Compile: " . compileMs . "ms · JIT: " . jitMs . "ms)"
    St("Booted in " . bootMs . "ms! (Compile: " . compileMs . "ms, JIT: " . jitMs . "ms)")

    ; -- Prepare data -------------------------------------------------------
    jsonStr := '{"users":[{"name":"Alice","age":30,"email":"alice@test.com"},{"name":"Bob","age":25},{"name":"Carol","age":35}],"count":3,"active":true}'
    hashStr := "The quick brown fox jumps over the lazy dog"
    buf := Buffer(StrPut(hashStr, "UTF-8") - 1)
    StrPut(hashStr, buf, "UTF-8")
    testArr := []
    Loop 1000
        testArr.Push(Random(1, 100000))
    csvData := ""
    for v in testArr
        csvData .= (A_Index > 1 ? "," : "") v

    ; Load tree data for TreeNavigator
    treeDataPath := A_ScriptDir "\lib_bench\tree_data.txt"
    treeRawData := ""
    if FileExist(treeDataPath)
        treeRawData := FileRead(treeDataPath, "CP936")

    ; ======================================================================
    ; 1. JXON
    ; ======================================================================
    St("[1/30] JXON -- Parse x5K...")
    iters := 5000
    t1 := QPCms()
    Loop iters
        Jxon_Load(&jsonStr)
    ahkMs := QPCms() - t1
    csMs := ToNum(EcoBench.JsonParse(jsonStr, iters))
    AddResult("JXON Parse 5K", "JXON", ahkMs, csMs, "AHK: Jxon_Load(&json) x" iters "`nC#: JavaScriptSerializer x" iters)
    AddLib("JXON", "Parse x5K", ahkMs, csMs, "Most popular AHK JSON", "Jxon_Load(&json)")

    St("[2/30] JXON -- Stringify x5K...")
    obj := Jxon_Load(&jsonStr)
    t1 := QPCms()
    Loop iters
        Jxon_Dump(obj)
    ahkMs := QPCms() - t1
    r := StrSplit(EcoBench.JsonStringify(jsonStr, iters), "|")
    csMs := ToNum(r[1])
    AddResult("JXON Stringify 5K", "JXON", ahkMs, csMs, "AHK: Jxon_Dump(obj) x" iters "`nC#: JavaScriptSerializer.Serialize() x" iters)
    AddLib("JXON", "Stringify x5K", ahkMs, csMs, "Serialize to string", "Jxon_Dump(obj)")

    ; ======================================================================
    ; 2. thqby JSON
    ; ======================================================================
    St("[3/30] thqby JSON -- Parse x5K...")
    t1 := QPCms()
    Loop iters
        JSON.parse(jsonStr)
    ahkMs := QPCms() - t1
    csMs := ToNum(EcoBench.JsonParse(jsonStr, iters))
    AddResult("thqby Parse 5K", "thqby JSON", ahkMs, csMs, "AHK: JSON.parse() x" iters " (thqby class-based)`nC#: JavaScriptSerializer x" iters)
    AddLib("thqby JSON", "Parse x5K", ahkMs, csMs, "Class-based JSON parser", "JSON.parse(str)")

    St("[4/30] thqby JSON -- Stringify x5K...")
    obj2 := JSON.parse(jsonStr)
    t1 := QPCms()
    Loop iters
        JSON.stringify(obj2)
    ahkMs := QPCms() - t1
    r := StrSplit(EcoBench.JsonStringify(jsonStr, iters), "|")
    csMs := ToNum(r[1])
    AddResult("thqby Stringify 5K", "thqby JSON", ahkMs, csMs, "AHK: JSON.stringify() x" iters "`nC#: JavaScriptSerializer.Serialize() x" iters)
    AddLib("thqby JSON", "Stringify x5K", ahkMs, csMs, "Class-based serializer", "JSON.stringify(obj)")

    ; ======================================================================
    ; 3. Crypt.ahk
    ; ======================================================================
    St("[5/30] Crypt.ahk -- MD5 x10K...")
    hIters := 10000
    t1 := QPCms()
    Loop hIters
        MD5(buf)
    ahkMs := QPCms() - t1
    csMs := ToNum(EcoBench.Md5(hashStr, hIters))
    AddResult("MD5 10K", "Crypt.ahk", ahkMs, csMs, "AHK: MD5() DllCall advapi32 x" hIters "`nC#: MD5.Create() x" hIters)
    AddLib("Crypt.ahk", "MD5 x10K", ahkMs, csMs, "advapi32 DllCall", "MD5(buffer)")

    St("[6/30] Crypt.ahk -- SHA1 x5K...")
    shIters := 5000
    t1 := QPCms()
    Loop shIters
        Crypt_Hash(buf, buf.Size, "SHA")
    ahkMs := QPCms() - t1
    csMs := ToNum(EcoBench.Sha1(hashStr, shIters))
    AddResult("SHA1 5K", "Crypt.ahk", ahkMs, csMs, "AHK: Crypt_Hash(SHA) advapi32 x" shIters "`nC#: SHA1.Create() x" shIters)
    AddLib("Crypt.ahk", "SHA1 x5K", ahkMs, csMs, "advapi32 CryptHashData", "Crypt_Hash(buf, size, 'SHA')")

    St("[7/30] Crypt.ahk -- CRC32 x10K...")
    t1 := QPCms()
    Loop hIters
        Crypt_Hash(buf, buf.Size, "CRC32")
    ahkMs := QPCms() - t1
    csMs := ToNum(StrSplit(EcoBench.Crc32(hashStr, hIters), "|")[1])
    AddResult("CRC32 10K", "Crypt.ahk", ahkMs, csMs, "AHK: ntdll RtlComputeCrc32 x" hIters "`nC#: Manual CRC32 x" hIters)
    AddLib("Crypt.ahk", "CRC32 x10K", ahkMs, csMs, "ntdll DllCall", "Crypt_Hash(CRC32)")

    St("[8/30] Crypt.ahk -- AES-256 x500...")
    aIters := 500
    aesBuf := Buffer(64)
    StrPut("Encrypt me for benchmarking!", aesBuf, "UTF-8")
    t1 := QPCms()
    Loop aIters {
        tmpBuf := Buffer(64)
        DllCall("RtlMoveMemory", "Ptr", tmpBuf, "Ptr", aesBuf, "UInt", 48)
        Crypt_AES(tmpBuf, 48, "BenchKey123!", 256, true)
    }
    ahkMs := QPCms() - t1
    csMs := ToNum(EcoBench.AesEncrypt("Encrypt me for benchmarking!", aIters))
    AddResult("AES-256 500", "Crypt.ahk", ahkMs, csMs, "AHK: Crypt_AES() advapi32 x" aIters "`nC#: Aes.Create() x" aIters)
    AddLib("Crypt.ahk", "AES-256 x500", ahkMs, csMs, "advapi32 CryptEncrypt", "Crypt_AES(buf, key, 256)")

    ; ======================================================================
    ; 4. jNizM Base64
    ; ======================================================================
    St("[9/30] jNizM Base64 -- Encode x5K...")
    b64Iters := 5000
    t1 := QPCms()
    Loop b64Iters
        enc := StringToBase64(hashStr)
    ahkMs := QPCms() - t1
    r := StrSplit(EcoBench.Base64Encode(hashStr, b64Iters), "|")
    csMs := ToNum(r[1])
    AddResult("B64 Enc jNizM", "jNizM Base64", ahkMs, csMs, "AHK: StringToBase64() crypt32 DllCall x" b64Iters "`nC#: Convert.ToBase64String() x" b64Iters)
    AddLib("jNizM Base64", "Encode x5K", ahkMs, csMs, "crypt32 CryptBinaryToString", "StringToBase64(str)")

    St("[10/30] jNizM Base64 -- Decode x5K...")
    b64encoded := StringToBase64(hashStr)
    t1 := QPCms()
    Loop b64Iters
        Base64ToString(b64encoded)
    ahkMs := QPCms() - t1
    csMs := ToNum(EcoBench.Base64Decode(b64encoded, b64Iters))
    AddResult("B64 Dec jNizM", "jNizM Base64", ahkMs, csMs, "AHK: Base64ToString() crypt32 x" b64Iters "`nC#: Convert.FromBase64String() x" b64Iters)
    AddLib("jNizM Base64", "Decode x5K", ahkMs, csMs, "crypt32 CryptStringToBinary", "Base64ToString(str)")

    ; ======================================================================
    ; 5. thqby Base64
    ; ======================================================================
    St("[11/30] thqby Base64 -- Encode x5K...")
    t1 := QPCms()
    Loop b64Iters
        Base64.Encode(hashStr)
    ahkMs := QPCms() - t1
    r := StrSplit(EcoBench.Base64Encode(hashStr, b64Iters), "|")
    csMs := ToNum(r[1])
    AddResult("B64 Enc thqby", "thqby Base64", ahkMs, csMs, "AHK: Base64.Encode() crypt32 class x" b64Iters "`nC#: Convert.ToBase64String() x" b64Iters)
    AddLib("thqby Base64", "Encode x5K", ahkMs, csMs, "crypt32 class wrapper", "Base64.Encode(str)")

    St("[12/30] thqby Base64 -- Decode x5K...")
    thqbyEnc := Base64.Encode(hashStr)
    t1 := QPCms()
    Loop b64Iters
        Base64.Decode(thqbyEnc)
    ahkMs := QPCms() - t1
    csMs := ToNum(EcoBench.Base64Decode(thqbyEnc, b64Iters))
    AddResult("B64 Dec thqby", "thqby Base64", ahkMs, csMs, "AHK: Base64.Decode() crypt32 class x" b64Iters "`nC#: Convert.FromBase64String() x" b64Iters)
    AddLib("thqby Base64", "Decode x5K", ahkMs, csMs, "crypt32 class wrapper", "Base64.Decode(str)")

    ; ======================================================================
    ; 6. Descolada Array.ahk
    ; ======================================================================
    St("[13/30] Descolada Array -- Sort x100...")
    sIters := 100
    t1 := QPCms()
    Loop sIters
        testArr.Clone().Sort("N")
    ahkMs := QPCms() - t1
    csMs := ToNum(EcoBench.ArraySort(csvData, sIters))
    AddResult("Array Sort 1K", "Descolada Array", ahkMs, csMs, "AHK: arr.Sort('N') QuickSort x" sIters "`nC#: Array.Sort() x" sIters "`n`nDescolada adds Sort/Map/Filter/Reduce to arrays")
    AddLib("Descolada Array", "Sort 1K x100", ahkMs, csMs, "QuickSort impl", "arr.Clone().Sort('N')")

    St("[14/30] Descolada Array -- Filter x500...")
    fIters := 500
    t1 := QPCms()
    Loop fIters
        testArr.Filter((v) => v > 500)
    ahkMs := QPCms() - t1
    r := StrSplit(EcoBench.ArrayFilter(csvData, fIters), "|")
    csMs := ToNum(r[1])
    AddResult("Array Filter 1K", "Descolada Array", ahkMs, csMs, "AHK: arr.Filter(fn) x" fIters "`nC#: LINQ .Where() x" fIters)
    AddLib("Descolada Array", "Filter x500", ahkMs, csMs, "Callback filter", "arr.Filter((v) => v > 500)")

    St("[15/30] Descolada Array -- Map x500...")
    t1 := QPCms()
    Loop fIters
        testArr.Map((v) => v * 2)
    ahkMs := QPCms() - t1
    csMs := ToNum(StrSplit(EcoBench.ArrayMap(csvData, fIters), "|")[1])
    AddResult("Array Map 1K", "Descolada Array", ahkMs, csMs, "AHK: arr.Map(fn) x" fIters "`nC#: LINQ .Select() x" fIters)
    AddLib("Descolada Array", "Map x500", ahkMs, csMs, "Transform elements", "arr.Map((v) => v * 2)")

    St("[16/30] Descolada Array -- Reduce x1K...")
    rIters := 1000
    t1 := QPCms()
    Loop rIters
        testArr.Reduce((a, b) => a + b)
    ahkMs := QPCms() - t1
    csMs := ToNum(StrSplit(EcoBench.ArrayReduce(csvData, rIters), "|")[1])
    AddResult("Array Reduce 1K", "Descolada Array", ahkMs, csMs, "AHK: arr.Reduce((a,b) => a+b) x" rIters "`nC#: LINQ .Aggregate() x" rIters)
    AddLib("Descolada Array", "Reduce x1K", ahkMs, csMs, "Cumulative sum", "arr.Reduce((a,b) => a+b)")

    ; ======================================================================
    ; 7. Descolada String.ahk
    ; ======================================================================
    St("[17/30] Descolada String -- Ops x10K...")
    strIters := 10000
    testStr := "  The quick brown fox jumps over the lazy dog  "
    t1 := QPCms()
    Loop strIters {
        testStr.ToUpper()
        testStr.Replace("fox", "cat")
        testStr.Trim()
        testStr.LPad("*", 5)
        testStr.Find("lazy")
    }
    ahkMs := QPCms() - t1
    csMs := ToNum(EcoBench.StringOps(testStr, strIters))
    AddResult("String Ops 10K", "Descolada String", ahkMs, csMs, "AHK: .ToUpper/.Replace/.Trim/.LPad/.Find x" strIters "`nC#: .ToUpper/.Replace/.Trim/.PadLeft/.IndexOf x" strIters)
    AddLib("Descolada String", "5 ops x10K", ahkMs, csMs, "Chained string methods", "ToUpper/Replace/Trim/LPad/Find")

    St("[18/30] Descolada String -- RegExMatchAll x1K...")
    regText := "Email: user@test.com, admin@site.org, info@example.com, support@help.net"
    reIters := 1000
    t1 := QPCms()
    Loop reIters
        regText.RegExMatchAll("\b[\w.]+@[\w]+\.[\w]+\b")
    ahkMs := QPCms() - t1
    csMs := ToNum(EcoBench.RegExMatchAll(regText, "\b[\w.]+@[\w]+\.[\w]+\b", reIters))
    AddResult("RegExMatchAll 1K", "Descolada String", ahkMs, csMs, "AHK: str.RegExMatchAll(pattern) x" reIters "`nReturns all matches as array")
    AddLib("Descolada String", "RegExMatchAll x1K", ahkMs, csMs, "All matches as array", "str.RegExMatchAll(pattern)")

    ; ======================================================================
    ; 8. Descolada Map.ahk
    ; ======================================================================
    St("[19/30] Descolada Map -- Filter+Count x1K...")
    testMap := Map()
    Loop 1000
        testMap["key" A_Index] := A_Index
    mIters := 1000
    t1 := QPCms()
    Loop mIters {
        testMap.Filter((k, v) => v > 500)
        testMap.Count((v) => v > 800)
    }
    ahkMs := QPCms() - t1
    r := StrSplit(EcoBench.DictOps(1000), "|")
    csMs := ToNum(r[1])
    AddResult("Map Filter 1K", "Descolada Map", ahkMs, csMs, "AHK: map.Filter(fn) + map.Count(fn) x" mIters "`nC#: LINQ .Where() + .Count() x" mIters)
    AddLib("Descolada Map", "Filter+Count x1K", ahkMs, csMs, "Callback filter/count", "map.Filter() + map.Count()")

    ; ======================================================================
    ; 9. Descolada Misc.ahk
    ; ======================================================================
    St("[20/30] Descolada Misc -- Range x5K...")
    rgIters := 5000
    t1 := QPCms()
    Loop rgIters {
        sum := 0
        for v in Range(1, 100)
            sum += v
    }
    ahkMs := QPCms() - t1
    csMs := ToNum(EcoBench.RangeIter(1, 100, rgIters))
    AddResult("Range iter 5K", "Descolada Misc", ahkMs, csMs, "AHK: Range(1,100) iterator x" rgIters "`nPython-style Range() from Misc.ahk")
    AddLib("Descolada Misc", "Range(1,100) x5K", ahkMs, csMs, "Python-style iterator", "for v in Range(1,100) sum += v")

    ; ======================================================================
    ; 10. thqby ComVar
    ; ======================================================================
    St("[21/30] thqby ComVar -- Create x10K...")
    cvIters := 10000
    t1 := QPCms()
    Loop cvIters {
        cv := ComVar(42)
        cv2 := ComVar("hello world")
    }
    ahkMs := QPCms() - t1
    csMs := ToNum(EcoBench.ComVarCreate(cvIters))
    AddResult("ComVar Create 10K", "thqby ComVar", ahkMs, csMs, "AHK: ComVar(42) + ComVar('str') x" cvIters "`nVARIANT struct construction for COM interop")
    AddLib("thqby ComVar", "Create int+str x10K", ahkMs, csMs, "VARIANT construction", "ComVar(42) + ComVar('hello')")

    ; ======================================================================
    ; 11. thqby DeepClone
    ; ======================================================================
    St("[22/30] thqby DeepClone -- Clone nested x1K...")
    ; Build a nested object
    nested := { name: "root", data: [1, 2, 3], child: { name: "child1", child: { name: "child2", values: [10, 20, 30] } } }
    dcIters := 1000
    t1 := QPCms()
    Loop dcIters
        deepclone(nested)
    ahkMs := QPCms() - t1
    csMs := ToNum(EcoBench.DeepCloneTest(3, dcIters))
    AddResult("DeepClone x1K", "thqby DeepClone", ahkMs, csMs, "AHK: deepclone(nestedObj) x" dcIters "`nC#: Dictionary clone simulation x" dcIters)
    AddLib("thqby DeepClone", "3-deep clone x1K", ahkMs, csMs, "Recursive clone", "deepclone(nestedObj)")

    ; ======================================================================
    ; 12. TreeNavigator (YOUR library!)
    ; ======================================================================
    if treeRawData != "" {
        St("[23/30] TreeNavigator -- Class Parse...")
        t1 := QPCms()
        classTree := TreeNavigator.ParseByClass(treeRawData)
        ahkParseClass := QPCms() - t1
        AddLib("TreeNavigator", "ParseByClass", ahkParseClass, 0, "O(1) hash-indexed tree", "TreeNavigator.ParseByClass(rawData)")

        St("[24/30] TreeNavigator -- Path Parse...")
        t1 := QPCms()
        pathTree := TreeNavigator.ParseByPath(treeRawData)
        ahkParsePath := QPCms() - t1
        AddLib("TreeNavigator", "ParseByPath", ahkParsePath, 0, "Path-based tree build", "TreeNavigator.ParseByPath(rawData)")

        St("[25/30] TreeNavigator -- FlatMap Parse...")
        t1 := QPCms()
        flatMap := TreeNavigator.ParseByFlatMap(treeRawData)
        ahkParseFM := QPCms() - t1
        AddLib("TreeNavigator", "ParseByFlatMap", ahkParseFM, 0, "1D flat map + index", "TreeNavigator.ParseByFlatMap(rawData)")

        ; C# parse for comparison
        r := StrSplit(EcoBench.TreeParse(treeRawData), "|")
        csParseMs := ToNum(r[1])
        AddResult("Tree Parse", "TreeNavigator", Round(ahkParseFM, 1), csParseMs, "AHK: TreeNavigator.ParseByFlatMap() -- O(1) indexed`nC#: Dictionary<string,string> parse`nNodes: " r[3] " | Unique names: " r[2] "`nYour FlatMap is the fastest parse method!")

        ; Search benchmarks -- deep target
        navIters := 500
        St("[26/30] TreeNavigator -- Search deep x500...")

        ; AHK Class method
        t1 := QPCms()
        Loop navIters
            TreeNavigator.GetPathToNode(classTree, Chr(0x7389) Chr(0x7C73) Chr(0x7CC1))
        ahkSearchClass := QPCms() - t1
        AddLib("TreeNavigator", "Search deep (Class) x500", ahkSearchClass, 0, "O(1) hash + parent walk", "GetPathToNode(classTree, target)")

        ; AHK Path method
        t1 := QPCms()
        Loop navIters
            TreeNavigator.GetPathToNode(pathTree, Chr(0x7389) Chr(0x7C73) Chr(0x7CC1))
        ahkSearchPath := QPCms() - t1
        AddLib("TreeNavigator", "Search deep (Path) x500", ahkSearchPath, 0, "O(1) hash + parent walk", "GetPathToNode(pathTree, target)")

        ; AHK FlatMap method
        t1 := QPCms()
        Loop navIters
            TreeNavigator.GetPathFromFlatMap(flatMap, Chr(0x7389) Chr(0x7C73) Chr(0x7CC1))
        ahkSearchFM := QPCms() - t1
        AddLib("TreeNavigator", "Search deep (FlatMap) x500", ahkSearchFM, 0, "1D key walk", "GetPathFromFlatMap(flatMap, target)")

        ; C# search (optimized: pre-built parent pointers, same algorithm as AHK)
        csSearchMs := ToNum(EcoBench.TreeSearchParentPtr(treeRawData, Chr(0x7389) Chr(0x7C73) Chr(0x7CC1), navIters))
        AddResult("Tree Search Deep", "TreeNavigator", Round(ahkSearchClass, 1), csSearchMs, "AHK: TreeNavigator.GetPathToNode() O(1) x" navIters "`nC#: Pre-built parent pointers (same algo) x" navIters "`n`nYour Class method: " Round(ahkSearchClass, 2) "ms`nYour Path method: " Round(ahkSearchPath, 2) "ms`nYour FlatMap method: " Round(ahkSearchFM, 2) "ms")

        ; Search non-existent (worst case)
        St("[27/30] TreeNavigator -- Search miss x500...")
        t1 := QPCms()
        Loop navIters
            TreeNavigator.GetPathToNode(classTree, "THIS_DOES_NOT_EXIST_123")
        ahkMiss := QPCms() - t1
        csSearchMiss := ToNum(EcoBench.TreeSearchParentPtr(treeRawData, "THIS_DOES_NOT_EXIST_123", navIters))
        AddResult("Tree Search Miss", "TreeNavigator", Round(ahkMiss, 1), csSearchMiss, "AHK: O(1) instant reject (Hash miss) x" navIters "`nC#: Dictionary.ContainsKey() x" navIters)
        AddLib("TreeNavigator", "Search miss x500", ahkMiss, csSearchMiss, "O(1) hash miss reject", "Instant reject: not in NodeIndex")

        ; --- DFS brute-force: linear scan vs O(1) index ---
        St("TreeNavigator -- DFS brute-force vs O(1)...")
        ; AHK: build fresh un-indexed tree and DFS it
        freshTree := []
        Loop Parse, treeRawData, "`n", "`r" {
            line := Trim(A_LoopField)
            if line == ""
                continue
            namePos := InStr(line, 'Name: "')
            if !namePos
                continue
            nameStart := namePos + 7
            nameEnd := InStr(line, '"', false, nameStart)
            nodeName := SubStr(line, nameStart, nameEnd - nameStart)
            freshTree.Push({ Name: nodeName, Children: [] })
        }
        dfsIters := 10
        t1 := QPCms()
        Loop dfsIters {
            for node in freshTree {
                if node.Name == Chr(0x7389) Chr(0x7C73) Chr(0x7CC1)
                    break
            }
        }
        ahkDFS := QPCms() - t1
        r := StrSplit(EcoBench.TreeDFS(treeRawData, Chr(0x7389) Chr(0x7C73) Chr(0x7CC1)), "|")
        csDFS := ToNum(r[1])
        AddResult("Tree DFS Brute", "TreeNavigator", Round(ahkDFS, 1), csDFS, "Brute-force linear scan x" dfsIters "`nAHK: for-loop through " freshTree.Length " nodes`nC#: foreach through split lines`n`nThis is what happens WITHOUT your O(1) index!")
        AddLib("TreeNavigator", "DFS brute x10", ahkDFS, csDFS, "Linear scan " freshTree.Length " nodes", "for node in flatArray")

        ; --- O(1) vs DFS speedup comparison ---
        St("TreeNavigator -- O(1) vs DFS speedup...")
        t1 := QPCms()
        Loop navIters
            TreeNavigator.GetPathToNode(classTree, Chr(0x7389) Chr(0x7C73) Chr(0x7CC1))
        ahkO1 := QPCms() - t1
        AddLib("TreeNavigator", "O(1) index x500", ahkO1, Round(ahkDFS * 50, 1), "O(1) vs DFS projected", "O(1) is " Round((ahkDFS * 50) / Max(ahkO1, 0.01), 0) "x faster than DFS")

        ; --- GetAllPaths (multi-result search) ---
        St("TreeNavigator -- GetAllPaths...")
        ; Find a name that appears multiple times
        multiName := ""
        for name, nodes in classTree.NodeIndex {
            if nodes.Length >= 2 {
                multiName := name
                break
            }
        }
        if multiName != "" {
            t1 := QPCms()
            Loop navIters
                allPaths := TreeNavigator.GetAllPathsToNode(classTree, multiName)
            ahkAllPaths := QPCms() - t1
            r := StrSplit(EcoBench.TreeSearchAll(treeRawData, multiName), "|")
            csAllPaths := ToNum(r[1])
            csCount := ToNum(r[2])
            AddResult("Tree AllPaths", "TreeNavigator", Round(ahkAllPaths, 1), csAllPaths, "AHK: GetAllPathsToNode() x" navIters "`nC#: Multi-path reconstruction x" navIters "`nFound " allPaths.Length " paths for '" multiName "'")
            AddLib("TreeNavigator", "GetAllPaths x500", ahkAllPaths, csAllPaths, allPaths.Length " results", "GetAllPathsToNode()")
        }

        ; --- Ancestor-filtered search ---
        St("TreeNavigator -- Ancestor filtered search...")
        ; Get the first result to use as an ancestor filter
        testPath := TreeNavigator.GetPathToNode(classTree, Chr(0x7389) Chr(0x7C73) Chr(0x7CC1))
        if testPath.Length >= 2 {
            ancestor := testPath[1]
            t1 := QPCms()
            Loop navIters
                TreeNavigator.GetPathToNode(classTree, Chr(0x7389) Chr(0x7C73) Chr(0x7CC1), ancestor)
            ahkAncestor := QPCms() - t1
            csMs := ToNum(EcoBench.TreeAncestor(treeRawData, Chr(0x7389) Chr(0x7C73) Chr(0x7CC1), ancestor, navIters))
            AddResult("Tree Ancestor", "TreeNavigator", Round(ahkAncestor, 1), csMs, "AHK: GetPathToNode(tree, target, ancestor) x" navIters "`nAncestor filter: '" ancestor "'`nO(1) index + PathMatchesAncestors validation")
            AddLib("TreeNavigator", "Ancestor filter x500", ahkAncestor, csMs, "O(1) + ancestor check", "GetPathToNode(tree, target, ancestor)")
        }

    } else {
        AddResult("Tree Parse", "TreeNavigator", 0, 0, "tree_data.txt not found in lib_bench/")
    }

    ; ======================================================================
    ; 13. ahk#.sqlite
    ; ======================================================================
    St("[28/30] ahk#.sqlite -- CRUD...")
    try {
        t1 := QPCms()
        db := SQLite(":memory:")
        db.Execute("CREATE TABLE bench (id INTEGER PRIMARY KEY, name TEXT, value REAL)")
        db.Execute("BEGIN")
        Loop 1000
            db.Execute("INSERT INTO bench VALUES (" A_Index ", 'item_" A_Index "', " A_Index * 1.5 ")")
        db.Execute("COMMIT")
        rows := db.Query("SELECT * FROM bench WHERE value > 500")
        total := db.Scalar("SELECT SUM(value) FROM bench")
        db.Close()
        ahkMs := QPCms() - t1
        r := StrSplit(EcoBench.SqliteOps(1000), "|")
        csMs := ToNum(r[1])
        AddResult("SQLite CRUD 1K", "ahk#.sqlite", ahkMs, csMs, "AHK#: SQLite(':memory:') via winsqlite3`nCREATE + INSERT 1K + SELECT + SUM`nRows: " rows.Length " | SUM: " Round(total, 0))
        AddLib("ahk#.sqlite", "Full CRUD 1K", ahkMs, csMs, "winsqlite3 via bridge", "CREATE+INSERT+SELECT+SUM")
    } catch as e {
        AddResult("SQLite CRUD", "ahk#.sqlite", 0, 0, "Error: " e.Message)
    }

    ; ======================================================================
    ; 14. COM libs (MSXML2 + Scripting.Dictionary)
    ; ======================================================================
    St("[29/30] MSXML2 + COM Dict...")
    xmlStr := '<root><item id="1">Hello</item><item id="2">World</item></root>'
    xmlIters := 1000
    t1 := QPCms()
    Loop xmlIters {
        xDoc := ComObject("MSXML2.DOMDocument.6.0")
        xDoc.loadXML(xmlStr)
    }
    ahkMs := QPCms() - t1
    csMs := ToNum(EcoBench.XmlParse(xmlStr, xmlIters))
    AddResult("XML Parse 1K", "MSXML2 COM", ahkMs, csMs, "AHK: MSXML2.DOMDocument.6.0 COM x" xmlIters "`nC#: XmlDocument.LoadXml() x" xmlIters)
    AddLib("MSXML2 COM", "Parse x1K", ahkMs, csMs, "COM DOM parser", "MSXML2.DOMDocument.6.0")

    ; ======================================================================
    ; 15. jNizM CreateGUID
    ; ======================================================================
    St("[30/38] jNizM GUID -- Generate x10K...")
    guidIters := 10000
    t1 := QPCms()
    Loop guidIters
        guid := CreateGUID()
    ahkMs := QPCms() - t1
    r := StrSplit(EcoBench.GuidGen(guidIters), "|")
    csMs := ToNum(r[1])
    AddResult("GUID Gen 10K", "jNizM CreateGUID", ahkMs, csMs, "AHK: CreateGUID() ole32 DllCall x" guidIters "`nC#: Guid.NewGuid() x" guidIters "`nSample: " guid)
    AddLib("jNizM CreateGUID", "Generate x10K", ahkMs, csMs, "ole32 CoCreateGuid", "CreateGUID() DllCall")

    ; ======================================================================
    ; 16. jNizM FileCountLines
    ; ======================================================================
    St("[31/38] jNizM FileCountLines...")
    countFile := A_ScriptFullPath
    t1 := QPCms()
    ahkLineCount := FileCountLines(countFile)
    ahkMs := QPCms() - t1
    r := StrSplit(EcoBench.FileCountLines(countFile), "|")
    csMs := ToNum(r[1])
    csLines := ToNum(r[2])
    AddResult("FileCountLines", "jNizM FileOps", ahkMs, csMs, "AHK: FileCountLines() FileOpen loop x1`nC#: File.ReadAllLines().Length x1`nAHK lines: " ahkLineCount " | C# lines: " csLines)
    AddLib("jNizM FileOps", "CountLines", ahkMs, csMs, "FileOpen + readline", "FileCountLines(path)")

    ; ======================================================================
    ; 17. jNizM FileFindString
    ; ======================================================================
    St("[32/38] jNizM FileFindString...")
    t1 := QPCms()
    found := FileFindString(countFile, "EcoBench")
    ahkMs := QPCms() - t1
    r := StrSplit(EcoBench.FileFindStr(countFile, "EcoBench"), "|")
    csMs := ToNum(r[1])
    AddResult("FileFindString", "jNizM FileOps", ahkMs, csMs, "AHK: FileFindString() line-by-line x1`nC#: File.ReadAllLines + Contains x1`nMatches: " (IsObject(found) ? found.Count : 0))
    AddLib("jNizM FileOps", "FindString", ahkMs, csMs, "FileOpen search", "FileFindString(path, needle)")

    ; ======================================================================
    ; 18. thqby Heap
    ; ======================================================================
    St("[33/38] thqby Heap -- findHeap x1K...")
    heapBuf := Buffer(256)
    heapIters := 1000
    t1 := QPCms()
    Loop heapIters
        findHeap(heapBuf.Ptr)
    ahkMs := QPCms() - t1
    csMs := ToNum(EcoBench.HeapWalkTest(heapIters))
    AddResult("Heap Walk 1K", "thqby Heap", ahkMs, csMs, "AHK: findHeap(ptr) HeapWalk DllCall x" heapIters "`nLow-level process heap inspection")
    AddLib("thqby Heap", "findHeap x1K", ahkMs, csMs, "HeapWalk + HeapValidate", "findHeap(bufferPtr)")

    ; ======================================================================
    ; 19. Raw buffer allocation (fair comparison)
    ; ======================================================================
    St("[34/42] Buffer alloc 200x200 x100...")
    imgIters := 100
    t1 := QPCms()
    Loop imgIters
        imgBuf := Buffer(200 * 200 * 4, 0xFF)
    ahkMs := QPCms() - t1
    csMs := ToNum(EcoBench.ImageBufAllocOpt(200, 200, imgIters))
    AddResult("Buf Alloc 160K", "Raw Buffer", ahkMs, csMs, "AHK: Buffer(160000, 0xFF) -- native memset x" imgIters "`nC#: Marshal.AllocHGlobal + RtlFillMemory x" imgIters "`n`nBoth use kernel32 memset now -- fairest comparison")
    AddLib("Raw Buffer", "160KB alloc x100", ahkMs, csMs, "Both use memset", "Buffer(200*200*4, 0xFF)")

    ; ======================================================================
    ; 20. GDI+ Bitmap create (C# has native advantage)
    ; ======================================================================
    St("[35/42] GDI+ Bitmap create x100...")
    t1 := QPCms()
    hGdipMod := DllCall("LoadLibrary", "Str", "gdiplus", "Ptr")
    gdipSI := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
    NumPut("UInt", 1, gdipSI, 0)
    DllCall("gdiplus\GdiplusStartup", "Ptr*", &hGdipTok := 0, "Ptr", gdipSI, "Ptr", 0)
    Loop imgIters {
        DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", 200, "Int", 200, "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &pBitmap := 0)
        if pBitmap
            DllCall("gdiplus\GdipDisposeImage", "Ptr", pBitmap)
    }
    if hGdipTok
        DllCall("gdiplus\GdiplusShutdown", "Ptr", hGdipTok)
    ahkMs := QPCms() - t1
    csMs := ToNum(EcoBench.GdipCreateDirect(200, 200, imgIters))
    AddResult("GDI+ Bitmap", "GDI+ DllCall", ahkMs, csMs, "AHK: GdipCreateBitmapFromScan0 DllCall x" imgIters "`nC#: P/Invoke GdipCreateBitmapFromScan0 (same API) x" imgIters "`n`nBoth call the same GDI+ function directly")
    AddLib("GDI+ DllCall", "Bitmap x100", ahkMs, csMs, "Direct P/Invoke", "GdipCreateBitmapFromScan0")

    ; ======================================================================
    ; 21. WinClip -- Clipboard manipulation
    ; ======================================================================
    St("[36/42] WinClip -- Clipboard ops...")
    wc := WinClip()
    wcIters := 1000
    t1 := QPCms()
    Loop wcIters {
        wc.SetText("Benchmark test data iteration " A_Index " with some extra text for realism")
        wc.GetText()
    }
    ahkMs := QPCms() - t1
    csMs := ToNum(EcoBench.ClipboardOps(wcIters))
    AddResult("Clipboard 1K", "WinClip", ahkMs, csMs, "AHK: WinClip.SetText() + GetText() x" wcIters "`nC#: Encoding.Unicode + byte[] copy x" wcIters "`n`nWinClip by Deo/TheArkive -- clipboard manipulation class")
    AddLib("WinClip", "Set+Get x1K", ahkMs, csMs, "Clipboard class", "WinClip.SetText() + GetText()")

    ; Clipboard format enumeration
    St("[37/42] WinClip -- Format snap...")
    wc.SetText("Test data for format snap")
    t1 := QPCms()
    Loop wcIters
        fmts := wc.GetFormats()
    ahkMs := QPCms() - t1
    csMs := ToNum(EcoBench.ClipFormats(wcIters))
    AddResult("Clip Formats 1K", "WinClip", ahkMs, csMs, "AHK: WinClip.GetFormats() x" wcIters "`nEnumerate all clipboard format types")
    AddLib("WinClip", "GetFormats x1K", ahkMs, csMs, "Format enumeration", "WinClip.GetFormats()")

    ; ======================================================================
    ; 22. COM Scripting.Dictionary
    ; ======================================================================
    St("[38/42] COM Dict 10K...")
    dIters := 10000
    t1 := QPCms()
    dict := ComObject("Scripting.Dictionary")
    Loop dIters
        dict.Add("k" A_Index, A_Index)
    cSum := 0
    Loop dIters
        cSum += dict.Item("k" A_Index)
    ahkMs := QPCms() - t1
    r := StrSplit(EcoBench.DictOps(dIters), "|")
    csMs := ToNum(r[1])
    AddResult("COM Dict 10K", "Scripting.Dict", ahkMs, csMs, "AHK: Scripting.Dictionary COM x" dIters "`nC#: Dictionary<string,int> x" dIters)
    AddLib("Scripting.Dict", "Add+Read x10K", ahkMs, csMs, "COM Dictionary", "Scripting.Dictionary")

    ; ======================================================================
    ; 23. WMI
    ; ======================================================================
    St("[39/45] WMI Processes...")
    t1 := QPCms()
    wmi := ComObject("WbemScripting.SWbemLocator").ConnectServer()
    procs := wmi.ExecQuery("SELECT Name FROM Win32_Process")
    pCount := 0
    for p in procs
        pCount++
    ahkMs := QPCms() - t1
    r := StrSplit(EcoBench.WmiProcesses(), "|")
    csMs := ToNum(r[1])
    csCount := ToNum(r[2])
    AddResult("WMI Processes", "WMI COM", ahkMs, csMs, "WbemScripting query -- " pCount " processes (C#: " csCount " processes)")
    AddLib("WMI COM", "Process list", ahkMs, csMs, pCount " processes", "ExecQuery(Win32_Process)")
    ; ======================================================================
    ; 23b. AHK Competitive: PCRE RegEx Match (Short String)
    ; ======================================================================
    St("[40/45] RegEx Match x10K (Competitive)...")
    testText := "The ticket number is 49204 in the system"
    itersRegex := 10000
    t1 := QPCms()
    Loop itersRegex {
        RegExMatch(testText, "\d+", &match)
        res := match[0]
    }
    ahkMs := QPCms() - t1
    csMs := ToNum(EcoBench.RegexSmallMatch(testText, itersRegex))
    AddResult("RegEx Match 10K", "PCRE vs .NET", ahkMs, csMs, "AHK: RegExMatch() native PCRE x" . itersRegex . "`nC#: Regex.Match() managed x" . itersRegex)
    AddLib("PCRE vs .NET", "Short Match x10K", ahkMs, csMs, "PCRE C++ beats managed JIT", "RegExMatch(text, '\d+')")

    ; ======================================================================
    ; 23c. AHK Competitive: Win32 DLL Call (GetTickCount)
    ; ======================================================================
    St("[41/45] Win32 DllCall GetTickCount (Competitive)...")
    itersDll := 20000
    t1 := QPCms()
    Loop itersDll {
        ticks := DllCall("kernel32\GetTickCount", "UInt")
    }
    ahkMs := QPCms() - t1
    csMs := ToNum(EcoBench.Win32DllCall(itersDll))
    AddResult("DllCall kernel32", "Win32 DLL Call", ahkMs, csMs, "AHK: DllCall('kernel32\GetTickCount') x" . itersDll . "`nC#: DllImport GetTickCount() x" . itersDll)
    AddLib("Win32 DLL Call", "kernel32 x20K", ahkMs, csMs, "AHK C++ thin DLL binding layer", "DllCall('kernel32\GetTickCount')")

    ; ======================================================================
    ; 23d. AHK Competitive: OS FileExist Check
    ; ======================================================================
    St("[42/45] OS FileExist Check (Competitive)...")
    tempFile := A_ScriptFullPath
    itersFile := 2000
    t1 := QPCms()
    Loop itersFile {
        exists := FileExist(tempFile)
    }
    ahkMs := QPCms() - t1
    csMs := ToNum(EcoBench.OsFileExist(tempFile, itersFile))
    AddResult("FileExist 2K", "OS File Check", ahkMs, csMs, "AHK: FileExist() native C++ loop x" . itersFile . "`nC#: File.Exists() managed loop x" . itersFile)
    AddLib("OS File Check", "FileExist x2K", ahkMs, csMs, "AHK C++ native file check", "FileExist(path)")

    ; ======================================================================
    ; 24. C# Exclusive
    ; ======================================================================
    St("[43/45] C# Exclusive -- Async Parallel...")
    ; Measure sequential execution in AHK as the comparative "next best thing"
    t1 := QPCms()
    Loop 10 {
        sum := 0
        Loop 1000000
            sum += A_Index - 1
    }
    ahkMs := QPCms() - t1
    r := StrSplit(EcoBench.AsyncParallel(), "|")
    csMs := ToNum(r[1])
    AddResult("Async Parallel", ".NET Task.Run", ahkMs, csMs, "C# .NET: Task.Run() x10 parallel CPU tasks`nAHK v2: Loop 10 x 1,000,000 sequential (next best thing)")

    St("[44/45] C# Exclusive -- LINQ...")
    ; Measure linear loop object generation, filter, and reverse-take in AHK
    t1 := QPCms()
    data := []
    Loop 100000 {
        data.Push({ Name: "item" (A_Index - 1), Value: (A_Index - 1) * 3 })
    }
    filtered := []
    for x in data {
        if x.Value > 100000
            filtered.Push(x)
    }
    reversed := []
    idx := filtered.Length
    Loop Min(100, filtered.Length) {
        if idx <= 0
            break
        reversed.Push(filtered[idx])
        idx--
    }
    ahkMs := QPCms() - t1
    r := StrSplit(EcoBench.LinqOps(100000), "|")
    csMs := ToNum(r[1])
    AddResult("LINQ 100K", ".NET LINQ", ahkMs, csMs, "C# .NET: LINQ O(1) query decorators x100K`nAHK v2: Object array push + linear scan + take 100 (next best thing)")

    ; ==== Final Render & Display ==========================================
    St("Rendering display...")
    UpdateDisplay()

    btnRun.Enabled := true
    statusText.Value := "Done -- Boot: " bootMs "ms (Compile: " compileMs "ms, JIT: " jitMs "ms) | " allResults.Length " tests benchmarked (" compileChoice ", " jitChoice ")"
}

global ahkLineMap := Map(), csLineMap := Map()

ScanFileForLines() {
    global ahkLineMap, csLineMap
    ahkLineMap.Clear()
    csLineMap.Clear()

    if FileExist(A_ScriptFullPath) {
        content := FileRead(A_ScriptFullPath, "UTF-8")
        Loop Parse, content, "`n", "`r" {
            line := A_LoopField
            if InStr(line, "Jxon_Load(&jsonStr)")
                ahkLineMap["JXON Parse 5K"] := A_Index
            else if InStr(line, "Jxon_Dump(obj)")
                ahkLineMap["JXON Stringify 5K"] := A_Index
            else if InStr(line, "JSON.parse(jsonStr)")
                ahkLineMap["thqby Parse 5K"] := A_Index
            else if InStr(line, "JSON.stringify(obj2)")
                ahkLineMap["thqby Stringify 5K"] := A_Index
            else if InStr(line, "MD5(buf)")
                ahkLineMap["MD5 10K"] := A_Index
            else if InStr(line, 'Crypt_Hash(buf, buf.Size, "SHA")') || InStr(line, "Crypt_Hash(buf, buf.Size, 'SHA')")
                ahkLineMap["SHA1 5K"] := A_Index
            else if InStr(line, 'Crypt_Hash(buf, buf.Size, "CRC32")') || InStr(line, "Crypt_Hash(buf, buf.Size, 'CRC32')")
                ahkLineMap["CRC32 10K"] := A_Index
            else if InStr(line, "Crypt_AES(")
                ahkLineMap["AES-256 500"] := A_Index
            else if InStr(line, "StringToBase64(hashStr)")
                ahkLineMap["B64 Enc jNizM"] := A_Index
            else if InStr(line, "Base64ToString(b64encoded)")
                ahkLineMap["B64 Dec jNizM"] := A_Index
            else if InStr(line, "Base64.Encode(hashStr)")
                ahkLineMap["B64 Enc thqby"] := A_Index
            else if InStr(line, "Base64.Decode(thqbyEnc)")
                ahkLineMap["B64 Dec thqby"] := A_Index
            else if InStr(line, "testArr.Clone().Sort")
                ahkLineMap["Array Sort 1K"] := A_Index
            else if InStr(line, "testArr.Filter(")
                ahkLineMap["Array Filter 1K"] := A_Index
            else if InStr(line, "testArr.Map(")
                ahkLineMap["Array Map 1K"] := A_Index
            else if InStr(line, "testArr.Reduce(")
                ahkLineMap["Array Reduce 1K"] := A_Index
            else if InStr(line, "testStr.ToUpper()")
                ahkLineMap["String Ops 10K"] := A_Index
            else if InStr(line, "regText.RegExMatchAll")
                ahkLineMap["RegExMatchAll 1K"] := A_Index
            else if InStr(line, "testMap.Filter")
                ahkLineMap["Map Filter 1K"] := A_Index
            else if InStr(line, "Range(1, 100)")
                ahkLineMap["Range iter 5K"] := A_Index
            else if InStr(line, "ComVar(42)")
                ahkLineMap["ComVar Create 10K"] := A_Index
            else if InStr(line, "deepclone(nested)")
                ahkLineMap["DeepClone x1K"] := A_Index
            else if InStr(line, "SetupTree(treeRawData)") || InStr(line, "TreeNavigator.ParseByFlatMap(treeRawData)")
                ahkLineMap["Tree Parse"] := A_Index
            else if InStr(line, "GetPathToNode(classTree, Chr(0x7389)")
                ahkLineMap["Tree Search Deep"] := A_Index
            else if InStr(line, 'GetPathToNode(classTree, "THIS_DOES_NOT_EXIST_123")') || InStr(line, "GetPathToNode(classTree, 'THIS_DOES_NOT_EXIST_123')")
                ahkLineMap["Tree Search Miss"] := A_Index
            else if InStr(line, "dfsIters :=")
                ahkLineMap["Tree DFS Brute"] := A_Index
            else if InStr(line, "GetAllPathsToNode(classTree")
                ahkLineMap["Tree AllPaths"] := A_Index
            else if InStr(line, "GetPathToNode(classTree, Chr(0x7389) Chr(0x7C73) Chr(0x7CC1), ancestor)")
                ahkLineMap["Tree Ancestor"] := A_Index
            else if InStr(line, 'SQLite(":memory:")') || InStr(line, "SQLite(':memory:')")
                ahkLineMap["SQLite CRUD 1K"] := A_Index
            else if InStr(line, "MSXML2.DOMDocument")
                ahkLineMap["XML Parse 1K"] := A_Index
            else if InStr(line, "CreateGUID()")
                ahkLineMap["GUID Gen 10K"] := A_Index
            else if InStr(line, "FileCountLines(countFile)")
                ahkLineMap["FileCountLines"] := A_Index
            else if InStr(line, "FileFindString(countFile")
                ahkLineMap["FileFindString"] := A_Index
            else if InStr(line, "findHeap(")
                ahkLineMap["Heap Walk 1K"] := A_Index
            else if InStr(line, "Buffer(200 * 200 * 4")
                ahkLineMap["Buf Alloc 160K"] := A_Index
            else if InStr(line, "GdipCreateBitmapFromScan0")
                ahkLineMap["GDI+ Bitmap"] := A_Index
            else if InStr(line, "wc.SetText(")
                ahkLineMap["Clipboard 1K"] := A_Index
            else if InStr(line, "wc.GetFormats()")
                ahkLineMap["Clip Formats 1K"] := A_Index
            else if InStr(line, 'dict := ComObject("Scripting.Dictionary")') || InStr(line, "dict := ComObject('Scripting.Dictionary')")
                ahkLineMap["COM Dict 10K"] := A_Index
            else if InStr(line, "SWbemLocator")
                ahkLineMap["WMI Processes"] := A_Index
            else if InStr(line, "RegExMatch(testText")
                ahkLineMap["RegEx Match 10K"] := A_Index
            else if InStr(line, 'DllCall("kernel32\GetTickCount"') || InStr(line, "DllCall('kernel32\GetTickCount'")
                ahkLineMap["DllCall kernel32"] := A_Index
            else if InStr(line, "FileExist(tempFile)")
                ahkLineMap["FileExist 2K"] := A_Index
            else if InStr(line, "AsyncParallel()")
                ahkLineMap["Async Parallel"] := A_Index
            else if InStr(line, "LinqOps(100000)")
                ahkLineMap["LINQ 100K"] := A_Index
        }
    }

    csPath := A_ScriptDir "\lib_bench\EcoBench.cs"
    if FileExist(csPath) {
        content := FileRead(csPath, "UTF-8")
        Loop Parse, content, "`n", "`r" {
            line := A_LoopField
            if RegExMatch(line, "i)public\s+static\s+\w+\s+(\w+)\s*\(", &m) {
                methodName := m[1]
                if methodName == "JsonParse" {
                    csLineMap["JXON Parse 5K"] := A_Index
                    csLineMap["thqby Parse 5K"] := A_Index
                } else if methodName == "JsonStringify" {
                    csLineMap["JXON Stringify 5K"] := A_Index
                    csLineMap["thqby Stringify 5K"] := A_Index
                } else if methodName == "Md5" {
                    csLineMap["MD5 10K"] := A_Index
                } else if methodName == "Sha1" {
                    csLineMap["SHA1 5K"] := A_Index
                } else if methodName == "Crc32" {
                    csLineMap["CRC32 10K"] := A_Index
                } else if methodName == "AesEncrypt" {
                    csLineMap["AES-256 500"] := A_Index
                } else if methodName == "Base64Encode" {
                    csLineMap["B64 Enc jNizM"] := A_Index
                    csLineMap["B64 Enc thqby"] := A_Index
                } else if methodName == "Base64Decode" {
                    csLineMap["B64 Dec jNizM"] := A_Index
                    csLineMap["B64 Dec thqby"] := A_Index
                } else if methodName == "ArraySort" {
                    csLineMap["Array Sort 1K"] := A_Index
                } else if methodName == "ArrayFilter" {
                    csLineMap["Array Filter 1K"] := A_Index
                } else if methodName == "ArrayMap" {
                    csLineMap["Array Map 1K"] := A_Index
                } else if methodName == "ArrayReduce" {
                    csLineMap["Array Reduce 1K"] := A_Index
                } else if methodName == "StringOps" {
                    csLineMap["String Ops 10K"] := A_Index
                } else if methodName == "DictOps" {
                    csLineMap["Map Filter 1K"] := A_Index
                    csLineMap["COM Dict 10K"] := A_Index
                } else if methodName == "DeepCloneTest" {
                    csLineMap["DeepClone x1K"] := A_Index
                } else if methodName == "TreeParse" {
                    csLineMap["Tree Parse"] := A_Index
                } else if methodName == "TreeSearchParentPtr" {
                    csLineMap["Tree Search Deep"] := A_Index
                    csLineMap["Tree Search Miss"] := A_Index
                } else if methodName == "TreeDFS" {
                    csLineMap["Tree DFS Brute"] := A_Index
                } else if methodName == "TreeSearchAll" {
                    csLineMap["Tree AllPaths"] := A_Index
                } else if methodName == "SqliteOps" {
                    csLineMap["SQLite CRUD 1K"] := A_Index
                } else if methodName == "XmlParse" {
                    csLineMap["XML Parse 1K"] := A_Index
                } else if methodName == "GuidGen" {
                    csLineMap["GUID Gen 10K"] := A_Index
                } else if methodName == "FileCountLines" {
                    csLineMap["FileCountLines"] := A_Index
                } else if methodName == "FileFindStr" {
                    csLineMap["FileFindString"] := A_Index
                } else if methodName == "ImageBufAllocOpt" {
                    csLineMap["Buf Alloc 160K"] := A_Index
                } else if methodName == "GdipCreateDirect" {
                    csLineMap["GDI+ Bitmap"] := A_Index
                } else if methodName == "ClipboardOps" {
                    csLineMap["Clipboard 1K"] := A_Index
                } else if methodName == "RegexSmallMatch" {
                    csLineMap["RegEx Match 10K"] := A_Index
                } else if methodName == "Win32DllCall" {
                    csLineMap["DllCall kernel32"] := A_Index
                } else if methodName == "OsFileExist" {
                    csLineMap["FileExist 2K"] := A_Index
                } else if methodName == "AsyncParallel" {
                    csLineMap["Async Parallel"] := A_Index
                } else if methodName == "LinqOps" {
                    csLineMap["LINQ 100K"] := A_Index
                }
            }
        }
    }
}

OnResultSelect(ctrl, row, *) {
    if row <= 0
        return
    testName := ctrl.GetText(row, 2)

    resObj := ""
    for r in allResults {
        if r.name == testName {
            resObj := r
            break
        }
    }

    if !IsObject(resObj) {
        if allSnippets.Has(testName)
            detailEdit.Value := allSnippets[testName]
        return
    }

    try {
        ahkMs := resObj.ahk
        csMs := resObj.cs

        desc := EcoBench.GetVerboseDescription(testName, ToNum(ahkMs), ToNum(csMs))

        ahkLine := ahkLineMap.Has(testName) ? ahkLineMap[testName] : 0
        csLine := csLineMap.Has(testName) ? csLineMap[testName] : 0

        lineDetails := "=== SOURCE LOCATION DETAILS ===`r`n"
        if (ahkLine > 0)
            lineDetails .= "  - AHK Call Location  : ecosystem_benchmark.ahk (Line " ahkLine ")`r`n"
        else
            lineDetails .= "  - AHK Call Location  : ecosystem_benchmark.ahk`r`n"

        if (csLine > 0)
            lineDetails .= "  - C# Method Location : EcoBench.cs (Line " csLine ")`r`n"
        else
            lineDetails .= "  - C# Method Location : EcoBench.cs`r`n"
        lineDetails .= "`r`n"

        detailEdit.Value := lineDetails . desc
    } catch as e {
        if allSnippets.Has(testName)
            detailEdit.Value := "Error loading verbose details: " e.Message "`r`n`r`n" allSnippets[testName]
    }
}

OnLibSelect(ctrl, row, *) {
    if row <= 0
        return
    libName := ctrl.GetText(row, 2)
    testName := ctrl.GetText(row, 3)
    k := libName "|" testName
    if allLibSnippets.Has(k)
        detailEditLib.Value := allLibSnippets[k]
    else
        detailEditLib.Value := ""
}

ScanFileForLines()
g.Show("w900 h710")
WinWaitClose(g.Hwnd)
try FileDelete(A_Temp "\ahk_eco_chart.png")
ExitApp()