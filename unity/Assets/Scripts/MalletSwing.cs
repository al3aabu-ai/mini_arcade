using UnityEngine;

namespace Frantics.Golf
{
    /// <summary>
    /// Rhythmic mallet swing for the monkey obstacle. Drives a KINEMATIC Rigidbody
    /// via MoveRotation in FixedUpdate, so the mallet head physically shoves the
    /// ball (clean, glitch-free deflection — kinematic bodies impart velocity to
    /// dynamic ones they sweep into, and never get pushed back).
    ///
    /// Timeline mirrors the SceneKit SCNAction loop: rest up, SLAM down across the
    /// path, hold, lift back up — on a fixed period.
    /// </summary>
    [RequireComponent(typeof(Rigidbody))]
    public class MalletSwing : MonoBehaviour
    {
        [Header("Swing angles (degrees about local Z)")]
        public float restAngle = 8f;     // arm hanging, just off vertical
        public float slamAngle = -86f;   // swept flat across the fairway

        [Header("Timeline (seconds)")]
        public float restHold = 1.2f;    // wait before the slam
        public float slamTime = 0.3f;    // fast slam down
        public float slamHold = 0.4f;    // pinned across the path
        public float liftTime = 0.7f;    // wind back up

        Rigidbody rb;
        Quaternion baseRotation;
        float t;
        float period;

        void Awake()
        {
            rb = GetComponent<Rigidbody>();
            rb.isKinematic = true;            // driven by animation, immovable by the ball
            baseRotation = transform.rotation;
            period = restHold + slamTime + slamHold + liftTime;
        }

        void FixedUpdate()
        {
            t = (t + Time.fixedDeltaTime) % period;
            float angle = AngleAt(t);
            // MoveRotation keeps the collider in the physics solver's hands, so the
            // sweep transfers momentum to the ball instead of clipping through it.
            rb.MoveRotation(baseRotation * Quaternion.Euler(0f, 0f, angle));
        }

        float AngleAt(float time)
        {
            if (time < restHold)
                return restAngle;
            time -= restHold;

            if (time < slamTime)
                return Mathf.Lerp(restAngle, slamAngle, Smooth(time / slamTime));
            time -= slamTime;

            if (time < slamHold)
                return slamAngle;
            time -= slamHold;

            return Mathf.Lerp(slamAngle, restAngle, Smooth(time / liftTime));
        }

        // Ease in/out so the slam reads as a snap and the lift as a wind-up.
        static float Smooth(float x) => x * x * (3f - 2f * x);
    }
}
