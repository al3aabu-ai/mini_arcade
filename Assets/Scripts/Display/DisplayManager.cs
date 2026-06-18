using UnityEngine;

namespace MiniArcade.Display
{
    /// <summary>
    /// Activates a second display when one is available so the public "TV" view
    /// and the host's private control view can render independently
    /// (spec section 3, Dual-Screen Video Output).
    ///
    /// On desktop this maps to a second monitor/window; on device it maps to
    /// AirPlay/HDMI external output. Unity exposes both through the engine's
    /// Display class.
    ///
    /// Note: this namespace (MiniArcade.Display) shadows UnityEngine.Display, so
    /// the engine type is referenced fully-qualified below.
    /// </summary>
    public class DisplayManager : MonoBehaviour
    {
        public bool HasExternalDisplay => UnityEngine.Display.displays.Length > 1;
        public static int PrivateDisplayIndex => 0;
        public static int PublicDisplayIndex => UnityEngine.Display.displays.Length > 1 ? 1 : 0;

        private void Start()
        {
            ActivateExternalDisplay();
        }

        /// <summary>Turns on every external display the OS reports.</summary>
        public void ActivateExternalDisplay()
        {
            // displays[0] is always active (the device's own screen).
            for (int i = 1; i < UnityEngine.Display.displays.Length; i++)
            {
                if (!UnityEngine.Display.displays[i].active)
                {
                    UnityEngine.Display.displays[i].Activate();
                    Debug.Log($"[DisplayManager] Activated external display {i}.");
                }
            }
        }
    }
}
