#if UNITY_EDITOR
using System.IO;
using UnityEngine;
using MiniArcade.Bridge;

namespace MiniArcade.Editor
{
    /// Headless self-verification: builds the GolfGame course in the editor (no play mode) and
    /// renders it to PNGs so the Unity TV visuals can be checked without a device build.
    /// Run: Unity -batchmode -quit -executeMethod MiniArcade.Editor.GolfPreview.Render
    public static class GolfPreview
    {
        static readonly Vector3 Cup = new Vector3(4.5f, 0f, 4f);

        public static void Render()
        {
            var root = new GameObject("GolfPreviewRoot");
            var gg = root.AddComponent<GolfGame>();
            gg.BuildAll();

            // simulate a multiplayer hole so the render shows colour-matched balls + the active arrow
            gg.OnHostMessage("{\"t\":\"newHole\",\"players\":\"p1|#FF5DA2;p2|#38E1FF;p3|#B6FF4B;p4|#FFD23F\",\"max\":8}");
            gg.OnHostMessage("{\"t\":\"setTurn\",\"id\":\"p1\"}");
            gg.OnHostMessage("{\"t\":\"aim\",\"angle\":0,\"power\":0}");
            gg.OnHostMessage("{\"t\":\"setTraps\",\"traps\":\"bumper,-4,-2.5;boost,-4,0.5\"}");   // plant + reveal tiki traps for the visual check
            gg.PreviewRevealTraps();
            gg.PreviewArrow();   // pose the active (pink) arrow on Ball_0

            var b0 = GameObject.Find("Ball_0");
            var bp = b0 != null ? b0.transform.position : new Vector3(-4f, 0.18f, -8f);

            var cam = GameObject.Find("Main Camera").GetComponent<Camera>();
            var sand = new Vector3(-3.7f, 0f, 4f);
            var gate = new Vector3(-4f, 0.3f, -3f);
            var tiki = new Vector3(-4f, 0.3f, -2.5f);
            Shot(cam, "/tmp/golf-preview.png", new Vector3(0f, 18f, -13f), new Vector3(0f, 0f, -1.5f), 54f);
            Shot(cam, "/tmp/golf-cup.png", Cup + new Vector3(-1.6f, 3.0f, -3.2f), Cup, 38f);
            Shot(cam, "/tmp/golf-tee.png", bp + new Vector3(0f, 3.4f, -3.6f), bp + Vector3.forward * 1.5f, 46f);
            Shot(cam, "/tmp/golf-sand.png", sand + new Vector3(0f, 3.2f, -3.6f), sand, 44f);
            Shot(cam, "/tmp/golf-wall.png", gate + new Vector3(2.8f, 2.4f, -2.6f), gate, 44f);
            Shot(cam, "/tmp/golf-traps.png", tiki + new Vector3(0f, 1.7f, -2.6f), tiki + new Vector3(0f, 0.1f, 1.2f), 46f);   // tiki trap close-up
            Debug.Log("[GolfPreview] wrote /tmp/golf-preview.png, -cup, -tee, -sand, -wall, -traps");

            // ---- Tiki Guard course (map 1) ----
            gg.OnHostMessage("{\"t\":\"newHole\",\"players\":\"p1|#FF5DA2;p2|#38E1FF\",\"max\":8,\"map\":1}");
            gg.OnHostMessage("{\"t\":\"setTurn\",\"id\":\"p1\"}");
            gg.OnHostMessage("{\"t\":\"aim\",\"angle\":0,\"power\":0}");
            gg.PreviewArrow();
            Shot(cam, "/tmp/golf-tiki.png", new Vector3(0f, 16.5f, -10.5f), new Vector3(0f, 0f, -1.5f), 56f);
            Shot(cam, "/tmp/golf-tiki-guard.png", new Vector3(2.8f, 3.6f, -5.6f), new Vector3(2.8f, 0.3f, -2f), 44f);
            Debug.Log("[GolfPreview] wrote /tmp/golf-tiki.png + -tiki-guard.png");

            // ---- Tiki Wind Bridge course (map 2/"Map 3"): data-driven from the SAME def the phone uses ----
            string defPath = "/Users/abdulellahhm/Desktop/games/mini-arcade-host/Resources/web/maps/map3.json";
            string defB64 = File.Exists(defPath) ? System.Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(File.ReadAllText(defPath))) : "";
            gg.OnHostMessage("{\"t\":\"newHole\",\"players\":\"p1|#FF5DA2;p2|#38E1FF\",\"max\":8,\"map\":2,\"defB64\":\"" + defB64 + "\"}");
            gg.OnHostMessage("{\"t\":\"setTurn\",\"id\":\"p1\"}");
            gg.OnHostMessage("{\"t\":\"aim\",\"angle\":0,\"power\":0}");
            gg.PreviewArrow();
            Shot(cam, "/tmp/golf-bridge.png", new Vector3(0f, 21f, -13.5f), new Vector3(0f, 0f, -1.5f), 62f);            // full route choice
            Shot(cam, "/tmp/golf-bridge-ramp.png", new Vector3(1.0f, 3.0f, -5.0f), new Vector3(3.4f, 0.2f, -0.4f), 54f); // ramp + water + island
            Shot(cam, "/tmp/golf-bridge-cup.png", new Vector3(2.4f, 3.4f, 0.6f), new Vector3(4.6f, 0.2f, 3.6f), 50f);    // fan + G2 + cup
            Debug.Log("[GolfPreview] wrote /tmp/golf-bridge.png + -ramp + -cup");
        }

        static void Shot(Camera cam, string path, Vector3 pos, Vector3 look, float fov)
        {
            int W = 1280, H = 720;
            cam.transform.position = pos; cam.transform.LookAt(look); cam.fieldOfView = fov;
            var rt = new RenderTexture(W, H, 24) { antiAliasing = 4 };
            cam.targetTexture = rt; cam.Render();
            RenderTexture.active = rt;
            var tex = new Texture2D(W, H, TextureFormat.RGB24, false);
            tex.ReadPixels(new Rect(0, 0, W, H), 0, 0); tex.Apply();
            RenderTexture.active = null; cam.targetTexture = null;
            File.WriteAllBytes(path, tex.EncodeToPNG());
            Object.DestroyImmediate(rt);
        }
    }
}
#endif
