// AHK# Phantom SQLite — Zero-Dependency SQLite via winsqlite3.dll P/Invoke
// Uses the Windows 10+ built-in winsqlite3.dll — no external downloads needed.

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;

[ComVisible(true)]
[ClassInterface(ClassInterfaceType.AutoDual)]
[Guid("E1F7A5B6-C8D9-0123-EFAB-234567890123")]
[ProgId("AhkSharp.Sqlite")]
public class PhantomSqlite : IDisposable
{
    // ── SQLite P/Invoke into Windows' built-in winsqlite3.dll ─────────────
    private const string SQLITE_DLL = "winsqlite3.dll";

    [DllImport(SQLITE_DLL, CallingConvention = CallingConvention.Cdecl)]
    private static extern int sqlite3_open(byte[] filename, out IntPtr db);
    [DllImport(SQLITE_DLL, CallingConvention = CallingConvention.Cdecl)]
    private static extern int sqlite3_close(IntPtr db);
    [DllImport(SQLITE_DLL, CallingConvention = CallingConvention.Cdecl)]
    private static extern int sqlite3_prepare_v2(IntPtr db, byte[] sql, int nByte, out IntPtr stmt, out IntPtr tail);
    [DllImport(SQLITE_DLL, CallingConvention = CallingConvention.Cdecl)]
    private static extern int sqlite3_step(IntPtr stmt);
    [DllImport(SQLITE_DLL, CallingConvention = CallingConvention.Cdecl)]
    private static extern int sqlite3_finalize(IntPtr stmt);
    [DllImport(SQLITE_DLL, CallingConvention = CallingConvention.Cdecl)]
    private static extern int sqlite3_column_count(IntPtr stmt);
    [DllImport(SQLITE_DLL, CallingConvention = CallingConvention.Cdecl)]
    private static extern int sqlite3_column_type(IntPtr stmt, int col);
    [DllImport(SQLITE_DLL, CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr sqlite3_column_name(IntPtr stmt, int col);
    [DllImport(SQLITE_DLL, CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr sqlite3_column_text(IntPtr stmt, int col);
    [DllImport(SQLITE_DLL, CallingConvention = CallingConvention.Cdecl)]
    private static extern int sqlite3_column_int(IntPtr stmt, int col);
    [DllImport(SQLITE_DLL, CallingConvention = CallingConvention.Cdecl)]
    private static extern double sqlite3_column_double(IntPtr stmt, int col);
    [DllImport(SQLITE_DLL, CallingConvention = CallingConvention.Cdecl)]
    private static extern long sqlite3_column_int64(IntPtr stmt, int col);
    [DllImport(SQLITE_DLL, CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr sqlite3_errmsg(IntPtr db);
    [DllImport(SQLITE_DLL, CallingConvention = CallingConvention.Cdecl)]
    private static extern int sqlite3_bind_text(IntPtr stmt, int index, byte[] val, int n, IntPtr destructor);
    [DllImport(SQLITE_DLL, CallingConvention = CallingConvention.Cdecl)]
    private static extern int sqlite3_bind_int(IntPtr stmt, int index, int val);
    [DllImport(SQLITE_DLL, CallingConvention = CallingConvention.Cdecl)]
    private static extern int sqlite3_bind_double(IntPtr stmt, int index, double val);
    [DllImport(SQLITE_DLL, CallingConvention = CallingConvention.Cdecl)]
    private static extern int sqlite3_bind_int64(IntPtr stmt, int index, long val);
    [DllImport(SQLITE_DLL, CallingConvention = CallingConvention.Cdecl)]
    private static extern int sqlite3_bind_null(IntPtr stmt, int index);
    [DllImport(SQLITE_DLL, CallingConvention = CallingConvention.Cdecl)]
    private static extern int sqlite3_changes(IntPtr db);
    [DllImport(SQLITE_DLL, CallingConvention = CallingConvention.Cdecl)]
    private static extern long sqlite3_last_insert_rowid(IntPtr db);

    private const int SQLITE_OK = 0;
    private const int SQLITE_ROW = 100;
    private const int SQLITE_DONE = 101;
    private const int SQLITE_INTEGER = 1;
    private const int SQLITE_FLOAT = 2;
    private const int SQLITE_TEXT = 3;
    private const int SQLITE_BLOB = 4;
    private const int SQLITE_NULL = 5;

    // SQLite hands back UTF-8; Marshal.PtrToStringAnsi would mangle every non-ASCII character
    private static string Utf8(IntPtr p)
    {
        if (p == IntPtr.Zero) return null;
        int len = 0;
        while (Marshal.ReadByte(p, len) != 0) len++;
        byte[] bytes = new byte[len];
        Marshal.Copy(p, bytes, 0, len);
        return Encoding.UTF8.GetString(bytes);
    }

    // SQLITE_TRANSIENT: SQLite must COPY bound text — the managed buffer is unpinned as soon as the call returns
    private static readonly IntPtr SQLITE_TRANSIENT = new IntPtr(-1);

    private IntPtr _db;
    private bool _disposed;

    public PhantomSqlite() { _db = IntPtr.Zero; }

    /// <summary>Open a database file. Use ":memory:" for in-memory.</summary>
    public void Open(string path)
    {
        byte[] utf8Path = Encoding.UTF8.GetBytes(path + "\0");
        int rc = sqlite3_open(utf8Path, out _db);
        if (rc != SQLITE_OK)
            throw new InvalidOperationException("sqlite3_open failed: " + GetError());

        // Enable WAL mode for performance
        ExecuteNonQuery("PRAGMA journal_mode=WAL");
    }

    /// <summary>Execute a non-query SQL statement.</summary>
    public int ExecuteNonQuery(string sql)
    {
        IntPtr stmt;
        Prepare(sql, out stmt);
        try
        {
            int rc = sqlite3_step(stmt);
            if (rc != SQLITE_DONE && rc != SQLITE_ROW)
                throw new InvalidOperationException("SQL error: " + GetError());
            return sqlite3_changes(_db);
        }
        finally
        {
            sqlite3_finalize(stmt);
        }
    }

    /// <summary>Execute SQL with parameters. Params are bound positionally (?1, ?2, etc.)</summary>
    public int Execute(string sql, object args)
    {
        IntPtr stmt;
        Prepare(sql, out stmt);
        try
        {
            BindParams(stmt, args);
            int rc = sqlite3_step(stmt);
            if (rc != SQLITE_DONE && rc != SQLITE_ROW)
                throw new InvalidOperationException("SQL error: " + GetError());
            return sqlite3_changes(_db);
        }
        finally
        {
            sqlite3_finalize(stmt);
        }
    }

    /// <summary>
    /// Query and return results as a 2D string array.
    /// First row contains column names.
    /// </summary>
    public string[,] Query(string sql, object args)
    {
        IntPtr stmt;
        Prepare(sql, out stmt);
        try
        {
            BindParams(stmt, args);

            int colCount = sqlite3_column_count(stmt);
            var rows = new List<string[]>();

            // Column names
            string[] header = new string[colCount];
            for (int i = 0; i < colCount; i++)
                header[i] = Utf8(sqlite3_column_name(stmt, i)) ?? "";
            rows.Add(header);

            // Data rows
            while (sqlite3_step(stmt) == SQLITE_ROW)
            {
                string[] row = new string[colCount];
                for (int i = 0; i < colCount; i++)
                {
                    int type = sqlite3_column_type(stmt, i);
                    switch (type)
                    {
                        case SQLITE_NULL:
                            row[i] = null;
                            break;
                        case SQLITE_INTEGER:
                            row[i] = sqlite3_column_int64(stmt, i).ToString();
                            break;
                        case SQLITE_FLOAT:
                            row[i] = sqlite3_column_double(stmt, i).ToString("R", CultureInfo.InvariantCulture);
                            break;
                        default:
                            IntPtr textPtr = sqlite3_column_text(stmt, i);
                            row[i] = textPtr != IntPtr.Zero ? Utf8(textPtr) : "";
                            break;
                    }
                }
                rows.Add(row);
            }

            // Convert to 2D array
            string[,] result = new string[rows.Count, colCount];
            for (int r = 0; r < rows.Count; r++)
                for (int c = 0; c < colCount; c++)
                    result[r, c] = rows[r][c];

            return result;
        }
        finally
        {
            sqlite3_finalize(stmt);
        }
    }

    /// <summary>
    /// Query and return the result as object[]: element 0 is the column-name string[], the rest are the
    /// rows (string[], NULL = null). One COM call, read straight out of memory by ext\ahk#.sqlite.ahk.
    /// </summary>
    public object[] QueryRows(string sql, object args)
    {
        string[,] grid = Query(sql, args);
        int rows = grid.GetLength(0), cols = grid.GetLength(1);
        object[] result = new object[rows];
        for (int r = 0; r < rows; r++)
        {
            string[] row = new string[cols];
            for (int c = 0; c < cols; c++) row[c] = grid[r, c];
            result[r] = row;
        }
        return result;
    }

    /// <summary>Query returning just a single scalar value.</summary>
    public string QueryScalar(string sql, object args)
    {
        IntPtr stmt;
        Prepare(sql, out stmt);
        try
        {
            BindParams(stmt, args);
            if (sqlite3_step(stmt) == SQLITE_ROW)
            {
                IntPtr textPtr = sqlite3_column_text(stmt, 0);
                return textPtr != IntPtr.Zero ? Utf8(textPtr) : "";
            }
            return null;
        }
        finally
        {
            sqlite3_finalize(stmt);
        }
    }

    /// <summary>Get last insert rowid.</summary>
    public long LastInsertId { get { return sqlite3_last_insert_rowid(_db); } }

    /// <summary>Begin a transaction.</summary>
    public void BeginTransaction() { ExecuteNonQuery("BEGIN TRANSACTION"); }

    /// <summary>Commit a transaction.</summary>
    public void Commit() { ExecuteNonQuery("COMMIT"); }

    /// <summary>Rollback a transaction.</summary>
    public void Rollback() { ExecuteNonQuery("ROLLBACK"); }

    // ── Internal Helpers ──────────────────────────────────────────────────

    private void Prepare(string sql, out IntPtr stmt)
    {
        byte[] utf8Sql = Encoding.UTF8.GetBytes(sql + "\0");
        IntPtr tail;
        int rc = sqlite3_prepare_v2(_db, utf8Sql, utf8Sql.Length, out stmt, out tail);
        if (rc != SQLITE_OK)
            throw new InvalidOperationException("Prepare failed: " + GetError() + "\nSQL: " + sql);
    }

    private void BindParams(IntPtr stmt, object args)
    {
        if (args == null || args is DBNull) return;

        if (args is object[])
        {
            object[] arr = (object[])args;
            for (int i = 0; i < arr.Length; i++)
                BindValue(stmt, i + 1, arr[i]);
        }
        else if (args is Array)
        {
            Array arr = (Array)args;
            for (int i = 0; i < arr.Length; i++)
                BindValue(stmt, i + 1, arr.GetValue(i));
        }
        else
        {
            BindValue(stmt, 1, args);
        }
    }

    private void BindValue(IntPtr stmt, int index, object value)
    {
        if (value == null || value is DBNull)
            sqlite3_bind_null(stmt, index);
        else if (value is int)
            sqlite3_bind_int(stmt, index, (int)value);
        else if (value is long)
            sqlite3_bind_int64(stmt, index, (long)value);
        else if (value is double || value is float)
            sqlite3_bind_double(stmt, index, Convert.ToDouble(value));
        else
        {
            byte[] utf8 = Encoding.UTF8.GetBytes(value.ToString() + "\0");
            sqlite3_bind_text(stmt, index, utf8, utf8.Length - 1, SQLITE_TRANSIENT);
        }
    }

    private string GetError()
    {
        if (_db == IntPtr.Zero) return "Database not open";
        IntPtr errPtr = sqlite3_errmsg(_db);
        return errPtr != IntPtr.Zero ? Utf8(errPtr) : "Unknown error";
    }

    public void Dispose()
    {
        if (!_disposed && _db != IntPtr.Zero)
        {
            sqlite3_close(_db);
            _db = IntPtr.Zero;
            _disposed = true;
        }
    }
}
