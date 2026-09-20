// ═══════════════════════════════════════════════════════════════════════════════
// AHK# Extras — implementing .NET interfaces from AHK, and wrapper generation
// ═══════════════════════════════════════════════════════════════════════════════
// Written in C# 4.0 syntax (csc v4.0.30319).

using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Runtime.Remoting.Messaging;
using System.Runtime.Remoting.Proxies;
using System.Text;

// ─────────────────────────────────────────────────────────────────────────────
// CS.Implement — an object that implements a .NET interface with AHK functions
// ─────────────────────────────────────────────────────────────────────────────
// Built on RealProxy (part of every .NET Framework 4.x): the transparent proxy IS-A
// the interface, every call is routed to the AHK function registered under the
// method's name. Property accessors look for "get_Name"/"set_Name", then "Name".
// Callbacks travel through AhkCallback, so they also work when .NET calls the
// object from a worker thread.

internal sealed class AhkInterfaceProxy : RealProxy
{
    private readonly Type _type;
    private readonly Dictionary<string, object> _handlers =
        new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase);

    public AhkInterfaceProxy(Type type, object[,] pairs) : base(type)
    {
        _type = type;
        if (pairs != null)
        {
            int n = pairs.GetLength(0);
            int l0 = pairs.GetLowerBound(0), l1 = pairs.GetLowerBound(1);
            for (int i = 0; i < n; i++)
            {
                string name = Convert.ToString(pairs[l0 + i, l1]);
                if (name.Length > 0) _handlers[name] = pairs[l0 + i, l1 + 1];
            }
        }
    }

    private object FindHandler(string methodName)
    {
        object h;
        if (_handlers.TryGetValue(methodName, out h)) return h;
        if ((methodName.StartsWith("get_") || methodName.StartsWith("set_")) && _handlers.TryGetValue(methodName.Substring(4), out h))
            return h;
        return null;
    }

    public override IMessage Invoke(IMessage msg)
    {
        IMethodCallMessage call = msg as IMethodCallMessage;
        if (call == null)
            return new ReturnMessage(new NotSupportedException("Unsupported remoting message."), null);

        MethodBase mb = call.MethodBase;
        try
        {
            Type ret = mb is MethodInfo ? ((MethodInfo)mb).ReturnType : typeof(void);
            object handler = FindHandler(mb.Name);
            object result;

            if (handler != null)
            {
                object raw = AhkCallback.Invoke(handler, call.Args);
                result = ret == typeof(void) ? null : AhkCallback.ConvertResult(ret, raw);
            }
            else if (mb.DeclaringType == typeof(object))
            {
                switch (mb.Name)
                {
                    case "ToString": result = "AhkImplementation<" + _type.Name + ">[" + string.Join(", ", _handlers.Select(kv => kv.Key + ":" + (kv.Value == null ? "null" : kv.Value.GetType().Name)).ToArray()) + "]"; break;
                    case "GetType": result = _type; break;      // transparent proxies route GetType() through Invoke
                    case "GetHashCode": result = System.Runtime.CompilerServices.RuntimeHelpers.GetHashCode(this); break;
                    case "Equals": result = object.ReferenceEquals(call.Args[0], GetTransparentProxy()); break;
                    default: result = null; break;
                }
            }
            else if (mb.Name == "Dispose" || mb.Name.StartsWith("add_") || mb.Name.StartsWith("remove_"))
                result = null;
            else if (ret == typeof(void))
                result = null;
            else
                throw new NotImplementedException("The AHK implementation of " + _type.Name + " has no handler for '" + mb.Name + "'.");

            return new ReturnMessage(result, null, 0, call.LogicalCallContext, call);
        }
        catch (Exception ex)
        {
            return new ReturnMessage(ex, call);
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// CS.Wrap — generate an AHK source file for a .NET type
// ─────────────────────────────────────────────────────────────────────────────
// Static members become static AHK methods; instance types become a wrapper class
// holding the object. Parameter names and every overload's signature are kept
// (as comments) so editors with AHK support show real IntelliSense.

internal static class WrapperGenerator
{
    private static string Ahk(string name)
    {
        // AHK identifiers cannot contain these; generic names look like List`1
        return new string(name.Select(c => char.IsLetterOrDigit(c) || c == '_' ? c : '_').ToArray());
    }

    private static string Sig(MethodBase m)
    {
        StringBuilder sb = new StringBuilder();
        MethodInfo mi = m as MethodInfo;
        if (mi != null) sb.Append(TypeName(mi.ReturnType)).Append(' ');
        sb.Append(m.Name).Append('(');
        ParameterInfo[] ps = m.GetParameters();
        for (int i = 0; i < ps.Length; i++)
        {
            if (i > 0) sb.Append(", ");
            sb.Append(TypeName(ps[i].ParameterType)).Append(' ').Append(ps[i].Name);
        }
        return sb.Append(')').ToString();
    }

    private static string TypeName(Type t)
    {
        if (t.IsByRef) return "ref " + TypeName(t.GetElementType());
        if (t.IsArray) return TypeName(t.GetElementType()) + "[]";
        if (t.IsGenericType)
            return t.Name.Substring(0, t.Name.IndexOf('`')) + "<" + string.Join(", ", t.GetGenericArguments().Select(TypeName).ToArray()) + ">";
        return t.Name;
    }

    // the overload with the most parameters names the AHK parameters; the rest become optional
    private static void EmitMethod(StringBuilder sb, MethodBase[] overloads, string target, bool isStatic, string ahkName)
    {
        MethodBase widest = overloads.OrderByDescending(m => m.GetParameters().Length).First();
        ParameterInfo[] ps = widest.GetParameters();
        int minParams = overloads.Min(m => m.GetParameters().Length);

        foreach (MethodBase m in overloads.OrderBy(m => m.GetParameters().Length))
            sb.Append("    ; ").Append(Sig(m)).Append('\n');

        List<string> names = new List<string>();
        for (int i = 0; i < ps.Length; i++)
        {
            string n = Ahk(ps[i].Name);
            if (n.Length == 0 || char.IsDigit(n[0])) n = "p" + i;
            names.Add(n);
        }
        string decl = string.Join(", ", names.Select((n, i) => i >= minParams ? n + "?" : n).ToArray());
        string pass = names.Count == 0 ? "" : string.Join(", ", names.Select((n, i) => i >= minParams ? n + "?" : n).ToArray());

        sb.Append("    ").Append(isStatic ? "static " : "").Append(ahkName).Append('(').Append(decl).Append(") {\n");
        if (names.Count == 0)
            sb.Append("        return ").Append(target).Append('.').Append(widest.Name).Append("()\n");
        else
            sb.Append("        return ").Append(target).Append('.').Append(widest.Name).Append("(_CSArgs(").Append(pass).Append(")*)\n");
        sb.Append("    }\n\n");
    }

    public static string Generate(Type t, string ahkClassName, string csPath)
    {
        StringBuilder sb = new StringBuilder();
        sb.Append("; Generated by AHK# (CS.Wrap) for ").Append(t.FullName).Append('\n');
        sb.Append("; Include this file after lib\\ahk#.ahk. Every method forwards to the real .NET member;\n");
        sb.Append("; the comment lines above each method list its .NET overloads.\n\n");

        bool staticOnly = t.IsAbstract && t.IsSealed;   // static class
        sb.Append("class ").Append(ahkClassName).Append(" {\n");

        if (!staticOnly)
        {
            sb.Append("    __New(args*) {\n");
            sb.Append("        this._o := ").Append(csPath).Append("(args*)\n");
            sb.Append("    }\n\n");
            sb.Append("    static FromObject(obj) {\n        w := ").Append(ahkClassName).Append("()\n        w._o := obj\n        return w\n    }\n\n");
        }

        // static members
        foreach (var grp in t.GetMethods(BindingFlags.Public | BindingFlags.Static | BindingFlags.FlattenHierarchy)
                             .Where(m => !m.IsSpecialName && !m.IsGenericMethodDefinition)
                             .GroupBy(m => m.Name).OrderBy(g => g.Key))
            EmitMethod(sb, grp.Cast<MethodBase>().ToArray(), csPath, true, Ahk(grp.Key));

        foreach (PropertyInfo p in t.GetProperties(BindingFlags.Public | BindingFlags.Static | BindingFlags.FlattenHierarchy).Where(p => p.GetIndexParameters().Length == 0))
        {
            sb.Append("    ; ").Append(TypeName(p.PropertyType)).Append(' ').Append(p.Name).Append('\n');
            sb.Append("    static ").Append(Ahk(p.Name)).Append(" {\n");
            if (p.CanRead) sb.Append("        get => ").Append(csPath).Append('.').Append(p.Name).Append('\n');
            if (p.CanWrite) sb.Append("        set => ").Append(csPath).Append('.').Append(p.Name).Append(" := value\n");
            sb.Append("    }\n\n");
        }

        foreach (FieldInfo fi in t.GetFields(BindingFlags.Public | BindingFlags.Static | BindingFlags.FlattenHierarchy))
        {
            sb.Append("    ; ").Append(TypeName(fi.FieldType)).Append(' ').Append(fi.Name).Append(fi.IsLiteral ? " (const)" : "").Append('\n');
            sb.Append("    static ").Append(Ahk(fi.Name)).Append(" {\n");
            sb.Append("        get => ").Append(csPath).Append('.').Append(fi.Name).Append('\n');
            if (!fi.IsInitOnly && !fi.IsLiteral) sb.Append("        set => ").Append(csPath).Append('.').Append(fi.Name).Append(" := value\n");
            sb.Append("    }\n\n");
        }
        // instance members
        if (!staticOnly)
        {
            foreach (var grp in t.GetMethods(BindingFlags.Public | BindingFlags.Instance)
                                 .Where(m => !m.IsSpecialName && !m.IsGenericMethodDefinition && m.DeclaringType != typeof(object))
                                 .GroupBy(m => m.Name).OrderBy(g => g.Key))
                EmitMethod(sb, grp.Cast<MethodBase>().ToArray(), "this._o", false, Ahk(grp.Key));

            foreach (FieldInfo fi in t.GetFields(BindingFlags.Public | BindingFlags.Instance))
            {
                sb.Append("    ; ").Append(TypeName(fi.FieldType)).Append(' ').Append(fi.Name).Append('\n');
                sb.Append("    ").Append(Ahk(fi.Name)).Append(" {\n");
                sb.Append("        get => this._o.").Append(fi.Name).Append('\n');
                if (!fi.IsInitOnly) sb.Append("        set => this._o.").Append(fi.Name).Append(" := value\n");
                sb.Append("    }\n\n");
            }
            foreach (PropertyInfo p in t.GetProperties(BindingFlags.Public | BindingFlags.Instance).Where(p => p.GetIndexParameters().Length == 0))
            {
                sb.Append("    ; ").Append(TypeName(p.PropertyType)).Append(' ').Append(p.Name).Append('\n');
                sb.Append("    ").Append(Ahk(p.Name)).Append(" {\n");
                if (p.CanRead) sb.Append("        get => this._o.").Append(p.Name).Append('\n');
                if (p.CanWrite) sb.Append("        set => this._o.").Append(p.Name).Append(" := value\n");
                sb.Append("    }\n\n");
            }
        }

        sb.Append("}\n");
        return sb.ToString();
    }
}
