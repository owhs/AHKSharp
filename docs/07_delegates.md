# Delegates — C# Event Subscription

Subscribe to .NET events using AHK functions as handlers.

## Usage

```Autohotkey
; Wrap an AHK function as a C# delegate
watcher := CS.System.IO.FileSystemWatcher('C:\MyFolder', '*.txt')
watcher.On('Created', (args) => MsgBox('New file: ' args))
watcher.EnableRaisingEvents := true

; Timer events
timer := CS.System.Timers.Timer(1000)
timer.On('Elapsed', (*) => ToolTip(A_Now))
timer.Start()
```

## How It Works

1. CS.Delegate(fn) registers the AHK function with the bridge
2. Bridge creates an EventHandler that posts WM_APP+2 to AHK
3. AHK's OnMessage handler invokes the original function
4. Result: thread-safe event delivery to AHK's single-threaded pump

## API

| Method | Description |
|--------|-------------|
| CS.Delegate(fn) | Register AHK function as delegate |
| proxy.On(event, fn) | Subscribe to .NET event |
| delegateRef.Unregister() | Remove subscription |
