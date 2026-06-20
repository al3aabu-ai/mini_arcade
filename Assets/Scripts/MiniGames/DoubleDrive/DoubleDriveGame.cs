using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using MiniArcade.Display;
using MiniArcade.Players;

namespace MiniArcade.MiniGames.DoubleDrive
{
    /// <summary>
    /// "Double Drive: Trap-Out" — turn-based 3D arcade golf. Every player gets a
    /// persistent ball that stays on the course as a physical obstacle, and TWO
    /// shots total to find the hole. Shot 1 round (all players in order), then
    /// Shot 2 round (players who haven't sunk). Hole on shot 1 = +50, shot 2 = +20,
    /// miss both = 0.
    ///
    /// Increment 1: the core 3D engine — corridor course with billiard walls, one
    /// Rigidbody ball per player (PhysX gives 8-ball collisions for free), the
    /// aim/power/shoot turn loop, hole detection, scoring, and a TV camera.
    /// Sabotage traps + the full Bumper Boulevard terrain land in later increments.
    /// </summary>
    public class DoubleDriveGame : IMiniGame
    {
        private const float RoundDuration = 240f;        // generous; turns drive progress
        private const float ShotClock = 12f;             // per the GDD
        private const float MinPower = 4.0f;
        private const float MaxPower = 17f;
        private const float BallStopSpeed = 0.22f;
        private const float HoleRadius = 0.62f;
        private const float HoleCaptureSpeed = 4.0f;

        // Corridor course laid out along +X. Tee end at -X, hole end at +X.
        private static readonly Vector3 TeePosition = new Vector3(-8.2f, 0.5f, 0f);
        private static readonly Vector3 HolePosition = new Vector3(8.2f, 0.34f, 0f);

        public string Id => "double_drive";
        public string DisplayName => "Double Drive: Trap-Out";
        public bool Running => _running;
        public float TimeLeft => _timeLeft;
        public IReadOnlyDictionary<string, int> Scores => _scores;

        public string Prompt
        {
            get
            {
                if (!_running) return "Get ready...";
                var p = CurrentPlayer;
                if (p == null) return "Finishing hole...";
                string suffix = _ballRolling ? "ball rolling" : $"aim {_aimDegrees:0} / power {_power01 * 100f:0}%";
                return $"DOUBLE DRIVE | {p.DisplayName} | Shot {_shotRound}/2 | {suffix}";
            }
        }

        public event Action<MiniGameResult> Finished;

        private readonly Dictionary<string, int> _scores = new Dictionary<string, int>();
        private readonly Dictionary<string, int> _bonus = new Dictionary<string, int>();
        private readonly Dictionary<string, int> _sunkOnShot = new Dictionary<string, int>();   // 0 = not sunk
        private readonly Dictionary<string, int> _shotsTaken = new Dictionary<string, int>();
        private readonly Dictionary<string, GameObject> _balls = new Dictionary<string, GameObject>();
        private readonly Dictionary<string, Rigidbody> _ballRbs = new Dictionary<string, Rigidbody>();
        private readonly Dictionary<string, Material> _ballMats = new Dictionary<string, Material>();

        private List<PlayerData> _players = new List<PlayerData>();
        private List<string> _order = new List<string>();    // players still to act this round
        private int _turnIndex;
        private int _shotRound = 1;                           // 1 or 2

        private float _timeLeft;
        private float _shotTimer;
        private float _aimDegrees;
        private float _power01 = 0.5f;
        private float _powerDir = 1f;                         // for the auto-cycling bar
        private bool _autoPower;                              // true while a phone is holding to aim
        private float _settleTimer;
        private bool _running;
        private bool _ballRolling;

        private GameObject _root;
        private Camera _camera;
        private Transform _aimArrow;
        private LineRenderer _aimLaser;
        private Vector3 _cameraVelocity;

        private PlayerData CurrentPlayer
        {
            get
            {
                if (_turnIndex < 0 || _turnIndex >= _order.Count) return null;
                string id = _order[_turnIndex];
                return _players.FirstOrDefault(p => p.Id == id);
            }
        }

        // ---------------- lifecycle ----------------

        public void Begin(IReadOnlyList<PlayerData> players, IReadOnlyDictionary<string, int> startingBonus)
        {
            CleanupScene();
            _players = new List<PlayerData>(players);
            _scores.Clear(); _bonus.Clear(); _sunkOnShot.Clear(); _shotsTaken.Clear();

            foreach (var p in _players)
            {
                _scores[p.Id] = 0;
                _bonus[p.Id] = startingBonus != null && startingBonus.TryGetValue(p.Id, out int b) ? b : 0;
                _sunkOnShot[p.Id] = 0;
                _shotsTaken[p.Id] = 0;
            }

            BuildCourse();
            SpawnBalls();

            _timeLeft = RoundDuration;
            _shotRound = 1;
            _order = _players.Select(p => p.Id).ToList();
            _turnIndex = 0;
            _running = true;
            StartTurn();
        }

        public void Tick(float deltaTime)
        {
            if (!_running) return;

            _timeLeft -= deltaTime;
            if (_timeLeft <= 0f) { End(); return; }

            UpdatePowerCycle(deltaTime);
            UpdateAimArrow();
            UpdateCamera(deltaTime);
            CheckHoles();

            if (_ballRolling)
            {
                if (MaxBallSpeed() <= BallStopSpeed) _settleTimer += deltaTime;
                else _settleTimer = 0f;
                if (_settleTimer >= 0.6f) FinishTurn();
            }
            else
            {
                // shot clock: if the player dawdles, auto-fire at the current power
                _shotTimer -= deltaTime;
                if (_shotTimer <= 0f) Shoot();
            }
        }

        public void HandleInput(string playerId, string action)
        {
            if (!_running || _ballRolling) return;
            var p = CurrentPlayer;
            if (p == null || p.Id != playerId) return;
            if (string.IsNullOrEmpty(action)) return;

            // Aimed-release scheme (web controller): aimStart / aim:<deg> / release
            if (action == "aimStart") { _autoPower = true; _power01 = 0f; _powerDir = 1f; return; }
            if (action.StartsWith("aim:"))
            {
                if (float.TryParse(action.Substring(4), out float deg)) _aimDegrees = NormalizeAim(deg);
                return;
            }
            if (action == "release") { Shoot(); return; }

            // Discrete scheme (host IMGUI buttons / simple controllers)
            switch (action)
            {
                case "aim_left": _aimDegrees = NormalizeAim(_aimDegrees - 8f); break;
                case "aim_right": _aimDegrees = NormalizeAim(_aimDegrees + 8f); break;
                case "power_down": _power01 = Mathf.Clamp01(_power01 - 0.1f); break;
                case "power_up": _power01 = Mathf.Clamp01(_power01 + 0.1f); break;
                case "shoot":
                case "tap": Shoot(); break;
            }
        }

        public void End()
        {
            if (!_running) return;
            _running = false;

            foreach (var p in _players) _scores[p.Id] = FinalScore(p.Id);

            var ordered = new List<PlayerData>(_players);
            ordered.Sort((a, b) => _scores[b.Id].CompareTo(_scores[a.Id]));

            var result = new MiniGameResult { MiniGameId = Id };
            for (int i = 0; i < ordered.Count; i++)
            {
                var p = ordered[i];
                result.Placements[p.Id] = i + 1;
                int shot = _sunkOnShot.TryGetValue(p.Id, out int s) ? s : 0;
                result.CoinsCollected[p.Id] = shot == 1 ? 50 : shot == 2 ? 20 : 0;
            }

            CleanupScene();
            Finished?.Invoke(result);
        }

        // ---------------- turn flow ----------------

        private void StartTurn()
        {
            if (!_running) return;

            // skip players who already sank
            int guard = 0;
            while (_turnIndex < _order.Count && IsSunk(_order[_turnIndex]) && guard++ < 64)
                _turnIndex++;

            if (_turnIndex >= _order.Count)
            {
                AdvanceRound();
                return;
            }

            _aimDegrees = 0f;
            _power01 = 0.5f;
            _powerDir = 1f;
            _autoPower = false;
            _ballRolling = false;
            _settleTimer = 0f;
            _shotTimer = ShotClock;
            ShowAimAids(true);
        }

        private void AdvanceRound()
        {
            if (_shotRound == 1)
            {
                _shotRound = 2;
                _order = _players.Where(p => !IsSunk(p.Id)).Select(p => p.Id).ToList();
                _turnIndex = 0;
                if (_order.Count == 0) { End(); return; }
                StartTurn();
            }
            else
            {
                End();
            }
        }

        private void Shoot()
        {
            var p = CurrentPlayer;
            if (p == null || _ballRolling) return;
            if (!_ballRbs.TryGetValue(p.Id, out var rb) || rb == null) return;

            _shotsTaken[p.Id] = _shotsTaken.TryGetValue(p.Id, out int st) ? st + 1 : 1;

            float power = Mathf.Lerp(MinPower, MaxPower, _power01);
            float radians = _aimDegrees * Mathf.Deg2Rad;
            var dir = new Vector3(Mathf.Cos(radians), 0f, Mathf.Sin(radians)).normalized;

            rb.isKinematic = false;
            rb.linearVelocity = Vector3.zero;
            rb.angularVelocity = Vector3.zero;
            rb.AddForce(dir * power, ForceMode.Impulse);

            _ballRolling = true;
            _autoPower = false;
            _settleTimer = 0f;
            ShowAimAids(false);
        }

        private void FinishTurn()
        {
            _ballRolling = false;
            CheckHoles();
            _turnIndex++;
            StartTurn();
        }

        private void CheckHoles()
        {
            foreach (var p in _players)
            {
                if (IsSunk(p.Id)) continue;
                if (!_balls.TryGetValue(p.Id, out var go) || go == null) continue;
                if (!_ballRbs.TryGetValue(p.Id, out var rb) || rb == null) continue;

                Vector3 a = new Vector3(go.transform.position.x, 0f, go.transform.position.z);
                Vector3 b = new Vector3(HolePosition.x, 0f, HolePosition.z);
                if (Vector3.Distance(a, b) <= HoleRadius && rb.linearVelocity.magnitude <= HoleCaptureSpeed)
                {
                    _sunkOnShot[p.Id] = Mathf.Clamp(_shotsTaken.TryGetValue(p.Id, out int s) ? s : _shotRound, 1, 2);
                    _scores[p.Id] = FinalScore(p.Id);
                    rb.isKinematic = true;
                    go.transform.position = HolePosition + Vector3.up * 0.1f;
                }
            }
        }

        private bool IsSunk(string id) => _sunkOnShot.TryGetValue(id, out int s) && s > 0;

        private int FinalScore(string id)
        {
            int bonus = _bonus.TryGetValue(id, out int b) ? b : 0;
            int shot = _sunkOnShot.TryGetValue(id, out int s) ? s : 0;
            if (shot == 1) return 50 + bonus;
            if (shot == 2) return 20 + bonus;

            // DNF: small tie-breaker by how close the ball ended up.
            if (_balls.TryGetValue(id, out var go) && go != null)
            {
                float d = Vector3.Distance(new Vector3(go.transform.position.x, 0f, go.transform.position.z),
                                           new Vector3(HolePosition.x, 0f, HolePosition.z));
                return Mathf.Clamp(10 - Mathf.RoundToInt(d), 0, 10) + bonus;
            }
            return bonus;
        }

        private float MaxBallSpeed()
        {
            float max = 0f;
            foreach (var rb in _ballRbs.Values)
                if (rb != null && !rb.isKinematic) max = Mathf.Max(max, rb.linearVelocity.magnitude);
            return max;
        }

        private static float NormalizeAim(float deg)
        {
            while (deg > 180f) deg -= 360f;
            while (deg < -180f) deg += 360f;
            return deg;
        }

        // ---------------- power / aim aids ----------------

        private void UpdatePowerCycle(float deltaTime)
        {
            if (_ballRolling || !_autoPower) return;
            _power01 += _powerDir * deltaTime * 1.4f;   // ~0.7s up, 0.7s down
            if (_power01 >= 1f) { _power01 = 1f; _powerDir = -1f; }
            else if (_power01 <= 0f) { _power01 = 0f; _powerDir = 1f; }
        }

        private void ShowAimAids(bool show)
        {
            if (_aimArrow != null) _aimArrow.gameObject.SetActive(show);
            if (_aimLaser != null) _aimLaser.enabled = show;
        }

        private void UpdateAimArrow()
        {
            var p = CurrentPlayer;
            if (p == null || _ballRolling) { ShowAimAids(false); return; }
            if (!_balls.TryGetValue(p.Id, out var ball) || ball == null) return;

            ShowAimAids(true);
            float radians = _aimDegrees * Mathf.Deg2Rad;
            var dir = new Vector3(Mathf.Cos(radians), 0f, Mathf.Sin(radians)).normalized;
            Vector3 basePos = ball.transform.position + Vector3.up * 0.05f;

            if (_aimArrow != null)
            {
                _aimArrow.position = basePos + dir * 1.0f;
                _aimArrow.rotation = Quaternion.Euler(0f, -_aimDegrees, 0f);
                _aimArrow.localScale = new Vector3(Mathf.Lerp(1.0f, 2.4f, _power01), 0.09f, 0.18f);
            }
            if (_aimLaser != null)
            {
                float len = Mathf.Lerp(2.0f, 6.5f, _power01);
                _aimLaser.SetPosition(0, basePos);
                _aimLaser.SetPosition(1, basePos + dir * len);
            }
        }

        // ---------------- scene ----------------

        private void BuildCourse()
        {
            _root = new GameObject("DoubleDriveCourse");
            CreateCamera();
            CreateLight();

            var grass = MakeMat("DD_Grass", new Color(0.10f, 0.55f, 0.24f));
            var wall = MakeMat("DD_Wall", new Color(0.20f, 0.16f, 0.30f));
            var rim = MakeMat("DD_Rim", new Color(0.97f, 0.82f, 0.25f));
            var dark = MakeMat("DD_Dark", new Color(0.04f, 0.10f, 0.06f));

            var bounce = new PhysicsMaterial("DD_Bounce") { bounciness = 0.62f, dynamicFriction = 0.25f, staticFriction = 0.25f };
            bounce.bounceCombine = PhysicsMaterialCombine.Maximum;
            bounce.frictionCombine = PhysicsMaterialCombine.Minimum;

            // fairway
            var floor = AddCube("Fairway", new Vector3(0f, -0.2f, 0f), new Vector3(20f, 0.4f, 9.2f), grass);
            floor.GetComponent<Collider>().material = bounce;

            // billiard walls (tall, bouncy)
            AddWall("WallBack", new Vector3(-10.1f, 0.6f, 0f), new Vector3(0.5f, 1.6f, 9.2f), wall, bounce);
            AddWall("WallFront", new Vector3(10.1f, 0.6f, 0f), new Vector3(0.5f, 1.6f, 9.2f), wall, bounce);
            AddWall("WallLeft", new Vector3(0f, 0.6f, -4.6f), new Vector3(20.6f, 1.6f, 0.5f), wall, bounce);
            AddWall("WallRight", new Vector3(0f, 0.6f, 4.6f), new Vector3(20.6f, 1.6f, 0.5f), wall, bounce);

            // hole (visual) + rim
            var hole = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            hole.name = "Hole";
            hole.transform.SetParent(_root.transform);
            hole.transform.position = HolePosition + new Vector3(0f, -0.03f, 0f);
            hole.transform.localScale = new Vector3(HoleRadius * 1.7f, 0.04f, HoleRadius * 1.7f);
            hole.GetComponent<Renderer>().material = dark;
            UnityEngine.Object.Destroy(hole.GetComponent<Collider>());

            var flagPole = AddCube("FlagPole", HolePosition + new Vector3(0f, 0.9f, 0f), new Vector3(0.06f, 1.8f, 0.06f), rim);
            UnityEngine.Object.Destroy(flagPole.GetComponent<Collider>());
            var flag = AddCube("Flag", HolePosition + new Vector3(0.28f, 1.55f, 0f), new Vector3(0.5f, 0.32f, 0.04f), MakeMat("DD_FlagCloth", new Color(1f, 0.36f, 0.62f)));
            UnityEngine.Object.Destroy(flag.GetComponent<Collider>());

            // tee marker
            var tee = AddCube("Tee", new Vector3(TeePosition.x, 0.02f, 0f), new Vector3(1.4f, 0.04f, 1.4f), rim);
            UnityEngine.Object.Destroy(tee.GetComponent<Collider>());

            // aim aids
            var arrow = GameObject.CreatePrimitive(PrimitiveType.Cube);
            arrow.name = "AimArrow";
            arrow.transform.SetParent(_root.transform);
            arrow.transform.localScale = new Vector3(1.6f, 0.09f, 0.18f);
            arrow.GetComponent<Renderer>().material = MakeGlowMat("DD_AimGlow", new Color(1f, 0.85f, 0.2f), new Color(1f, 0.6f, 0.05f) * 1.3f);
            UnityEngine.Object.Destroy(arrow.GetComponent<Collider>());
            _aimArrow = arrow.transform;

            var laserGo = new GameObject("AimLaser");
            laserGo.transform.SetParent(_root.transform);
            _aimLaser = laserGo.AddComponent<LineRenderer>();
            _aimLaser.material = MakeGlowMat("DD_LaserGlow", new Color(1f, 1f, 1f), new Color(1f, 0.9f, 0.5f));
            _aimLaser.widthMultiplier = 0.08f;
            _aimLaser.positionCount = 2;
            _aimLaser.numCapVertices = 4;
            _aimLaser.textureMode = LineTextureMode.Tile;
        }

        private void SpawnBalls()
        {
            int n = _players.Count;
            for (int i = 0; i < n; i++)
            {
                var p = _players[i];
                float z = (n <= 1) ? 0f : Mathf.Lerp(-2.6f, 2.6f, i / (float)(n - 1));
                Vector3 pos = new Vector3(TeePosition.x, TeePosition.y, z);

                var ball = GameObject.CreatePrimitive(PrimitiveType.Sphere);
                ball.name = "Ball_" + p.Id;
                ball.transform.SetParent(_root.transform);
                ball.transform.position = pos;
                ball.transform.localScale = Vector3.one * 0.55f;

                var mat = MakeMat("DD_Ball_" + p.Id, ColorFromHex(p.Color));
                ball.GetComponent<Renderer>().material = mat;

                var rb = ball.AddComponent<Rigidbody>();
                rb.mass = 0.4f;
                rb.linearDamping = 0.5f;
                rb.angularDamping = 0.5f;
                rb.collisionDetectionMode = CollisionDetectionMode.ContinuousDynamic;

                _balls[p.Id] = ball;
                _ballRbs[p.Id] = rb;
                _ballMats[p.Id] = mat;
            }
        }

        private void CreateCamera()
        {
            var go = new GameObject("DoubleDriveCamera");
            go.transform.SetParent(_root.transform);
            go.transform.position = new Vector3(0f, 15f, -12.5f);
            go.transform.rotation = Quaternion.Euler(54f, 0f, 0f);
            _camera = go.AddComponent<Camera>();
            _camera.clearFlags = CameraClearFlags.SolidColor;
            _camera.backgroundColor = new Color(0.04f, 0.05f, 0.09f);
            _camera.fieldOfView = 50f;
            _camera.depth = 20f;
            _camera.targetDisplay = DisplayManager.PublicDisplayIndex;
        }

        private void CreateLight()
        {
            RenderSettings.ambientLight = new Color(0.40f, 0.40f, 0.46f);
            var go = new GameObject("DoubleDriveKeyLight");
            go.transform.SetParent(_root.transform);
            go.transform.rotation = Quaternion.Euler(55f, -30f, 0f);
            var light = go.AddComponent<Light>();
            light.type = LightType.Directional;
            light.intensity = 1.4f;
            light.color = new Color(1f, 0.96f, 0.86f);
        }

        private void UpdateCamera(float deltaTime)
        {
            if (_camera == null) return;
            var p = CurrentPlayer;
            Vector3 focus = new Vector3(0f, 0.4f, 0f);
            if (p != null && _balls.TryGetValue(p.Id, out var ball) && ball != null)
                focus = Vector3.Lerp(ball.transform.position, HolePosition, 0.3f);

            Vector3 desired = focus + new Vector3(0f, 15f, -12.5f);
            _camera.transform.position = Vector3.SmoothDamp(_camera.transform.position, desired, ref _cameraVelocity, 0.35f);
            var look = Quaternion.LookRotation((focus - _camera.transform.position).normalized, Vector3.up);
            _camera.transform.rotation = Quaternion.Slerp(_camera.transform.rotation, look, 6f * deltaTime);
        }

        private GameObject AddCube(string name, Vector3 position, Vector3 scale, Material material)
        {
            var go = GameObject.CreatePrimitive(PrimitiveType.Cube);
            go.name = name;
            go.transform.SetParent(_root.transform);
            go.transform.position = position;
            go.transform.localScale = scale;
            go.GetComponent<Renderer>().material = material;
            return go;
        }

        private GameObject AddWall(string name, Vector3 position, Vector3 scale, Material material, PhysicsMaterial physic)
        {
            var go = AddCube(name, position, scale, material);
            var col = go.GetComponent<Collider>();
            if (col != null) col.material = physic;
            return go;
        }

        private static Material MakeMat(string name, Color color)
        {
            var mat = new Material(ResolveRuntimeShader()) { name = name };
            if (mat.HasProperty("_BaseColor")) mat.SetColor("_BaseColor", color);
            if (mat.HasProperty("_Color")) mat.SetColor("_Color", color);
            return mat;
        }

        private static Material MakeGlowMat(string name, Color color, Color emission)
        {
            var mat = MakeMat(name, color);
            mat.EnableKeyword("_EMISSION");
            if (mat.HasProperty("_EmissionColor")) mat.SetColor("_EmissionColor", emission);
            return mat;
        }

        private static Shader ResolveRuntimeShader()
        {
            return Shader.Find("Standard") ??
                   Shader.Find("Universal Render Pipeline/Lit") ??
                   Shader.Find("Universal Render Pipeline/Simple Lit") ??
                   Shader.Find("Unlit/Color") ??
                   Shader.Find("Sprites/Default") ??
                   Shader.Find("Hidden/Internal-Colored");
        }

        private static Color ColorFromHex(string hex)
        {
            if (!string.IsNullOrEmpty(hex) && ColorUtility.TryParseHtmlString(hex, out var c)) return c;
            return new Color(1f, 0.36f, 0.62f);
        }

        private void CleanupScene()
        {
            if (_root != null) { UnityEngine.Object.Destroy(_root); _root = null; }
            _balls.Clear();
            _ballRbs.Clear();
            _ballMats.Clear();
            _camera = null;
            _aimArrow = null;
            _aimLaser = null;
        }
    }
}
