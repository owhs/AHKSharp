;; AHK# — .NET Collections
;; Demonstrates using .NET collections (like List and Dictionary) from AHK:
;; indexing, for-in loops, and converting them to native AHK Array / Map with .ToAHK().

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

; 1. Using a .NET List<string>
MsgBox("Creating a .NET List<string>...", "AHK# Collections")

; Create a generic List<string>
myList := CS.System.Collections.Generic.List(CS.System.String)()

myList.Add("Apple")
myList.Add("Banana")
myList.Add("Cherry")

; .NET indexes start at 0
MsgBox("List count: " myList.Count "`nFirst item (index 0): " myList[0], "AHK# List Demo")

; A .NET collection works in a for-in loop
fruitText := ""
for fruit in myList
    fruitText .= A_Index ". " fruit "`n"
MsgBox("Looping over the List:`n`n" fruitText, "AHK# List Demo — for-in")

; .ToAHK() copies it into a native AHK Array (AHK indexes start at 1)
fruits := myList.ToAHK()
MsgBox("As an AHK Array:`nLength: " fruits.Length "`nfruits[1]: " fruits[1] "`nfruits[3]: " fruits[3]
    , "AHK# List Demo — ToAHK()")

; 2. Using a .NET Dictionary<string, int>
MsgBox("Creating a .NET Dictionary<string, int>...", "AHK# Collections")

scores := CS.System.Collections.Generic.Dictionary(CS.System.String, CS.System.Int32)()

scores.Add("Alice", 95)
scores.Add("Bob", 82)
scores.Add("Charlie", 89)

aliceScore := scores["Alice"]
MsgBox("Alice's score is: " aliceScore, "AHK# Dictionary Demo")

; .ToAHK() on a dictionary gives an AHK Map
scoreMap := scores.ToAHK()
scoreText := ""
for name, score in scoreMap
    scoreText .= name ": " score "`n"
MsgBox("As an AHK Map (" scoreMap.Count " entries):`n`n" scoreText, "AHK# Dictionary Demo — ToAHK()")

ExitApp()
