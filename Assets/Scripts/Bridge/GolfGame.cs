using UnityEngine;

namespace MiniArcade.Bridge
{
    /// First playable Unity golf slice — RELIABLE box-primitive course (stabilization build).
    /// Solid floor + walls + a real recessed SQUARE well, all from CreatePrimitive cubes.
    /// Materials use a FORCED built-in shader (Always-Included in the build) so they never fall
    /// back to the magenta error shader on device. The ball spawns ON the floor, rests, rolls,
    /// hits edges, slows, and DROPS into the well by gravity. "Holed" only after it physically
    /// settles in the well — no pull, no teleport, no absorb.
    public class GolfGame : MonoBehaviour
    {
        public static GolfGame Instance { get; private set; }

        const float BallR = 0.18f;
        const float CupHalf = 0.7f;
        const float CupDepth = 1.4f;
        static readonly Vector3 CupCenter = new Vector3(0f, 0f, 0f);
        static readonly Vector3 TeePos = new Vector3(0f, BallR + 0.20f, -7f);   // spawn clearly ABOVE the floor

        Rigidbody _ball;
        Transform _aim;
        Shader _shader;
        string _shaderName = "?";
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
            RenderSettings.ambientLight = new Color(0.42f, 0.44f, 0.46f);
            ResolveShader();
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
            foreach (var n in names)
            {
                var s = Shader.Find(n);
                if (s != null) { _shader = s; _shaderName = n; return; }
            }
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
            cam.backgroundColor = new Color(0.07f, 0.10f, 0.16f);
            cam.fieldOfView = 50f;
            go.transform.position = new Vector3(0f, 7f, -13.5f);
            go.transform.LookAt(new Vector3(0f, 0f, -1f));
        }

        void BuildLight()
        {
            var go = new GameObject("Sun");
            DontDestroyOnLoad(go);
            var l = go.AddComponent<Light>();
            l.type = LightType.Directional;
            l.intensity = 1.1f;
            go.transform.rotation = Quaternion.Euler(50f, -28f, 0f);
        }

        void BuildCourse()
        {
            var grass = new Color(0.24f, 0.52f, 0.30f);
            var wall = new Color(0.52f, 0.40f, 0.28f);
            var dark = new Color(0.05f, 0.06f, 0.06f);

            Box("Floor_Back", new Vector3(0f, -0.25f, -5.35f), new Vector3(14f, 0.5f, 9.3f), grass);
            Box("Floor_Front", new Vector3(0f, -0.25f, 3.35f), new Vector3(14f, 0.5f, 5.3f), grass);
            Box("Floor_Left", new Vector3(-3.85f, -0.25f, 0f), new Vector3(6.3f, 0.5f, 1.4f), grass);
            Box("Floor_Right", new Vector3(3.85f, -0.25f, 0f), new Vector3(6.3f, 0.5f, 1.4f), grass);

            Box("Wall_Back", new Vector3(0f, 0.3f, -10f), new Vector3(14.4f, 0.6f, 0.3f), wall);
            Box("Wall_Front", new Vector3(0f, 0.3f, 6f), new Vector3(14.4f, 0.6f, 0.3f), wall);
            Box("Wall_Left", new Vector3(-7f, 0.3f, -2f), new Vector3(0.3f, 0.6f, 16.3f), wall);
            Box("Wall_Right", new Vector3(7f, 0.3f, -2f), new Vector3(0.3f, 0.6f, 16.3f), wall);

            Box("Cup_X+", new Vector3(CupHalf, -0.7f, 0f), new Vector3(0.08f, 1.4f, 1.5f), dark);
            Box("Cup_X-", new Vector3(-CupHalf, -0.7f, 0f), new Vector3(0.08f, 1.4f, 1.5f), dark);
            Box("Cup_Z+", new Vector3(0f, -0.7f, CupHalf), new Vector3(1.5f, 1.4f, 0.08f), dark);
            Box("Cup_Z-", new Vector3(0f, -0.7f, -CupHalf), new Vector3(1.5f, 1.4f, 0.08f), dark);
            Box("Cup_Floor", new Vector3(0f, -CupDepth, 0f), new Vector3(1.4f, 0.08f, 1.4f), dark);

            var pole = Box("FlagPole", new Vector3(0f, 0.85f, 0f), new Vector3(0.04f, 1.7f, 0.04f), new Color(0.9f, 0.9f, 0.9f));
            Destroy(pole.GetComponent<Collider>());
            var pennant = Box("FlagPennant", new Vector3(0.28f, 1.5f, 0f), new Vector3(0.5f, 0.32f, 0.02f), new Color(0.92f, 0.22f, 0.27f));
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
                bounciness = 0.38f, dynamicFriction = 0.45f, staticFriction = 0.55f,
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

        void Update()
        {
            if (_ball != null)
            {
                _grounded = Physics.Raycast(_ball.position, Vector3.down, BallR + 0.10f);
                if (_grounded && !_loggedGround && !_inFlight) { _loggedGround = true; Debug.Log("[GOLF] ball grounded (resting on course)"); }
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

            // debug panel (you asked for this)
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

        GameObject Box(string name, Vector3 center, Vector3 size, Color color)
        {
            var go = GameObject.CreatePrimitive(PrimitiveType.Cube);
            DontDestroyOnLoad(go);
            go.name = name;
            go.transform.position = center;
            go.transform.localScale = size;
            go.GetComponent<MeshRenderer>().material = NewMat(color);
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
