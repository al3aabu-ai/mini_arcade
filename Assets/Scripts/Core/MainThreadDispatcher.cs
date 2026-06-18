using System;
using System.Collections.Concurrent;
using UnityEngine;

namespace MiniArcade.Core
{
    /// <summary>
    /// Marshals work from background (socket) threads onto Unity's main thread.
    /// Unity APIs must be touched on the main thread, so network callbacks are
    /// queued here and drained every frame in Update.
    /// </summary>
    public class MainThreadDispatcher : MonoBehaviour
    {
        private static readonly ConcurrentQueue<Action> Queue = new ConcurrentQueue<Action>();

        public static void Enqueue(Action action)
        {
            if (action != null)
                Queue.Enqueue(action);
        }

        private void Update()
        {
            while (Queue.TryDequeue(out Action action))
            {
                try { action(); }
                catch (Exception e) { Debug.LogException(e); }
            }
        }
    }
}
