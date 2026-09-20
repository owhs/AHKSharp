;; AHK# Example 24 — Parallel Image Processor (Resizer/Converter)
;; Drag and Drop dozens of PNG/BMP files onto the GUI.
;; C# will resize and convert them all to JPEGs instantly using all CPU cores.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

class ImageProcessor extends _CSModule {
    static References := "System.Drawing.dll"
    static CSharp := '
    (
        using System;
        using System.Drawing;
        using System.Drawing.Drawing2D;
        using System.Drawing.Imaging;
        using System.IO;
        using System.Threading.Tasks;
        
        public static string ProcessImages(string filesString, string outDir, int thumbW, int thumbH) {
            if (string.IsNullOrEmpty(filesString)) return "No files provided.";
            string[] files = filesString.Split('|');
            Directory.CreateDirectory(outDir);

            // Look the JPEG *encoder* up by MIME type - list indexes differ between Windows versions
            // (and GetImageDecoders() returns decoders, not encoders).
            ImageCodecInfo encoder = null;
            foreach (ImageCodecInfo codec in ImageCodecInfo.GetImageEncoders()) {
                if (codec.MimeType == "image/jpeg") { encoder = codec; break; }
            }
            if (encoder == null) return "No JPEG encoder is available on this system.";

            int success = 0;
            // Maximize CPU usage to process multiple images concurrently!
            Parallel.ForEach(files, file => {
                try {
                    using (Image img = Image.FromFile(file)) {
                        // Fit inside thumbW x thumbH keeping the aspect ratio (never enlarge)
                        double scale = Math.Min(1.0, Math.Min((double)thumbW / img.Width, (double)thumbH / img.Height));
                        int w = Math.Max(1, (int)Math.Round(img.Width * scale));
                        int h = Math.Max(1, (int)Math.Round(img.Height * scale));

                        using (Bitmap bmp = new Bitmap(w, h))
                        using (Graphics g = Graphics.FromImage(bmp)) {
                            // High quality resizing
                            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                            g.SmoothingMode = SmoothingMode.AntiAlias;
                            g.DrawImage(img, 0, 0, w, h);

                            string name = Path.GetFileNameWithoutExtension(file);
                            string outPath = Path.Combine(outDir, name + "_thumb.jpg");

                            // Save as high-quality JPEG
                            using (var p = new EncoderParameters(1)) {
                                p.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, 90L);
                                bmp.Save(outPath, encoder, p);
                            }
                            System.Threading.Interlocked.Increment(ref success);
                        }
                    }
                } catch { } // Skip invalid files silently
            });
            
            return "Successfully processed " + success + " of " + files.Length + " images.";
        }
    )'
}

; ── UI Setup ──
g := Gui("", "AHK# — Parallel Image Resizer")
g.SetFont("s14 cBlack", "Segoe UI")
g.Add("Text", "w400 center", "Drag && Drop Images Here!")
g.SetFont("s10")
g.Add("Text", "w400 center", "(They will be shrunk to fit 256x256, keeping their aspect ratio, as JPEGs in a 'thumbs' folder)")

lblStatus := g.Add("Text", "w400 center y+20 cBlue", "Waiting for files...")

g.OnEvent("DropFiles", OnFilesDropped)
g.OnEvent("Close", (*) => ExitApp())
g.Show("w420 h120")

OnFilesDropped(guiObj, ctrlObj, fileArray, x, y) {
    if (fileArray.Length == 0)
        return

    lblStatus.Value := "Processing " fileArray.Length " images on background threads..."

    ; We pack the AHK array into a single pipe-delimited string to pass to C# easily
    filesStr := ""
    for file in fileArray {
        filesStr .= file "|"
    }
    filesStr := RTrim(filesStr, "|")

    ; The Output directory is 'thumbs' inside the directory of the first file
    SplitPath(fileArray[1], , &dir)
    outDir := dir "\thumbs"

    global tStart := A_TickCount

    ; Dispatch the heavy image processing to C# ThreadPool!
    ImageProcessor.Async.ProcessImages(filesStr, outDir, 256, 256).Then(OnProcessingDone)
}

OnProcessingDone(result) {
    global tStart
    elapsed := A_TickCount - tStart

    ; Need to recalculate outDir or pass it. We can just parse it from the status text or keep it simple
    lblStatus.Value := result " (Took " elapsed " ms)"
}