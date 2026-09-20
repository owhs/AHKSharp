#Requires AutoHotkey v2.0
#SingleInstance Force

; Target process for the memory_bridge.ahk example: exposes three in-memory values
; (Int32 health, Int32 ammo, Float gold) whose addresses are shown in the window.
; Errors are logged to A_Temp but NOT swallowed - AutoHotkey still shows its normal dialog.
OnError(LogError)
LogError(exception, mode) {
    try FileAppend("CRASH " A_Now ": " exception.Message "`n" exception.Extra "`n" exception.File ":" exception.Line "`n`n", A_Temp "\memory_target_mock_crash.log")
    return 0   ; 0 = continue with the default error handling (do not suppress the error)
}

; Create stable memory buffers for three game variables
healthBuf := Buffer(4, 0)
NumPut("Int", 100, healthBuf)

ammoBuf := Buffer(4, 0)
NumPut("Int", 30, ammoBuf)

goldBuf := Buffer(4, 0)
NumPut("Float", 250.75, goldBuf)

; GUI to display addresses and values
g := Gui("+AlwaysOnTop", "AHK# — Process Memory Target Mock")
g.BackColor := "0x11111b"
g.SetFont("s10 cCDD6F4", "Segoe UI")

g.SetFont("s12 cA6E3A1 Bold")
g.Add("Text", "x10 y10 w380 Center", "🎮 Target Game Mock Process 🎮")
g.SetFont("s10 cCDD6F4 Norm")

g.Add("Text", "x20 y50 w100", "Health (Int32):")
hAddr := g.Add("Edit", "x130 y48 w100 ReadOnly Background313244 cCDD6F4", Format("0x{:X}", healthBuf.Ptr))
hVal  := g.Add("Edit", "x240 y48 w60 ReadOnly Center Background313244 cCDD6F4", "100")
btnH  := g.Add("Button", "x310 y46 w70 h26", "+10 HP")

g.Add("Text", "x20 y90 w100", "Ammo (Int32):")
aAddr := g.Add("Edit", "x130 y88 w100 ReadOnly Background313244 cCDD6F4", Format("0x{:X}", ammoBuf.Ptr))
aVal  := g.Add("Edit", "x240 y88 w60 ReadOnly Center Background313244 cCDD6F4", "30")
btnA  := g.Add("Button", "x310 y86 w70 h26", "-1 Ammo")

g.Add("Text", "x20 y130 w100", "Gold (Float):")
gAddr := g.Add("Edit", "x130 y128 w100 ReadOnly Background313244 cCDD6F4", Format("0x{:X}", goldBuf.Ptr))
gVal  := g.Add("Edit", "x240 y128 w60 ReadOnly Center Background313244 cCDD6F4", "250.75")
btnG  := g.Add("Button", "x310 y126 w70 h26", "+100 Gold")

; Event Handlers
btnH.OnEvent("Click", HPClick)
btnA.OnEvent("Click", AmmoClick)
btnG.OnEvent("Click", GoldClick)

HPClick(*) {
    val := NumGet(healthBuf, 0, "Int") + 10
    NumPut("Int", val, healthBuf)
    hVal.Value := val
}

AmmoClick(*) {
    val := NumGet(ammoBuf, 0, "Int") - 1
    NumPut("Int", val, ammoBuf)
    aVal.Value := val
}

GoldClick(*) {
    val := NumGet(goldBuf, 0, "Float") + 100.0
    NumPut("Float", val, goldBuf)
    gVal.Value := String(val)
}

; Refresh display periodically to see memory edits made by Cheat Engine clone
SetTimer(RefreshDisplay, 250)
RefreshDisplay() {
    hVal.Value := NumGet(healthBuf, 0, "Int")
    aVal.Value := NumGet(ammoBuf, 0, "Int")
    gVal.Value := Format("{:.2f}", NumGet(goldBuf, 0, "Float"))
}

g.OnEvent("Close", (*) => ExitApp())
g.Show("w400 h180")
