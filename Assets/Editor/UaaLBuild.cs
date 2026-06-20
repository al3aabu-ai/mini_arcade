#if UNITY_EDITOR
using System;
using System.IO;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;
using UnityEngine;

namespace MiniArcade.Editor
{
    /// Builds the Unity THIN-SLICE as an iOS Xcode project that contains UnityFramework
    /// (Unity-as-a-Library). The host app (mini-arcade-host) embeds that framework on the
    /// TV/external-display scene only. Splash is disabled; only ThinSliceScene runs.
    public static class UaaLBuild
    {
        private const string BootScenePath = "Assets/Scenes/Boot.unity";
        private const string OutPath = "Builds/iOS-UaaL";
        private const string UnityAppBundleId = "com.al3aabu.miniarcade.unity";

        [MenuItem("Mini Arcade/Export Unity Thin-Slice (iOS Library)")]
        public static void Export()
        {
            // thin-slice define -> old AppRoot shell OFF, ThinSliceScene ON
            PlayerSettings.SetScriptingDefineSymbols(NamedBuildTarget.iOS, "MINIARCADE_THINSLICE");

            // Unity 6: the "Made with Unity" splash is optional on every tier -> turn it off
            PlayerSettings.SplashScreen.show = false;
            PlayerSettings.SplashScreen.showUnityLogo = false;

            PlayerSettings.companyName = "Al3aabu";
            PlayerSettings.productName = "MiniArcadeUnity";
            PlayerSettings.SetApplicationIdentifier(BuildTargetGroup.iOS, UnityAppBundleId);
            PlayerSettings.defaultInterfaceOrientation = UIOrientation.LandscapeLeft;
            PlayerSettings.allowedAutorotateToPortrait = false;
            PlayerSettings.allowedAutorotateToPortraitUpsideDown = false;
            PlayerSettings.allowedAutorotateToLandscapeLeft = true;
            PlayerSettings.allowedAutorotateToLandscapeRight = true;
            PlayerSettings.iOS.targetOSVersionString = "16.0";
            PlayerSettings.iOS.sdkVersion = iOSSdkVersion.DeviceSDK;
            PlayerSettings.iOS.appleEnableAutomaticSigning = true;
            var team = Environment.GetEnvironmentVariable("MINI_ARCADE_APPLE_TEAM_ID");
            if (!string.IsNullOrEmpty(team)) PlayerSettings.iOS.appleDeveloperTeamID = team;

            EnsureBootScene();
            EnsureShadersIncluded();   // the Boot scene is empty -> force-include shaders or runtime materials go magenta

            if (!EditorUserBuildSettings.SwitchActiveBuildTarget(BuildTargetGroup.iOS, BuildTarget.iOS))
                throw new Exception("Could not switch to iOS build target. Install iOS Build Support for this Unity version.");

            Directory.CreateDirectory(OutPath);
            var report = BuildPipeline.BuildPlayer(new BuildPlayerOptions
            {
                scenes = new[] { BootScenePath },
                locationPathName = OutPath,
                target = BuildTarget.iOS,
                options = BuildOptions.None
            });
            if (report.summary.result != BuildResult.Succeeded)
                throw new Exception("Unity iOS build failed: " + report.summary.result + " (errors=" + report.summary.totalErrors + ")");
            Debug.Log("[UaaLBuild] thin-slice exported to " + Path.GetFullPath(OutPath));
        }

        // Runtime-created materials use these shaders. With an empty Boot scene nothing references
        // them, so Unity strips them from the iOS build and every material renders as the magenta
        // error shader. Force them into the build via Always Included Shaders.
        private static readonly string[] GuaranteedShaders = {
            "Legacy Shaders/Diffuse",
            "Unlit/Color",
            "Sprites/Default",
        };

        private static void EnsureShadersIncluded()
        {
            var assets = AssetDatabase.LoadAllAssetsAtPath("ProjectSettings/GraphicsSettings.asset");
            if (assets == null || assets.Length == 0) { Debug.LogWarning("[UaaLBuild] GraphicsSettings.asset not found"); return; }
            var so = new SerializedObject(assets[0]);
            var arr = so.FindProperty("m_AlwaysIncludedShaders");
            if (arr == null) { Debug.LogWarning("[UaaLBuild] m_AlwaysIncludedShaders not found"); return; }
            foreach (var name in GuaranteedShaders)
            {
                var shader = Shader.Find(name);
                if (shader == null) { Debug.LogWarning("[UaaLBuild] shader NOT FOUND, skipping: " + name); continue; }
                bool present = false;
                for (int i = 0; i < arr.arraySize; i++)
                    if (arr.GetArrayElementAtIndex(i).objectReferenceValue == shader) { present = true; break; }
                if (!present)
                {
                    arr.InsertArrayElementAtIndex(arr.arraySize);
                    arr.GetArrayElementAtIndex(arr.arraySize - 1).objectReferenceValue = shader;
                    Debug.Log("[UaaLBuild] Added Always-Included shader: " + name);
                }
                else Debug.Log("[UaaLBuild] Always-Included shader already present: " + name);
            }
            so.ApplyModifiedProperties();
            AssetDatabase.SaveAssets();
        }

        private static void EnsureBootScene()
        {
            if (File.Exists(BootScenePath)) return;
            Directory.CreateDirectory(Path.GetDirectoryName(BootScenePath));
            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            EditorSceneManager.SaveScene(scene, BootScenePath);
            AssetDatabase.Refresh();
        }
    }
}
#endif
