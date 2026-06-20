using UnityEngine;
using System.Runtime.InteropServices;

namespace MiniArcade.Bridge
{
    /// Two-way bridge between the native host app and embedded Unity (Unity-as-a-Library).
    ///   Host  -> Unity:  [ufw sendMessageToGOWithName:"UnityBridge" functionName:"OnHostMessage" message:json]
    ///   Unity -> Host:   MiniArcade_UnityToHost(...)  — a C symbol provided by the native host app.
    public class UnityBridge : MonoBehaviour
    {
        public static UnityBridge Instance { get; private set; }

#if UNITY_IOS && !UNITY_EDITOR
        [DllImport("__Internal")] private static extern void MiniArcade_UnityToHost(string message);
#endif

        private void Awake()
        {
            Instance = this;
            DontDestroyOnLoad(gameObject);
        }

        // Invoked by the native host app via UnityFramework.sendMessageToGOWithName.
        public void OnHostMessage(string json)
        {
            Debug.Log("[UnityBridge] host -> unity: " + json);
            if (GolfGame.Instance != null) GolfGame.Instance.OnHostMessage(json);
        }

        public void SendToHost(string message)
        {
#if UNITY_IOS && !UNITY_EDITOR
            try { MiniArcade_UnityToHost(message); } catch { }
#else
            Debug.Log("[UnityBridge] unity -> host (editor noop): " + message);
#endif
        }
    }
}
