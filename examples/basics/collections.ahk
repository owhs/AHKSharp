;; AHK# Example 04 — .NET Collections
;; Demonstrates using .NET collections (like List and Dictionary) from AHK

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

MsgBox("List count: " myList.Count "`nItem 1: " myList[0], "AHK# List Demo")

; 2. Using a .NET Dictionary<string, int>
MsgBox("Creating a .NET Dictionary<string, int>...", "AHK# Collections")

scores := CS.System.Collections.Generic.Dictionary(CS.System.String, CS.System.Int32)()

scores.Add("Alice", 95)
scores.Add("Bob", 82)
scores.Add("Charlie", 89)

aliceScore := scores["Alice"]
MsgBox("Alice's score is: " aliceScore, "AHK# Dictionary Demo")

ExitApp()
