;; AHK# Example 32 — Cross-Module References
;; One CSModule can reference another's compiled assembly.
;; This enables composable, reusable module architectures.

#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\lib\ahk#.ahk

; ── Base Module: MathCore ─────────────────────────────────────────────────────
; This module compiles first and provides shared math functions.

class MathCore extends _CSModule {
    static CSharp := '
    (
        public static double Hypotenuse(double a, double b) {
            return Math.Sqrt(a * a + b * b);
        }

        public static double Clamp(double value, double min, double max) {
            return Math.Max(min, Math.Min(max, value));
        }

        public static double Lerp(double a, double b, double t) {
            return a + (b - a) * Clamp(t, 0, 1);
        }

        public static double DegreesToRadians(double degrees) {
            return degrees * Math.PI / 180.0;
        }
    )'
}

; ── Dependent Module: Physics ─────────────────────────────────────────────────
; References MathCore's compiled DLL — can call MathCore.Hypotenuse() etc.

class Physics extends _CSModule {
    static References := CS.ModuleRef(MathCore)
    static CSharp := '
    (
        public static double Velocity(double dx, double dy, double dt) {
            return MathCore.Hypotenuse(dx, dy) / dt;
        }

        public static double KineticEnergy(double mass, double vx, double vy) {
            double speed = MathCore.Hypotenuse(vx, vy);
            return 0.5 * mass * speed * speed;
        }

        public static string ProjectileInfo(double angle, double speed) {
            double rad = MathCore.DegreesToRadians(angle);
            double vx = speed * Math.Cos(rad);
            double vy = speed * Math.Sin(rad);
            double range = (speed * speed * Math.Sin(2 * rad)) / 9.81;
            double maxH = (vy * vy) / (2 * 9.81);
            double time = (2 * vy) / 9.81;

            return "Angle: " + angle + " deg  Speed: " + speed + " m/s"
                + "\nVx: " + vx.ToString("F2") + "  Vy: " + vy.ToString("F2")
                + "\nRange: " + range.ToString("F2") + " m"
                + "\nMax Height: " + maxH.ToString("F2") + " m"
                + "\nFlight Time: " + time.ToString("F2") + " s";
        }
    )'
}

; ── Test ──────────────────────────────────────────────────────────────────────

; MathCore tests
hyp := MathCore.Hypotenuse(3, 4)
lerp := MathCore.Lerp(0, 100, 0.75)
rad := MathCore.DegreesToRadians(90)

msg := "── MathCore ──"
    . "`nHypotenuse(3, 4) = " hyp
    . "`nLerp(0, 100, 0.75) = " lerp
    . "`nDeg→Rad(90) = " Format("{:.4f}", rad)
MsgBox(msg, "AHK# — MathCore Module")

; Physics tests (calls MathCore internally!)
vel := Physics.Velocity(30, 40, 2)
ke := Physics.KineticEnergy(10, 3, 4)
proj := Physics.ProjectileInfo(45, 50)

msg2 := "── Physics (uses MathCore) ──"
    . "`nVelocity(dx=30, dy=40, dt=2) = " vel " m/s"
    . "`nKE(m=10, vx=3, vy=4) = " ke " J"
    . "`n`n── Projectile ──`n" proj
MsgBox(msg2, "AHK# — Cross-Module References")

MsgBox("Cross-module references work!`n`nPhysics.dll directly calls MathCore.dll functions.", "AHK# — Done", 0x40)
ExitApp()
