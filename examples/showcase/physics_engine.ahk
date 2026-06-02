;; AHK# Example 20 — Native 2D Physics Engine (1000 FPS calculation)
;; C# handles the math and directly renders onto the AHK GUI via System.Drawing!
;; Blazing fast, zero flickering, purely native performance.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

class PhysicsEngine extends _CSModule {
    static References := "System.Drawing.dll"
    static CSharp := '
    (
        using System;
        using System.Drawing;
        using System.Drawing.Drawing2D;

        private static double[] state;
        private static int ballCount;
        
        public static void Init(int count) {
            ballCount = count;
            state = new double[count * 5]; // x, y, vx, vy, radius
            var rng = new Random();
            for (int i = 0; i < count * 5; i += 5) {
                state[i] = rng.NextDouble() * 700 + 50;        // x
                state[i+1] = rng.NextDouble() * 200;           // y
                state[i+2] = (rng.NextDouble() - 0.5) * 15;    // vx
                state[i+3] = 0;                                // vy
                state[i+4] = rng.NextDouble() * 15 + 5;        // radius
            }
        }

        public static void StepAndDraw(long hwndLong, int width, int height) {
            IntPtr hwnd = (IntPtr)hwndLong;
            // 1. Math Step
            for (int i = 0; i < state.Length; i += 5) {
                double r = state[i+4];
                state[i] += state[i+2];       // x += vx
                state[i+1] += state[i+3];     // y += vy
                state[i+3] += 0.4;            // gravity
                
                // Floor / Ceiling Bounce
                if (state[i+1] > height - r) { 
                    state[i+1] = height - r; 
                    if (state[i+3] > 0) state[i+3] *= -0.85; 
                }
                else if (state[i+1] < r) { 
                    state[i+1] = r; 
                    if (state[i+3] < 0) state[i+3] *= -0.85; 
                }
                
                // Wall Bounce
                if (state[i] > width - r) { 
                    state[i] = width - r; 
                    if (state[i+2] > 0) state[i+2] *= -0.9; 
                }
                else if (state[i] < r) { 
                    state[i] = r; 
                    if (state[i+2] < 0) state[i+2] *= -0.9; 
                }
            }
            
            // 2. Render directly to HWND using Double Buffering
            using (Graphics g = Graphics.FromHwnd(hwnd))
            using (Bitmap bmp = new Bitmap(width, height))
            using (Graphics bg = Graphics.FromImage(bmp)) {
                bg.SmoothingMode = SmoothingMode.AntiAlias;
                bg.Clear(Color.FromArgb(17, 17, 34)); // Dark background
                
                // Draw all balls
                for (int i = 0; i < state.Length; i += 5) {
                    float x = (float)state[i];
                    float y = (float)state[i+1];
                    float r = (float)state[i+4];
                    bg.FillEllipse(Brushes.SpringGreen, x - r, y - r, r * 2, r * 2);
                }
                
                // Blit to screen (Zero flicker)
                g.DrawImage(bmp, 0, 0);
            }
        }
    )'
}

; ── Setup UI ──
WinWidth := 800
WinHeight := 600

g := Gui("+AlwaysOnTop", "AHK# — 2D Physics Engine")
g.BackColor := "0x111122"
g.MarginX := 0, g.MarginY := 0
g.OnEvent("Close", (*) => ExitApp())

; Instead of moving AHK controls, we just pass an empty picture box for C# to draw on!
pic := g.Add("Picture", "x0 y0 w" WinWidth " h" WinHeight " BackgroundTrans")

g.Show("w" WinWidth " h" WinHeight)

; Initialize the C# Engine
PhysicsEngine.Init(200) ; 200 bouncing balls!

; ── Game Loop ──
Loop {
    ; C# handles the math AND rendering flawlessly onto our Picture control HWND!
    PhysicsEngine.StepAndDraw(pic.Hwnd, WinWidth, WinHeight)
    Sleep(10) ; Limit to ~100 FPS
}
