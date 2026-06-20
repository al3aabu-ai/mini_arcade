using UnityEngine;

namespace MiniArcade.Bridge
{
    /// One polished arcade mini-golf hole (V5) — art fixes on the stable physics/bridge.
    /// ROUND cup (invisible square-well collider + round tube interior + collar + cream lip),
    /// NO hump, a fixed-length unlit semi-transparent aim arrow, a darker textured sand bunker,
    /// carpet turf, wood rails, an L-dogleg with a gate + risk/reward tight-cut sand.
    public class GolfGame : MonoBehaviour
    {
        public static GolfGame Instance { get; private set; }
        const string COURSE_BUILD = "L_SHAPE_V9_2026-06-20_darkerbamboo+nosquare+boldersand";
        const string SCENE_NAME = "UnityGolfPolishedCourse";

        const float BallR = 0.18f;
        const float CupHalf = 0.35f;   // visible hole 0.33 (~1.8x ball) with a thin lip; the 0.70 well stays forgiving so the ball drops
        const float CupDepth = 0.6f;
        const float RestSpeed = 0.12f;   // ball is "at rest" only below this speed...
        const float SettleTime = 0.40f;  // ...held for this long -> only then is the next shot allowed
        static readonly Vector3 CupCenter = new Vector3(4.5f, 0f, 4f);
        static readonly Vector3 TeePos = new Vector3(-4f, BallR + 0.20f, -8f);
        static readonly Vector2 SandCenter = new Vector2(-3.7f, 4f);
        const float SandRadius = 1.45f;

        Rigidbody _ball;
        Transform _aimShaft, _aimHead;
        Shader _shader, _shaderUnlit, _shaderTrans;
        string _shaderName = "?";
        Texture2D _turfTex, _sandTex;
        PhysicsMaterial _wallMat, _turfMat;
        float _aimAngle, _aimPower;
        int _strokes;
        bool _inFlight, _holed, _grounded, _enteredWell, _loggedGround;
        float _still, _flight;
        string _status = "Aim on your phone";
        static bool _showDebug = false;
        GUIStyle _hud, _hudBig, _dbg, _ver;

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

        public void BuildAll()   // public so the in-editor preview renderer can build the scene without play mode
        {
            Instance = this;
            Physics.gravity = new Vector3(0f, -16f, 0f);
            RenderSettings.ambientLight = new Color(0.30f, 0.32f, 0.34f);   // a touch lower so cast shadows read
            ResolveShaders();
            _turfTex = MakeNoiseTex(7, new Color(0.10f, 0.245f, 0.135f), 0.05f, true);
            _sandTex = MakeSandTex();   // tan/beige + radial ALPHA fade so the bunker edge feathers into the turf
            _wallMat = new PhysicsMaterial("wall") { bounciness = 0.80f, dynamicFriction = 0.07f, staticFriction = 0.07f,
                frictionCombine = PhysicsMaterialCombine.Minimum, bounceCombine = PhysicsMaterialCombine.Maximum };
            _turfMat = new PhysicsMaterial("turf") { bounciness = 0.05f, dynamicFriction = 0.45f, staticFriction = 0.50f,
                frictionCombine = PhysicsMaterialCombine.Average, bounceCombine = PhysicsMaterialCombine.Average };
            BuildCamera(); BuildLight(); BuildCourse(); BuildCup(); BuildBall(); BuildAim(); ResetBall();
            Debug.Log("[GOLF] COURSE=" + COURSE_BUILD + " SCENE=" + SCENE_NAME + " shader=" + _shaderName + " | oldRectangleCourse=NOT_LOADED");
        }

        void ResolveShaders()
        {
            string[] names = { "Legacy Shaders/Diffuse", "Unlit/Color", "Sprites/Default", "Standard" };
            foreach (var n in names) { var s = Shader.Find(n); if (s != null) { _shader = s; _shaderName = n; break; } }
            if (_shader == null) { _shader = Shader.Find("Hidden/InternalErrorShader"); _shaderName = "NONE-MAGENTA"; Debug.LogError("[GOLF] no shader!"); }
            _shaderUnlit = Shader.Find("Sprites/Default") ?? _shader;                       // unlit + transparent for the arrow
            _shaderTrans = Shader.Find("Legacy Shaders/Transparent/Diffuse") ?? _shader;     // alpha-blended (sand soft edge)
        }
        Material NewMat(Color c) { var m = new Material(_shader); m.color = c; return m; }
        Material NewMatUnlit(Color c) { var m = new Material(_shaderUnlit); m.color = c; m.renderQueue = 3100; return m; }
        Material NewMatTrans(Texture2D tex) { var m = new Material(_shaderTrans); m.color = Color.white; m.mainTexture = tex; m.renderQueue = 3000; return m; }
        Material NewMatUnlitTex(Texture2D tex) { var m = new Material(_shaderUnlit); m.color = Color.white; m.mainTexture = tex; m.renderQueue = 3000; return m; }   // unlit alpha-blended (sand, no lighting halo)

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

        // Tan/beige sand with a fine grain AND a radial alpha falloff: the disk fades to transparent at
        // its rim so the bunker blends into the turf instead of a hard pasted-circle edge.
        Texture2D MakeSandTex()
        {
            int N = 128; var tex = new Texture2D(N, N, TextureFormat.RGBA32, false) { wrapMode = TextureWrapMode.Clamp, filterMode = FilterMode.Bilinear };
            var rng = new System.Random(13); var b = new Color(0.74f, 0.59f, 0.34f);   // bolder, warmer tan/light-brown (not washed out)
            for (int y = 0; y < N; y++) for (int x = 0; x < N; x++)
            {
                float fine = (float)rng.NextDouble() * 0.12f - 0.06f;
                float coarse = Mathf.PerlinNoise(x * 0.09f, y * 0.09f) * 0.16f - 0.08f;   // sandy blotches so it isn't a flat fill
                float n = fine + coarse;
                float dx = (x + 0.5f) / N - 0.5f, dy = (y + 0.5f) / N - 0.5f, d = Mathf.Sqrt(dx * dx + dy * dy);
                float a = Mathf.Clamp01((0.49f - d) / 0.06f);                                   // tighter DEFINED edge (not a wide foggy fade)
                float dark = Mathf.Lerp(0.45f, 1f, Mathf.Clamp01((0.49f - d) / 0.16f));         // rim darkens to a depression shadow, no bright fringe
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
            // ---- carpet floor (L-shape) ----
            BoxTurf("Floor_Vert", new Vector3(-4f, -0.25f, -4.2f), new Vector3(4.4f, 0.5f, 12.0f), _turfTex, _turfMat);   // ends at z=1.8 to ABUT Floor_HoriL (no overlap -> no z-fighting square patch under the sand)
            BoxTurf("Floor_HoriL", new Vector3(-0.95f, -0.25f, 4f), new Vector3(10.1f, 0.5f, 4.4f), _turfTex, _turfMat);
            BoxTurf("Floor_HoriR", new Vector3(5.55f, -0.25f, 4f), new Vector3(1.3f, 0.5f, 4.4f), _turfTex, _turfMat);
            BoxTurf("Floor_HoriB", new Vector3(4.5f, -0.25f, 2.7f), new Vector3(0.8f, 0.5f, 1.8f), _turfTex, _turfMat);   // cup gap shrunk to 0.8 -> only a small collar needed
            BoxTurf("Floor_HoriF", new Vector3(4.5f, -0.25f, 5.3f), new Vector3(0.8f, 0.5f, 1.8f), _turfTex, _turfMat);

            // ---- wood rails ----
            WallRail("W_Bottom", new Vector3(-4f, 0.35f, -10f), new Vector3(4.6f, 0.7f, 0.3f));
            WallRail("W_Left", new Vector3(-6f, 0.35f, -2f), new Vector3(0.3f, 0.7f, 16.6f));
            WallRail("W_Top", new Vector3(0f, 0.35f, 6f), new Vector3(12.6f, 0.7f, 0.3f));
            WallRail("W_Right", new Vector3(6f, 0.35f, 4f), new Vector3(0.3f, 0.7f, 4.6f));
            WallRail("W_HoriBottom", new Vector3(2f, 0.35f, 2f), new Vector3(8.6f, 0.7f, 0.3f));
            WallRail("W_InnerRight", new Vector3(-2f, 0.35f, -4f), new Vector3(0.3f, 0.7f, 12.6f));

            // ---- narrow gate (mid-leg) ----  (NO hump anywhere)
            WallRail("Gate_L", new Vector3(-5.25f, 0.35f, -3f), new Vector3(1.5f, 0.7f, 0.3f));
            WallRail("Gate_R", new Vector3(-2.75f, 0.35f, -3f), new Vector3(1.5f, 0.7f, 0.3f));

            // ---- bamboo corner posts (clean the overlapping-pole joints) + gate posts (frame the opening) ----
            BambooPost(-6f, -10f); BambooPost(-6f, 6f); BambooPost(6f, 6f); BambooPost(6f, 2f); BambooPost(-2f, 2f); BambooPost(-2f, -10f);
            BambooPost(-4.5f, -3f); BambooPost(-3.5f, -3f);

            // ---- tan sand bunker: a flat disk whose alpha-feathered edge blends into the turf (no hard decal cutoff) ----
            var sand = new GameObject("Sand"); DDOL(sand);
            sand.AddComponent<MeshFilter>().sharedMesh = MakeDisk(SandRadius, 64);
            sand.AddComponent<MeshRenderer>().material = NewMatTrans(_sandTex);   // LIT so it shares the turf's lighting (no separate/pasted look)
            sand.transform.position = new Vector3(SandCenter.x, 0.012f, SandCenter.y);
        }

        void BuildCup()
        {
            var dark = new Color(0.02f, 0.025f, 0.025f);
            float wy = -CupDepth * 0.5f;   // square-well collider — INVISIBLE, physics only
            InvisBox("Cup_X+", new Vector3(CupCenter.x + CupHalf, wy, CupCenter.z), new Vector3(0.08f, CupDepth, 1.1f), _wallMat);
            InvisBox("Cup_X-", new Vector3(CupCenter.x - CupHalf, wy, CupCenter.z), new Vector3(0.08f, CupDepth, 1.1f), _wallMat);
            InvisBox("Cup_Z+", new Vector3(CupCenter.x, wy, CupCenter.z + CupHalf), new Vector3(1.1f, CupDepth, 0.08f), _wallMat);
            InvisBox("Cup_Z-", new Vector3(CupCenter.x, wy, CupCenter.z - CupHalf), new Vector3(1.1f, CupDepth, 0.08f), _wallMat);
            InvisBox("Cup_Floor", new Vector3(CupCenter.x, -CupDepth, CupCenter.z), new Vector3(1.1f, 0.08f, 1.1f), null);

            // ROUND visuals (no colliders): a SMALL collar made of the SAME turf texture (blends into the
            // carpet, just hides the square gap), a thin subtle lip, and a small dark recess.
            AnnulusTex("Cup_Collar", new Vector3(CupCenter.x, 0.012f, CupCenter.z), _turfTex, 0.62f, 0.365f);
            Annulus("Cup_Lip", new Vector3(CupCenter.x, 0.026f, CupCenter.z), new Color(0.82f, 0.80f, 0.70f), 0.365f, 0.33f);   // THIN lip so the dark hole reads at full size
            Tube("Cup_Tube", CupCenter, 0.33f, 0.03f, -0.50f, dark);                                          // deep recess wall -> normal-size sunk cup (~1.8x ball)
            Cyl("Cup_Bottom", new Vector3(CupCenter.x, -0.52f, CupCenter.z), 0.33f, 0.04f, new Color(0.01f, 0.012f, 0.012f));   // near-black bottom adds depth

            // flag planted in the CENTER of the cup — pole runs from the cup bottom up, so it clearly rises from the hole center
            var pole = Box("FlagPole", new Vector3(CupCenter.x, 0.69f, CupCenter.z), new Vector3(0.05f, 1.82f, 0.05f), new Color(0.93f, 0.93f, 0.93f));
            Destroy(pole.GetComponent<Collider>());
            var flag = Box("FlagCloth", new Vector3(CupCenter.x + 0.26f, 1.44f, CupCenter.z), new Vector3(0.5f, 0.30f, 0.02f), new Color(0.84f, 0.20f, 0.24f));
            Destroy(flag.GetComponent<Collider>());
        }

        void BuildBall()
        {
            var go = GameObject.CreatePrimitive(PrimitiveType.Sphere); DDOL(go); go.name = "Ball";
            go.transform.localScale = Vector3.one * (BallR * 2f);
            go.GetComponent<MeshRenderer>().material = NewMat(new Color(0.97f, 0.97f, 0.97f));
            go.GetComponent<SphereCollider>().material = new PhysicsMaterial("ball") { bounciness = 0.45f, dynamicFriction = 0.30f, staticFriction = 0.35f,
                frictionCombine = PhysicsMaterialCombine.Average, bounceCombine = PhysicsMaterialCombine.Average };
            _ball = go.AddComponent<Rigidbody>(); _ball.mass = 1f; _ball.linearDamping = 0.32f; _ball.angularDamping = 0.45f;
            _ball.collisionDetectionMode = CollisionDetectionMode.ContinuousDynamic; _ball.interpolation = RigidbodyInterpolation.Interpolate;
        }

        void BuildAim()
        {
            var ay = new Color(1f, 0.84f, 0.20f, 0.66f);   // one clean semi-transparent color
            var shaft = GameObject.CreatePrimitive(PrimitiveType.Cube); DDOL(shaft); Destroy(shaft.GetComponent<Collider>());
            shaft.name = "AimShaft"; shaft.transform.localScale = new Vector3(0.10f, 0.02f, 1.05f);
            shaft.GetComponent<MeshRenderer>().material = NewMatUnlit(ay);
            _aimShaft = shaft.transform;
            var head = new GameObject("AimHead"); DDOL(head);
            head.AddComponent<MeshFilter>().sharedMesh = MakeArrowhead();
            head.AddComponent<MeshRenderer>().material = NewMatUnlit(ay);
            _aimHead = head.transform;
        }

        public void OnHostMessage(string json)
        {
            string t = JStr(json, "t");
            if (t == "shoot") Shoot(JNum(json, "angle"), JNum(json, "power"));
            else if (t == "aim") { _aimAngle = JNum(json, "angle"); _aimPower = JNum(json, "power"); }
            else if (t == "newHole" || t == "reset") ResetBall();
            else if (t == "debug") _showDebug = !_showDebug;
        }

        void Shoot(float angleDeg, float power01)
        {
            if (_ball == null || _inFlight || _holed) return;
            if (_ball.linearVelocity.magnitude > 0.2f) return;   // belt-and-suspenders: never shoot while the ball is still moving
            power01 = Mathf.Clamp01(power01); _aimAngle = angleDeg;
            float speed = Mathf.Lerp(3.5f, 15f, power01);
            float a = angleDeg * Mathf.Deg2Rad; Vector3 dir = new Vector3(Mathf.Sin(a), 0f, Mathf.Cos(a)).normalized;
            _ball.linearVelocity = dir * speed; _ball.angularVelocity = Vector3.zero;
            _strokes++; _inFlight = true; _still = 0f; _flight = 0f; _enteredWell = false; _status = "Stroke " + _strokes + "…";
            Debug.Log("[GOLF] shot fired #" + _strokes + " angle=" + angleDeg + " power=" + power01 + " speed=" + speed);
            Send("{\"t\":\"shotStarted\",\"stroke\":" + _strokes + "}"); Send("{\"t\":\"strokeCount\",\"strokes\":" + _strokes + "}");
        }

        void ResetBall()
        {
            if (_ball == null) return;
            _ball.linearVelocity = Vector3.zero; _ball.angularVelocity = Vector3.zero; _ball.position = TeePos;
            _strokes = 0; _inFlight = false; _holed = false; _still = 0f; _enteredWell = false; _loggedGround = false; _status = "Aim on your phone";
            Debug.Log("[GOLF] ball spawned at " + TeePos);
        }

        bool OverSand(Vector3 p) => new Vector2(p.x - SandCenter.x, p.z - SandCenter.y).sqrMagnitude < SandRadius * SandRadius;

        void Update()
        {
            if (_ball != null)
            {
                _grounded = Physics.Raycast(_ball.position, Vector3.down, BallR + 0.10f);
                if (_grounded && !_loggedGround && !_inFlight) { _loggedGround = true; Debug.Log("[GOLF] ball grounded (resting on course)"); }
                if (_grounded)
                {
                    float sp = _ball.linearVelocity.magnitude;
                    if (OverSand(_ball.position)) _ball.linearVelocity = Vector3.MoveTowards(_ball.linearVelocity, Vector3.zero, 7f * Time.deltaTime);
                    else if (sp < 0.25f) _ball.linearVelocity = Vector3.MoveTowards(_ball.linearVelocity, Vector3.zero, 1.5f * Time.deltaTime);   // kill the endless micro-drift tail (main roll feel above 0.25 untouched)
                }
            }

            bool aiming = !_inFlight && !_holed && _ball != null;
            if (_aimShaft != null)
            {
                _aimShaft.gameObject.SetActive(aiming); _aimHead.gameObject.SetActive(aiming);
                if (aiming)
                {
                    float a = _aimAngle * Mathf.Deg2Rad; Vector3 dir = new Vector3(Mathf.Sin(a), 0f, Mathf.Cos(a)).normalized;
                    const float len = 1.05f;   // FIXED length, direction only (no power scaling)
                    Vector3 baseP = _ball.position + Vector3.up * (0.03f - BallR);
                    _aimShaft.position = baseP + dir * (0.25f + len * 0.5f); _aimShaft.rotation = Quaternion.LookRotation(dir, Vector3.up);
                    _aimHead.position = baseP + dir * (0.25f + len + 0.08f); _aimHead.rotation = Quaternion.LookRotation(dir, Vector3.up);
                }
            }

            if (!_inFlight || _ball == null) return;
            _flight += Time.deltaTime; Vector3 p = _ball.position; float speed = _ball.linearVelocity.magnitude;
            bool inWellColumn = Mathf.Abs(p.x - CupCenter.x) < CupHalf && Mathf.Abs(p.z - CupCenter.z) < CupHalf;
            bool downInWell = inWellColumn && p.y < -0.22f;
            if (downInWell && !_enteredWell) { _enteredWell = true; Debug.Log("[GOLF] ball entered well"); }
            if (speed < RestSpeed) _still += Time.deltaTime; else _still = 0f;

            if (downInWell && p.y <= (-CupDepth + BallR + 0.14f) && _still > 0.35f)
            {
                _holed = true; _inFlight = false; _status = "HOLED in " + _strokes + "!"; Debug.Log("[GOLF] HOLED confirmed in " + _strokes);
                Send("{\"t\":\"holed\",\"strokes\":" + _strokes + "}"); Send("{\"t\":\"roundComplete\",\"strokes\":" + _strokes + "}"); return;
            }
            if (p.y < -CupDepth - 3f || Mathf.Abs(p.x) > 8f || p.z < -11f || p.z > 7.5f)
            { Debug.Log("[GOLF] out of bounds -> reset"); ResetBall(); Send("{\"t\":\"ballStopped\",\"reset\":true,\"strokes\":" + _strokes + "}"); return; }
            if (_still > SettleTime && _flight > 0.4f && !downInWell)
            {
                _ball.linearVelocity = Vector3.zero; _ball.angularVelocity = Vector3.zero;   // hard stop -> truly at rest, no residual drift
                _inFlight = false; _status = "Stroke " + _strokes + " — your shot"; Debug.Log("[GOLF] ball stopped at " + p);
                Send("{\"t\":\"ballStopped\",\"x\":" + F(p.x) + ",\"z\":" + F(p.z) + ",\"strokes\":" + _strokes + "}");
            }
        }

        void OnGUI()
        {
            if (_hud == null)
            {
                _hud = new GUIStyle(GUI.skin.label) { fontSize = 26, fontStyle = FontStyle.Bold }; _hud.normal.textColor = Color.white;
                _hudBig = new GUIStyle(GUI.skin.label) { fontSize = 44, fontStyle = FontStyle.Bold }; _hudBig.normal.textColor = new Color(1f, 0.9f, 0.3f);
                _dbg = new GUIStyle(GUI.skin.label) { fontSize = 16 }; _dbg.normal.textColor = new Color(0.7f, 1f, 0.7f);
                _ver = new GUIStyle(GUI.skin.label) { fontSize = 26, fontStyle = FontStyle.Bold }; _ver.normal.textColor = new Color(0.45f, 1f, 0.55f);
            }
            GUI.Label(new Rect(24, 14, 1500, 34), "COURSE BUILD: " + COURSE_BUILD, _ver);
            GUI.Label(new Rect(24, 44, 1500, 34), "SCENE: " + SCENE_NAME + "   ·   NEW L-SHAPE COURSE", _ver);
            GUI.Label(new Rect(24, 88, 800, 40), "Strokes: " + _strokes, _hud);
            GUI.Label(new Rect(24, 124, 1100, 56), _status, _holed ? _hudBig : _hud);
            if (!_showDebug) return;
            float vel = _ball != null ? _ball.linearVelocity.magnitude : 0f, y = _ball != null ? _ball.position.y : 0f;
            string[] lines = { "DEBUG", "material: " + _shaderName, "ball Y: " + y.ToString("0.00"), "ball vel: " + vel.ToString("0.00"),
                "grounded: " + _grounded, "in flight: " + _inFlight, "shots: " + _strokes, "entered well: " + _enteredWell, "holed: " + _holed };
            for (int i = 0; i < lines.Length; i++) GUI.Label(new Rect(24, 200 + i * 20, 500, 22), lines[i], _dbg);
        }

        void Send(string json) { if (UnityBridge.Instance != null) UnityBridge.Instance.SendToHost(json); }

        // DontDestroyOnLoad throws outside play mode (the in-editor preview renderer), so guard it.
        static void DDOL(GameObject go) { if (Application.isPlaying) DontDestroyOnLoad(go); }

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
            go.GetComponent<MeshRenderer>().enabled = false;   // collider only
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
        // Bamboo-style border. The collider is the SAME invisible box as the old wood rail, so wall
        // collisions + bank shots are byte-for-byte unchanged; only the visual becomes rounded bamboo
        // poles (horizontal cylinders) with darker segment node rings.
        void WallRail(string name, Vector3 center, Vector3 size)
        {
            InvisBox(name + "_col", center, size, _wallMat);
            bool alongX = size.x >= size.z;
            float len = alongX ? size.x : size.z;
            var bamboo = new Color(0.34f, 0.35f, 0.17f);   // DEEP muted olive-brown bamboo (jungle rail) — clearly darker, no glow, still distinct from turf
            var node = new Color(0.21f, 0.22f, 0.10f);
            var rot = alongX ? Quaternion.Euler(0f, 0f, 90f) : Quaternion.Euler(90f, 0f, 0f);
            for (int k = 0; k < 2; k++)   // two stacked rounded poles
            {
                float py = 0.24f + k * 0.30f;
                var pole = GameObject.CreatePrimitive(PrimitiveType.Cylinder); DDOL(pole); Destroy(pole.GetComponent<Collider>());
                pole.name = name + "_pole" + k;
                pole.transform.position = new Vector3(center.x, py, center.z);
                pole.transform.rotation = rot;
                pole.transform.localScale = new Vector3(0.34f, len * 0.5f, 0.34f);   // radius ~0.17, length = len
                pole.GetComponent<MeshRenderer>().material = NewMat(bamboo);
                int nodes = Mathf.Max(1, Mathf.RoundToInt(len / 1.6f));
                for (int n = 0; n <= nodes; n++)
                {
                    float along = Mathf.Lerp(-len * 0.5f + 0.12f, len * 0.5f - 0.12f, (float)n / nodes);
                    var ring = GameObject.CreatePrimitive(PrimitiveType.Cylinder); DDOL(ring); Destroy(ring.GetComponent<Collider>());
                    ring.name = name + "_node" + k + "_" + n;
                    ring.transform.position = alongX ? new Vector3(center.x + along, py, center.z) : new Vector3(center.x, py, center.z + along);
                    ring.transform.rotation = rot;
                    ring.transform.localScale = new Vector3(0.40f, 0.05f, 0.40f);   // fatter + thin = a segment node
                    ring.GetComponent<MeshRenderer>().material = NewMat(node);
                }
            }
        }
        // a short vertical bamboo post — cleans the wall-corner joints and frames the gate opening
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
            mr.material.mainTexture = tex; mr.material.mainTextureScale = Vector2.one;   // MakeAnnulus UVs already match the floor's 1.3-unit tiling
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
                tr[t++] = o0; tr[t++] = o1; tr[t++] = in0; tr[t++] = in0; tr[t++] = o1; tr[t++] = in1;   // up
                tr[t++] = o0; tr[t++] = in0; tr[t++] = o1; tr[t++] = in0; tr[t++] = in1; tr[t++] = o1;   // down (double-sided, always visible)
            }
            m.vertices = v; m.normals = nm; m.uv = uv; m.triangles = tr; m.RecalculateBounds(); return m;
        }
        static Mesh MakeDisk(float r, int seg)
        {
            var m = new Mesh(); var v = new Vector3[seg + 1]; var nm = new Vector3[seg + 1]; var uv = new Vector2[seg + 1]; var tr = new int[seg * 3];
            v[0] = Vector3.zero; nm[0] = Vector3.up; uv[0] = new Vector2(0.5f, 0.5f);
            for (int i = 0; i < seg; i++) { float a = (float)i / seg * Mathf.PI * 2f, c = Mathf.Cos(a), s = Mathf.Sin(a);
                float rr = r * (1f + 0.07f * Mathf.Sin(a * 4f) + 0.05f * Mathf.Sin(a * 7f + 1.3f) + 0.03f * Mathf.Sin(a * 13f));   // strongly irregular natural sand border
                v[i + 1] = new Vector3(c * rr, 0, s * rr); nm[i + 1] = Vector3.up; uv[i + 1] = new Vector2(0.5f + 0.5f * c, 0.5f + 0.5f * s); }
            int t = 0;
            for (int i = 0; i < seg; i++) { int a0 = i + 1, a1 = (i + 1) % seg + 1;
                tr[t++] = 0; tr[t++] = a1; tr[t++] = a0;   // single up-facing face (no double-blend halo under a transparent material)
            }
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
                tr[t++] = t0; tr[t++] = b0; tr[t++] = t1; tr[t++] = t1; tr[t++] = b0; tr[t++] = b1;   // outer
                tr[t++] = t0; tr[t++] = t1; tr[t++] = b0; tr[t++] = b0; tr[t++] = t1; tr[t++] = b1;   // inner (double-sided)
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
        static string F(float v) => v.ToString("0.00", System.Globalization.CultureInfo.InvariantCulture);
    }
}
