// AHK# AhkCallback — AHK functions called by .NET (delegates, worker threads)

using System;
using System.Collections;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.ComponentModel;
using System.Globalization;
using System.Linq;
using System.Linq.Expressions;
using System.Reflection;
using System.Text;
using System.Threading;

// ─────────────────────────────────────────────────────────────────────────────
// AHK callbacks → .NET delegates
// ─────────────────────────────────────────────────────────────────────────────
// AHK v2 is single-threaded, so an AHK function only ever runs on the AHK thread:
//   • .NET calls the delegate on the AHK thread (list.Where(fn), list.Sort(fn)):   direct call.
//   • .NET calls it on ANOTHER thread (Task.Run(fn), Parallel.ForEach, a timer,
//     an implemented interface): the call is queued, a WM_APP message wakes the
//     AHK message loop, the AHK thread runs the function and hands the result back.
// The second case needs the AHK thread to be pumping messages (Sleep, a GUI,
// promise.Await, ...). If the AHK thread is stuck inside a synchronous .NET call
// that waits for the workers, nothing can service them — that call times out with
// an explanation; run such calls through .Async and Await the promise instead.

public static class AhkCallback
{
    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    public static int AhkThreadId;
    public static IntPtr Hwnd;
    public static int Msg;
    public static int TimeoutMs = 5000;

    private sealed class WorkItem
    {
        public object Callable;
        public object[] Args;
        public object Result;
        public Exception Error;
        public volatile bool Abandoned;
        public readonly ManualResetEvent Done = new ManualResetEvent(false);
    }

    private static readonly ConcurrentQueue<WorkItem> _queue = new ConcurrentQueue<WorkItem>();

    public static int QueuedCount { get { return _queue.Count; } }

    // Only the FIRST bridge (created by Boot() on the AHK thread) counts: AhkSharpBridge.Instance is also
    // constructed lazily on thread-pool threads by async calls and must not steal the AHK thread id.
    public static void Init()
    {
        if (AhkThreadId == 0)
            AhkThreadId = Thread.CurrentThread.ManagedThreadId;
    }

    

    public static void SetWindow(IntPtr hwnd, int msg)
    {
        Hwnd = hwnd;
        Msg = msg;
    }

    private static object InvokeDirect(object callable, object[] args)
    {
        try
        {
            return callable.GetType().InvokeMember("Call", BindingFlags.InvokeMethod, null, callable, args);
        }
        catch (TargetInvocationException ex)
        {
            throw ex.InnerException ?? ex;
        }
    }

    public static object Invoke(object callable, object[] args)
    {
        if (Thread.CurrentThread.ManagedThreadId == AhkThreadId)
            return InvokeDirect(callable, args);

        if (Hwnd == IntPtr.Zero)
            throw new InvalidOperationException("An AHK function was invoked from another thread but the AHK message window is not set up.");

        WorkItem item = new WorkItem { Callable = callable, Args = args };
        _queue.Enqueue(item);
        PostMessage(Hwnd, (uint)Msg, IntPtr.Zero, IntPtr.Zero);

        if (!item.Done.WaitOne(TimeoutMs))
        {
            item.Abandoned = true;
            throw new TimeoutException(
                "An AHK function called from a .NET worker thread was not run within " + TimeoutMs + " ms: the AHK thread "
                + "is not pumping messages. This happens when a synchronous .NET call (Parallel.ForEach, Task.Wait, ...) "
                + "blocks the AHK thread while its workers need AHK. Call it through .Async and Await() the promise, or keep "
                + "the script idle (Sleep / GUI) while the work runs.");
        }
        if (item.Error != null) throw item.Error;
        return item.Result;
    }

    /// <summary>Runs every queued callback. Called on the AHK thread from the WM_APP handler.</summary>
    public static int Pump()
    {
        int n = 0;
        WorkItem it;
        while (_queue.TryDequeue(out it))
        {
            if (it.Abandoned) { it.Done.Set(); continue; }
            try { it.Result = InvokeDirect(it.Callable, it.Args); }
            catch (Exception ex) { it.Error = ex; }
            it.Done.Set();
            n++;
        }
        return n;
    }

    public static object ConvertResult(Type t, object v)
    {
        if (t.IsInstanceOfType(v)) return v;
        string s = v as string;
        if (v == null || (s != null && s.Length == 0))
            return t.IsValueType ? Activator.CreateInstance(t) : null;   // AHK function returned nothing
        object c;
        if (OverloadBinder.Coerce(v, t, out c) < 0)
            throw new InvalidCastException("AHK callback returned " + v.GetType().Name + ", expected " + t.Name);
        return c;
    }

    public static Delegate MakeDelegate(Type delegateType, object callable)
    {
        MethodInfo inv = delegateType.GetMethod("Invoke");
        if (inv == null) return null;
        ParameterInfo[] ps = inv.GetParameters();
        ParameterExpression[] pes = new ParameterExpression[ps.Length];
        Expression[] boxed = new Expression[ps.Length];
        for (int i = 0; i < ps.Length; i++)
        {
            if (ps[i].ParameterType.IsByRef) return null;
            pes[i] = Expression.Parameter(ps[i].ParameterType, "p" + i);
            boxed[i] = Expression.Convert(pes[i], typeof(object));
        }

        Expression call = Expression.Call(
            typeof(AhkCallback).GetMethod("Invoke"),
            Expression.Constant(callable, typeof(object)),
            Expression.NewArrayInit(typeof(object), boxed));

        Expression body;
        if (inv.ReturnType == typeof(void))
            body = call;
        else
            body = Expression.Convert(
                Expression.Call(typeof(AhkCallback).GetMethod("ConvertResult"),
                    Expression.Constant(inv.ReturnType, typeof(Type)), call),
                inv.ReturnType);

        return Expression.Lambda(delegateType, body, pes).Compile();
    }
}
