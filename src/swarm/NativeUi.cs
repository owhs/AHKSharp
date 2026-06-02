// AHK# Native UI — Embed .NET WinForms controls into AHK GUI windows
// Creates DataGridView, Chart, and other controls parented to AHK Gui hwnds.

using System;
using System.Collections.Generic;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

[ComVisible(true)]
[ClassInterface(ClassInterfaceType.AutoDual)]
[Guid("F2A8B6C7-D9E0-1234-FABC-345678901234")]
[ProgId("AhkSharp.NativeUi")]
public class NativeUi
{
    [DllImport("user32.dll")]
    private static extern IntPtr SetParent(IntPtr hWndChild, IntPtr hWndNewParent);
    [DllImport("user32.dll")]
    private static extern bool MoveWindow(IntPtr hWnd, int x, int y, int w, int h, bool repaint);
    [DllImport("user32.dll")]
    private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
    [DllImport("user32.dll")]
    private static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")]
    private static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    private const int GWL_STYLE = -16;
    private const int WS_CHILD = 0x40000000;
    private const int WS_VISIBLE = 0x10000000;

    private static readonly Dictionary<int, Control> _controls = new Dictionary<int, Control>();
    private static int _nextId = 1;

    /// <summary>
    /// Create a DataGridView parented to an AHK GUI window.
    /// Returns a control ID for subsequent manipulation.
    /// </summary>
    public int CreateDataGridView(long parentHwnd, int x, int y, int w, int h)
    {
        var dgv = new DataGridView();
        dgv.Location = new Point(x, y);
        dgv.Size = new Size(w, h);
        dgv.BorderStyle = BorderStyle.None;
        dgv.BackgroundColor = Color.FromArgb(30, 30, 40);
        dgv.ForeColor = Color.White;
        dgv.GridColor = Color.FromArgb(60, 60, 80);
        dgv.DefaultCellStyle.BackColor = Color.FromArgb(30, 30, 40);
        dgv.DefaultCellStyle.ForeColor = Color.White;
        dgv.DefaultCellStyle.SelectionBackColor = Color.FromArgb(80, 100, 180);
        dgv.ColumnHeadersDefaultCellStyle.BackColor = Color.FromArgb(40, 40, 55);
        dgv.ColumnHeadersDefaultCellStyle.ForeColor = Color.White;
        dgv.EnableHeadersVisualStyles = false;
        dgv.RowHeadersVisible = false;
        dgv.AllowUserToAddRows = false;
        dgv.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill;

        return EmbedControl(dgv, (IntPtr)parentHwnd);
    }

    /// <summary>Add a column to a DataGridView.</summary>
    public void DataGridAddColumn(int controlId, string name, string headerText)
    {
        var dgv = GetControl<DataGridView>(controlId);
        dgv.Columns.Add(name, headerText);
    }

    /// <summary>Add a row to a DataGridView.</summary>
    public void DataGridAddRow(int controlId, object values)
    {
        var dgv = GetControl<DataGridView>(controlId);
        object[] vals = values is object[] ? (object[])values : new[] { values };
        dgv.Rows.Add(vals);
    }

    /// <summary>Clear all rows from a DataGridView.</summary>
    public void DataGridClear(int controlId)
    {
        var dgv = GetControl<DataGridView>(controlId);
        dgv.Rows.Clear();
    }

    /// <summary>Get cell value from DataGridView.</summary>
    public string DataGridGetCell(int controlId, int row, int col)
    {
        var dgv = GetControl<DataGridView>(controlId);
        object val = dgv.Rows[row].Cells[col].Value;
        return val != null ? val.ToString() : "";
    }

    /// <summary>Create a Panel with dark styling.</summary>
    public int CreatePanel(long parentHwnd, int x, int y, int w, int h)
    {
        var panel = new Panel();
        panel.Location = new Point(x, y);
        panel.Size = new Size(w, h);
        panel.BackColor = Color.FromArgb(25, 25, 35);
        panel.BorderStyle = BorderStyle.None;
        return EmbedControl(panel, (IntPtr)parentHwnd);
    }

    /// <summary>Create a RichTextBox with dark styling.</summary>
    public int CreateRichTextBox(long parentHwnd, int x, int y, int w, int h)
    {
        var rtb = new RichTextBox();
        rtb.Location = new Point(x, y);
        rtb.Size = new Size(w, h);
        rtb.BackColor = Color.FromArgb(30, 30, 40);
        rtb.ForeColor = Color.FromArgb(220, 220, 220);
        rtb.Font = new Font("Cascadia Code", 10f);
        rtb.BorderStyle = BorderStyle.None;
        rtb.DetectUrls = false;
        return EmbedControl(rtb, (IntPtr)parentHwnd);
    }

    /// <summary>Set text on a RichTextBox or other control.</summary>
    public void SetText(int controlId, string text)
    {
        Control ctrl;
        if (_controls.TryGetValue(controlId, out ctrl))
            ctrl.Text = text;
    }

    /// <summary>Get text from a control.</summary>
    public string GetText(int controlId)
    {
        Control ctrl;
        if (_controls.TryGetValue(controlId, out ctrl))
            return ctrl.Text;
        return "";
    }

    /// <summary>Set a property on any embedded control via reflection.</summary>
    public void SetProp(int controlId, string propName, object value)
    {
        Control ctrl;
        if (!_controls.TryGetValue(controlId, out ctrl))
            throw new InvalidOperationException("Control not found: " + controlId);

        var prop = ctrl.GetType().GetProperty(propName);
        if (prop != null)
        {
            object converted = value;
            if (prop.PropertyType == typeof(Color) && value is string)
                converted = ColorTranslator.FromHtml((string)value);
            else if (prop.PropertyType == typeof(Font) && value is string)
                converted = new Font((string)value, ctrl.Font.Size);
            else
                converted = Convert.ChangeType(value, prop.PropertyType);
            prop.SetValue(ctrl, converted, null);
        }
    }

    /// <summary>Resize an embedded control.</summary>
    public void Resize(int controlId, int x, int y, int w, int h)
    {
        Control ctrl;
        if (_controls.TryGetValue(controlId, out ctrl))
        {
            ctrl.Location = new Point(x, y);
            ctrl.Size = new Size(w, h);
        }
    }

    /// <summary>Destroy an embedded control.</summary>
    public void Destroy(int controlId)
    {
        Control ctrl;
        if (_controls.TryGetValue(controlId, out ctrl))
        {
            ctrl.Dispose();
            _controls.Remove(controlId);
        }
    }

    // ── Internal ──────────────────────────────────────────────────────────

    private int EmbedControl(Control ctrl, IntPtr parentHwnd)
    {
        // Force control handle creation
        ctrl.CreateControl();
        IntPtr ctrlHwnd = ctrl.Handle;

        // Reparent into the AHK GUI window
        int style = GetWindowLong(ctrlHwnd, GWL_STYLE);
        SetWindowLong(ctrlHwnd, GWL_STYLE, (int)((style | WS_CHILD | WS_VISIBLE) & ~0x80000000));
        SetParent(ctrlHwnd, parentHwnd);
        MoveWindow(ctrlHwnd, ctrl.Location.X, ctrl.Location.Y, ctrl.Size.Width, ctrl.Size.Height, true);
        ctrl.Visible = true;

        int id = _nextId++;
        _controls[id] = ctrl;
        return id;
    }

    private T GetControl<T>(int id) where T : Control
    {
        Control ctrl;
        if (!_controls.TryGetValue(id, out ctrl))
            throw new InvalidOperationException("Control not found: " + id);
        return (T)ctrl;
    }
}
