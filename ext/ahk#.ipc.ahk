;; AHK# IPC Extension — Memory-Mapped File IPC

#Requires AutoHotkey v2.0

class SharedMemory {
    __New(name, sizeBytes := 1048576) {
        bridge := _AhkSharpEngine.Boot()
        this._ipc := bridge.CreateInstance("MemoryMappedIpc", "")
        this._ipc.Create(name, sizeBytes)
    }

    Write(data) {
        this._ipc.Write(data)
        return this
    }

    WriteBytes(data) {
        this._ipc.WriteBytes(data)
        return this
    }

    Read() {
        return this._ipc.Read()
    }

    ReadBytes() {
        return this._ipc.ReadBytes()
    }

    Length {
        get => this._ipc.DataLength
    }

    Capacity {
        get => this._ipc.Capacity
    }

    Clear() {
        this._ipc.Clear()
        return this
    }

    WriteAt(offset, data) {
        this._ipc.WriteAt(offset, data)
        return this
    }

    ReadAt(offset, length) {
        return this._ipc.ReadAt(offset, length)
    }

    OnChanged(callback, intervalMs := 50) {
        this._lastData := ""
        fn := ObjBindMethod(this, "_PollChange", callback)
        SetTimer(fn, intervalMs)
        return this
    }

    _PollChange(callback) {
        current := this.Read()
        if (current != this._lastData && current != "") {
            this._lastData := current
            callback(current)
        }
    }

    Close() {
        this._ipc.Dispose()
    }

    __Delete() {
        try this._ipc.Dispose()
    }
}
