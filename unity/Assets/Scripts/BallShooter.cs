using UnityEngine;

namespace Frantics.Golf
{
    /// <summary>
    /// Pull-back slingshot shooting (ported from the SwiftUI touchpad + SceneKit
    /// applyFire). Press anywhere (mouse in the Editor, single touch on device),
    /// drag BACK, and release to launch the ball OPPOSITE the drag with power
    /// scaled by how far you pulled. A LineRenderer shows the aim while dragging,
    /// stretching and reddening with power.
    ///
    /// Unity's mouse-button API also reports single-finger touches, so this one
    /// path covers Editor testing and mobile.
    /// </summary>
    [RequireComponent(typeof(Rigidbody))]
    public class BallShooter : MonoBehaviour
    {
        [Header("Shot impulse (matches the SceneKit launch curve)")]
        public float minHorizontal = 5f;
        public float maxHorizontal = 19f;
        public float minLoft = 2f;
        public float maxLoft = 7f;

        [Header("Aim")]
        [Tooltip("Drag length as a fraction of screen height for full power (resolution-independent).")]
        public float fullPowerDragFraction = 0.3f;
        public float maxArrowLength = 6f;
        [Tooltip("The ball must be slower than this to shoot — must come to a complete stop.")]
        public float restSpeed = 0.05f;

        /// Fired on release with power 0..1 — hook SFX / haptics / networking here.
        public System.Action<float> OnShoot;

        /// Hard state lockout: no input at all while the ball is still moving.
        public bool CanShoot => rb.velocity.magnitude <= restSpeed;

        Rigidbody rb;
        GolfBall ball;
        Camera cam;
        LineRenderer aim;
        bool aiming;
        Vector2 dragStart;

        void Awake()
        {
            rb = GetComponent<Rigidbody>();
            ball = GetComponent<GolfBall>();
            cam = Camera.main;
            SetupAimLine();
        }

        void Update()
        {
            if (cam == null) cam = Camera.main;
            if (cam == null) return;

            if (Input.GetMouseButtonDown(0) && CanShoot)
            {
                aiming = true;
                dragStart = Input.mousePosition;
            }
            // Hard lockout: if the ball is still rolling, no aiming or shooting at all.
            if (aiming && !CanShoot)
            {
                aiming = false;
                aim.enabled = false;
            }
            if (!aiming) return;

            ShotVector shot = ComputeShot(dragStart, Input.mousePosition);
            DrawAim(shot);

            if (Input.GetMouseButtonUp(0))
            {
                aiming = false;
                aim.enabled = false;
                if (shot.power > 0.06f) Fire(shot);
            }
        }

        struct ShotVector { public Vector3 dir; public float power; }

        ShotVector ComputeShot(Vector2 start, Vector2 current)
        {
            Vector2 delta = current - start;
            // Flatten the camera basis onto the ground so the drag maps to XZ.
            Vector3 camF = Vector3.ProjectOnPlane(cam.transform.forward, Vector3.up).normalized;
            Vector3 camR = Vector3.ProjectOnPlane(cam.transform.right, Vector3.up).normalized;
            Vector3 dragWorld = camR * delta.x + camF * delta.y;
            float power = Mathf.Clamp01(delta.magnitude / (Screen.height * fullPowerDragFraction));
            // Slingshot: launch opposite the pull.
            Vector3 dir = dragWorld.sqrMagnitude > 1e-4f ? -dragWorld.normalized : Vector3.zero;
            return new ShotVector { dir = dir, power = power };
        }

        void Fire(ShotVector shot)
        {
            float horizontal = Mathf.Lerp(minHorizontal, maxHorizontal, shot.power);
            float loft = Mathf.Lerp(minLoft, maxLoft, shot.power);
            rb.AddForce(shot.dir * horizontal + Vector3.up * loft, ForceMode.Impulse);
            if (ball != null) ball.RegisterShot(); // +1 stroke per launched shot
            OnShoot?.Invoke(shot.power);
        }

        // --------------------------------------------------------- aim line

        void SetupAimLine()
        {
            var go = new GameObject("AimLine");
            go.transform.SetParent(transform, false);
            aim = go.AddComponent<LineRenderer>();
            aim.useWorldSpace = true;
            aim.widthMultiplier = 0.12f;
            aim.numCapVertices = 4;
            aim.positionCount = 2;
            aim.material = new Material(Shader.Find("Sprites/Default"));
            aim.enabled = false;
        }

        void DrawAim(ShotVector shot)
        {
            if (shot.power <= 0.02f) { aim.enabled = false; return; }
            aim.enabled = true;
            Vector3 a = transform.position;
            Vector3 b = a + shot.dir * (shot.power * maxArrowLength);
            aim.SetPosition(0, a);
            aim.SetPosition(1, b);
            Color c = Color.Lerp(new Color(0f, 0.96f, 0.83f), Color.red, shot.power); // cyan → red
            aim.startColor = c;
            aim.endColor = c;
        }
    }
}
