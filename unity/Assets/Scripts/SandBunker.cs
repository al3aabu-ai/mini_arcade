using UnityEngine;

namespace Frantics.Golf
{
    /// <summary>
    /// Trigger volume over the bunker. While the ball is inside it, spike the
    /// ball's linear drag so it bogs down in the sand; restore on exit. (Mirrors
    /// the SceneKit isOverSand() damping spike.)
    /// </summary>
    [RequireComponent(typeof(Collider))]
    public class SandBunker : MonoBehaviour
    {
        [Tooltip("Linear drag applied to the ball while it's in the sand.")]
        public float spikedDrag = 4.0f;

        void Reset() => GetComponent<Collider>().isTrigger = true;

        void OnTriggerEnter(Collider other)
        {
            var ball = other.GetComponentInParent<GolfBall>();
            if (ball != null) ball.EnterSand(spikedDrag);
        }

        void OnTriggerExit(Collider other)
        {
            var ball = other.GetComponentInParent<GolfBall>();
            if (ball != null) ball.ExitSand();
        }
    }
}
