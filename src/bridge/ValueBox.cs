// AHK# ValueBox — reference wrapper for boxed structs (see docs\17_marshaling.md)

using System;

/// <summary>
/// Reference wrapper for a boxed struct (DateTime, TimeSpan, Guid, Point, ...) that must stay a real
/// object on the AHK side. Structs cannot cross COM as objects (they would be marshalled by value or
/// as strings), so constructors of struct types — and calls made on such a value — hand out a ValueBox.
/// </summary>
[System.Runtime.InteropServices.ComVisible(true)]
public class ValueBox
{
    public object Value;
    public ValueBox(object value) { Value = value; }
    public override string ToString() { return Value == null ? "" : Value.ToString(); }
}
