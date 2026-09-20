;; AHK# — IPC: Messaging, Shared RAM, Batching & Parallelism
;; Demonstrates the SharedMemory extension (ext\ahk#.ipc.ahk) plus async promises.
;;
;; Showcases:
;;   1. Shared RAM — Named memory-mapped buffer (other processes can open the same name)
;;   2. IPC Messaging — Structured message passing via shared buffers
;;   3. Batched IPC Calls — Bulk data transfer with offset addressing
;;   4. Non-Blocking Parallelism — Async computation with Promises
;;   5. Change Notification — SharedMemory.OnChanged (a timer polls the buffer;
;;      here publisher and subscriber are the same script/process)

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk
#Include ..\..\ext\ahk#.ipc.ahk

; ══════════════════════════════════════════════════════════════════════════════
; Custom C# module for parallel compute tasks
; ══════════════════════════════════════════════════════════════════════════════

class ParallelMath extends _CSModule {
    static CSharp := "
    (
        using System.Threading;

        public static double MonteCarloPi(int iterations) {
            int inside = 0;
            var rng = new Random();
            for (int i = 0; i < iterations; i++) {
                double x = rng.NextDouble();
                double y = rng.NextDouble();
                if (x * x + y * y <= 1.0) inside++;
            }
            return 4.0 * inside / iterations;
        }

        public static long HeavySum(int count) {
            long sum = 0;
            for (int i = 1; i <= count; i++)
                sum += i;
            return sum;
        }

        public static long FibSum(int n) {
            long a = 0, b = 1, sum = 0;
            for (int i = 0; i < n; i++) {
                sum += a;
                long t = a + b;
                a = b;
                b = t;
            }
            return sum;
        }
    )"
}

out := ""

; ══════════════════════════════════════════════════════════════════════════════
; 1. SHARED RAM — Direct Memory Access
; ══════════════════════════════════════════════════════════════════════════════

out .= "═══ 1. SHARED RAM ═══`n"

; Create a 4KB shared memory buffer (any process can open the same name)
shm := SharedMemory("AhkSharp_Demo_RAM", 4096)

; Write a string — goes directly into kernel-managed shared memory
shm.Write("AHK# shared RAM round-trip")
readBack := shm.Read()
out .= "  Write → Read: " readBack "`n"
out .= "  Buffer capacity: " shm.Capacity " bytes`n"
out .= "  Data length: " shm.Length " bytes`n"

; Clear and verify
shm.Clear()
afterClear := shm.Read()
out .= "  After Clear: '" afterClear "' (empty = correct)`n"

shm.Close()

; ══════════════════════════════════════════════════════════════════════════════
; 2. IPC MESSAGING — Structured Message Passing
; ══════════════════════════════════════════════════════════════════════════════

out .= "`n═══ 2. IPC MESSAGING ═══`n"

; Simulate a message bus — could be read by another AHK process
msgBus := SharedMemory("AhkSharp_MsgBus", 8192)

; Write structured messages with timestamps
ts := FormatTime(, "HH:mm:ss")
msg1 := '{"type":"CMD","ts":"' ts '","payload":"start_scan"}'
msgBus.Write(msg1)
out .= "  Sent: " msg1 "`n"

; Read it back (in production, another process does this)
received := msgBus.Read()
out .= "  Recv: " received "`n"

; Overwrite with a response
resp := '{"type":"ACK","ts":"' ts '","status":"ok"}'
msgBus.Write(resp)
readResp := msgBus.Read()
out .= "  Response: " readResp "`n"

msgBus.Close()

; ══════════════════════════════════════════════════════════════════════════════
; 3. BATCHED IPC CALLS — Offset-Addressed Bulk Transfer
; ══════════════════════════════════════════════════════════════════════════════

out .= "`n═══ 3. BATCHED IPC (Offset Writes) ═══`n"

batch := SharedMemory("AhkSharp_Batch", 4096)
batch.Clear()

; Write multiple data chunks at fixed offsets — like a struct in shared memory
; Offset 0:   command (20 bytes)
; Offset 20:  param1  (20 bytes)
; Offset 40:  param2  (20 bytes)
; Offset 60:  status  (20 bytes)
batch.WriteAt(0, "COMPUTE")
batch.WriteAt(20, "iterations=5000")
batch.WriteAt(40, "precision=high")
batch.WriteAt(60, "status=PENDING")

; Read each field back by offset
cmd    := batch.ReadAt(0, 7)
param1 := batch.ReadAt(20, 15)
param2 := batch.ReadAt(40, 14)
status := batch.ReadAt(60, 14)

out .= "  Offset 0:  [CMD]    " cmd "`n"
out .= "  Offset 20: [PARAM1] " param1 "`n"
out .= "  Offset 40: [PARAM2] " param2 "`n"
out .= "  Offset 60: [STATUS] " status "`n"

; Update just the status field (a partial write: only those 14 bytes are touched;
; it is not atomic, so real multi-process use needs its own locking)
batch.WriteAt(60, "status=DONE   ")
newStatus := batch.ReadAt(60, 14)
out .= "  Updated status: " newStatus "`n"

batch.Close()

; ══════════════════════════════════════════════════════════════════════════════
; 4. NON-BLOCKING PARALLELISM — Async + Promises
; ══════════════════════════════════════════════════════════════════════════════

out .= "`n═══ 4. NON-BLOCKING PARALLELISM ═══`n"

; 4a. Fire-and-forget async: launches on .NET ThreadPool, returns Promise
t1 := A_TickCount
piPromise := ParallelMath.Async.MonteCarloPi(5000000)
out .= "  Async MonteCarlo launched (5M iterations)...`n"
out .= "  AHK is NOT blocked — doing other work while C# computes`n"

; Do other work while async runs
otherWork := CS.System.Math.Sqrt(144)
out .= "  Meanwhile: sqrt(144) = " otherWork "`n"

; Now await the result
pi := piPromise.Await()
elapsed := A_TickCount - t1
out .= "  MonteCarlo Pi ≈ " pi " (took " elapsed "ms)`n"

; 4b. Multiple parallel promises — fire 3 tasks at once
t2 := A_TickCount
p1 := ParallelMath.Async.HeavySum(10000000)
p2 := ParallelMath.Async.HeavySum(20000000)
p3 := ParallelMath.Async.HeavySum(30000000)

out .= "`n  Fired 3 parallel HeavySum tasks...`n"

; Collect all results (they run concurrently on ThreadPool)
r1 := p1.Await()
r2 := p2.Await()
r3 := p3.Await()
elapsed2 := A_TickCount - t2

out .= "  Sum(10M) = " r1 "`n"
out .= "  Sum(20M) = " r2 "`n"
out .= "  Sum(30M) = " r3 "`n"
out .= "  All 3 completed in " elapsed2 "ms (parallel!)`n"

; 4c. Async FibSum — test the third parallel method
t3 := A_TickCount
fibPromise := ParallelMath.Async.FibSum(50)
out .= "`n  Async FibSum(50) launched...`n"

; Do other work while waiting
guid := CS.System.Guid.NewGuid()
out .= "  Meanwhile: generated GUID = " guid "`n"

fibResult := fibPromise.Await()
elapsed3 := A_TickCount - t3
out .= "  FibSum(50) = " fibResult " (took " elapsed3 "ms)`n"

; ══════════════════════════════════════════════════════════════════════════════
; 5. CHANGE NOTIFICATION — SharedMemory.OnChanged
; ══════════════════════════════════════════════════════════════════════════════

out .= "`n═══ 5. CHANGE NOTIFICATION (OnChanged) ═══`n"

; Create a shared channel and register a change listener. OnChanged polls the
; buffer on a timer and calls back whenever its content differs from last time.
; (Another process opening the same name would see the same buffer; in this demo
; the publisher and the subscriber are both this script.)
pubsub := SharedMemory("AhkSharp_PubSub", 4096)
pubsub.Clear()

; Track received messages
receivedMsgs := []
pubsub.OnChanged((data) => receivedMsgs.Push(data), 25)

; Publish 3 events; each Sleep lets the polling timer run and deliver the change
for event in ["event:user_login|user=alice"
            , "event:file_saved|path=C:\data.txt"
            , "event:task_done|result=success"] {
    pubsub.Write(event)
    Sleep(100)
}

out .= "  Published 3 events, OnChanged delivered " receivedMsgs.Length ":`n"
for msg in receivedMsgs
    out .= "    → " msg "`n"

; No pubsub.Close() here: the OnChanged timer keeps polling until the script exits.

; ══════════════════════════════════════════════════════════════════════════════
; Display Everything
; ══════════════════════════════════════════════════════════════════════════════

MsgBox(out, "AHK# — IPC + Parallelism Demo", 0x40)
ExitApp()
