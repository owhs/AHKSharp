#Include harness.ahk

; ── struct results stay objects (they can be passed back to .NET) ─────────────
Test("CancellationToken (a struct) passes back into Task.Delay", () => (
    cts := CS.System.Threading.CancellationTokenSource(),
    CS.System.Threading.Tasks.Task.Delay(30, cts.Token).Await(3000), true))
Test("a cancelled token cancels the Task", () => (
    cts := CS.System.Threading.CancellationTokenSource(), cts.Cancel(),
    Throws(() => CS.System.Threading.Tasks.Task.Delay(5000, cts.Token).Await(3000), "cancel")))
Test("a struct property result keeps its members (Rectangle.Location.X)", () => (
    rect := CS.System.Drawing.Rectangle(1, 2, 30, 40), loc := rect.Location, Eq(loc.X, 1), Eq(loc.Y, 2)))
Test("struct fields can be read and the struct passed back", () => (
    p := CS.System.Drawing.Point(3, 4), Eq(p.X, 3), Eq(CS.System.Drawing.Point.Add(p, CS.System.Drawing.Size(1, 1)).X, 4)))
Test("Guid / TimeSpan / enums still come back as strings", () => (
    Eq(Type(CS.System.Guid.NewGuid()), "String"), Eq(Type(CS.System.TimeSpan.FromSeconds(5)), "String"), Eq(CS.System.DayOfWeek.Friday, "Friday")))

; ── multi-dimensional indexers ────────────────────────────────────────────────
Test("matrix[row, col] read and write on a 2-D array", () => (
    m := CS.System.Array.CreateInstance(CS.System.Int32, 2, 3), m[1, 2] := 7, m[0, 0] := 1,
    Eq(m[1, 2], 7), Eq(m[0, 0], 1), Eq(m[0, 2], 0)))
Test("wrong index count reports the problem", () => (
    m := CS.System.Array.CreateInstance(CS.System.Int32, 2, 3), Throws(() => m[1, 2, 3], "indexer")))

; ── explicit generic arguments ────────────────────────────────────────────────
Test("Enumerable.Empty<int>()", () => Eq(CS.CallGeneric(CS.System.Linq.Enumerable, "Empty", CS.System.Int32).ToAHK().Length, 0))
Test("Activator.CreateInstance<StringBuilder>()", () => (
    sb := CS.CallGeneric(CS.System.Activator, "CreateInstance", [CS.System.Text.StringBuilder]), sb.Append("ok"), Eq(sb.ToString(), "ok")))
Test("a wrong number of type arguments is reported", () => Throws(() => CS.CallGeneric(CS.System.Linq.Enumerable, "Empty", [CS.System.Int32, CS.System.Int32]), "No generic overload"))

; ── CS.Run: multi-statement C# ────────────────────────────────────────────────
Test("CS.Run executes statements and returns a value", () => Eq(CS.Run("int s = 0; for (int i = 1; i <= 10; i++) s += i; return s;"), 55))
Test("CS.Run without a return gives an empty result", () => Eq(CS.Run("int x = 1; x++;"), ""))
Test("CS.Run reports compiler errors", () => Throws(() => CS.Run("return @@@;"), "CS.Run"))

; ── static events ─────────────────────────────────────────────────────────────
Test("static events: On / Off on a type", () => (
    start := CS.Stats()["Delegates"],
    CS.System.Console.On("CancelKeyPress", (e, sender) => 1),
    Eq(CS.Stats()["Delegates"], start + 1, "registered"),
    CS.System.Console.Off("CancelKeyPress"),
    Eq(CS.Stats()["Delegates"], start, "unregistered")))
Test("On on a type with no such static event says so", () => Throws(() => CS.System.Math.On("Nope", (*) => 1), "Nope"))

RunTests()
