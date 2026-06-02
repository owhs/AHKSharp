;; AHK# UIA Extension — High-performance UIAutomation tree crawling

#Requires AutoHotkey v2.0

class UIA2 {
    static _crawler := ""

    static _GetCrawler() {
        if (this._crawler == "") {
            bridge := _AhkSharpEngine.Boot()
            this._crawler := bridge.CreateInstance("UiaDeepCrawler", "")
        }
        return this._crawler
    }

    static CrawlTree(hwnd := 0, maxDepth := 50) {
        return this._GetCrawler().CrawlWindow(hwnd, maxDepth)
    }

    static Find(hwnd, condition, maxDepth := 50) {
        return this._GetCrawler().FindElements(hwnd, condition, maxDepth)
    }

    static FromPoint(x, y) {
        return _CSProxy(this._GetCrawler().ElementFromPoint(x, y))
    }

    static Focused() {
        return _CSProxy(this._GetCrawler().FocusedElement())
    }

    static Invoke(hwnd, automationId) {
        return this._GetCrawler().InvokeElement(hwnd, automationId)
    }

    static SetValue(hwnd, automationId, value) {
        return this._GetCrawler().SetValue(hwnd, automationId, value)
    }
}
