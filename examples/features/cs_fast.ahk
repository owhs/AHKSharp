;; AHK# — CS.Fast: Parallel Map / Filter / Reduce
;; CS.Fast compiles a C# lambda body once and applies it to every element of an
;; AHK array on multiple threads (PLINQ). In the body, `x` is a C# dynamic, so
;; arithmetic like "x * 2" works without casts; Reduce also gets the running `acc`.
;;
;; Each element is dispatched through the bridge, so the payoff comes with
;; expensive per-item work; for cheap expressions a plain AHK loop is fine.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

; Join any array-like result (AHK Array or .NET array) into "a, b, c"
Join(items) {
    text := ""
    for item in items
        text .= (A_Index > 1 ? ", " : "") item
    return text
}

nums := []
Loop 20
    nums.Push(A_Index)

; ── Map: transform every element ─────────────────────────────────────────────
squares := CS.Fast.Map(nums, "x * x")
roots := CS.Fast.Map([1, 4, 9, 16, 25], "Math.Sqrt(x)")

; ── Filter: keep the elements for which the body is true ─────────────────────
evens := CS.Fast.Filter(nums, "x % 2 == 0")
big := CS.Fast.Filter(nums, "x > 15")

; ── Reduce: fold everything into one value (acc = running total, x = element) ─
total := CS.Fast.Reduce(nums, "acc + x", 0)
product := CS.Fast.Reduce([1, 2, 3, 4, 5], "acc * x", 1)

; ── Strings work too ─────────────────────────────────────────────────────────
shout := CS.Fast.Map(["apple", "banana", "cherry"], "x.ToUpper()")

MsgBox("Numbers: " Join(nums) "`n`n"
    . "Map     x * x         : " Join(squares) "`n"
    . "Map     Math.Sqrt(x)  : " Join(roots) "`n`n"
    . "Filter  x % 2 == 0    : " Join(evens) "`n"
    . "Filter  x > 15        : " Join(big) "`n`n"
    . "Reduce  acc + x  (0)  : " total "`n"
    . "Reduce  acc * x  (1)  : " product "`n`n"
    . "Map     x.ToUpper()   : " Join(shout)
    , "AHK# — CS.Fast", 0x40)

ExitApp()
