;; AHK# SQLite Extension — Zero-dependency SQLite via winsqlite3.dll (Windows 10+)
;;
;;   db := SQLite()                                   ; ":memory:"  (or SQLite("C:\data\app.db"))
;;   db.Execute("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT, score REAL)")
;;   db.Execute("INSERT INTO t (name, score) VALUES (?, ?)", "ünïcode ✓", 9.5)
;;   for row in db.Query("SELECT name, score FROM t")   ; Array of Map, keyed by column name
;;       MsgBox row["name"] " = " row["score"]
;;   n := db.Scalar("SELECT COUNT(*) FROM t")
;;   db.Transaction(() => ...)                        ; commits, or rolls back if the function throws
;;
;; Text is UTF-8 in and out; parameters are bound with SQLITE_TRANSIENT (SQLite copies them).
;; NULL comes back as "".

#Requires AutoHotkey v2.0

class SQLite {
    __New(path := ":memory:") {
        bridge := _AhkSharpEngine.Boot()
        this._db := bridge.CreateInstance("PhantomSqlite", "")
        this._db.Open(path)
    }

    ; Runs a statement; returns the number of rows changed
    Execute(sql, params*) {
        if params.Length > 0
            return this._db.Execute(sql, _PackArgs(params))
        return this._db.ExecuteNonQuery(sql)
    }

    ; Array of Map (column name → value). One COM call returns the whole result set.
    Query(sql, params*) {
        raw := this._db.QueryRows(sql, params.Length > 0 ? _PackArgs(params) : "")
        return SQLite._ToRows(_SafeArrayToAHK(raw))
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

    ; [headers, row1, row2 ...] → [Map, Map ...]
    static _ToRows(table) {
        rows := []
        if (table.Length < 1)
            return rows
        headers := table[1]
        Loop table.Length - 1 {
            row := table[A_Index + 1]
            m := Map()
            for i, h in headers
                m[h] := row[i]
            rows.Push(m)
        }
        return rows
    }
}
