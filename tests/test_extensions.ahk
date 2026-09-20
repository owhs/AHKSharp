#Include harness.ahk
#Include ..\ext\ahk#.http.ahk
#Include ..\ext\ahk#.sqlite.ahk
#Include ..\ext\ahk#.ipc.ahk
#Include ..\ext\ahk#.uia.ahk

; ── Json ──────────────────────────────────────────────────────────────────────
doc := '{"a":{"b":[10,20,{"c":"deep"}]},"n":5}'
Test("Json.Query walks objects and arrays", () => Eq(Json.Query(doc, "a.b.2.c"), "deep"))
Test("Json.Query scalar", () => Eq(Json.Query(doc, "n"), 5))
Test("Json.IsValid", () => (Eq(Json.IsValid(doc), 1), Eq(Json.IsValid("{oops"), 0)))
Test("Json.Build packs key/value pairs", () => Has(Json.Build("k1", "v1", "k2", 2), '"k2":2'))

; ── SQLite ────────────────────────────────────────────────────────────────────
Test("SQLite: create / insert with params / query / scalar", () => _sqliteBasics())
Test("SQLite: a failing Transaction rolls back", () => _sqliteRollback())

_sqliteBasics() {
    db := SQLite()
    db.Execute("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT, score REAL)")
    db.Execute("INSERT INTO t (name, score) VALUES (?, ?)", "alice", 9.5)
    db.Execute("INSERT INTO t (name, score) VALUES (?, ?)", "bob", 7)
    Eq(db.LastId, 2)
    rows := db.Query("SELECT name, score FROM t ORDER BY id")
    Eq(rows.Length, 2)
    Eq(rows[1]["name"], "alice")
    Near(rows[1]["score"], 9.5)
    Eq(db.Scalar("SELECT COUNT(*) FROM t"), 2)
    db.Close()
}

_sqliteRollback() {
    global __state
    db := SQLite()
    db.Execute("CREATE TABLE t (name TEXT)")
    __state["db"] := db
    try db.Transaction(_failingTx)
    catch as e
        Eq(e.Message, "boom")
    Eq(db.Scalar("SELECT COUNT(*) FROM t"), 0)
    db.Close()
}

_failingTx() {
    global __state
    __state["db"].Execute("INSERT INTO t (name) VALUES (?)", "carol")
    throw Error("boom")
}

Test("SQLite: non-ASCII text and column names round-trip (UTF-8)", () => _sqliteUnicode())
Test("SQLite: NULL, quotes, and a 2000-row transaction", () => _sqliteEdge())

_sqliteUnicode() {
    db := SQLite()
    db.Execute("CREATE TABLE u (s TEXT)")
    db.Execute("INSERT INTO u VALUES (?)", "héllo wörld 日本語 ✓")
    Eq(db.Query("SELECT s FROM u")[1]["s"], "héllo wörld 日本語 ✓")
    Eq(db.Scalar("SELECT s FROM u"), "héllo wörld 日本語 ✓")
    db.Execute('CREATE TABLE v ("naïve" INTEGER)')
    db.Execute("INSERT INTO v VALUES (5)")
    Eq(db.Query("SELECT * FROM v")[1]["naïve"], 5)
    db.Close()
}

_sqliteEdge() {
    db := SQLite()
    db.Execute("CREATE TABLE t (id INTEGER, s TEXT)")
    db.Execute("INSERT INTO t VALUES (1, NULL)")
    Eq(db.Query("SELECT s FROM t")[1]["s"], "")
    hostile := "O'Brien; DROP TABLE t;--"
    db.Execute("INSERT INTO t VALUES (2, ?)", hostile)
    Eq(db.Scalar("SELECT s FROM t WHERE id = 2"), hostile)
    Eq(db.Scalar("SELECT COUNT(*) FROM t"), 2)             ; the table survived
    db.Transaction(_bulkInsert.Bind(db))
    Eq(db.Scalar("SELECT COUNT(*) FROM t"), 2002)
    Eq(db.Scalar("SELECT SUM(id) FROM t WHERE id >= 100"), 1998051)   ; ids 100..2001
    Eq(db.Query("SELECT id FROM t WHERE id > 1990 ORDER BY id").Length, 11)
    db.Close()
}

_bulkInsert(db) {
    Loop 2000
        db.Execute("INSERT INTO t VALUES (?, ?)", A_Index + 1, "row " A_Index)
}

; ── UIA (reads the desktop's top-level windows: no windows are created) ───────
Test("UIA2.CrawlTree returns an Array of UIAElement", () => (
    els := UIA2.CrawlTree(0, 1), IsTrue(els.Length >= 1, "at least one element"),
    Eq(els[1].Depth, 0), IsTrue(HasProp(els[1], "ControlType"), "ControlType property"), IsTrue(HasProp(els[1], "BoundingW"), "bounds")))
Test("UIA2.Find filters by property", () => (
    all := UIA2.CrawlTree(0, 1), one := UIA2.Find(0, "ControlType=" all[1].ControlType, 1),
    IsTrue(one.Length >= 1, "matches"), Eq(one[1].ControlType, all[1].ControlType)))
Test("UIA2.FromPoint gives a UIAElement or an empty string", () => (
    el := UIA2.FromPoint(1, 1), IsTrue(el == "" || HasProp(el, "Name"), "shape")))
; ── shared memory ─────────────────────────────────────────────────────────────
Test("SharedMemory text round trip", () => (
    shm := SharedMemory("AhkSharpTest" A_TickCount, 4096), shm.Write("hello ipc"),
    Eq(shm.Read(), "hello ipc"), Eq(shm.Length, 9), shm.Close()))
Test("SharedMemory bytes: Buffer / byte[] proxy in, Buffer out", () => (
    shm := SharedMemory("AhkSharpTestB" A_TickCount, 4096),
    shm.WriteBytes(CS.System.Text.Encoding.ASCII.GetBytes("ABC")), b := shm.ReadBytes(),
    Eq(NumGet(b, 0, "UChar"), 65), Eq(b.Size, 3), shm.Close()))

; ── network (opt-in: set AHKSHARP_NET=1) ──────────────────────────────────────
if (EnvGet("AHKSHARP_NET") == "1") {
    Test("Http.Get over https (TLS 1.2 enabled process-wide)", () => IsTrue(StrLen(Http.Get("https://api.nuget.org/v3-flatcontainer/newtonsoft.json/index.json")) > 100, "body"))
    Test("Http.Get to a dead port throws", () => Throws(() => Http.Get("http://localhost:1/nothing"), "Http.Get() failed"))
    Test("NuGet.Require returns the package DLLs", () => IsTrue(InStr(CS.NuGet.Require("Newtonsoft.Json", "13.0.3"), "Newtonsoft.Json.dll"), "refs"))
    Test("NuGet package hashes verify against nuget.org; a corrupted file is caught", () => _nugetHash())
    Test("NuGet.Install of a missing package throws", () => Throws(() => CS.NuGet.Install("this-package-does-not-exist-zzz", "1.0.0"), "failed"))
} else
    Skip("network tests (Http, NuGet)", "set AHKSHARP_NET=1 to run")

_nugetHash() {
    bridge := _AhkSharpEngine.Boot()
    file := A_Temp "\ahksharp_pkg_" A_TickCount ".nupkg"
    Download("https://api.nuget.org/v3-flatcontainer/newtonsoft.json/13.0.3/newtonsoft.json.13.0.3.nupkg", file)
    Has(bridge.NuGetVerify("Newtonsoft.Json", "13.0.3", file), "verified sha512")
    f := FileOpen(file, "rw")
    f.Pos := 1000
    b := f.ReadUChar()
    f.Pos := 1000
    f.WriteUChar(b ^ 0xFF)
    f.Close()
    Has(bridge.NuGetVerify("Newtonsoft.Json", "13.0.3", file), "mismatch")
    try FileDelete(file)
}

RunTests()