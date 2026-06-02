;; AHK# SQLite Extension — Zero-dependency SQLite via winsqlite3.dll

#Requires AutoHotkey v2.0

class SQLite {
    __New(path := ":memory:") {
        bridge := _AhkSharpEngine.Boot()
        this._db := bridge.CreateInstance("PhantomSqlite", "")
        this._db.Open(path)
    }

    Execute(sql, params*) {
        if params.Length > 0
            return this._db.Execute(sql, _PackArgs(params))
        return this._db.ExecuteNonQuery(sql)
    }

    Query(sql, params*) {
        raw := this._db.Query(sql, params.Length > 0 ? _PackArgs(params) : "")
        return this._ParseQueryResult(raw)
    }

    Scalar(sql, params*) {
        return this._db.QueryScalar(sql, params.Length > 0 ? _PackArgs(params) : "")
    }

    Transaction(fn) {
        this._db.BeginTransaction()
        try {
            fn()
            this._db.Commit()
        } catch as e {
            this._db.Rollback()
            throw e
        }
    }

    LastId {
        get => this._db.LastInsertId
    }

    Close() {
        this._db.Dispose()
    }

    __Delete() {
        try this._db.Dispose()
    }

    _ParseQueryResult(raw) {
        results := []
        if !IsObject(raw)
            return results
        try {
            ; Probe column count by reading row 0 until error
            colCount := 0
            Loop {
                try {
                    raw[0, A_Index - 1]
                    colCount++
                } catch
                    break
            }
            if (colCount = 0)
                return results

            ; Read headers from row 0
            headers := []
            Loop colCount
                headers.Push(raw[0, A_Index - 1])

            ; Read data rows starting from row 1 until error
            rowIdx := 1
            Loop {
                try {
                    raw[rowIdx, 0]  ; probe if row exists
                } catch
                    break
                rowMap := Map()
                Loop colCount {
                    col := A_Index - 1
                    try
                        rowMap[headers[col + 1]] := raw[rowIdx, col]
                    catch
                        rowMap[headers[col + 1]] := ""
                }
                results.Push(rowMap)
                rowIdx++
            }
        }
        return results
    }
}
