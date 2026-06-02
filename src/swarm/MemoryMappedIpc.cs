// AHK# Memory-Mapped IPC — Gigabyte-scale instant RAM-to-RAM transfers
// Uses System.IO.MemoryMappedFiles for zero-serialization IPC between AHK scripts.

using System;
using System.IO;
using System.IO.MemoryMappedFiles;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

[ComVisible(true)]
[ClassInterface(ClassInterfaceType.AutoDual)]
[Guid("B4C0D1E2-F3A4-5678-BCDE-567890123456")]
[ProgId("AhkSharp.Ipc")]
public class MemoryMappedIpc : IDisposable
{
    private MemoryMappedFile _mmf;
    private MemoryMappedViewAccessor _accessor;
    private string _name;
    private long _capacity;
    private bool _disposed;
    private Mutex _mutex;

    // Header: [8 bytes: data length] [data...]
    private const int HEADER_SIZE = 8;

    /// <summary>Create or open a named memory-mapped channel.</summary>
    public void Create(string name, long capacityBytes)
    {
        _name = name;
        _capacity = capacityBytes + HEADER_SIZE;
        _mutex = new Mutex(false, "AhkSharp_IPC_" + name);

        try
        {
            // Try to open existing
            _mmf = MemoryMappedFile.OpenExisting(name);
        }
        catch
        {
            // Create new
            _mmf = MemoryMappedFile.CreateOrOpen(name, _capacity);
        }

        _accessor = _mmf.CreateViewAccessor(0, _capacity);
    }

    /// <summary>Write a string to the channel. Thread-safe via named mutex.</summary>
    public void Write(string data)
    {
        if (_accessor == null) throw new InvalidOperationException("Channel not created");

        byte[] bytes = Encoding.UTF8.GetBytes(data);
        if (bytes.Length + HEADER_SIZE > _capacity)
            throw new InvalidOperationException(string.Format(
                "Data size ({0} bytes) exceeds channel capacity ({1} bytes)",
                bytes.Length, _capacity - HEADER_SIZE));

        _mutex.WaitOne();
        try
        {
            // Write length header
            _accessor.Write(0, (long)bytes.Length);
            // Write data
            _accessor.WriteArray(HEADER_SIZE, bytes, 0, bytes.Length);
        }
        finally
        {
            _mutex.ReleaseMutex();
        }
    }

    /// <summary>Write raw bytes to the channel.</summary>
    public void WriteBytes(byte[] data)
    {
        if (_accessor == null) throw new InvalidOperationException("Channel not created");
        if (data.Length + HEADER_SIZE > _capacity)
            throw new InvalidOperationException("Data exceeds channel capacity");

        _mutex.WaitOne();
        try
        {
            _accessor.Write(0, (long)data.Length);
            _accessor.WriteArray(HEADER_SIZE, data, 0, data.Length);
        }
        finally
        {
            _mutex.ReleaseMutex();
        }
    }

    /// <summary>Read the current string content from the channel.</summary>
    public string Read()
    {
        if (_accessor == null) throw new InvalidOperationException("Channel not created");

        _mutex.WaitOne();
        try
        {
            long length = _accessor.ReadInt64(0);
            if (length <= 0 || length > _capacity - HEADER_SIZE)
                return "";

            byte[] bytes = new byte[length];
            _accessor.ReadArray(HEADER_SIZE, bytes, 0, (int)length);
            return Encoding.UTF8.GetString(bytes);
        }
        finally
        {
            _mutex.ReleaseMutex();
        }
    }

    /// <summary>Read raw bytes from the channel.</summary>
    public byte[] ReadBytes()
    {
        if (_accessor == null) throw new InvalidOperationException("Channel not created");

        _mutex.WaitOne();
        try
        {
            long length = _accessor.ReadInt64(0);
            if (length <= 0 || length > _capacity - HEADER_SIZE)
                return new byte[0];

            byte[] bytes = new byte[length];
            _accessor.ReadArray(HEADER_SIZE, bytes, 0, (int)length);
            return bytes;
        }
        finally
        {
            _mutex.ReleaseMutex();
        }
    }

    /// <summary>Get the current data length in bytes.</summary>
    public long DataLength
    {
        get
        {
            if (_accessor == null) return 0;
            return _accessor.ReadInt64(0);
        }
    }

    /// <summary>Get the channel capacity in bytes.</summary>
    public long Capacity { get { return _capacity - HEADER_SIZE; } }

    /// <summary>Clear the channel data.</summary>
    public void Clear()
    {
        if (_accessor == null) return;

        _mutex.WaitOne();
        try
        {
            _accessor.Write(0, (long)0);
        }
        finally
        {
            _mutex.ReleaseMutex();
        }
    }

    /// <summary>
    /// Write data at a specific offset within the buffer.
    /// For scatter/gather patterns or structured binary protocols.
    /// </summary>
    public void WriteAt(long offset, string data)
    {
        byte[] bytes = Encoding.UTF8.GetBytes(data);
        long actualOffset = HEADER_SIZE + offset;
        if (actualOffset + bytes.Length > _capacity)
            throw new InvalidOperationException("Write exceeds capacity");

        _mutex.WaitOne();
        try
        {
            _accessor.WriteArray(actualOffset, bytes, 0, bytes.Length);
        }
        finally
        {
            _mutex.ReleaseMutex();
        }
    }

    /// <summary>Read data from a specific offset.</summary>
    public string ReadAt(long offset, int length)
    {
        long actualOffset = HEADER_SIZE + offset;
        if (actualOffset + length > _capacity)
            throw new InvalidOperationException("Read exceeds capacity");

        byte[] bytes = new byte[length];
        _mutex.WaitOne();
        try
        {
            _accessor.ReadArray(actualOffset, bytes, 0, length);
        }
        finally
        {
            _mutex.ReleaseMutex();
        }
        return Encoding.UTF8.GetString(bytes);
    }

    /// <summary>Get the raw pointer to the memory-mapped region for direct DllCall access.</summary>
    public long GetPointer()
    {
        if (_mmf == null) return 0;

        using (var view = _mmf.CreateViewAccessor(0, _capacity, MemoryMappedFileAccess.ReadWrite))
        {
            unsafe
            {
                byte* ptr = null;
                System.Runtime.InteropServices.SafeBuffer buffer = view.SafeMemoryMappedViewHandle;
                buffer.AcquirePointer(ref ptr);
                long result = (long)ptr + HEADER_SIZE;
                buffer.ReleasePointer();
                return result;
            }
        }
    }

    public void Dispose()
    {
        if (!_disposed)
        {
            if (_accessor != null) { _accessor.Dispose(); _accessor = null; }
            if (_mmf != null) { _mmf.Dispose(); _mmf = null; }
            if (_mutex != null) { _mutex.Dispose(); _mutex = null; }
            _disposed = true;
        }
    }
}
