using System.Collections.Generic;
using UnityEngine;

namespace MiniArcade.Bridge
{
    /// Multiplayer arcade mini-golf hole (V10) on the V9 stable course.
    /// Each player gets a colour-matched ball + aim arrow; the host drives turns (setTurn),
    /// Unity owns the per-ball physics + per-player strokes and reports ballStopped/holed{id,strokes}.
    /// One bumper trap added. Course art / cup / arrow shape / stop logic unchanged from V9.
    public class GolfGame : MonoBehaviour
    {
        public static GolfGame Instance { get; private set; }
        const string COURSE_BUILD = "MULTIMAP_V14_2026-06-21_Lshape+tikiguards+windrun";
        const string SCENE_NAME = "UnityGolfPolishedCourse";

        const float BallR = 0.18f;
        const float CupHalf = 0.35f;
        const float CupDepth = 0.6f;
        const float RestSpeed = 0.12f;
        const float SettleTime = 0.40f;
        const int BallLayer = 30;        // balls ignore each other (no unfair knock-aways), still hit the course
        // ---- course-specific state (set by LoadCourse; defaults = L-shape V12 so nothing breaks pre-load) ----
        int _courseId = 0;
        Vector3 _cup = new Vector3(4.5f, 0f, 4f);
        Vector3 _tee = new Vector3(-4f, BallR + 0.20f, -8f);
        Vector2 _sandC = new Vector2(-3.7f, 4f);
        float _sandR = 1.45f;
        float _oobAbsX = 8f, _oobZMin = -11f, _oobZMax = 7.5f;          // out-of-bounds box
        readonly List<float[]> _turf = new List<float[]>();             // turf rects {xMin,zMin,xMax,zMax} for trap clamp
        readonly List<float[]> _trapBlock = new List<float[]>();        // extra no-trap rects (island, guard paths) {xMin,zMin,xMax,zMax}
        bool _buildingCourse;                                           // when true, builder helpers register objects for cleanup
        readonly List<GameObject> _courseObjects = new List<GameObject>();
        readonly List<Guard> _guards = new List<Guard>();
        static readonly Vector2 BumperPos = new Vector2(1.0f, 4.2f);    // L-shape static bumper
        // ---- map-3 fan/wind hazard (null/0 on the other courses, so they are untouched) ----
        float[] _windRect;                   // {xMin,zMin,xMax,zMax} push zone; null = no wind
        Vector2 _windDir = Vector2.zero;     // normalized push direction (xz plane)
        float _windAccel;                    // push strength (units/s^2); 0 = off
        float _windMax;                      // cap on wind-aligned carry speed (m/s) so dwell time can't pile up
        Transform _fanBlades;                // spinning fan blades (visual only), rotated each frame
        const float BumperR = 0.36f;
        const float BoostR = 0.55f;          // planted boost-pad radius
        const float MaxCamSpeed = 16f;       // follow-camera SmoothDamp clamp

        class Player
        {
            public string id;
            public Color color;
            public Rigidbody ball;
            public Renderer rend;
            public int strokes;
            public bool holed;
            public bool inFlight;
            public float still, flight;
            public bool enteredWell;
        }

        // A player-planted sabotage trap: starts HIDDEN; reveals (pops up) + acts only when a ball reaches it.
        class Trap
        {
            public string type;          // "bumper" | "boost"
            public Vector2 pos;          // xz world
            public float trigR;          // trigger radius
            public GameObject visA, visB;
            public Vector3 scaleA, scaleB;
            public bool revealed;
            public float cool, anim;     // re-trigger cooldown + reveal-pop timer
        }

        // A moving tiki guard: a KINEMATIC obstacle the dynamic ball collides with reliably. Moves on a
        // predictable sine path between two endpoints so players can learn the timing.
        class Guard
        {
            public Transform tr;
            public Rigidbody rb;         // kinematic (MovePosition) so the ContinuousDynamic ball never clips through
            public Vector3 a, b;         // path endpoints (slide guards)
            public float speed, phase;   // sine speed + phase offset (predictable, never random)
            public bool rot;             // true = rotating blocker (spins instead of sliding)
            public float rotSpeed;       // constant deg/s for rotating blockers (predictable)
        }

        readonly List<Player> _players = new List<Player>();
        int _active = -1;
        int _maxStrokes = 8;

        Transform _aimShaft, _aimHead;
        Renderer _aimShaftR, _aimHeadR;
        Shader _shader, _shaderUnlit, _shaderTrans;
        string _shaderName = "?";
        Texture2D _turfTex, _sandTex;
        PhysicsMaterial _wallMat, _turfMat, _ballMat, _bumperMat;
        float _aimAngle, _aimPower, _neutralAngle;   // _aimAngle = phone swipe (relative); _neutralAngle = per-turn world reference (toward cup)
        Camera _cam; Vector3 _camVel;        // follow-camera state
        readonly List<Trap> _traps = new List<Trap>();   // player-planted HIDDEN traps (revealed only when a ball triggers them; cleared each hole)
        const float RevealTime = 0.32f;      // reveal-pop animation length
        string _status = "Waiting for players…";
        static bool _showDebug = false;
        GUIStyle _hud, _hudBig, _dbg, _ver, _col;

#if MINIARCADE_THINSLICE
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void Boot()
        {
            if (Instance != null) return;
            var go = new GameObject("GolfGame"); DontDestroyOnLoad(go); Instance = go.AddComponent<GolfGame>();
            var bridge = new GameObject("UnityBridge"); DontDestroyOnLoad(bridge); bridge.AddComponent<UnityBridge>();
        }
#endif

        void Awake() { BuildAll(); }

        public void PreviewArrow() => UpdateArrow();   // editor preview: pose the active arrow without play-mode Update

        public void BuildAll()   // public so the in-editor preview renderer can build the scene without play mode
        {
            Instance = this;
            Physics.gravity = new Vector3(0f, -16f, 0f);
            Physics.IgnoreLayerCollision(BallLayer, BallLayer, true);   // balls never collide with each other
            RenderSettings.ambientLight = new Color(0.30f, 0.32f, 0.34f);
            ResolveShaders();
            _turfTex = MakeNoiseTex(7, new Color(0.10f, 0.245f, 0.135f), 0.05f, true);
            _sandTex = MakeSandTex();
            _wallMat = new PhysicsMaterial("wall") { bounciness = 0.80f, dynamicFriction = 0.07f, staticFriction = 0.07f,
                frictionCombine = PhysicsMaterialCombine.Minimum, bounceCombine = PhysicsMaterialCombine.Maximum };
            _turfMat = new PhysicsMaterial("turf") { bounciness = 0.05f, dynamicFriction = 0.45f, staticFriction = 0.50f,
                frictionCombine = PhysicsMaterialCombine.Average, bounceCombine = PhysicsMaterialCombine.Average };
            _ballMat = new PhysicsMaterial("ball") { bounciness = 0.45f, dynamicFriction = 0.30f, staticFriction = 0.35f,
                frictionCombine = PhysicsMaterialCombine.Average, bounceCombine = PhysicsMaterialCombine.Average };
            _bumperMat = new PhysicsMaterial("bumper") { bounciness = 0.92f, dynamicFriction = 0.05f, staticFriction = 0.05f,
                frictionCombine = PhysicsMaterialCombine.Minimum, bounceCombine = PhysicsMaterialCombine.Maximum };
            BuildCamera(); BuildLight(); BuildAim();
            LoadCourse(_courseId); BuildCourse();
            Debug.Log("[GOLF] COURSE=" + COURSE_BUILD + " SCENE=" + SCENE_NAME + " shader=" + _shaderName);
        }

        // Set the course-specific geometry params. L-shape (0) = exact V12 values; Tiki (1) = new compact course.
        void LoadCourse(int id)
        {
            _courseId = id; _turf.Clear(); _trapBlock.Clear();
            _windRect = null; _windDir = Vector2.zero; _windAccel = 0f; _windMax = 0f; _fanBlades = null;   // off unless a course sets it
            if (id == 2)
            {
                // ---- TIKI WIND RUN (map 3): 3 lanes — SAFE left, SKILL middle (sliding gate),
                // RISKY right (raised ramp/bridge over a sand pit + a fan that blows toward the cup).
                _tee = new Vector3(0f, BallR + 0.20f, -7.5f);
                _cup = new Vector3(0f, 0f, 3.2f);                       // top-centre; all 3 lanes converge here
                _sandC = new Vector2(3.6f, 0.8f); _sandR = 1.7f;        // sand pit the risky bridge crosses
                _oobAbsX = 7f; _oobZMin = -10.5f; _oobZMax = 6f;
                _turf.Add(new float[] { -5.5f, -9f, 5.5f, 2.85f });     // main field (below cup row)
                _turf.Add(new float[] { -5.5f, 2.85f, -0.35f, 4.5f });  // left of cup
                _turf.Add(new float[] { 0.35f, 2.85f, 5.5f, 4.5f });    // right of cup
                _trapBlock.Add(new float[] { -1.9f, -4.3f, -1.5f, 1.7f });  // left lane divider
                _trapBlock.Add(new float[] { 1.5f, -4.3f, 1.9f, 1.7f });    // right lane divider
                _trapBlock.Add(new float[] { 2.0f, -3.7f, 5.3f, 2.7f });    // risky bridge + sand + rotating guard + fan (no traps)
                _trapBlock.Add(new float[] { -1.3f, -1.7f, 1.3f, -0.3f });  // sliding-gate guard path (skill lane)
                _trapBlock.Add(new float[] { -1.4f, 1.8f, 1.4f, 2.9f });    // patrol guard path near the cup
                _windRect = new float[] { 1.9f, 0.4f, 5.3f, 2.4f };     // upper risky lane (releases BEFORE the cup row)
                _windDir = new Vector2(-1f, 0f); _windAccel = 7f; _windMax = 2.5f;   // blow LEFT toward cup; capped carry speed
            }
            else if (id == 1)
            {
                // ---- TIKI GUARD course (compact rectangle, central island, risky right lane) ----
                _tee = new Vector3(0f, BallR + 0.20f, -7f);
                _cup = new Vector3(1.5f, 0f, 3.5f);   // matches the floor cup-hole gap centre + phone marker
                _sandC = new Vector2(3f, 0.6f); _sandR = 1.15f;          // rough on the risky right lane
                _oobAbsX = 6.5f; _oobZMin = -9.5f; _oobZMax = 6f;
                _turf.Add(new float[] { -4.5f, -7.5f, 4.5f, 3.95f });    // main field (below the cup row)
                _turf.Add(new float[] { -4.5f, 3.0f, 1.0f, 4.0f });      // left of cup
                _turf.Add(new float[] { 2.0f, 3.0f, 4.5f, 4.0f });       // right of cup
                _trapBlock.Add(new float[] { -1.4f, -3.4f, 1.4f, 1.9f }); // central island (no traps)
                _trapBlock.Add(new float[] { 1.2f, -2.4f, 4.6f, -0.6f }); // sliding-gate guard path
                _trapBlock.Add(new float[] { 1.2f, 0.6f, 4.6f, 2.0f });   // patrol guard path
            }
            else
            {
                // ---- L-SHAPE course (V12, unchanged) ----
                _tee = new Vector3(-4f, BallR + 0.20f, -8f);
                _cup = new Vector3(4.5f, 0f, 4f);
                _sandC = new Vector2(-3.7f, 4f); _sandR = 1.45f;
                _oobAbsX = 8f; _oobZMin = -11f; _oobZMax = 7.5f;
                _turf.Add(new float[] { -6f + 0.55f, -10f + 0.55f, -2f - 0.55f, 2.5f });   // vertical leg + corner
                _turf.Add(new float[] { -6f + 0.55f, 2.7f, 6f - 0.55f, 6f - 0.55f });       // horizontal band
                _trapBlock.Add(new float[] { -6f, -3.7f, -2f, -2.3f });                     // V12 gate row (no traps)
            }
        }

        void ResolveShaders()
        {
            string[] names = { "Legacy Shaders/Diffuse", "Unlit/Color", "Sprites/Default", "Standard" };
            foreach (var n in names) { var s = Shader.Find(n); if (s != null) { _shader = s; _shaderName = n; break; } }
            if (_shader == null) { _shader = Shader.Find("Hidden/InternalErrorShader"); _shaderName = "NONE-MAGENTA"; Debug.LogError("[GOLF] no shader!"); }
            _shaderUnlit = Shader.Find("Sprites/Default") ?? _shader;
            _shaderTrans = Shader.Find("Legacy Shaders/Transparent/Diffuse") ?? _shader;
        }
        Material NewMat(Color c) { var m = new Material(_shader); m.color = c; return m; }
        Material NewMatUnlit(Color c) { var m = new Material(_shaderUnlit); m.color = c; m.renderQueue = 3100; return m; }
        Material NewMatTrans(Texture2D tex) { var m = new Material(_shaderTrans); m.color = Color.white; m.mainTexture = tex; m.renderQueue = 3000; return m; }

        Texture2D MakeNoiseTex(int seed, Color baseC, float amp, bool checker)
        {
            int N = 64; var tex = new Texture2D(N, N) { wrapMode = TextureWrapMode.Repeat, filterMode = FilterMode.Bilinear };
            var rng = new System.Random(seed);
            for (int y = 0; y < N; y++) for (int x = 0; x < N; x++)
            {
                float n = (float)rng.NextDouble() * amp - amp * 0.5f;
                float ch = checker ? ((((x / 16) + (y / 16)) % 2 == 0) ? 0.018f : -0.018f) : 0f;
                tex.SetPixel(x, y, new Color(baseC.r + n + ch, baseC.g + n + ch, baseC.b + n + ch));
            }
            tex.Apply(); return tex;
        }

        Texture2D MakeSandTex()
        {
            int N = 128; var tex = new Texture2D(N, N, TextureFormat.RGBA32, false) { wrapMode = TextureWrapMode.Clamp, filterMode = FilterMode.Bilinear };
            var rng = new System.Random(13); var b = new Color(0.74f, 0.59f, 0.34f);
            for (int y = 0; y < N; y++) for (int x = 0; x < N; x++)
            {
                float fine = (float)rng.NextDouble() * 0.12f - 0.06f;
                float coarse = Mathf.PerlinNoise(x * 0.09f, y * 0.09f) * 0.16f - 0.08f;
                float n = fine + coarse;
                float dx = (x + 0.5f) / N - 0.5f, dy = (y + 0.5f) / N - 0.5f, d = Mathf.Sqrt(dx * dx + dy * dy);
                float a = Mathf.Clamp01((0.49f - d) / 0.06f);
                float dark = Mathf.Lerp(0.45f, 1f, Mathf.Clamp01((0.49f - d) / 0.16f));
                tex.SetPixel(x, y, new Color((b.r + n) * dark, (b.g + n) * dark, (b.b + n) * dark, a));
            }
            tex.Apply(); return tex;
        }

        void BuildCamera()
        {
            var go = new GameObject("Main Camera"); DDOL(go);
            var cam = go.AddComponent<Camera>();
            cam.clearFlags = CameraClearFlags.SolidColor; cam.backgroundColor = new Color(0.05f, 0.07f, 0.10f);
            cam.fieldOfView = 54f; go.transform.position = new Vector3(0f, 18f, -13f); go.transform.LookAt(new Vector3(0f, 0f, -1.5f));
            _cam = cam;   // kept so the per-frame follow can track the active ball (in-editor preview keeps this cold-start pose)
        }
        void BuildLight()
        {
            var go = new GameObject("Sun"); DDOL(go);
            var l = go.AddComponent<Light>(); l.type = LightType.Directional; l.intensity = 1.05f; l.color = new Color(1f, 0.98f, 0.94f);
            l.shadows = LightShadows.Soft; l.shadowStrength = 0.72f; go.transform.rotation = Quaternion.Euler(52f, -26f, 0f);
            QualitySettings.shadows = ShadowQuality.All; QualitySettings.shadowResolution = ShadowResolution.VeryHigh;
            QualitySettings.shadowProjection = ShadowProjection.CloseFit; QualitySettings.shadowCascades = 2; QualitySettings.shadowDistance = 50f;
        }

        void BuildCourse()
        {
            ClearCourse();
            _buildingCourse = true;
            if (_courseId == 2) BuildCourseWindRun(); else if (_courseId == 1) BuildCourseTiki(); else BuildCourseLShape();
            BuildCup();
            BuildGuards();
            _buildingCourse = false;
        }
        void ClearCourse()
        {
            foreach (var g in _courseObjects) if (g != null) Kill(g);
            _courseObjects.Clear();
            foreach (var gd in _guards) if (gd != null && gd.tr != null) Kill(gd.tr.gameObject);
            _guards.Clear();
        }
        static void Kill(GameObject go) { if (Application.isPlaying) Destroy(go); else DestroyImmediate(go); }   // edit-mode preview needs Immediate
        void BuildCourseLShape()
        {
            BoxTurf("Floor_Vert", new Vector3(-4f, -0.25f, -4.2f), new Vector3(4.4f, 0.5f, 12.0f), _turfTex, _turfMat);
            BoxTurf("Floor_HoriL", new Vector3(-0.95f, -0.25f, 4f), new Vector3(10.1f, 0.5f, 4.4f), _turfTex, _turfMat);
            BoxTurf("Floor_HoriR", new Vector3(5.55f, -0.25f, 4f), new Vector3(1.3f, 0.5f, 4.4f), _turfTex, _turfMat);
            BoxTurf("Floor_HoriB", new Vector3(4.5f, -0.25f, 2.7f), new Vector3(0.8f, 0.5f, 1.8f), _turfTex, _turfMat);
            BoxTurf("Floor_HoriF", new Vector3(4.5f, -0.25f, 5.3f), new Vector3(0.8f, 0.5f, 1.8f), _turfTex, _turfMat);

            WallRail("W_Bottom", new Vector3(-4f, 0.35f, -10f), new Vector3(4.6f, 0.7f, 0.3f));
            WallRail("W_Left", new Vector3(-6f, 0.35f, -2f), new Vector3(0.3f, 0.7f, 16.6f));
            WallRail("W_Top", new Vector3(0f, 0.35f, 6f), new Vector3(12.6f, 0.7f, 0.3f));
            WallRail("W_Right", new Vector3(6f, 0.35f, 4f), new Vector3(0.3f, 0.7f, 4.6f));
            WallRail("W_HoriBottom", new Vector3(2f, 0.35f, 2f), new Vector3(8.6f, 0.7f, 0.3f));
            WallRail("W_InnerRight", new Vector3(-2f, 0.35f, -4f), new Vector3(0.3f, 0.7f, 12.6f));

            WallRail("Gate_L", new Vector3(-5.25f, 0.35f, -3f), new Vector3(1.5f, 0.7f, 0.3f));
            WallRail("Gate_R", new Vector3(-2.75f, 0.35f, -3f), new Vector3(1.5f, 0.7f, 0.3f));

            BambooPost(-6f, -10f); BambooPost(-6f, 6f); BambooPost(6f, 6f); BambooPost(6f, 2f); BambooPost(-2f, 2f); BambooPost(-2f, -10f);
            BambooPost(-4.5f, -3f); BambooPost(-3.5f, -3f);

            // tan sand bunker (heavy slowdown applied in Update over this region)
            var sand = new GameObject("Sand"); DDOL(sand);
            sand.AddComponent<MeshFilter>().sharedMesh = MakeDisk(_sandR, 64);
            sand.AddComponent<MeshRenderer>().material = NewMatTrans(_sandTex);
            sand.transform.position = new Vector3(_sandC.x, 0.012f, _sandC.y);

            BuildBumper(BumperPos.x, BumperPos.y);   // permanent course furniture (visible obstacle, like the sand)
        }

        // The permanent course bumper: a visible round post the ball banks off (always shown; NOT a planted trap).
        void BuildBumper(float x, float z)
        {
            var go = GameObject.CreatePrimitive(PrimitiveType.Cylinder); DDOL(go);
            Destroy(go.GetComponent<Collider>());                       // Cylinder's default collider is unreliable for bounce
            go.name = "Bumper"; go.transform.position = new Vector3(x, 0.28f, z);
            go.transform.localScale = new Vector3(BumperR * 2f, 0.28f, BumperR * 2f);
            go.GetComponent<MeshRenderer>().material = NewMat(new Color(0.88f, 0.22f, 0.28f));   // bright red bumper
            var cc = go.AddComponent<CapsuleCollider>(); cc.direction = 1; cc.material = _bumperMat;   // round, high-bounce
            go.layer = 0;
            var cap = Cyl("BumperCap", new Vector3(x, 0.44f, z), BumperR + 0.04f, 0.06f, new Color(0.98f, 0.98f, 0.98f));   // white top ring (arcade look)
            cap.transform.localScale = new Vector3((BumperR + 0.04f) * 2f, 0.03f, (BumperR + 0.04f) * 2f);
        }

        // ===================== TIKI GUARD course (map 1) =====================
        // Compact rectangle x[-4.5,4.5] z[-7.5,4]; a central stone island splits a SAFE left lane from a
        // RISKY right lane (sliding-gate + patrolling guards + rough). Cup top-right-of-centre at (1.5,3.5).
        void BuildCourseTiki()
        {
            var stone = new Color(0.16f, 0.21f, 0.13f);   // dark jungle stone for the island
            // floor: full field with ONLY the cup hole (x[1.15,1.85] z[3.15,3.85]) left open
            BoxTurf("T_Floor", new Vector3(0f, -0.25f, -2.175f), new Vector3(9.0f, 0.5f, 10.65f), _turfTex, _turfMat);
            BoxTurf("T_CupL", new Vector3(-1.675f, -0.25f, 3.575f), new Vector3(5.65f, 0.5f, 0.85f), _turfTex, _turfMat);
            BoxTurf("T_CupR", new Vector3(3.175f, -0.25f, 3.575f), new Vector3(2.65f, 0.5f, 0.85f), _turfTex, _turfMat);
            BoxTurf("T_CupB", new Vector3(1.5f, -0.25f, 3.925f), new Vector3(0.7f, 0.5f, 0.15f), _turfTex, _turfMat);

            // bamboo perimeter walls
            WallRail("TW_Bottom", new Vector3(0f, 0.35f, -7.5f), new Vector3(9.3f, 0.7f, 0.3f));
            WallRail("TW_Top", new Vector3(0f, 0.35f, 4f), new Vector3(9.3f, 0.7f, 0.3f));
            WallRail("TW_Left", new Vector3(-4.5f, 0.35f, -1.75f), new Vector3(0.3f, 0.7f, 11.8f));
            WallRail("TW_Right", new Vector3(4.5f, 0.35f, -1.75f), new Vector3(0.3f, 0.7f, 11.8f));

            // central stone island (the fork) + tiki totems guarding it
            Box("T_Island", new Vector3(0f, 0.30f, -0.75f), new Vector3(2.0f, 0.6f, 4.9f), stone, _wallMat);
            IslandTotem(new Vector3(0f, 0.6f, 1.1f), 1.0f);
            IslandTotem(new Vector3(0f, 0.6f, -2.6f), 1.0f);

            BambooPost(-4.5f, -7.5f); BambooPost(4.5f, -7.5f); BambooPost(-4.5f, 4f); BambooPost(4.5f, 4f);

            // rough/sand on the risky right lane (slowdown handled in Update via OverSand)
            var sand = new GameObject("T_Sand"); DDOL(sand);
            sand.AddComponent<MeshFilter>().sharedMesh = MakeDisk(_sandR, 64);
            sand.AddComponent<MeshRenderer>().material = NewMatTrans(_sandTex);
            sand.transform.position = new Vector3(_sandC.x, 0.012f, _sandC.y);
        }

        // ===================== TIKI WIND RUN course (map 3) =====================
        // Compact rectangle x[-5.5,5.5] z[-9,4.5]. Two free-standing dividers split THREE lanes that
        // converge at the top-centre cup (0,3.2): SAFE left (clear, indirect) / SKILL middle (sliding gate) /
        // RISKY right (a raised ramp+bridge over a sand pit + a fan blowing the ball left toward the cup).
        void BuildCourseWindRun()
        {
            // floor: full field with ONLY the cup hole (x[-0.35,0.35] z[2.85,3.55]) left open
            BoxTurf("WR_Floor", new Vector3(0f, -0.25f, -3.075f), new Vector3(11.0f, 0.5f, 11.85f), _turfTex, _turfMat);
            BoxTurf("WR_CupL", new Vector3(-2.925f, -0.25f, 3.675f), new Vector3(5.15f, 0.5f, 1.65f), _turfTex, _turfMat);
            BoxTurf("WR_CupR", new Vector3(2.925f, -0.25f, 3.675f), new Vector3(5.15f, 0.5f, 1.65f), _turfTex, _turfMat);
            BoxTurf("WR_CupB", new Vector3(0f, -0.25f, 4.025f), new Vector3(0.7f, 0.5f, 0.95f), _turfTex, _turfMat);

            // bamboo perimeter
            WallRail("WRW_Bottom", new Vector3(0f, 0.35f, -9f), new Vector3(11.3f, 0.7f, 0.3f));
            WallRail("WRW_Top", new Vector3(0f, 0.35f, 4.5f), new Vector3(11.3f, 0.7f, 0.3f));
            WallRail("WRW_Left", new Vector3(-5.5f, 0.35f, -2.25f), new Vector3(0.3f, 0.7f, 13.8f));
            WallRail("WRW_Right", new Vector3(5.5f, 0.35f, -2.25f), new Vector3(0.3f, 0.7f, 13.8f));

            // lane dividers (free-standing; the tee mouth z<-4.2 stays OPEN so nothing blocks the first shot)
            WallRail("WR_DivL", new Vector3(-1.7f, 0.35f, -1.3f), new Vector3(0.3f, 0.7f, 5.8f));
            WallRail("WR_DivR", new Vector3(1.7f, 0.35f, -1.3f), new Vector3(0.3f, 0.7f, 5.8f));

            // RISKY shortcut: a sand pit crossed by a raised ramp + flat bridge with a drop-off near the cup
            var sand = new GameObject("WR_Sand"); DDOL(sand);
            sand.AddComponent<MeshFilter>().sharedMesh = MakeDisk(_sandR, 64);
            sand.AddComponent<MeshRenderer>().material = NewMatTrans(_sandTex);
            sand.transform.position = new Vector3(_sandC.x, 0.012f, _sandC.y);
            var plank = new Color(0.52f, 0.37f, 0.19f);                                                              // wood: reads clearly as a BRIDGE (not green-on-green)
            RampBox("WR_Ramp", 3.6f, -1.4f, 0f, 0.1f, 0.4f, 1.5f, 0.30f, plank);                                     // up-ramp (surface 0 -> 0.4)
            Box("WR_Deck", new Vector3(3.6f, 0.15f, 0.95f), new Vector3(1.5f, 0.5f, 1.9f), plank, _turfMat);         // flat bridge top y=0.4 -> drop-off at z=1.9 (sides OPEN: off-centre = into the sand)

            // FAN: a carved tiki wind totem against the right wall that blows LEFT across the upper risky lane
            BuildFan(new Vector3(5.15f, 0f, 2.2f));

            // tiki dressing (all collider-free decoration)
            BambooPost(-5.5f, -9f); BambooPost(5.5f, -9f); BambooPost(-5.5f, 4.5f); BambooPost(5.5f, 4.5f);
            BambooPost(-1.7f, 1.9f); BambooPost(1.7f, 1.9f); BambooPost(-1.7f, -4.3f); BambooPost(1.7f, -4.3f);
            IslandTotem(new Vector3(-1.2f, 0f, 4.05f), 0.8f); IslandTotem(new Vector3(1.2f, 0f, 4.05f), 0.8f);
        }

        // a tilted ramp whose TOP SURFACE runs from (z0,ys0) up to (z1,ys1) at column x (solid roll surface)
        void RampBox(string name, float x, float z0, float ys0, float z1, float ys1, float width, float thick, Color color)
        {
            float dz = z1 - z0, dy = ys1 - ys0;
            float ang = Mathf.Atan2(dy, dz);                            // radians
            float len = Mathf.Sqrt(dz * dz + dy * dy);
            float drop = (thick * 0.5f) / Mathf.Cos(ang);              // lower the centreline so the TOP hits ys0..ys1
            var go = GameObject.CreatePrimitive(PrimitiveType.Cube); DDOL(go);
            go.name = name;
            go.transform.position = new Vector3(x, (ys0 + ys1) * 0.5f - drop, (z0 + z1) * 0.5f);
            go.transform.rotation = Quaternion.Euler(-ang * Mathf.Rad2Deg, 0f, 0f);   // raise the +z end
            go.transform.localScale = new Vector3(width, thick, len);
            go.GetComponent<MeshRenderer>().material = NewMat(color);
            go.GetComponent<BoxCollider>().material = _turfMat;
        }

        // a carved tiki wind fan: trunk + 4 palm-leaf blades that spin around the x-axis (blow direction = -x)
        void BuildFan(Vector3 pos)
        {
            var wood = new Color(0.40f, 0.26f, 0.14f); var wood2 = new Color(0.29f, 0.18f, 0.10f);
            var leaf = new Color(0.22f, 0.34f, 0.14f);
            Cyl("Fan_Post", new Vector3(pos.x, 0.5f, pos.z), 0.14f, 1.0f, wood2);          // trunk
            Cyl("Fan_Collar", new Vector3(pos.x, 1.0f, pos.z), 0.17f, 0.14f, wood);        // collar
            var hub = new GameObject("Fan_Hub"); DDOL(hub);
            hub.transform.position = new Vector3(pos.x - 0.10f, 1.0f, pos.z);
            hub.transform.rotation = Quaternion.Euler(0f, 90f, 0f);                        // spin axis (local z) -> world x
            for (int b = 0; b < 4; b++)
            {
                var bl = GameObject.CreatePrimitive(PrimitiveType.Cube); DDOL(bl); Destroy(bl.GetComponent<Collider>());
                bl.name = "Fan_Blade" + b; bl.transform.SetParent(hub.transform, false);
                bl.transform.localRotation = Quaternion.Euler(0f, 0f, b * 90f);
                bl.transform.localPosition = bl.transform.localRotation * new Vector3(0f, 0.42f, 0f);
                bl.transform.localScale = new Vector3(0.16f, 0.80f, 0.04f);
                bl.GetComponent<MeshRenderer>().material = NewMat(leaf);
            }
            var cap = GameObject.CreatePrimitive(PrimitiveType.Sphere); DDOL(cap); Destroy(cap.GetComponent<Collider>());
            cap.name = "Fan_HubCap"; cap.transform.SetParent(hub.transform, false); cap.transform.localScale = Vector3.one * 0.22f;
            cap.GetComponent<MeshRenderer>().material = NewMat(wood);
            _fanBlades = hub.transform;
        }

        // a ROTATING tiki blocker: a kinematic bar spinning at a constant (predictable) rate around a pivot
        Guard MakeRotGuard(Vector3 pivot, float barLen, float rotSpeed)
        {
            var root = new GameObject("TikiRotGuard"); if (Application.isPlaying) DontDestroyOnLoad(root);
            var rb = root.AddComponent<Rigidbody>(); rb.isKinematic = true; rb.useGravity = false;
            rb.interpolation = RigidbodyInterpolation.Interpolate; rb.collisionDetectionMode = CollisionDetectionMode.ContinuousSpeculative;
            var col = root.AddComponent<BoxCollider>(); col.center = new Vector3(0f, 0.45f, 0f);
            col.size = new Vector3(barLen, 0.9f, 0.42f); col.material = _bumperMat;   // long bouncy bar
            BuildRotBar(root.transform, barLen);
            root.transform.position = pivot;
            return new Guard { tr = root.transform, rb = rb, a = pivot, b = pivot, rot = true, rotSpeed = rotSpeed };
        }
        void BuildRotBar(Transform holder, float barLen)
        {
            var wood = new Color(0.40f, 0.26f, 0.14f); var wood2 = new Color(0.29f, 0.18f, 0.10f); var paint = new Color(0.85f, 0.64f, 0.20f);
            Prim(holder, new Vector3(0f, 0.45f, 0f), new Vector3(barLen, 0.34f, 0.30f), wood);    // bar
            Prim(holder, new Vector3(0f, 0.45f, 0f), new Vector3(0.28f, 0.5f, 0.42f), wood2);     // hub
            float e = barLen * 0.5f - 0.18f;
            for (int s = -1; s <= 1; s += 2)
            {
                Prim(holder, new Vector3(e * s, 0.55f, 0f), new Vector3(0.34f, 0.5f, 0.40f), wood2);       // end head
                Prim(holder, new Vector3(e * s, 0.55f, -0.21f), new Vector3(0.22f, 0.12f, 0.04f), paint);  // face paint
            }
        }

        // ---- moving tiki guards (Tiki + Wind Run courses) ----
        void BuildGuards()
        {
            if (_courseId == 1)
            {
                // Guard 1 — SLIDING TIKI GATE across the risky right lane (z=-2): time the shot through the open side.
                _guards.Add(MakeGuard(new Vector3(1.7f, 0f, -2f), new Vector3(3.7f, 0f, -2f), 1.1f, 0f, 1.1f));
                // Guard 2 — PATROLLING TIKI STATUE across the upper right lane (z=1.5): the safe LEFT route avoids it.
                _guards.Add(MakeGuard(new Vector3(1.7f, 0f, 1.5f), new Vector3(4.0f, 0f, 1.5f), 0.8f, 1.6f, 0.85f));
                return;
            }
            if (_courseId == 2)
            {
                // Wind Run: SLIDING gate (skill lane) + ROTATING blocker (risky lane) + PATROL near the cup.
                _guards.Add(MakeGuard(new Vector3(-1.0f, 0f, -1.0f), new Vector3(1.0f, 0f, -1.0f), 1.0f, 0f, 1.0f));   // sliding gate, middle
                _guards.Add(MakeRotGuard(new Vector3(3.6f, 0f, -2.6f), 2.0f, 55f));                                    // rotating blocker, risky lane
                _guards.Add(MakeGuard(new Vector3(-1.2f, 0f, 2.4f), new Vector3(1.2f, 0f, 2.4f), 0.7f, 1.0f, 0.9f));   // patrol near the cup
                return;
            }
        }
        Guard MakeGuard(Vector3 a, Vector3 b, float speed, float phase, float w)
        {
            var root = new GameObject("TikiGuard"); if (Application.isPlaying) DontDestroyOnLoad(root);   // tracked via _guards, not _courseObjects
            var rb = root.AddComponent<Rigidbody>(); rb.isKinematic = true; rb.useGravity = false;
            rb.interpolation = RigidbodyInterpolation.Interpolate; rb.collisionDetectionMode = CollisionDetectionMode.ContinuousSpeculative;
            var col = root.AddComponent<BoxCollider>(); col.center = new Vector3(0f, 0.45f, 0f);
            col.size = new Vector3(0.55f * w + 0.12f, 0.9f, 0.55f); col.material = _bumperMat;   // reliable bouncy box
            BuildTikiTotem(root.transform, w);
            root.transform.position = a;
            return new Guard { tr = root.transform, rb = rb, a = a, b = b, speed = speed, phase = phase };
        }
        // physics-synced movement (MovePosition in FixedUpdate) so the ContinuousDynamic ball never clips through
        void FixedUpdate()
        {
            for (int i = 0; i < _guards.Count; i++)
            {
                var g = _guards[i]; if (g.rb == null) continue;
                if (g.rot)   // rotating blocker: constant, predictable spin (kinematic MoveRotation)
                {
                    g.rb.MoveRotation(Quaternion.Euler(0f, Time.time * g.rotSpeed, 0f));
                    continue;
                }
                float t = Mathf.Sin(Time.time * g.speed + g.phase) * 0.5f + 0.5f;   // smooth, predictable ping-pong
                g.rb.MovePosition(Vector3.Lerp(g.a, g.b, t));
            }
        }

        // a standalone tiki totem at a world position (course object, cleaned on map switch)
        void IslandTotem(Vector3 worldPos, float w)
        {
            var holder = new GameObject("TikiTotem"); DDOL(holder); holder.transform.position = worldPos;
            BuildTikiTotem(holder.transform, w);
        }
        // a carved tiki totem (stacked wood blocks + a painted face), parented under `holder` (rides with it)
        void BuildTikiTotem(Transform holder, float w)
        {
            var wood = new Color(0.40f, 0.26f, 0.14f); var wood2 = new Color(0.29f, 0.18f, 0.10f);
            var paint = new Color(0.85f, 0.64f, 0.20f); var thatch = new Color(0.20f, 0.30f, 0.13f);
            Prim(holder, new Vector3(0f, 0.42f, 0f), new Vector3(0.55f * w, 0.84f, 0.45f * w), wood);          // body
            Prim(holder, new Vector3(0f, 0.74f, 0f), new Vector3(0.63f * w, 0.16f, 0.52f * w), wood2);         // brow ledge
            Prim(holder, new Vector3(-0.13f * w, 0.58f, -0.23f * w), new Vector3(0.12f * w, 0.12f, 0.05f), paint);  // L eye
            Prim(holder, new Vector3(0.13f * w, 0.58f, -0.23f * w), new Vector3(0.12f * w, 0.12f, 0.05f), paint);   // R eye
            Prim(holder, new Vector3(0f, 0.36f, -0.23f * w), new Vector3(0.28f * w, 0.09f, 0.05f), wood2);     // mouth
            Prim(holder, new Vector3(0f, 0.92f, 0f), new Vector3(0.5f * w, 0.16f, 0.42f * w), thatch);         // thatch cap
        }
        void Prim(Transform holder, Vector3 localPos, Vector3 scale, Color c)
        {
            var go = GameObject.CreatePrimitive(PrimitiveType.Cube); Destroy(go.GetComponent<Collider>());
            go.transform.SetParent(holder, false); go.transform.localPosition = localPos; go.transform.localScale = scale;
            go.GetComponent<MeshRenderer>().material = NewMat(c);
        }

        void BuildCup()
        {
            var dark = new Color(0.02f, 0.025f, 0.025f);
            float wy = -CupDepth * 0.5f;
            InvisBox("Cup_X+", new Vector3(_cup.x + CupHalf, wy, _cup.z), new Vector3(0.08f, CupDepth, 1.1f), _wallMat);
            InvisBox("Cup_X-", new Vector3(_cup.x - CupHalf, wy, _cup.z), new Vector3(0.08f, CupDepth, 1.1f), _wallMat);
            InvisBox("Cup_Z+", new Vector3(_cup.x, wy, _cup.z + CupHalf), new Vector3(1.1f, CupDepth, 0.08f), _wallMat);
            InvisBox("Cup_Z-", new Vector3(_cup.x, wy, _cup.z - CupHalf), new Vector3(1.1f, CupDepth, 0.08f), _wallMat);
            InvisBox("Cup_Floor", new Vector3(_cup.x, -CupDepth, _cup.z), new Vector3(1.1f, 0.08f, 1.1f), null);

            AnnulusTex("Cup_Collar", new Vector3(_cup.x, 0.012f, _cup.z), _turfTex, 0.62f, 0.365f);
            Annulus("Cup_Lip", new Vector3(_cup.x, 0.026f, _cup.z), new Color(0.82f, 0.80f, 0.70f), 0.365f, 0.33f);
            Tube("Cup_Tube", _cup, 0.33f, 0.03f, -0.50f, dark);
            Cyl("Cup_Bottom", new Vector3(_cup.x, -0.52f, _cup.z), 0.33f, 0.04f, new Color(0.01f, 0.012f, 0.012f));

            var pole = Box("FlagPole", new Vector3(_cup.x, 0.69f, _cup.z), new Vector3(0.05f, 1.82f, 0.05f), new Color(0.93f, 0.93f, 0.93f));
            Destroy(pole.GetComponent<Collider>());
            var flag = Box("FlagCloth", new Vector3(_cup.x + 0.26f, 1.44f, _cup.z), new Vector3(0.5f, 0.30f, 0.02f), new Color(0.84f, 0.20f, 0.24f));
            Destroy(flag.GetComponent<Collider>());
        }

        void BuildAim()
        {
            var shaft = GameObject.CreatePrimitive(PrimitiveType.Cube); DDOL(shaft); Destroy(shaft.GetComponent<Collider>());
            shaft.name = "AimShaft"; shaft.transform.localScale = new Vector3(0.10f, 0.02f, 1.05f);
            _aimShaftR = shaft.GetComponent<MeshRenderer>(); _aimShaftR.material = NewMatUnlit(new Color(1f, 0.84f, 0.20f, 0.72f));
            _aimShaft = shaft.transform;
            var head = new GameObject("AimHead"); DDOL(head);
            head.AddComponent<MeshFilter>().sharedMesh = MakeArrowhead();
            _aimHeadR = head.AddComponent<MeshRenderer>(); _aimHeadR.material = NewMatUnlit(new Color(1f, 0.84f, 0.20f, 0.72f));
            _aimHead = head.transform;
            _aimShaft.gameObject.SetActive(false); _aimHead.gameObject.SetActive(false);
        }

        // ---- multiplayer balls ----
        void CreateBall(Player p, int index)
        {
            var go = GameObject.CreatePrimitive(PrimitiveType.Sphere); DDOL(go); go.name = "Ball_" + index;
            go.layer = BallLayer;
            go.transform.localScale = Vector3.one * (BallR * 2f);
            p.rend = go.GetComponent<MeshRenderer>(); p.rend.material = NewMat(p.color);
            go.GetComponent<SphereCollider>().material = _ballMat;
            p.ball = go.AddComponent<Rigidbody>(); p.ball.mass = 1f; p.ball.linearDamping = 0.32f; p.ball.angularDamping = 0.45f;
            p.ball.collisionDetectionMode = CollisionDetectionMode.ContinuousDynamic; p.ball.interpolation = RigidbodyInterpolation.Interpolate;
            var tee = TeeFor(index); p.ball.position = tee; go.transform.position = tee;   // transform too: edit-mode preview + clean spawn
        }
        // Single SHARED fair tee for every player (GDD: all drive from the same Tee Box). The old
        // per-index fan made each player start from a different x — unfair. Non-active balls are
        // hidden (RefreshBalls) so they never visually stack on this one spot.
        Vector3 TeeFor(int i) => _tee;

        public void OnHostMessage(string json)
        {
            string t = JStr(json, "t");
            if (t == "newHole") NewHole(JStr(json, "players"), Mathf.RoundToInt(JNum(json, "max")), Mathf.RoundToInt(JNum(json, "map")));
            else if (t == "setTurn") SetTurn(JStr(json, "id"));
            else if (t == "shoot") Shoot(JStr(json, "id"), JNum(json, "angle"), JNum(json, "power"));
            else if (t == "aim") { _aimAngle = JNum(json, "angle"); _aimPower = JNum(json, "power"); }
            else if (t == "setTraps") SetTraps(JStr(json, "traps"));   // planted traps for this round ("type,x,y;...")
            else if (t == "reset") ReTeeAll();
            else if (t == "debug") _showDebug = !_showDebug;
        }

        void NewHole(string playersStr, int max, int map)
        {
            _maxStrokes = max > 0 ? max : 8;
            if (map != _courseId) { LoadCourse(map); BuildCourse(); }   // switch maps: rebuild geometry + guards
            foreach (var p in _players) if (p.ball != null) Destroy(p.ball.gameObject);
            _players.Clear(); _active = -1;
            ClearTraps();   // no trap may carry over from the previous round
            if (!string.IsNullOrEmpty(playersStr))
            {
                var parts = playersStr.Split(';');
                foreach (var part in parts)
                {
                    if (string.IsNullOrEmpty(part)) continue;
                    var kv = part.Split('|');
                    var p = new Player { id = kv[0], color = kv.Length > 1 ? HexColor(kv[1]) : Color.white };
                    _players.Add(p);
                }
                for (int i = 0; i < _players.Count; i++) CreateBall(_players[i], i);
            }
            RefreshBalls();   // _active == -1 -> all balls hidden until the first turn (no stacking on the shared tee)
            _status = "Get ready!";
            Debug.Log("[GOLF] newHole players=" + _players.Count + " max=" + _maxStrokes);
        }

        void SetTurn(string id)
        {
            _active = _players.FindIndex(p => p.id == id);
            // defensively settle every off-turn ball so none can drift invisibly between turns
            for (int i = 0; i < _players.Count; i++)
            {
                if (i == _active || _players[i].ball == null || _players[i].holed) continue;
                _players[i].ball.linearVelocity = Vector3.zero; _players[i].ball.angularVelocity = Vector3.zero; _players[i].inFlight = false;
            }
            RefreshBalls();   // show only the active player's ball; their ball stays at its lie (GDD: play it where it lies)
            if (_active < 0) { _status = "…"; return; }
            var p = _players[_active];
            // reset the per-turn reference + aim TOGETHER: neutral = toward the cup, aim = 0.
            // => phone "up" == camera "forward" == toward the cup at the start of every turn (no drift).
            if (p.ball != null) _neutralAngle = Mathf.Atan2(_cup.x - p.ball.position.x, _cup.z - p.ball.position.z) * Mathf.Rad2Deg;
            _aimAngle = 0f; _aimPower = 0f;
            var ac = ArrowCol(p.color);
            if (_aimShaftR != null) _aimShaftR.material.color = ac;
            if (_aimHeadR != null) _aimHeadR.material.color = ac;
            _status = "Player " + (_active + 1) + " — your shot";
            Debug.Log("[GOLF] setTurn -> " + id + " (index " + _active + ")");
        }

        void Shoot(string id, float angleDeg, float power01)
        {
            int idx = _players.FindIndex(p => p.id == id);
            if (idx < 0 || idx != _active) return;                         // only the active player may shoot
            var p = _players[idx];
            if (p.ball == null || p.inFlight || p.holed) return;
            if (p.ball.linearVelocity.magnitude > 0.2f) return;            // never shoot while moving
            power01 = Mathf.Clamp01(power01); _aimAngle = angleDeg;
            float speed = Mathf.Lerp(3.5f, 15f, power01);
            Vector3 dir = WorldAim();   // neutral(toward cup) + phone swipe; the camera follows this same direction
            p.ball.linearVelocity = dir * speed; p.ball.angularVelocity = Vector3.zero;
            p.strokes++; p.inFlight = true; p.still = 0f; p.flight = 0f; p.enteredWell = false;
            _status = "Player " + (idx + 1) + " — stroke " + p.strokes + "…";
            Debug.Log("[GOLF] P" + (idx + 1) + " shot #" + p.strokes + " angle=" + angleDeg + " power=" + power01);
            Send("{\"t\":\"shotStarted\",\"id\":\"" + p.id + "\",\"strokes\":" + p.strokes + "}");
        }

        void ReTeeAll()
        {
            for (int i = 0; i < _players.Count; i++)
            {
                var p = _players[i];
                if (p.ball == null) continue;
                p.ball.isKinematic = false; p.ball.linearVelocity = Vector3.zero; p.ball.angularVelocity = Vector3.zero;
                p.ball.position = TeeFor(i); p.strokes = 0; p.holed = false; p.inFlight = false; p.still = 0f; p.enteredWell = false;
            }
            _active = -1; _status = "Get ready!"; RefreshBalls();
        }

        // Only the active player's ball is shown (avoids stacking on the shared tee + keeps the follow-cam clean).
        void RefreshBalls()
        {
            for (int i = 0; i < _players.Count; i++)
                if (_players[i].rend != null) _players[i].rend.enabled = (i == _active);
        }

        // ---- player-planted HIDDEN traps (round-scoped, WORLD coordinates) ----
        // Course geometry is shared with the phone trap map (web/game.js `COURSE`) so a phone tap lands
        // at the SAME world spot on the TV. World rect x[-6.5,6.5] z[-10.5,6.5]; the L = vertical leg
        // x[-6,-2] z[-10,2] + horizontal band x[-6,6] z[2,6]. tee(-4,-8), cup(4.5,4).
        void ClearTraps()
        {
            foreach (var t in _traps) { if (t.visA != null) Destroy(t.visA); if (t.visB != null) Destroy(t.visB); }
            _traps.Clear();
        }
        void SetTraps(string s)
        {
            ClearTraps();
            if (string.IsNullOrEmpty(s)) return;
            foreach (var part in s.Split(';'))
            {
                if (string.IsNullOrEmpty(part)) continue;
                var f = part.Split(',');
                if (f.Length < 3) continue;
                Vector2 w = SafePlace(ParseF(f[1]), ParseF(f[2]));   // phone already validated; clamp defensively
                SpawnTrap(f[0], w.x, w.y);
            }
            Debug.Log("[GOLF] setTraps -> " + _traps.Count + " hidden traps");
        }
        // Build a trap with visuals HIDDEN (renderer off, no physics collider — the effect is applied
        // manually on trigger). Revealed + popped only when a ball reaches it (CheckTraps).
        void SpawnTrap(string type, float x, float z)
        {
            var t = new Trap { type = type, pos = new Vector2(x, z) };
            if (type == "boost")
            {
                var pad = Cyl("PBoost", new Vector3(x, 0.03f, z), BoostR, 0.04f, new Color(0.55f, 0.90f, 0.25f));
                pad.GetComponent<MeshRenderer>().enabled = false;
                t.visA = pad; t.scaleA = pad.transform.localScale; t.trigR = BoostR + BallR;
            }
            else   // bumper (default for any type)
            {
                var post = GameObject.CreatePrimitive(PrimitiveType.Cylinder); DDOL(post); Destroy(post.GetComponent<Collider>());
                post.name = "PBumper"; post.transform.position = new Vector3(x, 0.28f, z);
                post.transform.localScale = new Vector3(BumperR * 2f, 0.28f, BumperR * 2f);
                var pr = post.GetComponent<MeshRenderer>(); pr.material = NewMat(new Color(0.88f, 0.22f, 0.28f)); pr.enabled = false;
                var cap = Cyl("PBumperCap", new Vector3(x, 0.44f, z), BumperR + 0.04f, 0.06f, new Color(0.98f, 0.98f, 0.98f));
                cap.transform.localScale = new Vector3((BumperR + 0.04f) * 2f, 0.03f, (BumperR + 0.04f) * 2f);
                cap.GetComponent<MeshRenderer>().enabled = false;
                t.visA = post; t.visB = cap; t.scaleA = post.transform.localScale; t.scaleB = cap.transform.localScale;
                t.trigR = BumperR + BallR + 0.04f;
            }
            _traps.Add(t);
        }
        // every frame: tick re-trigger cooldowns + play the reveal pop
        void AnimateTraps(float dt)
        {
            for (int i = 0; i < _traps.Count; i++)
            {
                var t = _traps[i];
                if (t.cool > 0f) t.cool -= dt;
                if (t.anim > 0f)
                {
                    t.anim -= dt;
                    float f = EaseOutBack(1f - Mathf.Clamp01(t.anim / RevealTime));
                    if (t.visA != null) t.visA.transform.localScale = t.scaleA * f;
                    if (t.visB != null) t.visB.transform.localScale = t.scaleB * f;
                }
            }
        }
        // the active in-flight ball springs any trap it reaches: reveal (pop) + apply the effect
        void CheckTraps(Player p, Vector3 pos)
        {
            for (int i = 0; i < _traps.Count; i++)
            {
                var t = _traps[i];
                if (t.cool > 0f) continue;
                if (new Vector2(pos.x - t.pos.x, pos.z - t.pos.y).sqrMagnitude >= t.trigR * t.trigR) continue;
                if (!t.revealed)
                {
                    t.revealed = true; t.anim = RevealTime;
                    if (t.visA != null) t.visA.GetComponent<MeshRenderer>().enabled = true;
                    if (t.visB != null) t.visB.GetComponent<MeshRenderer>().enabled = true;
                }
                if (t.type == "boost")
                {
                    Vector3 bv = p.ball.linearVelocity * 1.35f; if (bv.magnitude > 16f) bv = bv.normalized * 16f;
                    p.ball.linearVelocity = bv;
                }
                else   // bumper: reflect the ball away from the post
                {
                    Vector2 n = new Vector2(pos.x - t.pos.x, pos.z - t.pos.y); float d = n.magnitude;
                    n = (d < 0.001f) ? new Vector2(0f, 1f) : n / d;
                    Vector3 v = p.ball.linearVelocity; Vector2 v2 = new Vector2(v.x, v.z); float vn = Vector2.Dot(v2, n);
                    if (vn < 0f) v2 = (v2 - 2f * vn * n) * 0.92f;
                    p.ball.linearVelocity = new Vector3(v2.x, v.y, v2.y);
                }
                t.cool = 0.45f;
                Debug.Log("[GOLF] trap sprung: " + t.type);
            }
        }
        static float EaseOutBack(float p) { float c1 = 1.70158f, c3 = c1 + 1f, x = p - 1f; return 1f + c3 * x * x * x + c1 * x * x; }
        // world-space placement clamp (phone validates first; this guarantees on-turf + clear of blocks/cup/tee)
        Vector2 SafePlace(float x, float z)
        {
            Vector2 p = ClampTurf(new Vector2(x, z));
            foreach (var b in _trapBlock) p = PushOutRect(p, b);     // out of island / gate / guard paths
            p = PushFrom(p, new Vector2(_cup.x, _cup.z), 1.8f);
            p = PushFrom(p, new Vector2(_tee.x, _tee.z), 2.5f);
            return ClampTurf(p);                                    // re-project so the pushes can't leave the turf
        }
        // snap onto the nearest per-course turf rect {xMin,zMin,xMax,zMax}
        Vector2 ClampTurf(Vector2 p)
        {
            if (_turf.Count == 0) return p;
            Vector2 best = p; float bestD = float.MaxValue;
            foreach (var r in _turf)
            {
                Vector2 c = new Vector2(Mathf.Clamp(p.x, r[0], r[2]), Mathf.Clamp(p.y, r[1], r[3]));
                float d = (c - p).sqrMagnitude; if (d < bestD) { bestD = d; best = c; }
            }
            return best;
        }
        static Vector2 PushOutRect(Vector2 p, float[] r)            // push p just outside rect r if inside
        {
            if (p.x < r[0] || p.x > r[2] || p.y < r[1] || p.y > r[3]) return p;
            float dl = p.x - r[0], dr = r[2] - p.x, db = p.y - r[1], dt = r[3] - p.y;
            float m = Mathf.Min(Mathf.Min(dl, dr), Mathf.Min(db, dt));
            if (m == dl) p.x = r[0] - 0.1f; else if (m == dr) p.x = r[2] + 0.1f; else if (m == db) p.y = r[1] - 0.1f; else p.y = r[3] + 0.1f;
            return p;
        }
        static Vector2 PushFrom(Vector2 p, Vector2 c, float minD)
        {
            Vector2 d = p - c; float m = d.magnitude;
            if (m >= minD) return p;
            return c + ((m < 0.001f) ? new Vector2(0f, 1f) : d / m) * minD;
        }
        static float ParseF(string s)
        {
            float.TryParse(s, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out float v); return v;
        }

        bool OverSand(Vector3 p) => new Vector2(p.x - _sandC.x, p.z - _sandC.y).sqrMagnitude < _sandR * _sandR;
        Color ArrowCol(Color c) => new Color(c.r, c.g, c.b, 0.72f);

        void Update()
        {
            UpdateArrow();
            UpdateCamera(Time.deltaTime);
            AnimateTraps(Time.deltaTime);   // tick trap cooldowns + play reveal pops every frame
            if (_fanBlades != null) _fanBlades.Rotate(0f, 0f, 150f * Time.deltaTime, Space.Self);   // map-3 fan spins always
            if (_active < 0 || _active >= _players.Count) return;
            var p = _players[_active];
            if (p.ball == null || p.ball.isKinematic) return;

            bool grounded = Physics.Raycast(p.ball.position, Vector3.down, BallR + 0.10f);
            if (grounded)
            {
                float sp = p.ball.linearVelocity.magnitude;
                // sand slows the ball — but ONLY at ground level, so the raised map-3 bridge above the sand is fast.
                if (OverSand(p.ball.position) && p.ball.position.y < 0.35f) p.ball.linearVelocity = Vector3.MoveTowards(p.ball.linearVelocity, Vector3.zero, 7f * Time.deltaTime);
                else if (sp < 0.25f) p.ball.linearVelocity = Vector3.MoveTowards(p.ball.linearVelocity, Vector3.zero, 1.5f * Time.deltaTime);
            }

            if (!p.inFlight) return;
            p.flight += Time.deltaTime; Vector3 pos = p.ball.position; float speed = p.ball.linearVelocity.magnitude;

            CheckTraps(p, pos);   // spring any hidden trap the ball reaches (reveal + bounce/boost)

            // map-3 fan: bend the ball sideways while it crosses the wind zone. Predictable + modest:
            // the push only accelerates the ball UP TO _windMax along the wind dir, so dwell time can't pile up.
            if (_windAccel > 0f && _windRect != null &&
                pos.x >= _windRect[0] && pos.x <= _windRect[2] && pos.z >= _windRect[1] && pos.z <= _windRect[3])
            {
                Vector3 wdir = new Vector3(_windDir.x, 0f, _windDir.y);
                float along = Vector3.Dot(p.ball.linearVelocity, wdir);      // current speed along the wind
                if (along < _windMax)
                {
                    float add = Mathf.Min(_windAccel * Time.deltaTime, _windMax - along);
                    p.ball.linearVelocity += wdir * add;
                }
            }

            bool inWellColumn = Mathf.Abs(pos.x - _cup.x) < CupHalf && Mathf.Abs(pos.z - _cup.z) < CupHalf;
            bool downInWell = inWellColumn && pos.y < -0.22f;
            if (downInWell && !p.enteredWell) { p.enteredWell = true; }
            if (speed < RestSpeed) p.still += Time.deltaTime; else p.still = 0f;

            if (downInWell && pos.y <= (-CupDepth + BallR + 0.14f) && p.still > 0.35f)
            {
                p.holed = true; p.inFlight = false;
                p.ball.linearVelocity = Vector3.zero; p.ball.angularVelocity = Vector3.zero; p.ball.isKinematic = true;
                _status = "Player " + (_active + 1) + " HOLED in " + p.strokes + "!";
                Debug.Log("[GOLF] P" + (_active + 1) + " HOLED in " + p.strokes);
                Send("{\"t\":\"holed\",\"id\":\"" + p.id + "\",\"strokes\":" + p.strokes + "}"); return;
            }
            if (pos.y < -CupDepth - 3f || Mathf.Abs(pos.x) > _oobAbsX || pos.z < _oobZMin || pos.z > _oobZMax)
            {
                p.ball.linearVelocity = Vector3.zero; p.ball.angularVelocity = Vector3.zero; p.ball.position = TeeFor(_active);
                p.inFlight = false; Debug.Log("[GOLF] P" + (_active + 1) + " OOB -> re-tee");
                Send("{\"t\":\"ballStopped\",\"id\":\"" + p.id + "\",\"strokes\":" + p.strokes + ",\"reset\":true}"); return;
            }
            if (p.still > SettleTime && p.flight > 0.4f && !downInWell)
            {
                p.ball.linearVelocity = Vector3.zero; p.ball.angularVelocity = Vector3.zero;
                p.inFlight = false; _status = "Player " + (_active + 1) + " — stroke " + p.strokes;
                Debug.Log("[GOLF] P" + (_active + 1) + " stopped at " + pos);
                Send("{\"t\":\"ballStopped\",\"id\":\"" + p.id + "\",\"strokes\":" + p.strokes + "}");
            }
        }

        // World shot direction = per-turn neutral (toward cup) + the phone's relative swipe angle.
        // The camera FOLLOWS this same direction (UpdateCamera), so arrow / camera / shot stay in sync.
        // No feedback spin: the aim is built from the fixed _neutralAngle + phone input, never from the live camera.
        Vector3 WorldAim()
        {
            float a = (_neutralAngle + _aimAngle) * Mathf.Deg2Rad;
            return new Vector3(Mathf.Sin(a), 0f, Mathf.Cos(a)).normalized;
        }
        void UpdateArrow()
        {
            if (_aimShaft == null) return;
            bool show = false; Player p = null;
            if (_active >= 0 && _active < _players.Count) { p = _players[_active]; show = p.ball != null && !p.inFlight && !p.holed; }
            _aimShaft.gameObject.SetActive(show); _aimHead.gameObject.SetActive(show);
            if (show)
            {
                Vector3 dir = WorldAim();   // arrow matches the shot + the camera forward
                const float len = 1.05f;
                Vector3 baseP = p.ball.position + Vector3.up * (0.03f - BallR);
                _aimShaft.position = baseP + dir * (0.25f + len * 0.5f); _aimShaft.rotation = Quaternion.LookRotation(dir, Vector3.up);
                _aimHead.position = baseP + dir * (0.25f + len + 0.08f); _aimHead.rotation = Quaternion.LookRotation(dir, Vector3.up);
            }
        }

        // Smooth chase camera: sits behind the active ball along the AIM arrow while resting/aiming,
        // and follows the travel direction while the ball rolls. SmoothDamp + Slerp => never snaps,
        // including on turn changes (it just glides to the next active ball).
        void UpdateCamera(float dt)
        {
            if (_cam == null) return;
            Vector3 target, forward; float speedT;
            if (_active >= 0 && _active < _players.Count && _players[_active].ball != null)
            {
                var p = _players[_active];
                Vector3 vel = p.ball.linearVelocity; float speed = vel.magnitude;
                speedT = Mathf.Clamp01(speed / 12f);
                // While the ball rolls, follow its travel direction. At rest, FOLLOW THE AIM (WorldAim) so the camera
                // rotates smoothly with the player's aim. No feedback spin: WorldAim is the fixed per-turn neutral +
                // the phone swipe, never the live camera. On turn change SetTurn resets neutral+aim => camera resets here.
                forward = (p.inFlight && speed > 0.6f) ? new Vector3(vel.x, 0f, vel.z).normalized : WorldAim();
                if (forward.sqrMagnitude < 1e-4f) forward = Vector3.forward;
                target = p.ball.position;
            }
            else { target = new Vector3(0f, 0f, -2f); forward = Vector3.forward; speedT = 0f; }   // establishing shot between turns

            float dist = Mathf.Lerp(6.0f, 8.5f, speedT);
            float height = Mathf.Lerp(5.0f, 7.0f, speedT);
            float lookAhead = Mathf.Lerp(0.8f, 3.0f, speedT);
            Vector3 focus = target + forward * lookAhead + Vector3.up * 0.4f;
            Vector3 desiredPos = target - forward * dist + Vector3.up * height;
            float damp = Mathf.Lerp(0.30f, 0.14f, speedT);   // tighter while fast
            _cam.transform.position = Vector3.SmoothDamp(_cam.transform.position, desiredPos, ref _camVel, damp, MaxCamSpeed);
            Quaternion want = Quaternion.LookRotation(focus - _cam.transform.position, Vector3.up);
            _cam.transform.rotation = Quaternion.Slerp(_cam.transform.rotation, want, Mathf.Clamp01(Mathf.Lerp(5f, 10f, speedT) * dt));
        }

        void OnGUI()
        {
            if (_hud == null)
            {
                _hud = new GUIStyle(GUI.skin.label) { fontSize = 26, fontStyle = FontStyle.Bold }; _hud.normal.textColor = Color.white;
                _hudBig = new GUIStyle(GUI.skin.label) { fontSize = 40, fontStyle = FontStyle.Bold }; _hudBig.normal.textColor = Color.white;
                _dbg = new GUIStyle(GUI.skin.label) { fontSize = 16 }; _dbg.normal.textColor = new Color(0.7f, 1f, 0.7f);
                _ver = new GUIStyle(GUI.skin.label) { fontSize = 20, fontStyle = FontStyle.Bold }; _ver.normal.textColor = new Color(0.45f, 1f, 0.55f);
                _col = new GUIStyle(GUI.skin.label) { fontSize = 28, fontStyle = FontStyle.Bold };
            }
            if (!_showDebug) return;   // normal play: the Game-UI web HUD overlay shows the leaderboard/turn/power; no Unity debug text
            GUI.Label(new Rect(24, 12, 1500, 28), "COURSE BUILD: " + COURSE_BUILD, _ver);

            // active player banner (in their colour)
            if (_active >= 0 && _active < _players.Count)
            {
                var p = _players[_active];
                _col.normal.textColor = p.color; _col.fontSize = 40;
                GUI.Label(new Rect(24, 46, 1200, 50), "> PLAYER " + (_active + 1) + (p.holed ? "  (done)" : "  - stroke " + (p.strokes + (p.inFlight ? 0 : 1))), _col);
            }
            else GUI.Label(new Rect(24, 46, 1200, 50), _status, _hudBig);

            // simple per-player scoreboard
            _col.fontSize = 26;
            for (int i = 0; i < _players.Count; i++)
            {
                var p = _players[i];
                _col.normal.textColor = (i == _active) ? p.color : new Color(p.color.r * 0.8f, p.color.g * 0.8f, p.color.b * 0.8f, 0.9f);
                string mark = p.holed ? "HOLED in " + p.strokes : (p.strokes >= _maxStrokes ? "max " + p.strokes : p.strokes + " strokes");
                GUI.Label(new Rect(24, 108 + i * 30, 500, 28), "P" + (i + 1) + ":  " + mark, _col);
            }

            if (!_showDebug) return;
            var ap = (_active >= 0 && _active < _players.Count) ? _players[_active] : null;
            float vel = ap != null && ap.ball != null ? ap.ball.linearVelocity.magnitude : 0f;
            string[] lines = { "DEBUG", "shader: " + _shaderName, "players: " + _players.Count, "active: " + _active,
                "active vel: " + vel.ToString("0.00"), "max: " + _maxStrokes };
            for (int i = 0; i < lines.Length; i++) GUI.Label(new Rect(540, 108 + i * 20, 500, 22), lines[i], _dbg);
        }

        void Send(string json) { if (UnityBridge.Instance != null) UnityBridge.Instance.SendToHost(json); }

        // Persists the object across scene load AND, while a course is building, registers it for map-switch cleanup.
        void DDOL(GameObject go) { if (Application.isPlaying) DontDestroyOnLoad(go); if (_buildingCourse && go != null) _courseObjects.Add(go); }

        static Color HexColor(string hex)
        {
            if (string.IsNullOrEmpty(hex)) return Color.white;
            hex = hex.TrimStart('#');
            if (hex.Length < 6) return Color.white;
            try
            {
                int r = System.Convert.ToInt32(hex.Substring(0, 2), 16);
                int g = System.Convert.ToInt32(hex.Substring(2, 2), 16);
                int b = System.Convert.ToInt32(hex.Substring(4, 2), 16);
                return new Color(r / 255f, g / 255f, b / 255f);
            }
            catch { return Color.white; }
        }

        // ---- builders ----
        GameObject Box(string name, Vector3 center, Vector3 size, Color color, PhysicsMaterial pm = null)
        {
            var go = GameObject.CreatePrimitive(PrimitiveType.Cube); DDOL(go);
            go.name = name; go.transform.position = center; go.transform.localScale = size;
            go.GetComponent<MeshRenderer>().material = NewMat(color);
            if (pm != null) go.GetComponent<BoxCollider>().material = pm; return go;
        }
        void InvisBox(string name, Vector3 center, Vector3 size, PhysicsMaterial pm)
        {
            var go = GameObject.CreatePrimitive(PrimitiveType.Cube); DDOL(go);
            go.name = name; go.transform.position = center; go.transform.localScale = size;
            go.GetComponent<MeshRenderer>().enabled = false;
            if (pm != null) go.GetComponent<BoxCollider>().material = pm;
        }
        GameObject BoxTurf(string name, Vector3 center, Vector3 size, Texture2D tex, PhysicsMaterial pm)
        {
            var go = GameObject.CreatePrimitive(PrimitiveType.Cube); DDOL(go);
            go.name = name; go.transform.position = center; go.transform.localScale = size;
            var mr = go.GetComponent<MeshRenderer>(); mr.material = NewMat(Color.white);
            mr.material.mainTexture = tex; mr.material.mainTextureScale = new Vector2(size.x / 1.3f, size.z / 1.3f);
            if (pm != null) go.GetComponent<BoxCollider>().material = pm; return go;
        }
        void WallRail(string name, Vector3 center, Vector3 size)
        {
            InvisBox(name + "_col", center, size, _wallMat);
            bool alongX = size.x >= size.z;
            float len = alongX ? size.x : size.z;
            var bamboo = new Color(0.34f, 0.35f, 0.17f);
            var node = new Color(0.21f, 0.22f, 0.10f);
            var rot = alongX ? Quaternion.Euler(0f, 0f, 90f) : Quaternion.Euler(90f, 0f, 0f);
            for (int k = 0; k < 2; k++)
            {
                float py = 0.24f + k * 0.30f;
                var pole = GameObject.CreatePrimitive(PrimitiveType.Cylinder); DDOL(pole); Destroy(pole.GetComponent<Collider>());
                pole.name = name + "_pole" + k;
                pole.transform.position = new Vector3(center.x, py, center.z);
                pole.transform.rotation = rot;
                pole.transform.localScale = new Vector3(0.34f, len * 0.5f, 0.34f);
                pole.GetComponent<MeshRenderer>().material = NewMat(bamboo);
                int nodes = Mathf.Max(1, Mathf.RoundToInt(len / 1.6f));
                for (int n = 0; n <= nodes; n++)
                {
                    float along = Mathf.Lerp(-len * 0.5f + 0.12f, len * 0.5f - 0.12f, (float)n / nodes);
                    var ring = GameObject.CreatePrimitive(PrimitiveType.Cylinder); DDOL(ring); Destroy(ring.GetComponent<Collider>());
                    ring.name = name + "_node" + k + "_" + n;
                    ring.transform.position = alongX ? new Vector3(center.x + along, py, center.z) : new Vector3(center.x, py, center.z + along);
                    ring.transform.rotation = rot;
                    ring.transform.localScale = new Vector3(0.40f, 0.05f, 0.40f);
                    ring.GetComponent<MeshRenderer>().material = NewMat(node);
                }
            }
        }
        void BambooPost(float x, float z)
        {
            var bamboo = new Color(0.34f, 0.35f, 0.17f); var node = new Color(0.21f, 0.22f, 0.10f);
            var post = GameObject.CreatePrimitive(PrimitiveType.Cylinder); DDOL(post); Destroy(post.GetComponent<Collider>());
            post.name = "Post"; post.transform.position = new Vector3(x, 0.42f, z); post.transform.localScale = new Vector3(0.42f, 0.46f, 0.42f);
            post.GetComponent<MeshRenderer>().material = NewMat(bamboo);
            for (int n = 0; n < 2; n++)
            {
                var ring = GameObject.CreatePrimitive(PrimitiveType.Cylinder); DDOL(ring); Destroy(ring.GetComponent<Collider>());
                ring.name = "PostNode"; ring.transform.position = new Vector3(x, 0.30f + n * 0.34f, z); ring.transform.localScale = new Vector3(0.48f, 0.05f, 0.48f);
                ring.GetComponent<MeshRenderer>().material = NewMat(node);
            }
        }
        GameObject Annulus(string name, Vector3 center, Color color, float outerR, float innerR)
        {
            var go = new GameObject(name); DDOL(go);
            go.AddComponent<MeshFilter>().sharedMesh = MakeAnnulus(outerR, innerR, 48);
            go.AddComponent<MeshRenderer>().material = NewMat(color); go.transform.position = center; return go;
        }
        GameObject AnnulusTex(string name, Vector3 center, Texture2D tex, float outerR, float innerR)
        {
            var go = new GameObject(name); DDOL(go);
            go.AddComponent<MeshFilter>().sharedMesh = MakeAnnulus(outerR, innerR, 48);
            var mr = go.AddComponent<MeshRenderer>(); mr.material = NewMat(Color.white);
            mr.material.mainTexture = tex; mr.material.mainTextureScale = Vector2.one;
            go.transform.position = center; return go;
        }
        GameObject Cyl(string name, Vector3 center, float radius, float height, Color color)
        {
            var go = GameObject.CreatePrimitive(PrimitiveType.Cylinder); DDOL(go); Destroy(go.GetComponent<Collider>());
            go.name = name; go.transform.position = center; go.transform.localScale = new Vector3(radius * 2f, height * 0.5f, radius * 2f);
            go.GetComponent<MeshRenderer>().material = NewMat(color); return go;
        }
        GameObject Tube(string name, Vector3 center, float radius, float yTop, float yBottom, Color color)
        {
            var go = new GameObject(name); DDOL(go);
            go.AddComponent<MeshFilter>().sharedMesh = MakeTube(radius, yTop, yBottom, 40);
            go.AddComponent<MeshRenderer>().material = NewMat(color);
            go.transform.position = new Vector3(center.x, 0f, center.z); return go;
        }

        static Mesh MakeAnnulus(float outerR, float innerR, int seg)
        {
            var m = new Mesh(); var v = new Vector3[seg * 2]; var nm = new Vector3[seg * 2]; var uv = new Vector2[seg * 2]; var tr = new int[seg * 12];
            for (int i = 0; i < seg; i++) { float a = (float)i / seg * Mathf.PI * 2f, c = Mathf.Cos(a), s = Mathf.Sin(a);
                v[i * 2] = new Vector3(c * outerR, 0, s * outerR); v[i * 2 + 1] = new Vector3(c * innerR, 0, s * innerR);
                nm[i * 2] = Vector3.up; nm[i * 2 + 1] = Vector3.up;
                uv[i * 2] = new Vector2(c * outerR / 1.3f, s * outerR / 1.3f); uv[i * 2 + 1] = new Vector2(c * innerR / 1.3f, s * innerR / 1.3f); }
            int t = 0;
            for (int i = 0; i < seg; i++) { int o0 = i * 2, in0 = i * 2 + 1, o1 = ((i + 1) % seg) * 2, in1 = ((i + 1) % seg) * 2 + 1;
                tr[t++] = o0; tr[t++] = o1; tr[t++] = in0; tr[t++] = in0; tr[t++] = o1; tr[t++] = in1;
                tr[t++] = o0; tr[t++] = in0; tr[t++] = o1; tr[t++] = in0; tr[t++] = in1; tr[t++] = o1;
            }
            m.vertices = v; m.normals = nm; m.uv = uv; m.triangles = tr; m.RecalculateBounds(); return m;
        }
        static Mesh MakeDisk(float r, int seg)
        {
            var m = new Mesh(); var v = new Vector3[seg + 1]; var nm = new Vector3[seg + 1]; var uv = new Vector2[seg + 1]; var tr = new int[seg * 3];
            v[0] = Vector3.zero; nm[0] = Vector3.up; uv[0] = new Vector2(0.5f, 0.5f);
            for (int i = 0; i < seg; i++) { float a = (float)i / seg * Mathf.PI * 2f, c = Mathf.Cos(a), s = Mathf.Sin(a);
                float rr = r * (1f + 0.07f * Mathf.Sin(a * 4f) + 0.05f * Mathf.Sin(a * 7f + 1.3f) + 0.03f * Mathf.Sin(a * 13f));
                v[i + 1] = new Vector3(c * rr, 0, s * rr); nm[i + 1] = Vector3.up; uv[i + 1] = new Vector2(0.5f + 0.5f * c, 0.5f + 0.5f * s); }
            int t = 0;
            for (int i = 0; i < seg; i++) { int a0 = i + 1, a1 = (i + 1) % seg + 1; tr[t++] = 0; tr[t++] = a1; tr[t++] = a0; }
            m.vertices = v; m.normals = nm; m.uv = uv; m.triangles = tr; m.RecalculateBounds(); return m;
        }
        static Mesh MakeTube(float r, float yTop, float yBottom, int seg)
        {
            var m = new Mesh(); var v = new Vector3[seg * 2]; var tr = new int[seg * 12];
            for (int i = 0; i < seg; i++) { float a = (float)i / seg * Mathf.PI * 2f, c = Mathf.Cos(a), s = Mathf.Sin(a);
                v[i * 2] = new Vector3(c * r, yTop, s * r); v[i * 2 + 1] = new Vector3(c * r, yBottom, s * r); }
            int t = 0;
            for (int i = 0; i < seg; i++)
            {
                int t0 = i * 2, b0 = i * 2 + 1, t1 = ((i + 1) % seg) * 2, b1 = ((i + 1) % seg) * 2 + 1;
                tr[t++] = t0; tr[t++] = b0; tr[t++] = t1; tr[t++] = t1; tr[t++] = b0; tr[t++] = b1;
                tr[t++] = t0; tr[t++] = t1; tr[t++] = b0; tr[t++] = b0; tr[t++] = t1; tr[t++] = b1;
            }
            m.vertices = v; m.triangles = tr; m.RecalculateNormals(); m.RecalculateBounds(); return m;
        }
        static Mesh MakeArrowhead()
        {
            var m = new Mesh();
            m.vertices = new Vector3[] { new Vector3(0, 0, 0.24f), new Vector3(-0.17f, 0, -0.10f), new Vector3(0.17f, 0, -0.10f) };
            m.triangles = new int[] { 0, 1, 2, 0, 2, 1 };
            m.normals = new Vector3[] { Vector3.up, Vector3.up, Vector3.up };
            m.RecalculateBounds(); return m;
        }

        static string JStr(string json, string key)
        {
            int i = json.IndexOf("\"" + key + "\""); if (i < 0) return ""; i = json.IndexOf(':', i); if (i < 0) return "";
            int q = json.IndexOf('"', i + 1); if (q < 0) return ""; int e = json.IndexOf('"', q + 1); if (e < 0) return ""; return json.Substring(q + 1, e - q - 1);
        }
        static float JNum(string json, string key)
        {
            int i = json.IndexOf("\"" + key + "\""); if (i < 0) return 0f; i = json.IndexOf(':', i); if (i < 0) return 0f;
            int s = i + 1; while (s < json.Length && (json[s] == ' ' || json[s] == '"')) s++;
            int e = s; while (e < json.Length && (char.IsDigit(json[e]) || json[e] == '.' || json[e] == '-' || json[e] == '+')) e++;
            float.TryParse(json.Substring(s, e - s), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out float val); return val;
        }
    }
}
