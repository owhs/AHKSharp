using System;
using System.Collections.Generic;
using System.Windows.Automation;
using System.Windows.Threading;
using Frida;

public class FridaBridge {
    private static Dispatcher _dispatcher;

    public static void Initialize(object dispatcherObj) {
        _dispatcher = (Dispatcher)dispatcherObj;
    }

    public static string GetDeviceType(object deviceObj) {
        return ((Device)deviceObj).Type.ToString();
    }

    public static void SubscribeScriptMessage(object scriptObj, object ahkCallback) {
        Script script = (Script)scriptObj;
        script.Message += (sender, e) => {
            if (_dispatcher != null) {
                _dispatcher.BeginInvoke((Action)(() => {
                    try {
                        dynamic callback = ahkCallback;
                        callback.Call(e.Message);
                    } catch {}
                }));
            } else {
                try {
                    dynamic callback = ahkCallback;
                    callback.Call(e.Message);
                } catch {}
            }
        };
    }

    public static void SubscribeSessionDetached(object sessionObj, object ahkCallback) {
        Session session = (Session)sessionObj;
        session.Detached += (sender, e) => {
            if (_dispatcher != null) {
                _dispatcher.BeginInvoke((Action)(() => {
                    try {
                        dynamic callback = ahkCallback;
                        callback.Call(e.Reason.ToString());
                    } catch {}
                }));
            } else {
                try {
                    dynamic callback = ahkCallback;
                    callback.Call(e.Reason.ToString());
                } catch {}
            }
        };
    }

    public static void SubscribeDeviceLost(object deviceObj, object ahkCallback) {
        Device device = (Device)deviceObj;
        device.Lost += (sender, e) => {
            if (_dispatcher != null) {
                _dispatcher.BeginInvoke((Action)(() => {
                    try {
                        dynamic callback = ahkCallback;
                        callback.Call();
                    } catch {}
                }));
            } else {
                try {
                    dynamic callback = ahkCallback;
                    callback.Call();
                } catch {}
            }
        };
    }

    public static void SubscribeDeviceManagerChanged(object managerObj, object ahkCallback) {
        DeviceManager manager = (DeviceManager)managerObj;
        manager.Changed += (sender, e) => {
            if (_dispatcher != null) {
                _dispatcher.BeginInvoke((Action)(() => {
                    try {
                        dynamic callback = ahkCallback;
                        callback.Call();
                    } catch {}
                }));
            } else {
                try {
                    dynamic callback = ahkCallback;
                    callback.Call();
                } catch {}
            }
        };
    }

    // ── UI Automation Browser Helpers ──

    public static string[] GetBrowserTabs(IntPtr hwnd) {
        var list = new List<string>();
        try {
            AutomationElement winEl = AutomationElement.FromHandle(hwnd);
            if (winEl == null) return list.ToArray();

            var tabCond = new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.TabItem);
            var tabs = winEl.FindAll(TreeScope.Descendants, tabCond);
            foreach (AutomationElement tab in tabs) {
                string name = tab.Current.Name;
                if (!string.IsNullOrEmpty(name)) {
                    list.Add(name);
                }
            }
        } catch {}
        return list.ToArray();
    }

    public static string GetActiveTabUrl(IntPtr hwnd) {
        try {
            AutomationElement winEl = AutomationElement.FromHandle(hwnd);
            if (winEl == null) return string.Empty;

            var cond = new OrCondition(
                new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Edit),
                new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Document)
            );
            var elements = winEl.FindAll(TreeScope.Descendants, cond);
            foreach (AutomationElement el in elements) {
                object valPattern;
                if (el.TryGetCurrentPattern(ValuePattern.Pattern, out valPattern)) {
                    string url = ((ValuePattern)valPattern).Current.Value;
                    if (!string.IsNullOrEmpty(url)) {
                        url = url.Trim();
                        if (url.Contains("://") || url.StartsWith("www.") || (url.Contains(".") && !url.Contains(" ") && !url.Contains("\\"))) {
                            return url;
                        }
                    }
                }
            }
        } catch {}
        return string.Empty;
    }

    public static bool SelectBrowserTab(IntPtr hwnd, string tabName) {
        try {
            AutomationElement winEl = AutomationElement.FromHandle(hwnd);
            if (winEl == null) return false;

            var tabCond = new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.TabItem);
            var tabs = winEl.FindAll(TreeScope.Descendants, tabCond);
            foreach (AutomationElement tab in tabs) {
                if (tab.Current.Name == tabName) {
                    object selectPattern;
                    if (tab.TryGetCurrentPattern(SelectionItemPattern.Pattern, out selectPattern)) {
                        ((SelectionItemPattern)selectPattern).Select();
                        return true;
                    }
                }
            }
        } catch {}
        return false;
    }
}
