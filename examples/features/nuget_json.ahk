;; AHK# Example 27 — NuGet Package Manager
;; Install packages from nuget.org and use them in CSModules.
;; Demonstrates: CS.NuGet.Install, CS.NuGet.Require, progress GUI
;;
;; First run downloads Newtonsoft.Json (~300KB). Subsequent runs use cache.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

; ── Install Newtonsoft.Json via NuGet ─────────────────────────────────────────
; Shows a progress GUI during download, auto-closes when done.
CS.NuGet.Install("Newtonsoft.Json", "13.0.3")

; ── Use it in a CSModule ──────────────────────────────────────────────────────
class JsonHelper extends _CSModule {
    static References := CS.NuGet.Require("Newtonsoft.Json", "13.0.3")
    static CSharp := '
    (
        using Newtonsoft.Json;
        using Newtonsoft.Json.Linq;
        using System.Collections.Generic;

        public static string PrettyPrint(string json) {
            var obj = JsonConvert.DeserializeObject(json);
            return JsonConvert.SerializeObject(obj, Formatting.Indented);
        }

        public static string Query(string json, string jpath) {
            var obj = JObject.Parse(json);
            var token = obj.SelectToken(jpath);
            return token != null ? token.ToString() : "(not found)";
        }

        public static string BuildJson(string name, int age, string city) {
            var person = new {
                Name = name,
                Age = age,
                City = city,
                Tags = new[] { "ahk#", "dotnet", "automation" }
            };
            return JsonConvert.SerializeObject(person, Formatting.Indented);
        }
    )'
}

; ── Demo ──────────────────────────────────────────────────────────────────────

; Build a JSON object
json := JsonHelper.BuildJson("Alice", 30, "London")
MsgBox(json, "AHK# — Built JSON")

; Query with JSONPath
name := JsonHelper.Query(json, "Name")
firstTag := JsonHelper.Query(json, "Tags[0]")
MsgBox("Name: " name "`nFirst tag: " firstTag, "AHK# — JSONPath Query")

; Pretty-print messy JSON
messy := '{"a":1,"b":{"c":[1,2,3]},"d":"hello"}'
pretty := JsonHelper.PrettyPrint(messy)
MsgBox(pretty, "AHK# — Pretty Print")

; Check if NuGet package is installed
installed := CS.NuGet.IsInstalled("Newtonsoft.Json", "13.0.3")
MsgBox("Newtonsoft.Json installed: " installed, "AHK# — NuGet Status")

MsgBox("NuGet package manager demo complete!", "AHK# — Done", 0x40)
ExitApp()
