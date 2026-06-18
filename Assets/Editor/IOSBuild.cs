#if UNITY_EDITOR
using System;
using System.IO;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.SceneManagement;

namespace MiniArcade.Editor
{
    public static class IOSBuild
    {
        private const string BootScenePath = "Assets/Scenes/Boot.unity";
        private const string DefaultXcodeProjectPath = "Builds/iOS/MiniArcade-iOS";
        private const string BundleIdentifier = "com.al3aabu.miniarcade";
        private const string MinimumIosVersion = "15.0";

        [MenuItem("Mini Arcade/Export iOS Xcode Project")]
        public static void ExportXcodeProject()
        {
            EnsureBootScene();
            ConfigureIosPlayer();

            var xcodeProjectPath = ReadEnv("MINI_ARCADE_IOS_EXPORT_PATH", DefaultXcodeProjectPath);
            Directory.CreateDirectory(Path.GetDirectoryName(xcodeProjectPath));

            if (!EditorUserBuildSettings.SwitchActiveBuildTarget(BuildTargetGroup.iOS, BuildTarget.iOS))
            {
                throw new InvalidOperationException("Could not switch Unity build target to iOS. Install Unity iOS Build Support on this editor version.");
            }

            var options = new BuildPlayerOptions
            {
                scenes = new[] { BootScenePath },
                locationPathName = xcodeProjectPath,
                target = BuildTarget.iOS,
                options = BuildOptions.None
            };

            var report = BuildPipeline.BuildPlayer(options);
            var summary = report.summary;
            if (summary.result != BuildResult.Succeeded)
            {
                throw new InvalidOperationException(
                    $"iOS Xcode export failed: {summary.result}. Errors: {summary.totalErrors}, warnings: {summary.totalWarnings}.");
            }

            Debug.Log($"Mini Arcade iOS Xcode project exported at {Path.GetFullPath(xcodeProjectPath)}");
        }

        private static void EnsureBootScene()
        {
            if (File.Exists(BootScenePath))
            {
                return;
            }

            Directory.CreateDirectory(Path.GetDirectoryName(BootScenePath));

            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            scene.name = "Boot";

            var lightGo = new GameObject("BootLight");
            var light = lightGo.AddComponent<Light>();
            light.type = LightType.Directional;
            light.intensity = 0.8f;
            light.transform.rotation = Quaternion.Euler(50f, -30f, 0f);

            EditorSceneManager.SaveScene(scene, BootScenePath);
            AssetDatabase.Refresh();
        }

        private static void ConfigureIosPlayer()
        {
            PlayerSettings.companyName = "Al3aabu";
            PlayerSettings.productName = "Mini Arcade";
            PlayerSettings.bundleVersion = ReadEnv("MINI_ARCADE_IOS_VERSION", "1.0");
            PlayerSettings.SetApplicationIdentifier(BuildTargetGroup.iOS, ReadEnv("MINI_ARCADE_IOS_BUNDLE_ID", BundleIdentifier));
            PlayerSettings.defaultInterfaceOrientation = UIOrientation.LandscapeLeft;
            PlayerSettings.allowedAutorotateToPortrait = false;
            PlayerSettings.allowedAutorotateToPortraitUpsideDown = false;
            PlayerSettings.allowedAutorotateToLandscapeLeft = true;
            PlayerSettings.allowedAutorotateToLandscapeRight = true;
            PlayerSettings.fullScreenMode = FullScreenMode.FullScreenWindow;
            PlayerSettings.stripEngineCode = false;
            PlayerSettings.iOS.targetOSVersionString = MinimumIosVersion;
            PlayerSettings.iOS.sdkVersion = iOSSdkVersion.DeviceSDK;
            PlayerSettings.iOS.appleEnableAutomaticSigning = true;
            PlayerSettings.iOS.appleDeveloperTeamID = ReadEnv("MINI_ARCADE_APPLE_TEAM_ID", PlayerSettings.iOS.appleDeveloperTeamID);
            PlayerSettings.iOS.buildNumber = ReadEnv("MINI_ARCADE_IOS_BUILD_NUMBER", "1");
            PlayerSettings.iOS.requiresPersistentWiFi = true;
            PlayerSettings.iOS.requiresFullScreen = true;
        }

        private static string ReadEnv(string key, string fallback)
        {
            var value = Environment.GetEnvironmentVariable(key);
            return string.IsNullOrWhiteSpace(value) ? fallback : value.Trim();
        }
    }
}
#endif
