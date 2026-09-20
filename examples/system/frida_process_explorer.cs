using System;
using System.Collections.Generic;
using System.Windows.Threading;
using Frida;

public class FridaExplorerBridge {
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
}
