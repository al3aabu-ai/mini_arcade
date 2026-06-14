using UnityEngine;

namespace Frantics.Golf
{
    /// <summary>
    /// Trigger volume over the hippo pool. Any ball that rolls in is instantly
    /// reset to the level spawn point. (Mirrors the SceneKit isOverWater() OOB reset.)
    /// </summary>
    [RequireComponent(typeof(Collider))]
    public class WaterHazard : MonoBehaviour
    {
        [Tooltip("Where the ball returns to (the tee). Set by the course builder.")]
        public Vector3 respawnPoint;

        void Reset() => GetComponent<Collider>().isTrigger = true;

        void OnTriggerEnter(Collider other)
        {
            var ball = other.GetComponentInParent<GolfBall>();
            if (ball == null) return;
            ball.spawnPoint = respawnPoint; // keep the ball's home in sync
            ball.ResetToSpawn();
        }
    }
}
