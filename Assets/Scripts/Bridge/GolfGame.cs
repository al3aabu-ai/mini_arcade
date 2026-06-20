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
        const string COURSE_BUILD = "L_SHAPE_V12_2026-06-20_accuratemap+hiddentraps+validplacement";
        const string SCENE_NAME = "UnityGolfPolishedCourse";

        const float BallR = 0.18f;
        const float CupHalf = 0.35f;
        const float CupDepth = 0.6f;
        const float RestSpeed = 0.12f;
        const float SettleTime = 0.40f;
        const int BallLayer = 30;        // balls ignore each other (no unfair knock-aways), still hit the course
        static readonly Vector3 CupCenter = new Vector3(4.5f, 0f, 4f);
        static readonly Vector3 TeePos = new Vector3(-4f, BallR + 0.20f, -8f);
        static readonly Vector2 SandCenter = new Vector2(-3.7f, 4f);
        const float SandRadius = 1.45f;
        static readonly Vector2 BumperPos = new Vector2(1.0f, 4.2f);
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

        readonly List<Player> _players = new List<Player>();
        int _active = -1;
        int _maxStrokes = 8;

        Transform _aimShaft, _aimHead;
        Renderer _aimShaftR, _aimHeadR;
        Shader _shader, _shaderUnlit, _shaderTrans;
        string _shaderName = "?";
        Texture2D _turfTex, _sandTex;
        PhysicsMaterial _wallMat, _turfMat, _ballMat, _bumperMat;
        float _aimAngle, _aimPower;
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
            var go = new GameObject("GolfGame"); DDOL(go); Instance = go.AddComponent<GolfGame>();
            var bridge = new GameObject("UnityBridge"); DDOL(bridge); bridge.AddComponent<UnityBridge>();
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
            BuildCamera(); BuildLight(); BuildCourse(); BuildCup(); BuildAim();
            Debug.Log("[GOLF] COURSE=" + COURSE_BUILD + " SCENE=" + SCENE_NAME + " shader=" + _shaderName);
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
            sand.AddComponent<MeshFilter>().sharedMesh = MakeDisk(SandRadius, 64);
            sand.AddComponent<MeshRenderer>().material = NewMatTrans(_sandTex);
            sand.transform.position = new Vector3(SandCenter.x, 0.012f, SandCenter.y);

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

        void BuildCup()
        {
            var dark = new Color(0.02f, 0.025f, 0.025f);
            float wy = -CupDepth * 0.5f;
            InvisBox("Cup_X+", new Vector3(CupCenter.x + CupHalf, wy, CupCenter.z), new Vector3(0.08f, CupDepth, 1.1f), _wallMat);
            InvisBox("Cup_X-", new Vector3(CupCenter.x - CupHalf, wy, CupCenter.z), new Vector3(0.08f, CupDepth, 1.1f), _wallMat);
            InvisBox("Cup_Z+", new Vector3(CupCenter.x, wy, CupCenter.z + CupHalf), new Vector3(1.1f, CupDepth, 0.08f), _wallMat);
            InvisBox("Cup_Z-", new Vector3(CupCenter.x, wy, CupCenter.z - CupHalf), new Vector3(1.1f, CupDepth, 0.08f), _wallMat);
            InvisBox("Cup_Floor", new Vector3(CupCenter.x, -CupDepth, CupCenter.z), new Vector3(1.1f, 0.08f, 1.1f), null);

            AnnulusTex("Cup_Collar", new Vector3(CupCenter.x, 0.012f, CupCenter.z), _turfTex, 0.62f, 0.365f);
            Annulus("Cup_Lip", new Vector3(CupCenter.x, 0.026f, CupCenter.z), new Color(0.82f, 0.80f, 0.70f), 0.365f, 0.33f);
            Tube("Cup_Tube", CupCenter, 0.33f, 0.03f, -0.50f, dark);
            Cyl("Cup_Bottom", new Vector3(CupCenter.x, -0.52f, CupCenter.z), 0.33f, 0.04f, new Color(0.01f, 0.012f, 0.012f));

            var pole = Box("FlagPole", new Vector3(CupCenter.x, 0.69f, CupCenter.z), new Vector3(0.05f, 1.82f, 0.05f), new Color(0.93f, 0.93f, 0.93f));
            Destroy(pole.GetComponent<Collider>());
            var flag = Box("FlagCloth", new Vector3(CupCenter.x + 0.26f, 1.44f, CupCenter.z), new Vector3(0.5f, 0.30f, 0.02f), new Color(0.84f, 0.20f, 0.24f));
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
        Vector3 TeeFor(int i) => TeePos;

        public void OnHostMessage(string json)
        {
            string t = JStr(json, "t");
            if (t == "newHole") NewHole(JStr(json, "players"), Mathf.RoundToInt(JNum(json, "max")));
            else if (t == "setTurn") SetTurn(JStr(json, "id"));
            else if (t == "shoot") Shoot(JStr(json, "id"), JNum(json, "angle"), JNum(json, "power"));
            else if (t == "aim") { _aimAngle = JNum(json, "angle"); _aimPower = JNum(json, "power"); }
            else if (t == "setTraps") SetTraps(JStr(json, "traps"));   // planted traps for this round ("type,x,y;...")
            else if (t == "reset") ReTeeAll();
            else if (t == "debug") _showDebug = !_showDebug;
        }

        void NewHole(string playersStr, int max)
        {
            _maxStrokes = max > 0 ? max : 8;
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
            // start the new player's aim pointed at the cup — don't inherit the previous player's angle (camera + arrow)
            if (p.ball != null) _aimAngle = Mathf.Atan2(CupCenter.x - p.ball.position.x, CupCenter.z - p.ball.position.z) * Mathf.Rad2Deg;
            _aimPower = 0f;
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
            float a = angleDeg * Mathf.Deg2Rad; Vector3 dir = new Vector3(Mathf.Sin(a), 0f, Mathf.Cos(a)).normalized;
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
        // world-space placement clamp (phone validates first; this just guarantees on-turf + clear of gate/cup/tee)
        Vector2 SafePlace(float x, float z)
        {
            Vector2 p = ClampTurf(new Vector2(x, z));
            if (p.x <= -2f && p.y > -3.7f && p.y < -2.3f) p.y = (p.y > -3f) ? -2.3f : -3.7f;   // out of the z=-3 gate row
            p = PushFrom(p, new Vector2(CupCenter.x, CupCenter.z), 1.8f);
            p = PushFrom(p, new Vector2(TeePos.x, TeePos.z), 2.5f);
            return ClampTurf(p);   // re-project so a push can't leave the turf
        }
        // left column = vertical leg + corner (no W_HoriBottom wall here); right band sits above that wall (z=2.15)
        Vector2 ClampTurf(Vector2 p)
        {
            const float m = 0.55f;
            Vector2 a = new Vector2(Mathf.Clamp(p.x, -6f + m, -2f - m), Mathf.Clamp(p.y, -10f + m, 6f - m));
            Vector2 b = new Vector2(Mathf.Clamp(p.x, -2f + m, 6f - m), Mathf.Clamp(p.y, 2.7f, 6f - m));
            return ((a - p).sqrMagnitude <= (b - p).sqrMagnitude) ? a : b;
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

        bool OverSand(Vector3 p) => new Vector2(p.x - SandCenter.x, p.z - SandCenter.y).sqrMagnitude < SandRadius * SandRadius;
        Color ArrowCol(Color c) => new Color(c.r, c.g, c.b, 0.72f);

        void Update()
        {
            UpdateArrow();
            UpdateCamera(Time.deltaTime);
            AnimateTraps(Time.deltaTime);   // tick trap cooldowns + play reveal pops every frame
            if (_active < 0 || _active >= _players.Count) return;
            var p = _players[_active];
            if (p.ball == null || p.ball.isKinematic) return;

            bool grounded = Physics.Raycast(p.ball.position, Vector3.down, BallR + 0.10f);
            if (grounded)
            {
                float sp = p.ball.linearVelocity.magnitude;
                if (OverSand(p.ball.position)) p.ball.linearVelocity = Vector3.MoveTowards(p.ball.linearVelocity, Vector3.zero, 7f * Time.deltaTime);
                else if (sp < 0.25f) p.ball.linearVelocity = Vector3.MoveTowards(p.ball.linearVelocity, Vector3.zero, 1.5f * Time.deltaTime);
            }

            if (!p.inFlight) return;
            p.flight += Time.deltaTime; Vector3 pos = p.ball.position; float speed = p.ball.linearVelocity.magnitude;

            CheckTraps(p, pos);   // spring any hidden trap the ball reaches (reveal + bounce/boost)

            bool inWellColumn = Mathf.Abs(pos.x - CupCenter.x) < CupHalf && Mathf.Abs(pos.z - CupCenter.z) < CupHalf;
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
            if (pos.y < -CupDepth - 3f || Mathf.Abs(pos.x) > 8f || pos.z < -11f || pos.z > 7.5f)
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

        void UpdateArrow()
        {
            if (_aimShaft == null) return;
            bool show = false; Player p = null;
            if (_active >= 0 && _active < _players.Count) { p = _players[_active]; show = p.ball != null && !p.inFlight && !p.holed; }
            _aimShaft.gameObject.SetActive(show); _aimHead.gameObject.SetActive(show);
            if (show)
            {
                float a = _aimAngle * Mathf.Deg2Rad; Vector3 dir = new Vector3(Mathf.Sin(a), 0f, Mathf.Cos(a)).normalized;
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
                float a = _aimAngle * Mathf.Deg2Rad;
                Vector3 aimDir = new Vector3(Mathf.Sin(a), 0f, Mathf.Cos(a)).normalized;     // same convention as Shoot/UpdateArrow
                forward = (p.inFlight && speed > 0.6f) ? new Vector3(vel.x, 0f, vel.z).normalized : aimDir;
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

        static void DDOL(GameObject go) { if (Application.isPlaying) DontDestroyOnLoad(go); }

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
