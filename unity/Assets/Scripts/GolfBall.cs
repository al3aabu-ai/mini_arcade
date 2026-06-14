using UnityEngine;

namespace Frantics.Golf
{
    /// <summary>
    /// Marker + controller on the golf ball. Hazards talk to this rather than
    /// poking the Rigidbody directly, so the rules live in one place.
    /// </summary>
    [RequireComponent(typeof(Rigidbody))]
    public class GolfBall : MonoBehaviour
    {
        [Tooltip("Where the ball returns to when it falls in the water / off the map.")]
        public Vector3 spawnPoint;

        [Tooltip("Baseline linear drag, restored when the ball leaves the sand.")]
        public float normalDrag = 0.16f;

        [Tooltip("Shots taken this hole — drives the lowest-stroke scoring.")]
        public int strokeCount;

        Rigidbody rb;
        int sandContacts; // supports overlapping bunkers without flicker

        void Awake() => rb = GetComponent<Rigidbody>();

        /// <summary>Count one successful launch (called by BallShooter on release).</summary>
        public void RegisterShot()
        {
            strokeCount++;
        }

        /// <summary>Teleport home and kill all motion (water hazard / out of bounds).</summary>
        public void ResetToSpawn()
        {
            rb.velocity = Vector3.zero;
            rb.angularVelocity = Vector3.zero;
            // Move via the body so the physics transform stays in sync (no one-frame desync).
            rb.position = spawnPoint;
            transform.position = spawnPoint;
            sandContacts = 0;
            rb.drag = normalDrag;
        }

        /// <summary>Ball entered a bunker — drastically slow it down.</summary>
        public void EnterSand(float spikedDrag)
        {
            sandContacts++;
            rb.drag = spikedDrag;
        }

        /// <summary>Ball left a bunker — restore normal roll once clear of all bunkers.</summary>
        public void ExitSand()
        {
            sandContacts = Mathf.Max(0, sandContacts - 1);
            if (sandContacts == 0) rb.drag = normalDrag;
        }

        /// <summary>Safety net: if the ball ever leaves the world, send it home.</summary>
        void FixedUpdate()
        {
            if (transform.position.y < -9f) ResetToSpawn();
        }
    }
}
