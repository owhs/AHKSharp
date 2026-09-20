// ═══════════════════════════════════════════════════════════════════════════════
// AHK# Bridge — AsyncRouter: thread-pool calls and Tasks → AHK promises
// (part of ahk#.bridge.dll; see AhkSharpBridge.cs for the COM entry point)
// ═══════════════════════════════════════════════════════════════════════════════

using System;
using System.CodeDom.Compiler;
using System.Collections;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Linq.Expressions;
using System.Net;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Runtime.ExceptionServices;
using Microsoft.CSharp;

// ─────────────────────────────────────────────────────────────────────────────
// Async Router — ThreadPool dispatch → AHK Promise via PostMessage
// ─────────────────────────────────────────────────────────────────────────────

internal static class AsyncRouter
{
    [DllImport("user32.dll")]
    private static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    private static int _nextId = 0;

    private class TaskResult
    {
        public object Value;
        public Exception Error;
        public volatile bool Complete;
    }

    private static readonly ConcurrentDictionary<int, TaskResult> _tasks =
        new ConcurrentDictionary<int, TaskResult>();

    public static int PendingCount { get { return _tasks.Count; } }

    private static Exception Unwrap(Exception ex)
    {
        while (ex != null && ex.InnerException != null
               && (ex is AggregateException || ex is TargetInvocationException))
            ex = ex.InnerException;
        return ex;
    }

    private static object TaskValue(Task t)
    {
        Type tt = t.GetType();
        if (tt.IsGenericType)
        {
            if (tt.GetGenericArguments()[0].Name == "VoidTaskResult") return null;
            return MarshalEngine.PackResult(tt.GetProperty("Result").GetValue(t, null));
        }
        return null;
    }

    // A method that returns a Task: wait for it here (we are on a pool thread) and hand back its value
    private static object AwaitIfTask(object r)
    {
        Task t = r as Task;
        if (t == null) return r;
        t.Wait();
        return TaskValue(t);
    }

    /// <summary>Completes an async slot when a .NET Task finishes (no thread is blocked).</summary>
    public static int FromTask(Task task, IntPtr ahkHwnd, int callbackMsg)
    {
        int id = Interlocked.Increment(ref _nextId);
        var result = new TaskResult();
        _tasks[id] = result;
        task.ContinueWith(t =>
        {
            try
            {
                if (t.IsFaulted) result.Error = Unwrap(t.Exception);
                else if (t.IsCanceled) result.Error = new OperationCanceledException("The task was canceled.");
                else result.Value = TaskValue(t);
            }
            catch (Exception ex) { result.Error = Unwrap(ex); }
            finally
            {
                result.Complete = true;
                if (ahkHwnd != IntPtr.Zero)
                    PostMessage(ahkHwnd, (uint)callbackMsg, (IntPtr)id, IntPtr.Zero);
            }
        }, TaskScheduler.Default);
        return id;
    }

    public static int Begin(object target, string methodName, object[] args, IntPtr ahkHwnd, int callbackMsg)
    {
        int id = Interlocked.Increment(ref _nextId);
        var result = new TaskResult();
        _tasks[id] = result;

        ThreadPool.QueueUserWorkItem(_ =>
        {
            try
            {
                object r = AhkSharpBridge.Instance.InvokeMember(target, methodName, args);
                result.Value = AwaitIfTask(r);
            }
            catch (Exception ex)
            {
                result.Error = Unwrap(ex);
            }
            finally
            {
                result.Complete = true;
                if (ahkHwnd != IntPtr.Zero)
                    PostMessage(ahkHwnd, (uint)callbackMsg, (IntPtr)id, IntPtr.Zero);
            }
        });

        return id;
    }

    public static int BeginStatic(string typeName, string methodName, object[] args, IntPtr ahkHwnd, int callbackMsg)
    {
        int id = Interlocked.Increment(ref _nextId);
        var result = new TaskResult();
        _tasks[id] = result;

        ThreadPool.QueueUserWorkItem(_ =>
        {
            try
            {
                object r = AhkSharpBridge.Instance.InvokeStatic(typeName, methodName, args);
                result.Value = AwaitIfTask(r);
            }
            catch (Exception ex)
            {
                result.Error = Unwrap(ex);
            }
            finally
            {
                result.Complete = true;
                if (ahkHwnd != IntPtr.Zero)
                    PostMessage(ahkHwnd, (uint)callbackMsg, (IntPtr)id, IntPtr.Zero);
            }
        });

        return id;
    }

    public static int BeginModule(string assemblyId, string className, string methodName, object[] args, IntPtr ahkHwnd, int callbackMsg)
    {
        int id = Interlocked.Increment(ref _nextId);
        var result = new TaskResult();
        _tasks[id] = result;

        ThreadPool.QueueUserWorkItem(_ =>
        {
            try
            {
                object r = RuntimeCompiler.InvokeModule(assemblyId, className, methodName, args);
                result.Value = AwaitIfTask(r);
            }
            catch (Exception ex)
            {
                result.Error = Unwrap(ex);
            }
            finally
            {
                result.Complete = true;
                if (ahkHwnd != IntPtr.Zero)
                    PostMessage(ahkHwnd, (uint)callbackMsg, (IntPtr)id, IntPtr.Zero);
            }
        });

        return id;
    }

    public static object End(int taskId)
    {
        TaskResult r;
        if (!_tasks.TryGetValue(taskId, out r))
            throw new InvalidOperationException("Unknown task: " + taskId);

        // Spin-wait with message pumping (short wait, AHK pumps its own loop)
        while (!r.Complete)
            Thread.Sleep(1);

        TaskResult removed;
        _tasks.TryRemove(taskId, out removed);

        if (r.Error != null)
            throw r.Error;

        return MarshalEngine.PackResult(r.Value);
    }

    public static bool IsComplete(int taskId)
    {
        TaskResult r;
        return _tasks.TryGetValue(taskId, out r) && r.Complete;
    }

    public static string GetError(int taskId)
    {
        TaskResult r;
        if (_tasks.TryGetValue(taskId, out r) && r.Error != null)
        {
            Exception ex = r.Error;
            while (ex is TargetInvocationException && ex.InnerException != null)
                ex = ex.InnerException;
            return ex.GetType().Name + ": " + ex.Message;
        }
        return null;
    }
}

