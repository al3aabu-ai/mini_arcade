#if UNITY_EDITOR
using System.IO;
using System.Text.RegularExpressions;
using UnityEditor;
using UnityEditor.Callbacks;

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
            var plist = File.ReadAllText(plistPath);

            plist = SetBooleanKey(plist, "UIRequiresFullScreen", true);
            plist = SetBooleanKey(plist, "UIViewControllerBasedStatusBarAppearance", false);
            plist = SetStringKey(
                plist,
                "NSLocalNetworkUsageDescription",
                "Mini Arcade hosts a local party room so phones on the same Wi-Fi can join as controllers.");

            File.WriteAllText(plistPath, plist);
        }

        private static string SetBooleanKey(string plist, string key, bool value)
        {
            var replacement = $"<key>{key}</key>\n    <{(value ? "true" : "false")} />";
            var pattern = $@"<key>{Regex.Escape(key)}</key>\s*<(true|false)\s*/>";

            if (Regex.IsMatch(plist, pattern))
            {
                return Regex.Replace(plist, pattern, replacement);
            }

            return InsertBeforeDictClose(plist, replacement);
        }

        private static string SetStringKey(string plist, string key, string value)
        {
            var replacement = $"<key>{key}</key>\n    <string>{EscapePlistString(value)}</string>";
            var pattern = $@"<key>{Regex.Escape(key)}</key>\s*<string>.*?</string>";

            if (Regex.IsMatch(plist, pattern, RegexOptions.Singleline))
            {
                return Regex.Replace(plist, pattern, replacement, RegexOptions.Singleline);
            }

            return InsertBeforeDictClose(plist, replacement);
        }

        private static string InsertBeforeDictClose(string plist, string entry)
        {
            const string marker = "  </dict>";
            var index = plist.LastIndexOf(marker);
            if (index < 0)
            {
                return plist;
            }

            return plist.Insert(index, $"    {entry}\n");
        }

        private static string EscapePlistString(string value)
        {
            return value
                .Replace("&", "&amp;")
                .Replace("<", "&lt;")
                .Replace(">", "&gt;")
                .Replace("\"", "&quot;")
                .Replace("'", "&apos;");
        }
    }
}
#endif
