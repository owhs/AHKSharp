;; AHK# — CS.LoadAssembly & CS.CreateObject
;; Use types from a compiled .NET DLL: CS.LoadAssembly(path) makes its types
;; available, CS.CreateObject("Namespace.Type") instantiates one.
;;
;; To keep the demo self-contained we build the DLL ourselves: a _CSModule is
;; compiled and .Precompile writes it to your temp folder. In real use the DLL
;; would come from elsewhere (your own project, a build, a colleague).

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

dllPath := A_Temp "\AHKSharp_DemoLib.dll"

; ── Step 1: compile a small library and export it as a DLL ───────────────────

class DemoLibBuilder extends _CSModule {
    static CSharp := '
    (
        namespace DemoLib {
            public class Counter {
                public int Count { get; private set; }
                public string Label { get; set; }

                public Counter() { Label = "counter"; }

                public void Add(int n) { Count += n; }

                public string Describe() { return Label + " = " + Count; }
            }
        }
    )'
}

DemoLibBuilder.Precompile(dllPath)
dllSize := CS.System.IO.FileInfo(dllPath).Length
MsgBox("Wrote " dllPath " (" dllSize " bytes).", "AHK# — Step 1: DLL built")

; ── Step 2: load it and create an object ─────────────────────────────────────

CS.LoadAssembly(dllPath)
counter := CS.CreateObject("DemoLib.Counter")
counter.Label := "clicks"
counter.Add(5)
counter.Add(37)
MsgBox("Describe(): " counter.Describe() "`nCount property: " counter.Count
    , "AHK# — Step 2: LoadAssembly + CreateObject")

; ── Step 3: CreateObject can also load the DLL for you ───────────────────────

other := CS.CreateObject("DemoLib.Counter", dllPath)
other.Add(100)
MsgBox("Second instance: " other.Describe() "`nFirst instance is unchanged: " counter.Describe()
    , "AHK# — Step 3: CreateObject(type, dllPath)", 0x40)

ExitApp()
