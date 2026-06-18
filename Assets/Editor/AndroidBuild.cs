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
    public static class AndroidBuild
    {
        private const string BootScenePath = "Assets/Scenes/Boot.unity";
        private const string ApkPath = "Builds/Android/MiniArcade.apk";
        private const string WindowsRootTrustStoreOption = "-Djavax.net.ssl.trustStoreType=Windows-ROOT";

        [MenuItem("Mini Arcade/Build Android APK")]
        public static void BuildApk()
        {
            EnsureBootScene();
            ConfigureAndroidPlayer();
            ConfigureAndroidBuildEnvironment();

            Directory.CreateDirectory(Path.GetDirectoryName(ApkPath));

            if (!EditorUserBuildSettings.SwitchActiveBuildTarget(BuildTargetGroup.Android, BuildTarget.Android))
            {
                throw new InvalidOperationException("Could not switch Unity build target to Android.");
            }

            var options = new BuildPlayerOptions
            {
                scenes = new[] { BootScenePath },
                locationPathName = ApkPath,
                target = BuildTarget.Android,
                options = BuildOptions.Development | BuildOptions.AllowDebugging
            };

            var report = BuildPipeline.BuildPlayer(options);
            var summary = report.summary;
            if (summary.result != BuildResult.Succeeded)
            {
                throw new InvalidOperationException(
                    $"Android build failed: {summary.result}. Errors: {summary.totalErrors}, warnings: {summary.totalWarnings}.");
            }

            Debug.Log($"Mini Arcade Android APK built at {Path.GetFullPath(ApkPath)}");
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

        private static void ConfigureAndroidPlayer()
        {
            PlayerSettings.companyName = "Al3aabu";
            PlayerSettings.productName = "Mini Arcade";
            PlayerSettings.SetApplicationIdentifier(BuildTargetGroup.Android, "com.al3aabu.miniarcade");
            PlayerSettings.defaultInterfaceOrientation = UIOrientation.LandscapeLeft;
            PlayerSettings.allowedAutorotateToPortrait = false;
            PlayerSettings.allowedAutorotateToPortraitUpsideDown = false;
            PlayerSettings.allowedAutorotateToLandscapeLeft = true;
            PlayerSettings.allowedAutorotateToLandscapeRight = true;
            PlayerSettings.fullScreenMode = FullScreenMode.FullScreenWindow;
            PlayerSettings.stripEngineCode = false;
            PlayerSettings.Android.targetArchitectures = AndroidArchitecture.ARM64 | AndroidArchitecture.X86_64;
            PlayerSettings.Android.useCustomKeystore = false;
        }

        private static void ConfigureAndroidBuildEnvironment()
        {
            var javaToolOptions = Environment.GetEnvironmentVariable("JAVA_TOOL_OPTIONS") ?? "";
            if (javaToolOptions.Contains("javax.net.ssl.trustStoreType"))
            {
                return;
            }

            Environment.SetEnvironmentVariable(
                "JAVA_TOOL_OPTIONS",
                string.IsNullOrWhiteSpace(javaToolOptions)
                    ? WindowsRootTrustStoreOption
                    : $"{javaToolOptions} {WindowsRootTrustStoreOption}");
        }
    }
}
#endif
