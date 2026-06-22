using System;
using System.Collections.Generic;

namespace MiniArcade.Bridge
{
    // ---- Data-driven golf course definition (the "map builder" format) ----
    // ONE definition (authored as JSON in mini-arcade-host/Resources/web/maps/mapN.json) drives BOTH the
    // Unity 3D course (GolfGame.BuildFromDef) AND the phone trap map (web/game.js renderMapFromDef), so the
    // two can never hand-drift. All coordinates are WORLD units (same space the ball/physics use).
    // JsonUtility-compatible: plain [Serializable] classes + List<T> of [Serializable] + floats/strings only.

    [Serializable] public class R4 { public float x0, z0, x1, z1; public string label; }   // a rect (trapBlocks add a label)
    [Serializable] public class WallDef { public float x, z, w, d, yaw; }                    // axis-aligned (or yaw-rotated) bamboo wall: center (x,z), size w(x)*d(z)
    [Serializable] public class RampDef { public float x, z0, ys0, z1, ys1, w; }             // tilted roll surface from (z0,ys0) up to (z1,ys1) at column x
    [Serializable] public class DeckDef { public float x, z, w, d, h; }                      // flat raised plank (bridge): center (x,z), size w*d, top height h
    [Serializable] public class SandDef { public float x, z, r; }                            // round rough/sand patch (slows the ball)
    [Serializable] public class WaterDef { public float x0, z0, x1, z1; }                    // water hazard rect: a ball here at ground level resets to its last safe lie
    [Serializable] public class WindDef { public float x0, z0, x1, z1, dirx, dirz, accel, max; }   // fan push zone (capped carry speed)
    [Serializable] public class FanDef { public float x, z; }                                // carved tiki fan visual (spinning blades)
    // guard: "slide"/"patrol" move a->b on a sine; "rotate" spins a bar of length len around pivot (ax,az)
    [Serializable] public class GuardDef { public string type; public float ax, az, bx, bz, speed, phase, w, len, rotSpeed; }

    [Serializable]
    public class CourseDef
    {
        public string name, theme;
        public float teeX, teeZ, cupX, cupZ;
        public float oobAbsX, oobZMin, oobZMax;
        public float boundX0, boundX1, boundZ0, boundZ1;   // phone trap-map projection bounds (world)
        public List<R4> turf = new List<R4>();             // grass floor pieces (leave the cup hole open)
        public List<R4> trapBlocks = new List<R4>();       // no-trap zones (water/ramp/guard/fan) — shared with the phone
        public List<WallDef> walls = new List<WallDef>();
        public List<RampDef> ramps = new List<RampDef>();
        public List<DeckDef> decks = new List<DeckDef>();
        public List<WaterDef> water = new List<WaterDef>();
        public List<SandDef> sand = new List<SandDef>();
        public List<GuardDef> guards = new List<GuardDef>();
        public List<FanDef> fans = new List<FanDef>();
        public List<WindDef> wind = new List<WindDef>();
    }
}
