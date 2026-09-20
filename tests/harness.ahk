;; ── AHK# test harness ──────────────────────────────────────────────────────────
;; Tiny TAP-style runner. A test file does:
;;
;;   #Include harness.ahk
;;   Test("Math.Abs keeps the fraction", () => Eq(CS.System.Math.Abs(-2.5), 2.5))
;;   Test("bad parse throws", () => Throws(() => CS.System.Int32.Parse("abc"), "not in a correct format"))
;;   RunTests()
;;
;; Output goes to stdout as `ok N - name` / `not ok N - name # reason`, then a `# pass=… fail=…`
;; summary; the exit code is the number of failures (0 = green). Run with tests\run_tests.ps1.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\lib\ahk#.ahk

CS.Config.ShowErrorGui := false      ; a compile error must throw, never open a window
CS.Config.NuGetGui := false

global __tests := []
global __state := Map()              ; scratch space for callbacks (fat-arrow lambdas assign LOCALS in AHK v2)

Test(name, fn) {
    __tests.Push([name, fn])
}

Skip(name, why) {
    __tests.Push([name, "", why])
}

Eq(actual, expected, what := "") {
    if (String(actual) != String(expected))
        throw Error((what != "" ? what ": " : "") "expected [" String(expected) "] but got [" String(actual) "]", -2)
}

Near(actual, expected, eps := 0.000001) {
    if (Abs(actual - expected) > eps)
        throw Error("expected ~" expected " but got " actual, -2)
}

IsTrue(cond, what := "condition") {
    if !cond
        throw Error(what " was false", -2)
}

Has(text, needle, what := "text") {
    if !InStr(text, needle)
        throw Error(what " does not contain [" needle "]: " SubStr(text, 1, 200), -2)
}

; fn() must throw an Error whose message contains `needle`
Throws(fn, needle := "") {
    try
        fn()
    catch as e {
        if (needle != "" && !InStr(e.Message, needle))
            throw Error("threw, but the message lacks [" needle "]: " SubStr(e.Message, 1, 300), -2)
        return
    }
    throw Error("expected an error but nothing was thrown", -2)
}

; Wait (pumping messages) until cond() is true
WaitFor(cond, timeoutMs := 5000) {
    end := A_TickCount + timeoutMs
    while (A_TickCount < end) {
        if cond()
            return true
        Sleep(20)
    }
    return false
}

RunTests() {
    global __tests
    pass := fail := skip := 0
    FileAppend("TAP version 13`n1.." __tests.Length "`n", "*")
    for i, t in __tests {
        if (t.Length >= 3) {
            skip++
            FileAppend("ok " i " - " t[1] " # SKIP " t[3] "`n", "*")
            continue
        }
        try {
            t[2]()
            pass++
            FileAppend("ok " i " - " t[1] "`n", "*")
        } catch as e {
            fail++
            FileAppend("not ok " i " - " t[1] " # " StrReplace(StrReplace(e.Message, "`r", ""), "`n", " | ") "`n", "*")
        }
    }
    FileAppend("# pass=" pass " fail=" fail " skip=" skip "`n", "*")
    ExitApp(fail)
}
