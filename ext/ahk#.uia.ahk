;; AHK# UIA Extension — High-performance UIAutomation tree crawling
;;
;;   elements := UIA2.CrawlTree(WinExist("A"), 5)      ; Array of UIAElement (1-based), depth-limited
;;   for el in elements
;;       MsgBox el.ControlType ": " el.Name
;;   buttons := UIA2.Find(hwnd, "ControlType=Button", 10)
;;   el := UIA2.FromPoint(x, y)                        ; a UIAElement, or "" when nothing is there
;;
;; The whole tree walk runs in C# (CacheRequest batch fetch) and comes back in ONE COM call as
;; plain rows — reading a 10,000-element tree is milliseconds, not one COM call per property.

#Requires AutoHotkey v2.0

; One UI element: plain AHK properties (Name, AutomationId, ClassName, ControlType, LocalizedControlType,
; ProcessId, NativeWindowHandle, BoundingX/Y/W/H, IsEnabled, IsOffscreen, Value, Depth, ChildCount).
class UIAElement {
    static _fields := ["Name", "AutomationId", "ClassName", "ControlType", "LocalizedControlType", "ProcessId"
        , "NativeWindowHandle", "BoundingX", "BoundingY", "BoundingW", "BoundingH", "IsEnabled", "IsOffscreen"
        , "Value", "Depth", "ChildCount"]

    static FromRow(row) {
        el := UIAElement()
        for i, name in UIAElement._fields
            el.%name% := row[i]
        return el
    }

    ToString() => "[" this.ControlType "] " this.Name " (id=" this.AutomationId ", class=" this.ClassName ")"
}

class UIA2 {
    static _crawler := ""

    static _GetCrawler() {
        if (this._crawler == "") {
            bridge := _AhkSharpEngine.Boot()
            this._crawler := bridge.CreateInstance("UiaDeepCrawler", "")
        }
        return this._crawler
    }

    ; rows (from C#) → Array of UIAElement
    static _Elements(raw) {
        out := []
        for row in _SafeArrayToAHK(raw)
            out.Push(UIAElement.FromRow(row))
        return out
    }

    static _Element(raw) {
        if !(raw is ComObjArray)
            return ""
        return UIAElement.FromRow(_SafeArrayToAHK(raw))
    }

    static CrawlTree(hwnd := 0, maxDepth := 50) {
        return this._Elements(this._GetCrawler().CrawlWindowRows(hwnd, maxDepth))
    }

    ; condition: "ControlType=Button", "Name=OK" (substring), "AutomationId=btnSubmit", "ClassName=Edit"
    static Find(hwnd, condition, maxDepth := 50) {
        return this._Elements(this._GetCrawler().FindElementRows(hwnd, condition, maxDepth))
    }

    static FromPoint(x, y) {
        return this._Element(this._GetCrawler().ElementFromPointRow(x, y))
    }

    static Focused() {
        return this._Element(this._GetCrawler().FocusedElementRow())
    }

    static Invoke(hwnd, automationId) {
        return this._GetCrawler().InvokeElement(hwnd, automationId)
    }

    static SetValue(hwnd, automationId, value) {
        return this._GetCrawler().SetValue(hwnd, automationId, value)
    }
}
