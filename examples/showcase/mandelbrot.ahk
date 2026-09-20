;; AHK# — Parallel Mandelbrot Fractal Explorer
;; Demonstrates raw multi-core C# processing, Parallel.For, and native Bitmap memory manipulation.
;; C# calculates millions of math operations instantly, AHK handles the UI!

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

class FractalEngine extends _CSModule {
    static References := "System.Drawing.dll"
    static CSharp := '
    (
        using System;
        using System.Drawing;
        using System.Drawing.Imaging;
        using System.Threading.Tasks;
        using System.Runtime.InteropServices;
        
        public static string Render(double centerX, double centerY, double zoom, int w, int h, string path, int maxIter) {
            using (Bitmap bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb)) {
                BitmapData data = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
                int stride = data.Stride;
                IntPtr ptr = data.Scan0;
                
                // Maximize CPU usage using Parallel For
                Parallel.For(0, h, y => {
                    byte[] row = new byte[w * 4];
                    double cy = centerY + (y - h / 2.0) / zoom;
                    for (int x = 0; x < w; x++) {
                        double cx = centerX + (x - w / 2.0) / zoom;
                        double zx = 0, zy = 0;
                        int iter = 0;
                        while (zx * zx + zy * zy < 4 && iter < maxIter) {
                            double tmp = zx * zx - zy * zy + cx;
                            zy = 2.0 * zx * zy + cy;
                            zx = tmp;
                            iter++;
                        }
                        int offset = x * 4;
                        if (iter == maxIter) {
                            row[offset] = 0; row[offset+1] = 0; row[offset+2] = 0; row[offset+3] = 255;
                        } else {
                            // Beautiful neon coloring based on iteration escape
                            row[offset] = (byte)(iter * 255 / maxIter);       // Blue
                            row[offset+1] = (byte)((iter * 15) % 255);        // Green
                            row[offset+2] = (byte)((iter * 5) % 255);         // Red
                            row[offset+3] = 255;                              // Alpha
                        }
                    }
                    Marshal.Copy(row, 0, ptr + y * stride, w * 4);
                });
                bmp.UnlockBits(data);
                bmp.Save(path, ImageFormat.Png);
            }
            return path;
        }
    )'
}

; ── AHK UI Setup ──
g := Gui("+AlwaysOnTop +Resize", "AHK# — Parallel Mandelbrot")
g.BackColor := "Black"
g.MarginX := 0, g.MarginY := 0
pic := g.Add("Picture", "x0 y0 w600 h400")

g.SetFont("s12 cWhite")
lblInfo := g.Add("Text", "x10 y10 w580 BackgroundTrans", "Use Arrow Keys to pan, Numpad +/- to zoom!")
g.Show("w600 h400")
g.OnEvent("Close", (*) => ExitApp())

; ── Global State ──
global centerX := -0.5
global centerY := 0.0
global zoom := 150.0
global maxIter := 100
global tmpFile := A_Temp "\ahk_mandelbrot.png"
global viewW := 600
global viewH := 400

g.OnEvent("Size", OnGuiSize)

OnGuiSize(guiObj, minMax, width, height) {
    if (minMax = -1 || width < 10 || height < 10)
        return
    global viewW := width, viewH := height
    pic.Move(0, 0, width, height)
    SetTimer(DrawFractal, -150) ; Debounce rendering so resize is smooth
}

DrawFractal() {
    global centerX, centerY, zoom, maxIter, tmpFile, viewW, viewH
    t := A_TickCount

    ; Call the C# renderer natively with dynamic window size!
    FractalEngine.Render(centerX, centerY, zoom, viewW, viewH, tmpFile, maxIter)

    elapsed := A_TickCount - t
    pic.Value := tmpFile
    lblInfo.Value := "Rendered in " elapsed "ms | Zoom: " Round(zoom, 1) "x"
}

DrawFractal()

Navigate(dx, dy, dz) {
    global centerX, centerY, zoom, maxIter
    centerX += dx / zoom
    centerY += dy / zoom
    zoom *= dz
    if (dz > 1.0)
        maxIter += 10
    else if (dz < 1.0)
        maxIter := Max(50, maxIter - 10)
    DrawFractal()
}

; ── Hotkeys scoped to the GUI ──
HotIfWinActive("AHK# — Parallel Mandelbrot")
Hotkey("Left", (*) => Navigate(-50, 0, 1.0))
Hotkey("Right", (*) => Navigate(50, 0, 1.0))
Hotkey("Up", (*) => Navigate(0, -50, 1.0))
Hotkey("Down", (*) => Navigate(0, 50, 1.0))
Hotkey("NumpadAdd", (*) => Navigate(0, 0, 1.5))
Hotkey("NumpadSub", (*) => Navigate(0, 0, 1 / 1.5))
HotIf()