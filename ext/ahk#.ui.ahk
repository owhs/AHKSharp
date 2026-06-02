;; AHK# Native UI Extension — Embed .NET WinForms controls in AHK GUIs

#Requires AutoHotkey v2.0

class NativeUI {
    static _ui := ""

    static _GetUI() {
        if (this._ui == "") {
            bridge := _AhkSharpEngine.Boot()
            this._ui := bridge.CreateInstance("NativeUi", "")
        }
        return this._ui
    }

    static DataGridView(guiObj, x, y, w, h) {
        hwnd := guiObj is Gui ? guiObj.Hwnd : guiObj
        id := this._GetUI().CreateDataGridView(hwnd, x, y, w, h)
        return NativeControl(id, "DataGridView")
    }

    static Panel(guiObj, x, y, w, h) {
        hwnd := guiObj is Gui ? guiObj.Hwnd : guiObj
        id := this._GetUI().CreatePanel(hwnd, x, y, w, h)
        return NativeControl(id, "Panel")
    }

    static RichTextBox(guiObj, x, y, w, h) {
        hwnd := guiObj is Gui ? guiObj.Hwnd : guiObj
        id := this._GetUI().CreateRichTextBox(hwnd, x, y, w, h)
        return NativeControl(id, "RichTextBox")
    }
}

class NativeControl {
    __New(id, type) {
        this.DefineProp("_id", {Get: (*) => id})
        this.DefineProp("_type", {Get: (*) => type})
        _uiRef := NativeUI._GetUI()
        this.DefineProp("_ui", {Get: (*) => _uiRef})
    }

    AddColumn(name, headerText := "") {
        this._ui.DataGridAddColumn(this._id, name, headerText != "" ? headerText : name)
        return this
    }

    AddRow(values*) {
        this._ui.DataGridAddRow(this._id, _PackArgs(values))
        return this
    }

    Clear() {
        this._ui.DataGridClear(this._id)
        return this
    }

    GetCell(row, col) {
        return this._ui.DataGridGetCell(this._id, row, col)
    }

    Text {
        get => this._ui.GetText(this._id)
        set => this._ui.SetText(this._id, value)
    }

    __Set(name, params, value) {
        this._ui.SetProp(this._id, name, value)
    }

    Resize(x, y, w, h) {
        this._ui.Resize(this._id, x, y, w, h)
        return this
    }

    Destroy() {
        this._ui.Destroy(this._id)
    }
}
