using System.Collections;
using UnityEngine;

namespace Frantics.Golf
{
    /// <summary>
    /// Trigger on the cup. When the ball drops in: stop it dead, log the final
    /// stroke count, shout "Hole In!", and play a placeholder sink animation
    /// (scale the ball to zero as it drops into the cup).
    /// </summary>
    [RequireComponent(typeof(Collider))]
    public class GolfHole : MonoBehaviour
    {
        /// Raised when a ball is holed, with its final stroke count (for scoring/UI).
        public System.Action<int> OnHoled;

        bool sunk;

        void Reset() => GetComponent<Collider>().isTrigger = true;

        void OnTriggerEnter(Collider other)
        {
            if (sunk) return;
            var ball = other.GetComponentInParent<GolfBall>();
            if (ball == null) return;
            sunk = true;

            // Stop the ball entirely and take it out of the simulation.
            var rb = ball.GetComponent<Rigidbody>();
            if (rb != null)
            {
                rb.velocity = Vector3.zero;
                rb.angularVelocity = Vector3.zero;
                rb.isKinematic = true;
            }

            Debug.Log($"⛳️ Hole In! Final strokes: {ball.strokeCount}");
            OnHoled?.Invoke(ball.strokeCount);

            StartCoroutine(DropIntoCup(ball.transform));
        }

        IEnumerator DropIntoCup(Transform ball)
        {
            Vector3 fromScale = ball.localScale;
            Vector3 fromPos = ball.position;
            Vector3 cupPos = new Vector3(transform.position.x, transform.position.y - 0.4f, transform.position.z);

            const float duration = 0.35f;
            float t = 0f;
            while (t < duration)
            {
                t += Time.deltaTime;
                float k = Mathf.Clamp01(t / duration);
                ball.localScale = Vector3.Lerp(fromScale, Vector3.zero, k);
                ball.position = Vector3.Lerp(fromPos, cupPos, k);
                yield return null;
            }
            ball.localScale = Vector3.zero;
            // Placeholder: a real build would fire confetti / advance the round here.
        }
    }
}
