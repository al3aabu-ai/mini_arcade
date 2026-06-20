using UnityEngine;

namespace MiniArcade.Bridge
{
    /// Unity golf slice — polish pass on the proven box-primitive baseline.
    /// Same reliable approach (CreatePrimitive cubes, forced built-in shader, real colliders,
    /// real square well). This pass: darker arcade palette, bouncier fence walls (separate physics
    /// material), and a more interesting course — a diagonal bank (a turn), a speed-bump, a sand
    /// hazard, and a cup in the far corner. Ball/shot feel and the well behavior are kept.
    public class GolfGame : MonoBehaviour
    {
        public static GolfGame Instance { get; private set; }

        const float BallR = 0.18f;
        const float CupHalf = 0.7f;
        const float CupDepth = 1.4f;
        static readonly Vector3 CupCenter = new Vector3(4f, 0f, 3f);
        static readonly Vector3 TeePos = new Vector3(-3.5f, BallR + 0.20f, -8.5f);
        // sand hazard rectangle (XZ) — the ball slows here
        static readonly Vector2 SandMin = new Vector2(0.5f, -0.25f);
        static readonly Vector2 SandMax = new Vector2(3.5f, 2.25f);

        Rigidbody _ball;
        Transform _aim;
        Shader _shader;
        string _shaderName = "?";
        PhysicsMaterial _wallMat;
        float _aimAngle;
        int _strokes;
        bool _inFlight, _holed, _grounded, _enteredWell, _loggedGround;
        float _still, _flight;
        string _status = "Aim on your phone";
        GUIStyle _hud, _hudBig, _dbg;

#if MINIARCADE_THINSLICE
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void Boot()
        {
            if (Instance != null) return;
            var go = new GameObject("GolfGame");
            DontDestroyOnLoad(go);
            Instance = go.AddComponent<GolfGame>();
            var bridge = new GameObject("UnityBridge");
            DontDestroyOnLoad(bridge);
            bridge.AddComponent<UnityBridge>();
        }
#endif

        void Awake()
        {
            Instance = this;
            Physics.gravity = new Vector3(0f, -16f, 0f);
            RenderSettings.ambientLight = new Color(0.28f, 0.30f, 0.32f);   // darker, less neon
            ResolveShader();
            _wallMat = new PhysicsMaterial("wall") {
                bounciness = 0.72f, dynamicFriction = 0.15f, staticFriction = 0.15f,
                frictionCombine = PhysicsMaterialCombine.Minimum, bounceCombine = PhysicsMaterialCombine.Maximum
            };
            BuildCamera();
            BuildLight();
            BuildCourse();
            BuildBall();
            BuildAim();
            ResetBall();
            Debug.Log("[GOLF] scene loaded; shader=" + _shaderName);
        }

        void ResolveShader()
        {
            string[] names = { "Legacy Shaders/Diffuse", "Unlit/Color", "Sprites/Default", "Standard" };
            foreach (var n in names) { var s = Shader.Find(n); if (s != null) { _shader = s; _shaderName = n; return; } }
            _shader = null; _shaderName = "NONE-MAGENTA";
            Debug.LogError("[GOLF] no built-in shader found -> materials will be magenta!");
        }

        Material NewMat(Color c)
        {
            var m = _shader != null ? new Material(_shader) : new Material(Shader.Find("Hidden/InternalErrorShader"));
            m.color = c;
            return m;
        }

        void BuildCamera()
        {
            var go = new GameObject("Main Camera");
            DontDestroyOnLoad(go);
            var cam = go.AddComponent<Camera>();
            cam.clearFlags = CameraClearFlags.SolidColor;
            cam.backgroundColor = new Color(0.06f, 0.08f, 0.11f);   // darker bg
            cam.fieldOfView = 54f;
            go.transform.position = new Vector3(0f, 13f, -17f);
            go.transform.LookAt(new Vector3(0f, 0f, -2.5f));
        }

        void BuildLight()
        {
            var go = new GameObject("Sun");
            DontDestroyOnLoad(go);
            var l = go.AddComponent<Light>();
            l.type = LightType.Directional;
            l.intensity = 1.0f;
            go.transform.rotation = Quaternion.Euler(50f, -28f, 0f);
        }

        void BuildCourse()
        {
            var grass = new Color(0.13f, 0.32f, 0.18f);   // darker forest green
            var grass2 = new Color(0.16f, 0.38f, 0.22f);  // hump (slightly lighter)
            var wall = new Color(0.30f, 0.20f, 0.12f);    // dark warm brown
            var sand = new Color(0.45f, 0.39f, 0.24f);    // muted khaki
            var dark = new Color(0.04f, 0.05f, 0.05f);

            // floor (rectangle x[-6.5,6.5] z[-10.5,5.5]) split around the cup gap at (4,3)
            Box("Floor_A", new Vector3(0f, -0.25f, -4.1f), new Vector3(13f, 0.5f, 12.8f), grass);
            Box("Floor_B", new Vector3(0f, -0.25f, 4.6f), new Vector3(13f, 0.5f, 1.8f), grass);
            Box("Floor_C", new Vector3(-1.6f, -0.25f, 3f), new Vector3(9.8f, 0.5f, 1.4f), grass);
            Box("Floor_D", new Vector3(5.6f, -0.25f, 3f), new Vector3(1.8f, 0.5f, 1.4f), grass);

            // perimeter fence (bouncy)
            Box("Wall_Bottom", new Vector3(0f, 0.3f, -10.5f), new Vector3(13.3f, 0.6f, 0.3f), wall, _wallMat);
            Box("Wall_Top", new Vector3(0f, 0.3f, 5.5f), new Vector3(13.3f, 0.6f, 0.3f), wall, _wallMat);
            Box("Wall_Left", new Vector3(-6.5f, 0.3f, -2.5f), new Vector3(0.3f, 0.6f, 16.3f), wall, _wallMat);
            Box("Wall_Right", new Vector3(6.5f, 0.3f, -2.5f), new Vector3(0.3f, 0.6f, 16.3f), wall, _wallMat);

            // diagonal bank (the "turn") — ball goes around it or banks off it
            var bank = Box("Bank", new Vector3(0.5f, 0.3f, -2f), new Vector3(5.5f, 0.6f, 0.35f), wall, _wallMat);
            bank.transform.rotation = Quaternion.Euler(0f, 32f, 0f);

            // speed bump (gentle hump in the lower lane)
            Box("Hump", new Vector3(-2f, 0f, -5.5f), new Vector3(3.5f, 0.22f, 0.7f), grass2);

            // sand hazard (visual; slowdown applied in Update)
            Box("Sand", new Vector3((SandMin.x + SandMax.x) / 2f, 0.01f, (SandMin.y + SandMax.y) / 2f),
                new Vector3(SandMax.x - SandMin.x, 0.04f, SandMax.y - SandMin.y), sand);

            // recessed square well
            Box("Cup_X+", new Vector3(CupCenter.x + CupHalf, -0.7f, CupCenter.z), new Vector3(0.08f, 1.4f, 1.5f), dark, _wallMat);
            Box("Cup_X-", new Vector3(CupCenter.x - CupHalf, -0.7f, CupCenter.z), new Vector3(0.08f, 1.4f, 1.5f), dark, _wallMat);
            Box("Cup_Z+", new Vector3(CupCenter.x, -0.7f, CupCenter.z + CupHalf), new Vector3(1.5f, 1.4f, 0.08f), dark, _wallMat);
            Box("Cup_Z-", new Vector3(CupCenter.x, -0.7f, CupCenter.z - CupHalf), new Vector3(1.5f, 1.4f, 0.08f), dark, _wallMat);
            Box("Cup_Floor", new Vector3(CupCenter.x, -CupDepth, CupCenter.z), new Vector3(1.4f, 0.08f, 1.4f), dark);

            var pole = Box("FlagPole", new Vector3(CupCenter.x, 0.85f, CupCenter.z), new Vector3(0.04f, 1.7f, 0.04f), new Color(0.85f, 0.85f, 0.85f));
            Destroy(pole.GetComponent<Collider>());
            var pennant = Box("FlagPennant", new Vector3(CupCenter.x + 0.28f, 1.5f, CupCenter.z), new Vector3(0.5f, 0.32f, 0.02f), new Color(0.80f, 0.20f, 0.24f));
            Destroy(pennant.GetComponent<Collider>());
        }

        void BuildBall()
        {
            var go = GameObject.CreatePrimitive(PrimitiveType.Sphere);
            DontDestroyOnLoad(go);
            go.name = "Ball";
            go.transform.localScale = Vector3.one * (BallR * 2f);
            go.GetComponent<MeshRenderer>().material = NewMat(Color.white);

            var pm = new PhysicsMaterial("ball") {
                bounciness = 0.42f, dynamicFriction = 0.40f, staticFriction = 0.50f,
                frictionCombine = PhysicsMaterialCombine.Average, bounceCombine = PhysicsMaterialCombine.Average
            };
            go.GetComponent<SphereCollider>().material = pm;

            _ball = go.AddComponent<Rigidbody>();
            _ball.mass = 1f;
            _ball.linearDamping = 0.35f;
            _ball.angularDamping = 0.45f;
            _ball.collisionDetectionMode = CollisionDetectionMode.ContinuousDynamic;
            _ball.interpolation = RigidbodyInterpolation.Interpolate;
        }

        void BuildAim()
        {
            var go = GameObject.CreatePrimitive(PrimitiveType.Cube);
            DontDestroyOnLoad(go);
            go.name = "AimArrow";
            Destroy(go.GetComponent<Collider>());
            go.transform.localScale = new Vector3(0.07f, 0.02f, 1.3f);
            go.GetComponent<MeshRenderer>().material = NewMat(new Color(1f, 0.85f, 0.2f));
            _aim = go.transform;
        }

        public void OnHostMessage(string json)
        {
            string t = JStr(json, "t");
            if (t == "shoot") Shoot(JNum(json, "angle"), JNum(json, "power"));
            else if (t == "aim") _aimAngle = JNum(json, "angle");
            else if (t == "newHole" || t == "reset") ResetBall();
        }

        void Shoot(float angleDeg, float power01)
        {
            if (_ball == null || _inFlight || _holed) return;
            power01 = Mathf.Clamp01(power01);
            _aimAngle = angleDeg;
            float speed = Mathf.Lerp(3.5f, 15f, power01);
            float a = angleDeg * Mathf.Deg2Rad;
            Vector3 dir = new Vector3(Mathf.Sin(a), 0f, Mathf.Cos(a)).normalized;
            _ball.linearVelocity = dir * speed;
            _ball.angularVelocity = Vector3.zero;
            _strokes++;
            _inFlight = true; _still = 0f; _flight = 0f; _enteredWell = false;
            _status = "Stroke " + _strokes + "…";
            Debug.Log("[GOLF] shot fired #" + _strokes + " angle=" + angleDeg + " power=" + power01 + " speed=" + speed);
            Send("{\"t\":\"shotStarted\",\"stroke\":" + _strokes + "}");
            Send("{\"t\":\"strokeCount\",\"strokes\":" + _strokes + "}");
        }

        void ResetBall()
        {
            if (_ball == null) return;
            _ball.linearVelocity = Vector3.zero;
            _ball.angularVelocity = Vector3.zero;
            _ball.position = TeePos;
            _strokes = 0; _inFlight = false; _holed = false; _still = 0f; _enteredWell = false; _loggedGround = false;
            _status = "Aim on your phone";
            Debug.Log("[GOLF] ball spawned at " + TeePos);
        }

        bool OverSand(Vector3 p) =>
            p.x >= SandMin.x && p.x <= SandMax.x && p.z >= SandMin.y && p.z <= SandMax.y;

        void Update()
        {
            if (_ball != null)
            {
                _grounded = Physics.Raycast(_ball.position, Vector3.down, BallR + 0.10f);
                if (_grounded && !_loggedGround && !_inFlight) { _loggedGround = true; Debug.Log("[GOLF] ball grounded (resting on course)"); }
                // sand hazard: extra drag while grounded over the patch
                if (_grounded && OverSand(_ball.position))
                    _ball.linearVelocity = Vector3.MoveTowards(_ball.linearVelocity, Vector3.zero, 6f * Time.deltaTime);
            }

            if (_aim != null)
            {
                bool show = !_inFlight && !_holed && _ball != null;
                _aim.gameObject.SetActive(show);
                if (show)
                {
                    float a = _aimAngle * Mathf.Deg2Rad;
                    Vector3 dir = new Vector3(Mathf.Sin(a), 0f, Mathf.Cos(a)).normalized;
                    _aim.position = _ball.position + dir * 0.85f + Vector3.up * (0.02f - BallR);
                    _aim.rotation = Quaternion.LookRotation(dir, Vector3.up);
                }
            }

            if (!_inFlight || _ball == null) return;
            _flight += Time.deltaTime;
            Vector3 p = _ball.position;
            float speed = _ball.linearVelocity.magnitude;
            bool inWellColumn = Mathf.Abs(p.x - CupCenter.x) < CupHalf && Mathf.Abs(p.z - CupCenter.z) < CupHalf;
            bool downInWell = inWellColumn && p.y < -0.40f;

            if (downInWell && !_enteredWell) { _enteredWell = true; Debug.Log("[GOLF] ball entered well"); }
            if (speed < 0.30f) _still += Time.deltaTime; else _still = 0f;

            if (downInWell && p.y <= (-CupDepth + BallR + 0.14f) && _still > 0.35f)
            {
                _holed = true; _inFlight = false;
                _status = "HOLED in " + _strokes + "!";
                Debug.Log("[GOLF] HOLED confirmed in " + _strokes);
                Send("{\"t\":\"holed\",\"strokes\":" + _strokes + "}");
                Send("{\"t\":\"roundComplete\",\"strokes\":" + _strokes + "}");
                return;
            }
            if (p.y < -CupDepth - 3f)
            {
                Debug.Log("[GOLF] ball fell out of bounds -> reset");
                ResetBall();
                Send("{\"t\":\"ballStopped\",\"reset\":true,\"strokes\":" + _strokes + "}");
                return;
            }
            if (_still > 0.5f && _flight > 0.4f && !downInWell)
            {
                _inFlight = false;
                _status = "Stroke " + _strokes + " — your shot";
                Debug.Log("[GOLF] ball stopped at " + p);
                Send("{\"t\":\"ballStopped\",\"x\":" + F(p.x) + ",\"z\":" + F(p.z) + ",\"strokes\":" + _strokes + "}");
            }
        }

        void OnGUI()
        {
            if (_hud == null)
            {
                _hud = new GUIStyle(GUI.skin.label) { fontSize = 26, fontStyle = FontStyle.Bold };
                _hud.normal.textColor = Color.white;
                _hudBig = new GUIStyle(GUI.skin.label) { fontSize = 44, fontStyle = FontStyle.Bold };
                _hudBig.normal.textColor = new Color(1f, 0.9f, 0.3f);
                _dbg = new GUIStyle(GUI.skin.label) { fontSize = 16 };
                _dbg.normal.textColor = new Color(0.7f, 1f, 0.7f);
            }
            GUI.Label(new Rect(28, 22, 800, 40), "Strokes: " + _strokes, _hud);
            GUI.Label(new Rect(28, 60, 1100, 56), _status, _holed ? _hudBig : _hud);

            float vel = _ball != null ? _ball.linearVelocity.magnitude : 0f;
            float y = _ball != null ? _ball.position.y : 0f;
            string[] lines = {
                "DEBUG",
                "scene loaded: yes",
                "material: " + _shaderName,
                "ball Y: " + y.ToString("0.00"),
                "ball vel: " + vel.ToString("0.00"),
                "grounded: " + _grounded,
                "in flight: " + _inFlight,
                "shots: " + _strokes,
                "entered well: " + _enteredWell,
                "holed: " + _holed,
                "fallback: JS (host)",
            };
            for (int i = 0; i < lines.Length; i++)
                GUI.Label(new Rect(28, 130 + i * 20, 500, 22), lines[i], _dbg);
        }

        void Send(string json)
        {
            if (UnityBridge.Instance != null) UnityBridge.Instance.SendToHost(json);
        }

        GameObject Box(string name, Vector3 center, Vector3 size, Color color, PhysicsMaterial pm = null)
        {
            var go = GameObject.CreatePrimitive(PrimitiveType.Cube);
            DontDestroyOnLoad(go);
            go.name = name;
            go.transform.position = center;
            go.transform.localScale = size;
            go.GetComponent<MeshRenderer>().material = NewMat(color);
            if (pm != null) go.GetComponent<BoxCollider>().material = pm;
            return go;
        }

        static string JStr(string json, string key)
        {
            int i = json.IndexOf("\"" + key + "\""); if (i < 0) return "";
            i = json.IndexOf(':', i); if (i < 0) return "";
            int q = json.IndexOf('"', i + 1); if (q < 0) return "";
            int e = json.IndexOf('"', q + 1); if (e < 0) return "";
            return json.Substring(q + 1, e - q - 1);
        }
        static float JNum(string json, string key)
        {
            int i = json.IndexOf("\"" + key + "\""); if (i < 0) return 0f;
            i = json.IndexOf(':', i); if (i < 0) return 0f;
            int s = i + 1;
            while (s < json.Length && (json[s] == ' ' || json[s] == '"')) s++;
            int e = s;
            while (e < json.Length && (char.IsDigit(json[e]) || json[e] == '.' || json[e] == '-' || json[e] == '+')) e++;
            float.TryParse(json.Substring(s, e - s), System.Globalization.NumberStyles.Float,
                           System.Globalization.CultureInfo.InvariantCulture, out float val);
            return val;
        }
        static string F(float v) => v.ToString("0.00", System.Globalization.CultureInfo.InvariantCulture);
    }
}
