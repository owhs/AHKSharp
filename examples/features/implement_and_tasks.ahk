;; AHK# — Tasks, out parameters, interfaces implemented in AHK, and worker-thread callbacks

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

; ── 1. out parameters: pass &var, get the value back ─────────────────────────
ok := CS.System.Int32.TryParse("1234", &parsed)
MsgBox("TryParse ok: " ok "`nparsed: " parsed, "out parameters")

; ── 2. .NET Tasks are awaitable ──────────────────────────────────────────────
;      Any method that returns a Task: .Await(timeoutMs), .Then(cb), .Catch(cb)
client := CS.System.Net.Http.HttpClient()
try {
    body := client.GetStringAsync("https://api.nuget.org/v3/index.json").Await(15000)
    MsgBox("Downloaded " StrLen(body) " characters without blocking the message loop.", "Task.Await")
} catch as e
    MsgBox("Network unavailable: " e.Message, "Task.Await")

; ── 3. implement a .NET interface with AHK functions ─────────────────────────
;      Array.Sort(Array, IComparer) calls YOUR function to order the elements.
numbers := CS.System.Array.CreateInstance(CS.System.Int32, 5)
for i, n in [42, 7, 19, 3, 25]
    numbers[i - 1] := n

descending := CS.Implement(CS.System.Collections.IComparer, Map("Compare", (a, b) => b - a))
CS.System.Array.Sort(numbers, descending)

sorted := ""
for n in numbers
    sorted .= n " "
MsgBox("Sorted by an AHK comparer:`n" sorted, "CS.Implement")

; ── 4. AHK functions running on .NET worker threads ──────────────────────────
;      Task.Run executes on the thread pool, but your function still runs on the AHK
;      thread (the message loop services it) — so it may touch GUIs and variables.
state := Map("ran", "no")
CS.System.Threading.Tasks.Task.Run(() => state["ran"] := "yes, on the AHK thread").Await(5000)
MsgBox("Callback from a pool thread: " state["ran"], "worker-thread callbacks")

; ── 5. see how an overload is chosen ─────────────────────────────────────────
MsgBox(CS.Explain(CS.System.Math, "Abs", -2.5), "CS.Explain (=> marks the winner)")

ExitApp()
