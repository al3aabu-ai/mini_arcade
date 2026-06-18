using System;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using MiniArcade.Display;
using MiniArcade.Players;

namespace MiniArcade.MiniGames.MiniGolf
{
    /// <summary>
    /// 3D party mini-golf prototype. The host builds and simulates a small
    /// procedural course at runtime: rails, blockers, a rotating bumper, coins,
    /// a physics ball, and a TV camera. Controllers only send simple private
    /// commands: aim, power, and shoot.
    /// </summary>
    public class MiniGolfGame : IMiniGame
    {
        private const float RoundDuration = 120f;
        private const int MaxStrokes = 6;
        private const float MinPower = 3.5f;
        private const float MaxPower = 15f;
        private const float BallStopSpeed = 0.18f;
        private const float HoleRadius = 0.55f;
        private const float MaxCameraSpeed = 15f;

        private static readonly Vector3 TeePosition = new Vector3(-7f, 0.42f, 0f);
        private static readonly Vector3 HolePosition = new Vector3(7f, 0.34f, 0f);

        public string Id => "mini_golf";
        public string DisplayName => "Party Mini Golf";
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
                int stroke = Mathf.Min(_strokes[p.Id] + 1, MaxStrokes);
                string suffix = _ballRolling ? "ball rolling" : $"aim {_aimDegrees:0} / power {_power01 * 100f:0}%";
                return $"TIKI TURN: {p.DisplayName} | Stroke {stroke}/{MaxStrokes} | Coins {_coins[p.Id]} | {suffix}";
            }
        }

        public event Action<MiniGameResult> Finished;

        private readonly Dictionary<string, int> _scores = new Dictionary<string, int>();
        private readonly Dictionary<string, int> _strokes = new Dictionary<string, int>();
        private readonly Dictionary<string, int> _coins = new Dictionary<string, int>();
        private readonly Dictionary<string, int> _bonus = new Dictionary<string, int>();
        private readonly Dictionary<string, bool> _holed = new Dictionary<string, bool>();
        private readonly Dictionary<string, Vector3> _positions = new Dictionary<string, Vector3>();
        private readonly List<CoinPickup> _coinPickups = new List<CoinPickup>();

        private List<PlayerData> _players = new List<PlayerData>();
        private int _currentIndex;
        private float _timeLeft;
        private float _aimDegrees;
        private float _power01 = 0.45f;
        private float _settleTimer;
        private bool _running;
        private bool _ballRolling;

        private GameObject _root;
        private GameObject _ball;
        private Rigidbody _ballRb;
        private Transform _aimArrow;
        private Transform _spinner;
        private Material _ballMaterial;
        private Material _trailMaterial;
        private Material _flameMaterial;
        private Camera _camera;
        private TrailRenderer _trail;
        private Vector3 _cameraVelocity;

        private PlayerData CurrentPlayer =>
            _players.Count == 0 ? null : _players[Mathf.Clamp(_currentIndex, 0, _players.Count - 1)];

        public void Begin(IReadOnlyList<PlayerData> players, IReadOnlyDictionary<string, int> startingBonus)
        {
            CleanupScene();

            _players = new List<PlayerData>(players);
            _scores.Clear();
            _strokes.Clear();
            _coins.Clear();
            _bonus.Clear();
            _holed.Clear();
            _positions.Clear();
            _coinPickups.Clear();

            foreach (var p in _players)
            {
                _scores[p.Id] = 0;
                _strokes[p.Id] = 0;
                _coins[p.Id] = 0;
                _bonus[p.Id] = startingBonus != null && startingBonus.TryGetValue(p.Id, out int b) ? b : 0;
                _holed[p.Id] = false;
                _positions[p.Id] = TeePosition;
            }

            BuildCourse();
            _timeLeft = RoundDuration;
            _currentIndex = 0;
            _running = true;
            StartTurn();
        }

        public void Tick(float deltaTime)
        {
            if (!_running) return;

            _timeLeft -= deltaTime;
            if (_timeLeft <= 0f)
            {
                _timeLeft = 0f;
                End();
                return;
            }

            if (_spinner != null)
                _spinner.Rotate(0f, 95f * deltaTime, 0f, Space.World);

            RotateCoins(deltaTime);

            if (_ball == null || _ballRb == null) return;

            UpdateAimArrow();
            UpdateCamera(deltaTime);
            UpdateTrail();
            CollectCoinsForCurrentPlayer();

            if (_ball.transform.position.y < -4f || Mathf.Abs(_ball.transform.position.x) > 12f || Mathf.Abs(_ball.transform.position.z) > 8f)
            {
                ResetCurrentBallToTee();
                FinishTurn(false);
                return;
            }

            if (IsBallInHole())
            {
                FinishTurn(true);
                return;
            }

            if (_ballRolling)
            {
                if (_ballRb.linearVelocity.magnitude <= BallStopSpeed)
                    _settleTimer += deltaTime;
                else
                    _settleTimer = 0f;

                if (_settleTimer >= 0.55f)
                    FinishTurn(false);
            }
        }

        public void HandleInput(string playerId, string action)
        {
            if (!_running || _ballRolling || CurrentPlayer == null || CurrentPlayer.Id != playerId)
                return;

            switch (action)
            {
                case "aim_left":
                    _aimDegrees = Mathf.Clamp(_aimDegrees - 8f, -70f, 70f);
                    break;
                case "aim_right":
                    _aimDegrees = Mathf.Clamp(_aimDegrees + 8f, -70f, 70f);
                    break;
                case "power_down":
                    _power01 = Mathf.Clamp01(_power01 - 0.1f);
                    break;
                case "power_up":
                    _power01 = Mathf.Clamp01(_power01 + 0.1f);
                    break;
                case "shoot":
                case "tap":
                    Shoot();
                    break;
            }
        }

        public void End()
        {
            if (!_running) return;
            _running = false;

            foreach (var p in _players)
                _scores[p.Id] = CalculateScore(p.Id);

            var ordered = new List<PlayerData>(_players);
            ordered.Sort((a, b) => _scores[b.Id].CompareTo(_scores[a.Id]));

            var result = new MiniGameResult { MiniGameId = Id };
            for (int i = 0; i < ordered.Count; i++)
            {
                var p = ordered[i];
                result.Placements[p.Id] = i + 1;
                result.CoinsCollected[p.Id] = _coins[p.Id] + (_holed[p.Id] ? 8 : 0);
            }

            CleanupScene();
            Finished?.Invoke(result);
        }

        private void StartTurn()
        {
            if (!_running || _players.Count == 0) return;

            int guard = 0;
            while (guard++ < _players.Count && IsPlayerDone(CurrentPlayer.Id))
                _currentIndex = (_currentIndex + 1) % _players.Count;

            if (_players.All(p => IsPlayerDone(p.Id)))
            {
                End();
                return;
            }

            var p = CurrentPlayer;
            _aimDegrees = 0f;
            _power01 = 0.45f;
            _settleTimer = 0f;
            _ballRolling = false;
            SetBallColor(_currentIndex);
            PlaceBall(_positions[p.Id]);
            UpdateAimArrow();
        }

        private void Shoot()
        {
            var p = CurrentPlayer;
            if (p == null) return;

            _strokes[p.Id]++;
            float power = Mathf.Lerp(MinPower, MaxPower, _power01);
            float radians = _aimDegrees * Mathf.Deg2Rad;
            var direction = new Vector3(Mathf.Cos(radians), 0f, Mathf.Sin(radians)).normalized;

            _ballRb.isKinematic = false;
            _ballRb.linearVelocity = Vector3.zero;
            _ballRb.angularVelocity = Vector3.zero;
            _ballRb.AddForce(direction * power, ForceMode.Impulse);
            _ballRolling = true;
            _settleTimer = 0f;
            if (_aimArrow != null) _aimArrow.gameObject.SetActive(false);
            if (_trail != null) _trail.Clear();
            if (_power01 >= 0.78f)
                SpawnBurst(_ball.transform.position - direction * 0.45f, new Color(0.2f, 0.75f, 1f), 28, 3.2f, 0.14f);
        }

        private void FinishTurn(bool holed)
        {
            var p = CurrentPlayer;
            if (p == null) return;

            if (holed)
            {
                _holed[p.Id] = true;
                _positions[p.Id] = HolePosition;
            }
            else
            {
                _positions[p.Id] = _ball.transform.position;
            }

            _scores[p.Id] = CalculateScore(p.Id);
            _currentIndex = (_currentIndex + 1) % _players.Count;
            StartTurn();
        }

        private bool IsPlayerDone(string id)
        {
            return _holed[id] || _strokes[id] >= MaxStrokes;
        }

        private int CalculateScore(string id)
        {
            int strokes = _strokes.TryGetValue(id, out int s) ? s : MaxStrokes;
            int coins = _coins.TryGetValue(id, out int c) ? c : 0;
            int bonus = _bonus.TryGetValue(id, out int b) ? b : 0;
            bool holed = _holed.TryGetValue(id, out bool h) && h;

            if (holed)
                return 1200 - strokes * 120 + coins * 35 + bonus;

            Vector3 pos = _positions.TryGetValue(id, out Vector3 saved) ? saved : TeePosition;
            float distance = Vector3.Distance(new Vector3(pos.x, 0f, pos.z), new Vector3(HolePosition.x, 0f, HolePosition.z));
            return Mathf.RoundToInt(500f - strokes * 70f - distance * 18f + coins * 30f + bonus);
        }

        private void BuildCourse()
        {
            _root = new GameObject("MiniGolfCourse");
            CreateCamera();
            CreateLight();

            var turf = MakeMat("TikiTurf", new Color(0.07f, 0.72f, 0.31f));
            var wood = MakeMat("WarmCarvedWood", new Color(0.54f, 0.25f, 0.10f));
            var darkWood = MakeMat("DarkTikiWood", new Color(0.28f, 0.11f, 0.04f));
            var bamboo = MakeMat("SunlitBamboo", new Color(0.95f, 0.76f, 0.32f));
            var leaf = MakeMat("TropicalLeaf", new Color(0.03f, 0.68f, 0.23f));
            var bumper = MakeMat("HotTikiBumper", new Color(0.95f, 0.22f, 0.08f));
            var coin = MakeGlowMat("GlowingCoinGold", new Color(1f, 0.72f, 0.10f), new Color(1f, 0.45f, 0.02f) * 0.8f);
            var maskGlow = MakeGlowMat("NeonTikiGlow", new Color(0.15f, 0.95f, 0.70f), new Color(0.05f, 0.85f, 0.55f) * 1.6f);
            _flameMaterial = MakeGlowMat("TorchFlame", new Color(1f, 0.43f, 0.05f), new Color(1f, 0.24f, 0.02f) * 2.0f);

            AddCube("RaisedWoodPlatform", new Vector3(0f, -0.22f, 0f), new Vector3(19.2f, 0.55f, 10.7f), wood);
            AddCube("BrightTurfFairway", new Vector3(0f, 0.10f, 0f), new Vector3(18f, 0.22f, 9.5f), turf);
            AddPlankLines(darkWood);

            AddBambooRailX("LeftBambooRail", new Vector3(0f, 0.58f, -4.95f), 18.6f, bamboo);
            AddBambooRailX("RightBambooRail", new Vector3(0f, 0.58f, 4.95f), 18.6f, bamboo);
            AddBambooRailZ("BackBambooRail", new Vector3(-9.2f, 0.58f, 0f), 9.8f, bamboo);
            AddBambooRailZ("HoleBambooRailTop", new Vector3(9.1f, 0.58f, 2.6f), 4.7f, bamboo);
            AddBambooRailZ("HoleBambooRailBottom", new Vector3(9.1f, 0.58f, -2.6f), 4.7f, bamboo);

            AddLeafCluster(new Vector3(-8.2f, 0.36f, -4.2f), leaf);
            AddLeafCluster(new Vector3(-8.0f, 0.36f, 4.1f), leaf);
            AddLeafCluster(new Vector3(8.0f, 0.36f, -4.1f), leaf);
            AddLeafCluster(new Vector3(8.1f, 0.36f, 4.0f), leaf);

            AddCube("AngledTikiBlockA", new Vector3(-1.7f, 0.55f, -1.8f), new Vector3(4.4f, 0.85f, 0.5f), bumper).transform.rotation = Quaternion.Euler(0f, 28f, 0f);
            AddCube("AngledTikiBlockB", new Vector3(2.1f, 0.55f, 1.9f), new Vector3(4.1f, 0.85f, 0.5f), bumper).transform.rotation = Quaternion.Euler(0f, -25f, 0f);

            AddTikiMask("TikiMaskA", new Vector3(-2.9f, 1.05f, -2.45f), Quaternion.Euler(0f, 28f, 0f), darkWood, maskGlow);
            AddTikiMask("TikiMaskB", new Vector3(3.1f, 1.05f, 2.45f), Quaternion.Euler(0f, -25f, 0f), darkWood, maskGlow);

            var spinnerBase = AddCube("SpinnerTotemBase", new Vector3(1.15f, 0.6f, 0f), new Vector3(0.45f, 0.8f, 0.45f), darkWood);
            var spinnerBody = spinnerBase.AddComponent<Rigidbody>();
            spinnerBody.isKinematic = true;
            _spinner = spinnerBase.transform;
            var arm = AddCube("SpinnerBambooArm", Vector3.zero, new Vector3(5.2f, 0.26f, 0.35f), bumper);
            arm.transform.SetParent(_spinner, false);
            arm.transform.localPosition = new Vector3(0f, 0.35f, 0f);

            AddTikiTorch("TeeTorchLeft", new Vector3(-7.4f, 0.72f, -1.15f), darkWood);
            AddTikiTorch("TeeTorchRight", new Vector3(-7.4f, 0.72f, 1.15f), darkWood);
            AddTikiTorch("HoleTorchLeft", new Vector3(7.8f, 0.72f, -1.15f), darkWood);
            AddTikiTorch("HoleTorchRight", new Vector3(7.8f, 0.72f, 1.15f), darkWood);

            var hole = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            hole.name = "Hole";
            hole.transform.SetParent(_root.transform);
            hole.transform.position = HolePosition + new Vector3(0f, -0.03f, 0f);
            hole.transform.localScale = new Vector3(0.75f, 0.03f, 0.75f);
            hole.GetComponent<Renderer>().material = darkWood;
            UnityEngine.Object.Destroy(hole.GetComponent<Collider>());

            for (int i = 0; i < 8; i++)
            {
                float x = -5.2f + i * 1.45f;
                float z = (i % 2 == 0) ? 2.7f : -2.7f;
                AddCoin("Coin" + i, new Vector3(x, 0.55f, z), coin);
            }

            _ball = GameObject.CreatePrimitive(PrimitiveType.Sphere);
            _ball.name = "GolfBall";
            _ball.transform.SetParent(_root.transform);
            _ball.transform.localScale = Vector3.one * 0.48f;
            _ballMaterial = MakeMat("MiniGolfBall", Color.white);
            _ball.GetComponent<Renderer>().material = _ballMaterial;
            _ballRb = _ball.AddComponent<Rigidbody>();
            _ballRb.mass = 0.35f;
            _ballRb.linearDamping = 0.85f;
            _ballRb.angularDamping = 0.4f;
            _ballRb.collisionDetectionMode = CollisionDetectionMode.ContinuousDynamic;
            var relay = _ball.AddComponent<MiniGolfCollisionRelay>();
            relay.Hit += OnBallCollision;

            _trailMaterial = MakeGlowMat("MiniGolfTrail", new Color(0.25f, 0.85f, 1f, 0.9f), new Color(0.15f, 0.85f, 1f) * 1.5f);
            _trail = _ball.AddComponent<TrailRenderer>();
            _trail.material = _trailMaterial;
            _trail.time = 0.28f;
            _trail.minVertexDistance = 0.04f;
            _trail.startWidth = 0f;
            _trail.endWidth = 0f;
            _trail.emitting = false;

            var arrow = GameObject.CreatePrimitive(PrimitiveType.Cube);
            arrow.name = "AimArrow";
            arrow.transform.SetParent(_root.transform);
            arrow.transform.localScale = new Vector3(1.7f, 0.08f, 0.16f);
            arrow.GetComponent<Renderer>().material = MakeGlowMat("TikiAimGlow", new Color(1f, 0.62f, 0.05f), new Color(1f, 0.35f, 0.02f) * 1.4f);
            UnityEngine.Object.Destroy(arrow.GetComponent<Collider>());
            _aimArrow = arrow.transform;
        }

        private void CreateCamera()
        {
            var cameraGo = new GameObject("MiniGolfCamera");
            cameraGo.transform.SetParent(_root.transform);
            cameraGo.transform.position = new Vector3(0f, 12.5f, -10.5f);
            cameraGo.transform.rotation = Quaternion.Euler(58f, 0f, 0f);
            _camera = cameraGo.AddComponent<Camera>();
            _camera.clearFlags = CameraClearFlags.SolidColor;
            _camera.backgroundColor = new Color(0.08f, 0.11f, 0.15f);
            _camera.depth = 20f;
            _camera.fieldOfView = 52f;
            _camera.rect = new Rect(0f, 0.18f, 1f, 0.70f);
            _camera.targetDisplay = DisplayManager.PublicDisplayIndex;
        }

        private void CreateLight()
        {
            RenderSettings.ambientLight = new Color(0.42f, 0.34f, 0.24f);

            var lightGo = new GameObject("MiniGolfKeyLight");
            lightGo.transform.SetParent(_root.transform);
            lightGo.transform.rotation = Quaternion.Euler(52f, -35f, 0f);
            var light = lightGo.AddComponent<Light>();
            light.type = LightType.Directional;
            light.intensity = 1.45f;
            light.color = new Color(1f, 0.82f, 0.55f);
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

        private void AddPlankLines(Material material)
        {
            for (int i = 0; i < 10; i++)
            {
                float x = -8.1f + i * 1.8f;
                var plank = AddCube("WoodPlankGroove" + i, new Vector3(x, 0.075f, -5.05f), new Vector3(0.04f, 0.035f, 0.28f), material);
                UnityEngine.Object.Destroy(plank.GetComponent<Collider>());
                var plankB = AddCube("WoodPlankGrooveBack" + i, new Vector3(x, 0.075f, 5.05f), new Vector3(0.04f, 0.035f, 0.28f), material);
                UnityEngine.Object.Destroy(plankB.GetComponent<Collider>());
            }
        }

        private void AddBambooRailX(string name, Vector3 position, float length, Material material)
        {
            AddBambooLog(name + "_Low", position, length, true, material);
            AddBambooLog(name + "_High", position + Vector3.up * 0.34f, length, true, material);
            int posts = Mathf.Max(2, Mathf.RoundToInt(length / 2.7f));
            for (int i = 0; i <= posts; i++)
            {
                float t = i / (float)posts;
                float x = Mathf.Lerp(-length * 0.5f, length * 0.5f, t);
                AddBambooPost(name + "_Post" + i, position + new Vector3(x, 0.02f, 0f), material);
            }
        }

        private void AddBambooRailZ(string name, Vector3 position, float length, Material material)
        {
            AddBambooLog(name + "_Low", position, length, false, material);
            AddBambooLog(name + "_High", position + Vector3.up * 0.34f, length, false, material);
            int posts = Mathf.Max(2, Mathf.RoundToInt(length / 2.3f));
            for (int i = 0; i <= posts; i++)
            {
                float t = i / (float)posts;
                float z = Mathf.Lerp(-length * 0.5f, length * 0.5f, t);
                AddBambooPost(name + "_Post" + i, position + new Vector3(0f, 0.02f, z), material);
            }
        }

        private GameObject AddBambooLog(string name, Vector3 position, float length, bool alongX, Material material)
        {
            var go = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            go.name = name;
            go.transform.SetParent(_root.transform);
            go.transform.position = position;
            go.transform.rotation = alongX ? Quaternion.Euler(0f, 0f, 90f) : Quaternion.Euler(90f, 0f, 0f);
            go.transform.localScale = new Vector3(0.18f, length * 0.5f, 0.18f);
            go.GetComponent<Renderer>().material = material;
            return go;
        }

        private void AddBambooPost(string name, Vector3 position, Material material)
        {
            var go = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            go.name = name;
            go.transform.SetParent(_root.transform);
            go.transform.position = position;
            go.transform.localScale = new Vector3(0.16f, 0.46f, 0.16f);
            go.GetComponent<Renderer>().material = material;
        }

        private void AddLeafCluster(Vector3 center, Material material)
        {
            for (int i = 0; i < 5; i++)
            {
                float angle = i * 72f;
                var leaf = AddCube("TropicalLeaf" + i, center + Quaternion.Euler(0f, angle, 0f) * new Vector3(0.28f, 0.12f, 0f), new Vector3(0.16f, 0.035f, 0.95f), material);
                leaf.transform.rotation = Quaternion.Euler(18f, angle, 0f);
                UnityEngine.Object.Destroy(leaf.GetComponent<Collider>());
            }
        }

        private void AddTikiMask(string name, Vector3 position, Quaternion rotation, Material wood, Material glow)
        {
            var mask = AddCube(name, position, new Vector3(0.55f, 1.05f, 0.22f), wood);
            mask.transform.rotation = rotation;
            UnityEngine.Object.Destroy(mask.GetComponent<Collider>());

            Vector3 eyeOffsetL = rotation * new Vector3(-0.14f, 0.14f, -0.13f);
            Vector3 eyeOffsetR = rotation * new Vector3(0.14f, 0.14f, -0.13f);
            var leftEye = AddCube(name + "_EyeL", position + eyeOffsetL, new Vector3(0.12f, 0.10f, 0.035f), glow);
            leftEye.transform.rotation = rotation;
            UnityEngine.Object.Destroy(leftEye.GetComponent<Collider>());
            var rightEye = AddCube(name + "_EyeR", position + eyeOffsetR, new Vector3(0.12f, 0.10f, 0.035f), glow);
            rightEye.transform.rotation = rotation;
            UnityEngine.Object.Destroy(rightEye.GetComponent<Collider>());

            var mouth = AddCube(name + "_Mouth", position + rotation * new Vector3(0f, -0.24f, -0.13f), new Vector3(0.28f, 0.07f, 0.035f), glow);
            mouth.transform.rotation = rotation;
            UnityEngine.Object.Destroy(mouth.GetComponent<Collider>());

            var lightGo = new GameObject(name + "_GlowLight");
            lightGo.transform.SetParent(_root.transform);
            lightGo.transform.position = position + Vector3.up * 0.1f;
            var light = lightGo.AddComponent<Light>();
            light.type = LightType.Point;
            light.color = new Color(0.05f, 1f, 0.65f);
            light.intensity = 1.0f;
            light.range = 2.2f;
        }

        private void AddTikiTorch(string name, Vector3 position, Material wood)
        {
            var pole = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            pole.name = name + "_Pole";
            pole.transform.SetParent(_root.transform);
            pole.transform.position = position;
            pole.transform.localScale = new Vector3(0.08f, 0.62f, 0.08f);
            pole.GetComponent<Renderer>().material = wood;

            var bowl = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            bowl.name = name + "_Bowl";
            bowl.transform.SetParent(_root.transform);
            bowl.transform.position = position + Vector3.up * 0.72f;
            bowl.transform.localScale = new Vector3(0.22f, 0.08f, 0.22f);
            bowl.GetComponent<Renderer>().material = wood;
            UnityEngine.Object.Destroy(bowl.GetComponent<Collider>());

            var flame = new GameObject(name + "_Flame");
            flame.transform.SetParent(_root.transform);
            flame.transform.position = position + Vector3.up * 0.88f;

            var ps = flame.AddComponent<ParticleSystem>();
            var main = ps.main;
            main.loop = true;
            main.startLifetime = 0.42f;
            main.startSpeed = 0.65f;
            main.startSize = 0.22f;
            main.startColor = new Color(1f, 0.42f, 0.02f, 0.9f);
            main.simulationSpace = ParticleSystemSimulationSpace.World;
            var emission = ps.emission;
            emission.rateOverTime = 18f;
            var shape = ps.shape;
            shape.shapeType = ParticleSystemShapeType.Cone;
            shape.angle = 16f;
            shape.radius = 0.08f;

            var renderer = ps.GetComponent<ParticleSystemRenderer>();
            if (_flameMaterial != null) renderer.material = _flameMaterial;

            var lightGo = new GameObject(name + "_Light");
            lightGo.transform.SetParent(_root.transform);
            lightGo.transform.position = flame.transform.position;
            var light = lightGo.AddComponent<Light>();
            light.type = LightType.Point;
            light.color = new Color(1f, 0.45f, 0.08f);
            light.intensity = 1.4f;
            light.range = 3.0f;
        }

        private void AddCoin(string name, Vector3 position, Material material)
        {
            var go = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            go.name = name;
            go.transform.SetParent(_root.transform);
            go.transform.position = position;
            go.transform.rotation = Quaternion.Euler(90f, 0f, 0f);
            go.transform.localScale = new Vector3(0.34f, 0.05f, 0.34f);
            go.GetComponent<Renderer>().material = material;
            UnityEngine.Object.Destroy(go.GetComponent<Collider>());
            _coinPickups.Add(new CoinPickup { Go = go, Active = true });
        }

        private static Material MakeMat(string name, Color color)
        {
            var mat = new Material(ResolveRuntimeShader());
            mat.name = name;
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
            var shader =
                Shader.Find("Standard") ??
                Shader.Find("Universal Render Pipeline/Lit") ??
                Shader.Find("Universal Render Pipeline/Simple Lit") ??
                Shader.Find("Unlit/Color") ??
                Shader.Find("Sprites/Default") ??
                Shader.Find("Hidden/Internal-Colored");

            if (shader != null)
                return shader;

            var probe = GameObject.CreatePrimitive(PrimitiveType.Cube);
            shader = probe.GetComponent<Renderer>()?.sharedMaterial?.shader;
            UnityEngine.Object.Destroy(probe);
            return shader;
        }

        private void RotateCoins(float deltaTime)
        {
            foreach (var pickup in _coinPickups)
            {
                if (pickup.Active && pickup.Go != null)
                    pickup.Go.transform.Rotate(0f, 180f * deltaTime, 0f, Space.World);
            }
        }

        private void CollectCoinsForCurrentPlayer()
        {
            var p = CurrentPlayer;
            if (p == null) return;

            for (int i = 0; i < _coinPickups.Count; i++)
            {
                var pickup = _coinPickups[i];
                if (!pickup.Active || pickup.Go == null) continue;

                Vector3 a = new Vector3(_ball.transform.position.x, 0f, _ball.transform.position.z);
                Vector3 b = new Vector3(pickup.Go.transform.position.x, 0f, pickup.Go.transform.position.z);
                if (Vector3.Distance(a, b) <= 0.55f)
                {
                    pickup.Active = false;
                    pickup.Go.SetActive(false);
                    _coins[p.Id] += 3;
                    _coinPickups[i] = pickup;
                }
            }
        }

        private void PlaceBall(Vector3 position)
        {
            _ball.transform.position = position;
            _ballRb.isKinematic = false;
            _ballRb.linearVelocity = Vector3.zero;
            _ballRb.angularVelocity = Vector3.zero;
            if (_trail != null) _trail.Clear();
        }

        private void ResetCurrentBallToTee()
        {
            var p = CurrentPlayer;
            if (p == null) return;
            _positions[p.Id] = TeePosition;
            PlaceBall(TeePosition);
        }

        private void UpdateAimArrow()
        {
            if (_aimArrow == null || _ball == null) return;
            _aimArrow.gameObject.SetActive(!_ballRolling);
            if (_ballRolling) return;

            float radians = _aimDegrees * Mathf.Deg2Rad;
            var direction = new Vector3(Mathf.Cos(radians), 0f, Mathf.Sin(radians)).normalized;
            _aimArrow.position = _ball.transform.position + direction * 0.95f + Vector3.up * 0.18f;
            _aimArrow.rotation = Quaternion.Euler(0f, -_aimDegrees, 0f);
            _aimArrow.localScale = new Vector3(Mathf.Lerp(1.0f, 2.2f, _power01), 0.08f, 0.16f);
        }

        private void SetBallColor(int index)
        {
            if (_ballMaterial == null) return;
            Color[] colors =
            {
                Color.white,
                new Color(0.25f, 0.65f, 1f),
                new Color(1f, 0.3f, 0.35f),
                new Color(1f, 0.85f, 0.25f),
                new Color(0.55f, 1f, 0.45f),
                new Color(0.9f, 0.45f, 1f)
            };
            _ballMaterial.color = colors[index % colors.Length];
        }

        private bool IsBallInHole()
        {
            Vector3 a = new Vector3(_ball.transform.position.x, 0f, _ball.transform.position.z);
            Vector3 b = new Vector3(HolePosition.x, 0f, HolePosition.z);
            return Vector3.Distance(a, b) <= HoleRadius && _ballRb.linearVelocity.magnitude <= 3.5f;
        }

        private void UpdateCamera(float deltaTime)
        {
            if (_camera == null || _ball == null) return;

            Vector3 ballPos = _ball.transform.position;
            Vector3 velocity = _ballRb != null ? _ballRb.linearVelocity : Vector3.zero;
            float speed = velocity.magnitude;
            float speedT = Mathf.Clamp01(speed / MaxCameraSpeed);
            Vector3 aimForward = AimForward();
            Vector3 travelForward = speed > 0.35f ? new Vector3(velocity.x, 0f, velocity.z).normalized : aimForward;

            Vector3 holeFlat = new Vector3(HolePosition.x, ballPos.y, HolePosition.z);
            Vector3 ballToHole = (holeFlat - ballPos);
            float holeDistance = ballToHole.magnitude;
            Vector3 holeDir = holeDistance > 0.01f ? ballToHole.normalized : aimForward;
            float holeAlignment = Mathf.Clamp01((Vector3.Dot(travelForward, holeDir) + 1f) * 0.5f);

            float holeWeight = _ballRolling ? Mathf.Lerp(0.08f, 0.38f, holeAlignment) : 0.28f;
            if (holeDistance > 9f) holeWeight *= 0.45f;
            Vector3 focus = Vector3.Lerp(ballPos, HolePosition, holeWeight);
            focus.y = Mathf.Lerp(ballPos.y + 0.55f, 1.15f, 0.65f);

            Vector3 desiredPos;
            if (!_ballRolling)
            {
                float distance = 5.2f + _power01 * 1.1f;
                desiredPos = ballPos - aimForward * distance + Vector3.up * 2.4f;
                focus = ballPos + aimForward * Mathf.Lerp(2.8f, 5.2f, _power01) + Vector3.up * 0.75f;
            }
            else
            {
                float followDistance = Mathf.Lerp(5.4f, 8.8f, speedT);
                float followHeight = Mathf.Lerp(2.3f, 4.2f, speedT);
                float lookAhead = Mathf.Lerp(1.2f, 4.6f, speedT);

                Bounds framingBounds = new Bounds(ballPos, Vector3.one);
                if (holeAlignment > 0.45f || holeDistance < 7f)
                    framingBounds.Encapsulate(HolePosition + Vector3.up * 0.35f);
                framingBounds.Encapsulate(ballPos + travelForward * lookAhead);

                float fovRad = _camera.fieldOfView * Mathf.Deg2Rad;
                float requiredDistance = framingBounds.extents.magnitude / Mathf.Tan(fovRad * 0.5f);
                followDistance = Mathf.Clamp(Mathf.Max(followDistance, requiredDistance * 0.68f), 4.7f, 11.5f);

                desiredPos = focus - travelForward * followDistance + Vector3.up * followHeight;
            }

            float damping = Mathf.Lerp(0.34f, 0.09f, speedT);
            _camera.transform.position = Vector3.SmoothDamp(_camera.transform.position, desiredPos, ref _cameraVelocity, damping);

            Quaternion desiredRot = Quaternion.LookRotation(focus - _camera.transform.position, Vector3.up);
            float rotLerp = Mathf.Lerp(7f, 15f, speedT) * deltaTime;
            _camera.transform.rotation = Quaternion.Slerp(_camera.transform.rotation, desiredRot, Mathf.Clamp01(rotLerp));
        }

        private Vector3 AimForward()
        {
            float radians = _aimDegrees * Mathf.Deg2Rad;
            return new Vector3(Mathf.Cos(radians), 0f, Mathf.Sin(radians)).normalized;
        }

        private void UpdateTrail()
        {
            if (_trail == null || _ballRb == null) return;

            float speedT = Mathf.Clamp01(_ballRb.linearVelocity.magnitude / MaxCameraSpeed);
            bool active = _ballRolling && speedT > 0.08f;
            _trail.emitting = active;
            _trail.startWidth = active ? Mathf.Lerp(0.05f, 0.28f, speedT) : 0f;
            _trail.endWidth = 0f;
        }

        private void OnBallCollision(Collision collision)
        {
            if (!_running || collision.contactCount == 0) return;

            float impact = collision.impulse.magnitude;
            if (impact < 0.55f) return;

            ContactPoint contact = collision.GetContact(0);
            float impactT = Mathf.Clamp01(impact / 8f);
            int count = Mathf.RoundToInt(Mathf.Lerp(8f, 34f, impactT));
            SpawnBurst(contact.point + contact.normal * 0.04f, new Color(1f, 0.85f, 0.35f), count, Mathf.Lerp(0.8f, 3.4f, impactT), Mathf.Lerp(0.05f, 0.16f, impactT));
        }

        private void SpawnBurst(Vector3 position, Color color, int count, float speed, float size)
        {
            if (_root == null) return;

            var go = new GameObject("ArcadeBurst");
            go.transform.SetParent(_root.transform);
            go.transform.position = position;

            var ps = go.AddComponent<ParticleSystem>();
            var main = ps.main;
            main.duration = 0.32f;
            main.loop = false;
            main.startLifetime = 0.35f;
            main.startSpeed = speed;
            main.startSize = size;
            main.startColor = color;
            main.simulationSpace = ParticleSystemSimulationSpace.World;

            var emission = ps.emission;
            emission.rateOverTime = 0f;
            ps.Emit(count);
            UnityEngine.Object.Destroy(go, 1.0f);
        }

        private void CleanupScene()
        {
            if (_root != null)
            {
                UnityEngine.Object.Destroy(_root);
                _root = null;
            }
            _ball = null;
            _ballRb = null;
            _aimArrow = null;
            _spinner = null;
            _camera = null;
            _trail = null;
        }

        private struct CoinPickup
        {
            public GameObject Go;
            public bool Active;
        }
    }

    public class MiniGolfCollisionRelay : MonoBehaviour
    {
        public event Action<Collision> Hit;

        private void OnCollisionEnter(Collision collision)
        {
            Hit?.Invoke(collision);
        }
    }
}
