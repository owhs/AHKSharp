// ═══════════════════════════════════════════════════════════════════════════════
// AHK# Bridge — DelegateBridge: .NET events → AHK callbacks
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
// Delegate Bridge — .NET events → AHK callbacks
// ─────────────────────────────────────────────────────────────────────────────
// Events may fire on ANY thread. Each firing is queued and one WM_APP message is
// posted; the AHK main thread pops exactly one queued event per message and calls
// the AHK callable with the real event objects — nothing is stringified and
// bursts of events are never collapsed.
//
// For the standard (object sender, TEventArgs e) pattern the AHK callback
// receives (e, sender). For any other delegate shape it receives the delegate's
// own arguments in order.

public static class AhkEventRelay
{
    public static void Fire(int delegateId, object[] args)
    {
        DelegateBridge.Enqueue(delegateId, args);
    }
}

internal static class DelegateBridge
{
    [DllImport("user32.dll")]
    private static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    private static int _nextId = 0;

    private class DelegateEntry
    {
        public object Callable;     // AHK IDispatch object with a Call() method
        public IntPtr Hwnd;         // AHK hidden window for PostMessage
        public int Msg;             // WM_APP+2
        public readonly ConcurrentQueue<object[]> Pending = new ConcurrentQueue<object[]>();
        public Delegate Subscription;
        public object Target;
        public EventInfo Event;
        public bool SenderLast;     // (sender, e) is delivered to AHK as (e, sender)
    }

    private static readonly ConcurrentDictionary<int, DelegateEntry> _delegates =
        new ConcurrentDictionary<int, DelegateEntry>();

    public static int Count { get { return _delegates.Count; } }

    /// <summary>Registers an AHK callable for use as a C# callback.</summary>
    public static int Register(object ahkCallable, IntPtr ahkHwnd, int callbackMsg)
    {
        int id = Interlocked.Increment(ref _nextId);
        _delegates[id] = new DelegateEntry
        {
            Callable = ahkCallable,
            Hwnd = ahkHwnd,
            Msg = callbackMsg
        };
        return id;
    }

    /// <summary>Subscribes a registered delegate to a static .NET event.</summary>
    public static void SubscribeStatic(Type type, string eventName, int delegateId)
    {
        SubscribeCore(null, type, eventName, delegateId);
    }

    /// <summary>Subscribes a registered delegate to a .NET event.</summary>
    public static void Subscribe(object target, string eventName, int delegateId)
    {
        SubscribeCore(target, target.GetType(), eventName, delegateId);
    }

    private static void SubscribeCore(object target, Type targetType, string eventName, int delegateId)
    {
        DelegateEntry entry;
        if (!_delegates.TryGetValue(delegateId, out entry))
            throw new InvalidOperationException("Delegate not registered: " + delegateId);

        BindingFlags scope = target == null ? BindingFlags.Static : BindingFlags.Instance;
        EventInfo ev = targetType.GetEvent(eventName, BindingFlags.Public | scope)
            ?? targetType.GetEvent(eventName, BindingFlags.Public | scope | BindingFlags.IgnoreCase);
        if (ev == null)
            throw new MissingMemberException("Event '" + targetType.FullName + "." + eventName + "' not found."
                + MemberHints.Suggest(targetType, eventName, target == null, true));

        Type handlerType = ev.EventHandlerType;
        MethodInfo inv = handlerType.GetMethod("Invoke");
        ParameterInfo[] ps = inv.GetParameters();

        ParameterExpression[] pes = new ParameterExpression[ps.Length];
        Expression[] boxed = new Expression[ps.Length];
        for (int i = 0; i < ps.Length; i++)
        {
            if (ps[i].ParameterType.IsByRef)
                throw new NotSupportedException("Events with ref/out parameters are not supported: " + eventName);
            pes[i] = Expression.Parameter(ps[i].ParameterType, "p" + i);
            boxed[i] = Expression.Convert(pes[i], typeof(object));
        }

        Expression call = Expression.Call(
            typeof(AhkEventRelay).GetMethod("Fire"),
            Expression.Constant(delegateId),
            Expression.NewArrayInit(typeof(object), boxed));
        Expression body = inv.ReturnType == typeof(void)
            ? call
            : (Expression)Expression.Block(call, Expression.Default(inv.ReturnType));

        Delegate handler = Expression.Lambda(handlerType, body, pes).Compile();

        entry.Target = target;
        entry.Event = ev;
        entry.Subscription = handler;
        entry.SenderLast = ps.Length == 2
            && ps[0].ParameterType == typeof(object)
            && typeof(EventArgs).IsAssignableFrom(ps[1].ParameterType);

        ev.AddEventHandler(target, handler);
    }

    /// <summary>Called by the generated handler on whatever thread raised the event.</summary>
    internal static void Enqueue(int delegateId, object[] args)
    {
        DelegateEntry e;
        if (!_delegates.TryGetValue(delegateId, out e))
            return;

        object[] packed = new object[args.Length];
        for (int i = 0; i < args.Length; i++)
            packed[i] = MarshalEngine.PackResult(args[i]);
        if (e.SenderLast && packed.Length == 2)
            packed = new object[] { packed[1], packed[0] };

        e.Pending.Enqueue(packed);
        if (e.Hwnd != IntPtr.Zero)
            PostMessage(e.Hwnd, (uint)e.Msg, (IntPtr)delegateId, IntPtr.Zero);
    }

    /// <summary>Called from the AHK main thread: delivers ONE queued event to the AHK callable.</summary>
    public static object InvokeQueued(int delegateId)
    {
        DelegateEntry entry;
        if (!_delegates.TryGetValue(delegateId, out entry))
            return null;

        object[] args;
        if (!entry.Pending.TryDequeue(out args))
            return null;

        try
        {
            return entry.Callable.GetType().InvokeMember(
                "Call", BindingFlags.InvokeMethod, null, entry.Callable, args);
        }
        catch (TargetInvocationException ex)
        {
            throw AhkSharpBridge.FlattenAggregate(ex.InnerException ?? ex);
        }
    }

    /// <summary>Unregisters a delegate and removes its event subscription.</summary>
    public static void Unregister(int delegateId)
    {
        DelegateEntry entry;
        if (_delegates.TryRemove(delegateId, out entry))
        {
            if (entry.Event != null && entry.Subscription != null)
            {
                try { entry.Event.RemoveEventHandler(entry.Target, entry.Subscription); }
                catch { }
            }
            object[] discard;
            while (entry.Pending.TryDequeue(out discard)) { }
        }
    }
}

