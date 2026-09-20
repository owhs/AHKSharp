#Include harness.ahk
#Include ..\ext\ahk#.spatial.ahk

; Spatial with a fake reader — no OCR engine needed.

reset() {
    global __state
    Spatial.StopAll()
    Spatial.Reader := ""
    Spatial.Parser := ""
    Spatial.OnError := ""
    __state["texts"] := []
    __state["reads"] := 0
    __state["errors"] := []
}

script(list) {
    global __state
    __state["script"] := list
    __state["pos"] := 0
    return (*) => (__state["reads"] += 1, __state["script"][Min(++__state["pos"], __state["script"].Length)])
}

Test("Watch calls back only when the text changes", () => (
    reset(), Spatial.Reader := script(["a", "a", "b", "b", "b", "c"]),
    Spatial.Watch(0, 0, 10, 10, 30, (r) => __state["texts"].Push(r.text)),
    WaitFor(() => __state["texts"].Length >= 3), Spatial.StopAll(),
    Eq(__state["texts"][1], "a"), Eq(__state["texts"][2], "b"), Eq(__state["texts"][3], "c"), Eq(__state["texts"].Length, 3)))

Test("empty text is ignored", () => (
    reset(), Spatial.Reader := script(["", "", "x"]),
    Spatial.Watch(0, 0, 1, 1, 30, (r) => __state["texts"].Push(r.text)),
    WaitFor(() => __state["texts"].Length >= 1), Spatial.StopAll(), Eq(__state["texts"][1], "x")))

Test("WatchFor passes the regex match", () => (
    reset(), Spatial.Reader := script(["nothing", "error 42 happened"]),
    Spatial.WatchFor(0, 0, 1, 1, "i)error (\d+)", (r) => __state["texts"].Push(r.match[1]), 30),
    WaitFor(() => __state["texts"].Length >= 1), Spatial.StopAll(), Eq(__state["texts"][1], "42")))

Test("Stop cancels the timer (no more reads)", () => _stopTest())

_stopTest() {
    global __state
    reset()
    Spatial.Reader := script(["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"])
    id := Spatial.Watch(0, 0, 1, 1, 25, (r) => 1)
    WaitFor(() => __state["reads"] >= 2)
    Spatial.Stop(id)
    after := __state["reads"]
    Sleep(300)
    Eq(__state["reads"], after, "reader calls after Stop")
    Eq(Spatial.Count, 0)
}

Test("StopAll stops every watcher", () => (
    reset(), Spatial.Reader := script(["a", "b"]),
    Spatial.Watch(0, 0, 1, 1, 40, (r) => 1), Spatial.Watch(0, 0, 1, 1, 40, (r) => 1),
    Eq(Spatial.Count, 2), Spatial.StopAll(), Eq(Spatial.Count, 0)))

Test("a missing Reader is reported, not swallowed", () => (
    reset(), Spatial.OnError := (e, id) => __state["errors"].Push(e.Message),
    Spatial.Watch(0, 0, 1, 1, 30, (r) => 1), WaitFor(() => __state["errors"].Length >= 1), Spatial.StopAll(),
    Has(__state["errors"][1], "no Reader")))

Test("a throwing reader is reported and the watcher keeps running", () => (
    reset(), Spatial.OnError := (e, id) => __state["errors"].Push(e.Message),
    Spatial.Reader := (*) => (__state["reads"] += 1, __state["reads"] < 3 ? _fail() : "recovered"),
    Spatial.Watch(0, 0, 1, 1, 25, (r) => __state["texts"].Push(r.text)),
    WaitFor(() => __state["texts"].Length >= 1), Spatial.StopAll(),
    IsTrue(__state["errors"].Length >= 2, "errors were reported"), Eq(__state["texts"][1], "recovered")))

_fail() {
    throw Error("reader failed")
}

Test("a Parser's result is merged into the callback object", () => (
    reset(), Spatial.Reader := script(["MsgBox 1"]), Spatial.Parser := (text) => {errorCount: 0, kind: "ahk"},
    Spatial.Watch(0, 0, 1, 1, 30, (r) => __state["texts"].Push(r.kind ":" r.errorCount)),
    WaitFor(() => __state["texts"].Length >= 1), Spatial.StopAll(), Eq(__state["texts"][1], "ahk:0")))

RunTests()
