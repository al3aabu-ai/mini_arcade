#if UNITY_EDITOR
using System.IO;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEngine;

namespace MiniArcade.Editor
{
    /// <summary>
    /// Single source of truth for the phone-controller UI: the repo's top-level
    /// <c>web/</c> folder. The Editor serves that folder live (see
    /// <see cref="MiniArcade.Networking.WebControllerServer"/>), and this mirrors
    /// it into <c>Assets/StreamingAssets/web</c> so device/player builds bundle the
    /// exact same files. Runs automatically before every build; also on the menu.
    /// </summary>
    public sealed class WebSync : IPreprocessBuildWithReport
    {
        public int callbackOrder => 0;

        public void OnPreprocessBuild(BuildReport report) => Sync();

        [MenuItem("Mini Arcade/Sync Web Controller → StreamingAssets")]
        public static void SyncMenu()
        {
            Sync();
            AssetDatabase.Refresh();
            Debug.Log("[WebSync] Synced web/ → Assets/StreamingAssets/web.");
        }

        public static void Sync()
        {
            string src = Path.GetFullPath(Path.Combine(Application.dataPath, "..", "web"));
            string dst = Path.Combine(Application.streamingAssetsPath, "web");
            if (!Directory.Exists(src))
            {
                Debug.LogWarning("[WebSync] No web/ folder found at " + src + "; nothing to sync.");
                return;
            }
            Directory.CreateDirectory(dst);

            // Refresh the runtime files from web/ (top level only — never the
            // design/ references), keeping existing .meta so GUIDs stay stable.
            foreach (string existing in Directory.GetFiles(dst))
                if (!existing.EndsWith(".meta")) File.Delete(existing);

            foreach (string from in Directory.GetFiles(src))
            {
                string name = Path.GetFileName(from);
                if (name.EndsWith(".meta")) continue;
                File.Copy(from, Path.Combine(dst, name), true);
            }
        }
    }
}
#endif
