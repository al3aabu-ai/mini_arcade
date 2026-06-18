#if UNITY_EDITOR && UNITY_IOS
using System.IO;
using UnityEditor;
using UnityEditor.Callbacks;
using UnityEditor.iOS.Xcode;

namespace MiniArcade.Editor
{
    public static class IOSPostProcessBuild
    {
        [PostProcessBuild(100)]
        public static void OnPostProcessBuild(BuildTarget target, string pathToBuiltProject)
        {
            if (target != BuildTarget.iOS)
            {
                return;
            }

            ConfigureInfoPlist(pathToBuiltProject);
        }

        private static void ConfigureInfoPlist(string pathToBuiltProject)
        {
            var plistPath = Path.Combine(pathToBuiltProject, "Info.plist");
            var plist = new PlistDocument();
            plist.ReadFromFile(plistPath);

            var root = plist.root;
            root.SetBoolean("UIRequiresFullScreen", true);
            root.SetBoolean("UIViewControllerBasedStatusBarAppearance", false);
            root.SetString(
                "NSLocalNetworkUsageDescription",
                "Mini Arcade hosts a local party room so phones on the same Wi-Fi can join as controllers.");

            File.WriteAllText(plistPath, plist.WriteToString());
        }
    }
}
#endif
