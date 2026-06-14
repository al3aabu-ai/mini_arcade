using UnityEngine;

namespace Frantics.Golf
{
    /// <summary>
    /// Smoothly trails the golf ball: a damped follow plus a damped look-target,
    /// so the camera glides after a shot and re-frames without hard cuts.
    /// Attach to the Main Camera; the course builder sets <see cref="target"/>.
    /// </summary>
    public class GolfCameraController : MonoBehaviour
    {
        [Tooltip("The ball to follow. Auto-found if left empty.")]
        public Transform target;

        [Tooltip("World-space offset from the ball (behind + above).")]
        public Vector3 offset = new Vector3(0f, 16f, 14f);

        public float followSmoothTime = 0.35f;
        public float lookSmoothTime = 0.2f;

        Vector3 followVel;
        Vector3 lookVel;
        Vector3 currentLook;

        void Start()
        {
            if (target == null)
            {
                var ball = FindObjectOfType<GolfBall>();
                if (ball != null) target = ball.transform;
            }
            if (target != null)
            {
                currentLook = target.position;
                transform.position = target.position + offset; // start framed (no opening lurch)
                transform.LookAt(currentLook);
            }
        }

        void LateUpdate()
        {
            if (target == null) return;

            Vector3 desired = target.position + offset;
            transform.position = Vector3.SmoothDamp(transform.position, desired, ref followVel, followSmoothTime);

            currentLook = Vector3.SmoothDamp(currentLook, target.position, ref lookVel, lookSmoothTime);
            transform.LookAt(currentLook);
        }
    }
}
