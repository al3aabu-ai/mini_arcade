using UnityEngine;

namespace Frantics.Golf
{
    /// <summary>
    /// Tiki Jungle Adventure — Hole 5, ported from the SceneKit course.
    ///
    /// Procedural builder (mirrors the Swift TikiJungleCourse): attach to an empty
    /// GameObject and it assembles the whole hole at Awake into clean child groups
    /// — fairway, fence, archways, bunker, water, monkey, scenery — plus a ball at
    /// the tee. The fairway is ONE thick slab (no tile seams; ball can't tunnel),
    /// hazards are triggers, and the monkey's mallet is a kinematic Rigidbody.
    ///
    /// Layers (set these up in Project Settings ▸ Tags and Layers, see README):
    ///   "Environment" — floor, fence, arches, pedestal, mallet
    ///   "Ball"        — the golf ball
    /// The collision matrix must let Ball ↔ Environment collide (default does).
    /// </summary>
    public class TikiJungleCourse : MonoBehaviour
    {
        [Header("Identity")]
        public string courseTitle = "Tiki Jungle Adventure";
        public int hole = 5;

        [Header("Layout (Unity units, Y up, +Z = tee end → -Z = green)")]
        public Vector3 teeSpawn = new Vector3(0f, 1.0f, 15.5f);
        public Vector3 holeCenter = new Vector3(2.5f, 0.0f, -16f);

        [Header("Physics feel")]
        [Range(0f, 1f)] public float fairwayFriction = 0.95f;   // matches the SceneKit 0.95
        [Range(0f, 1f)] public float fairwayBounciness = 0.2f;
        public float ballRadius = 0.42f;
        public float ballMass = 1f;
        public float ballDrag = 0.16f;       // baseline linear drag (SceneKit damping)
        public float sandDrag = 4.0f;        // drastically higher drag inside the bunker

        [Header("Hazards (xz centre + radius)")]
        public Vector2 bunkerCenter = new Vector2(2.0f, 4.0f);
        public float bunkerRadius = 2.4f;
        public Vector2 waterCenter = new Vector2(-4.0f, -6.0f);
        public float waterRadius = 3.0f;

        // Modular group roots (parallels the SceneKit node groups).
        Transform fairwayRoot, fenceRoot, archwaysRoot, bunkerRoot, waterRoot, monkeyRoot, sceneryRoot;

        // Cached layers + shared materials.
        int environmentLayer, ballLayer;
        PhysicMaterial fairwayPhysics, wallPhysics, ballPhysics;

        void Awake()
        {
            environmentLayer = SafeLayer("Environment");
            ballLayer = SafeLayer("Ball");
            BuildSharedMaterials();

            fairwayRoot  = NewGroup("FairwayRoot");
            fenceRoot    = NewGroup("FenceRoot");
            archwaysRoot = NewGroup("ArchwaysRoot");
            bunkerRoot   = NewGroup("BunkerRoot");
            waterRoot    = NewGroup("WaterRoot");
            monkeyRoot   = NewGroup("MonkeyRoot");
            sceneryRoot  = NewGroup("SceneryRoot");

            BuildFairway();
            BuildGreenAndHole();
            BuildFence();
            BuildArchways();
            BuildBunker();
            BuildWaterHazard();
            BuildMonkey();
            BuildScenery();
            SpawnBall();
            SetupCamera();
        }

        GameObject spawnedBall;

        // ----------------------------------------------------------------- setup

        void BuildSharedMaterials()
        {
            // Smooth, high-friction fairway. Maximum combine so the rolling feel
            // is dominated by this surface regardless of the ball's own material.
            fairwayPhysics = new PhysicMaterial("Fairway")
            {
                dynamicFriction = fairwayFriction,
                staticFriction = fairwayFriction,
                bounciness = fairwayBounciness,
                frictionCombine = PhysicMaterialCombine.Maximum,
                bounceCombine = PhysicMaterialCombine.Average,
            };
            wallPhysics = new PhysicMaterial("Wall")
            {
                dynamicFriction = 0.4f, staticFriction = 0.4f, bounciness = 0.45f,
                frictionCombine = PhysicMaterialCombine.Average,
                bounceCombine = PhysicMaterialCombine.Maximum,
            };
            ballPhysics = new PhysicMaterial("Ball")
            {
                dynamicFriction = 0.4f, staticFriction = 0.4f, bounciness = 0.3f,
                frictionCombine = PhysicMaterialCombine.Average,
            };
        }

        // --------------------------------------------------- 1. Seamless fairway

        void BuildFairway()
        {
            // ONE thick slab. Top surface flush at y = 0, 3 units thick so the ball
            // can never tunnel; a single BoxCollider means zero internal seams.
            var slab = GameObject.CreatePrimitive(PrimitiveType.Cube);
            slab.name = "FairwaySlab";
            slab.transform.SetParent(fairwayRoot, false);
            slab.transform.localScale = new Vector3(17f, 3f, 39f);
            slab.transform.position = new Vector3(0f, -1.5f, -1f); // top at y = 0
            slab.layer = environmentLayer;
            Tint(slab, new Color(0.30f, 0.66f, 0.36f));            // grass green
            var box = slab.GetComponent<BoxCollider>();            // thick, solid floor
            box.sharedMaterial = fairwayPhysics;

            // Decorative overhang lip (no collider).
            var lip = GameObject.CreatePrimitive(PrimitiveType.Cube);
            lip.name = "IslandLip";
            lip.transform.SetParent(sceneryRoot, false);
            lip.transform.localScale = new Vector3(17.7f, 0.26f, 39.7f);
            lip.transform.position = new Vector3(0f, -0.12f, -1f);
            Destroy(lip.GetComponent<Collider>());
            Tint(lip, new Color(0.26f, 0.6f, 0.34f));
        }

        // ------------------------------------------------------- 1b. Green + hole

        void BuildGreenAndHole()
        {
            // Flush felt disc decal (no collider step), and the cup + flag.
            var green = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            green.name = "Green";
            green.transform.SetParent(fairwayRoot, false);
            green.transform.localScale = new Vector3(8f, 0.04f, 8f); // Ø ≈ 8, very flat
            green.transform.position = new Vector3(holeCenter.x, 0.04f, holeCenter.z);
            Destroy(green.GetComponent<Collider>());                 // decal only
            green.layer = environmentLayer;
            Tint(green, new Color(0.42f, 0.82f, 0.45f));

            var flagPole = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            flagPole.name = "FlagPole";
            flagPole.transform.SetParent(sceneryRoot, false);
            flagPole.transform.localScale = new Vector3(0.06f, 1.3f, 0.06f);
            flagPole.transform.position = new Vector3(holeCenter.x, 1.3f, holeCenter.z);
            Destroy(flagPole.GetComponent<Collider>());
            Tint(flagPole, Color.white);

            var flag = GameObject.CreatePrimitive(PrimitiveType.Cube);
            flag.name = "Flag";
            flag.transform.SetParent(flagPole.transform, false);
            flag.transform.localScale = new Vector3(0.05f, 0.45f, 0.7f);
            flag.transform.localPosition = new Vector3(0f, 0.7f, 0.35f);
            Destroy(flag.GetComponent<Collider>());
            Tint(flag, new Color(0.9f, 0.2f, 0.2f));
        }

        // ----------------------------------------------------- 1c. Bamboo fence

        void BuildFence()
        {
            Vector3[] pts =
            {
                new Vector3(-7.5f, 0, 18f),  new Vector3(7.5f, 0, 18f),
                new Vector3(8.5f, 0, -3f),   new Vector3(7.5f, 0, -20f),
                new Vector3(-7.5f, 0, -20f), new Vector3(-8.5f, 0, -3f),
            };
            for (int i = 0; i < pts.Length; i++)
                AddFenceRail(pts[i], pts[(i + 1) % pts.Length]);
        }

        void AddFenceRail(Vector3 a, Vector3 b)
        {
            Vector3 mid = (a + b) * 0.5f + Vector3.up * 0.55f;
            float length = Vector3.Distance(a, b);
            var rail = GameObject.CreatePrimitive(PrimitiveType.Cube);
            rail.name = "FenceRail";
            rail.transform.SetParent(fenceRoot, false);
            rail.transform.position = mid;
            rail.transform.rotation = Quaternion.LookRotation((b - a).normalized, Vector3.up);
            rail.transform.localScale = new Vector3(0.3f, 1.1f, length);
            rail.layer = environmentLayer;
            rail.GetComponent<BoxCollider>().sharedMaterial = wallPhysics;
            Tint(rail, new Color(0.78f, 0.68f, 0.36f)); // bamboo
        }

        // ------------------------------------------------------ 2c. Stone arches

        void BuildArchways()
        {
            AddArch(new Vector3(0f, 0f, 11f));       // near the tee
            AddArch(new Vector3(1.5f, 0f, -12.5f));  // green entrance
        }

        void AddArch(Vector3 at)
        {
            var stone = new Color(0.62f, 0.6f, 0.55f);
            foreach (float x in new[] { -2.0f, 2.0f })
            {
                var pillar = GameObject.CreatePrimitive(PrimitiveType.Cube);
                pillar.name = "ArchPillar";
                pillar.transform.SetParent(archwaysRoot, false);
                pillar.transform.localScale = new Vector3(1f, 3.4f, 1f);
                pillar.transform.position = at + new Vector3(x, 1.7f, 0f);
                pillar.layer = environmentLayer;
                pillar.GetComponent<BoxCollider>().sharedMaterial = wallPhysics;
                Tint(pillar, stone);
            }
            var lintel = GameObject.CreatePrimitive(PrimitiveType.Cube);
            lintel.name = "ArchLintel";
            lintel.transform.SetParent(archwaysRoot, false);
            lintel.transform.localScale = new Vector3(5f, 1f, 1.3f);
            lintel.transform.position = at + new Vector3(0f, 3.7f, 0f);
            lintel.layer = environmentLayer;
            lintel.GetComponent<BoxCollider>().sharedMaterial = wallPhysics;
            Tint(lintel, stone);
        }

        // -------------------------------------------------------- 2a. Sand bunker

        void BuildBunker()
        {
            var disc = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            disc.name = "SandBunker";
            disc.transform.SetParent(bunkerRoot, false);
            disc.transform.localScale = new Vector3(bunkerRadius * 2f, 0.04f, bunkerRadius * 2f);
            disc.transform.position = new Vector3(bunkerCenter.x, 0.04f, bunkerCenter.y);
            Tint(disc, new Color(0.93f, 0.85f, 0.62f));

            // Replace the visual collider with a trigger zone that spikes drag.
            Destroy(disc.GetComponent<Collider>());
            var zone = new GameObject("SandTrigger");
            zone.transform.SetParent(bunkerRoot, false);
            zone.transform.position = new Vector3(bunkerCenter.x, 0.4f, bunkerCenter.y);
            var col = zone.AddComponent<SphereCollider>();
            col.isTrigger = true;
            col.radius = bunkerRadius;
            var sand = zone.AddComponent<SandBunker>();
            sand.spikedDrag = sandDrag;
        }

        // ------------------------------------------------- 2b. Hippo water hazard

        void BuildWaterHazard()
        {
            var pool = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            pool.name = "HippoPool";
            pool.transform.SetParent(waterRoot, false);
            pool.transform.localScale = new Vector3(waterRadius * 2f, 0.05f, waterRadius * 2f);
            pool.transform.position = new Vector3(waterCenter.x, 0.05f, waterCenter.y);
            Destroy(pool.GetComponent<Collider>());
            Tint(pool, new Color(0.24f, 0.55f, 0.85f));

            var hippo = GameObject.CreatePrimitive(PrimitiveType.Sphere);
            hippo.name = "Hippo";
            hippo.transform.SetParent(waterRoot, false);
            hippo.transform.localScale = new Vector3(1.6f, 0.9f, 1.3f);
            hippo.transform.position = new Vector3(waterCenter.x, 0.3f, waterCenter.y);
            Destroy(hippo.GetComponent<Collider>());
            Tint(hippo, new Color(0.55f, 0.45f, 0.62f));

            // Trigger that resets any ball that rolls in, back to the tee.
            var zone = new GameObject("WaterTrigger");
            zone.transform.SetParent(waterRoot, false);
            zone.transform.position = new Vector3(waterCenter.x, 0.4f, waterCenter.y);
            var col = zone.AddComponent<SphereCollider>();
            col.isTrigger = true;
            col.radius = waterRadius;
            var hazard = zone.AddComponent<WaterHazard>();
            hazard.respawnPoint = teeSpawn;
        }

        // --------------------------------------------------- 3. Mallet monkey

        void BuildMonkey()
        {
            monkeyRoot.position = new Vector3(5.5f, 0f, -8f); // right side, before the green

            var pedestal = GameObject.CreatePrimitive(PrimitiveType.Cube);
            pedestal.name = "Pedestal";
            pedestal.transform.SetParent(monkeyRoot, false);
            pedestal.transform.localScale = new Vector3(1.8f, 1.8f, 1.8f);
            pedestal.transform.localPosition = new Vector3(0f, 0.9f, 0f);
            pedestal.layer = environmentLayer;
            pedestal.GetComponent<BoxCollider>().sharedMaterial = wallPhysics;
            Tint(pedestal, new Color(0.62f, 0.6f, 0.55f));

            var fur = new Color(0.5f, 0.36f, 0.24f);
            var body = GameObject.CreatePrimitive(PrimitiveType.Sphere);
            body.name = "Monkey";
            body.transform.SetParent(monkeyRoot, false);
            body.transform.localScale = Vector3.one * 1.2f;
            body.transform.localPosition = new Vector3(0f, 2.0f, 0f);
            Destroy(body.GetComponent<Collider>());
            Tint(body, fur);
            var head = GameObject.CreatePrimitive(PrimitiveType.Sphere);
            head.transform.SetParent(body.transform, false);
            head.transform.localScale = Vector3.one * 0.7f;
            head.transform.localPosition = new Vector3(0f, 0.7f, 0f);
            Destroy(head.GetComponent<Collider>());
            Tint(head, fur);

            // Swing pivot at the shoulder; the arm + mallet hang from it and the
            // MalletSwing script sweeps them across the path.
            var pivot = new GameObject("SwingPivot");
            pivot.transform.SetParent(monkeyRoot, false);
            pivot.transform.localPosition = new Vector3(0f, 2.6f, 0f);

            var arm = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            arm.transform.SetParent(pivot.transform, false);
            arm.transform.localScale = new Vector3(0.26f, 0.7f, 0.26f);
            arm.transform.localPosition = new Vector3(0f, -0.7f, 0f);
            Destroy(arm.GetComponent<Collider>());
            Tint(arm, fur);

            var head2 = GameObject.CreatePrimitive(PrimitiveType.Cube);
            head2.name = "MalletHead";
            head2.transform.SetParent(pivot.transform, false);
            head2.transform.localScale = new Vector3(1.5f, 0.8f, 0.8f);
            head2.transform.localPosition = new Vector3(0f, -1.7f, 0f);
            head2.layer = environmentLayer;
            head2.GetComponent<BoxCollider>().sharedMaterial = wallPhysics;
            Tint(head2, new Color(0.5f, 0.48f, 0.44f));

            // Kinematic Rigidbody on the PIVOT so MoveRotation physically shoves
            // the ball when the head sweeps into it.
            var rb = pivot.AddComponent<Rigidbody>();
            rb.isKinematic = true;
            rb.useGravity = false;
            rb.interpolation = RigidbodyInterpolation.Interpolate;
            pivot.AddComponent<MalletSwing>();
        }

        // --------------------------------------------------------- scenery + ball

        void BuildScenery()
        {
            Vector3[] palmSpots =
            {
                new Vector3(-6.5f, 0, 16f), new Vector3(6.5f, 0, 16f),
                new Vector3(-6.8f, 0, -17f), new Vector3(6.5f, 0, -2f),
            };
            foreach (var spot in palmSpots) AddPalm(spot);

            // Sun + ambient so the procedural scene is lit even in an empty project.
            if (FindObjectOfType<Light>() == null)
            {
                var sunGo = new GameObject("Sun");
                var sun = sunGo.AddComponent<Light>();
                sun.type = LightType.Directional;
                sun.intensity = 1.1f;
                sun.color = new Color(1f, 0.96f, 0.86f);
                sunGo.transform.rotation = Quaternion.Euler(55f, -30f, 0f);
            }
            RenderSettings.ambientLight = new Color(0.55f, 0.62f, 0.55f);
        }

        void AddPalm(Vector3 at)
        {
            var trunk = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            trunk.name = "Palm";
            trunk.transform.SetParent(sceneryRoot, false);
            trunk.transform.localScale = new Vector3(0.36f, 1.3f, 0.36f);
            trunk.transform.position = at + new Vector3(0f, 1.3f, 0f);
            Destroy(trunk.GetComponent<Collider>());
            Tint(trunk, new Color(0.6f, 0.45f, 0.28f));

            var canopy = GameObject.CreatePrimitive(PrimitiveType.Sphere);
            canopy.transform.SetParent(trunk.transform, false);
            canopy.transform.localScale = new Vector3(3.4f, 2.2f, 3.4f);
            canopy.transform.localPosition = new Vector3(0f, 1.2f, 0f);
            Destroy(canopy.GetComponent<Collider>());
            Tint(canopy, new Color(0.2f, 0.7f, 0.4f));
        }

        void SpawnBall()
        {
            var ball = GameObject.CreatePrimitive(PrimitiveType.Sphere);
            ball.name = "GolfBall";
            ball.transform.localScale = Vector3.one * (ballRadius * 2f);
            ball.transform.position = teeSpawn; // born above the slab, drops clean
            ball.layer = ballLayer;
            Tint(ball, new Color(1f, 0.95f, 0.95f));

            var col = ball.GetComponent<SphereCollider>();
            col.sharedMaterial = ballPhysics;

            var rb = ball.AddComponent<Rigidbody>();
            rb.mass = ballMass;
            rb.drag = ballDrag;
            rb.angularDrag = 0.4f;
            // Continuous detection so even a hard shot can't tunnel through the slab.
            rb.collisionDetectionMode = CollisionDetectionMode.ContinuousDynamic;
            rb.interpolation = RigidbodyInterpolation.Interpolate;

            var gb = ball.AddComponent<GolfBall>();
            gb.spawnPoint = teeSpawn;
            gb.normalDrag = ballDrag;

            ball.AddComponent<BallShooter>(); // pull-back shooting + aim line
            spawnedBall = ball;
        }

        /// Ensure a Main Camera exists and smoothly follows the ball.
        void SetupCamera()
        {
            var cam = Camera.main;
            if (cam == null)
            {
                var camGo = new GameObject("Main Camera") { tag = "MainCamera" };
                cam = camGo.AddComponent<Camera>();
            }
            var follow = cam.GetComponent<GolfCameraController>()
                         ?? cam.gameObject.AddComponent<GolfCameraController>();
            if (spawnedBall != null) follow.target = spawnedBall.transform;
        }

        // ------------------------------------------------------------- helpers

        Transform NewGroup(string name)
        {
            var go = new GameObject(name);
            go.transform.SetParent(transform, false);
            return go.transform;
        }

        static void Tint(GameObject go, Color color)
        {
            // Standard shader for built-in RP; swap to "Universal Render Pipeline/Lit" on URP.
            var shader = Shader.Find("Standard") ?? Shader.Find("Universal Render Pipeline/Lit");
            var mat = new Material(shader) { color = color };
            go.GetComponent<Renderer>().sharedMaterial = mat;
        }

        int SafeLayer(string name)
        {
            int layer = LayerMask.NameToLayer(name);
            if (layer < 0)
            {
                Debug.LogWarning($"[Tiki] Layer \"{name}\" is missing — add it in " +
                                 "Project Settings ▸ Tags and Layers (see unity/README.md). " +
                                 "Falling back to Default.");
                return 0;
            }
            return layer;
        }
    }
}
