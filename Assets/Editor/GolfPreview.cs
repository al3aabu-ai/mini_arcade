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
            gg.PreviewArrow();   // pose the active (pink) arrow on Ball_0

            var b0 = GameObject.Find("Ball_0");
            var bp = b0 != null ? b0.transform.position : new Vector3(-4f, 0.18f, -8f);

            var cam = GameObject.Find("Main Camera").GetComponent<Camera>();
            var sand = new Vector3(-3.7f, 0f, 4f);
            var gate = new Vector3(-4f, 0.3f, -3f);
            Shot(cam, "/tmp/golf-preview.png", new Vector3(0f, 18f, -13f), new Vector3(0f, 0f, -1.5f), 54f);
            Shot(cam, "/tmp/golf-cup.png", Cup + new Vector3(-1.6f, 3.0f, -3.2f), Cup, 38f);
            Shot(cam, "/tmp/golf-tee.png", bp + new Vector3(0f, 3.4f, -3.6f), bp + Vector3.forward * 1.5f, 46f);
            Shot(cam, "/tmp/golf-sand.png", sand + new Vector3(0f, 3.2f, -3.6f), sand, 44f);
            Shot(cam, "/tmp/golf-wall.png", gate + new Vector3(2.8f, 2.4f, -2.6f), gate, 44f);
            Debug.Log("[GolfPreview] wrote /tmp/golf-preview.png, -cup, -tee, -sand, -wall");

            // ---- Tiki Guard course (map 1) ----
            gg.OnHostMessage("{\"t\":\"newHole\",\"players\":\"p1|#FF5DA2;p2|#38E1FF\",\"max\":8,\"map\":1}");
            gg.OnHostMessage("{\"t\":\"setTurn\",\"id\":\"p1\"}");
            gg.OnHostMessage("{\"t\":\"aim\",\"angle\":0,\"power\":0}");
            gg.PreviewArrow();
            Shot(cam, "/tmp/golf-tiki.png", new Vector3(0f, 16.5f, -10.5f), new Vector3(0f, 0f, -1.5f), 56f);
            Shot(cam, "/tmp/golf-tiki-guard.png", new Vector3(2.8f, 3.6f, -5.6f), new Vector3(2.8f, 0.3f, -2f), 44f);
            Debug.Log("[GolfPreview] wrote /tmp/golf-tiki.png + -tiki-guard.png");

            // ---- Tiki Wind Run course (map 2): top-down + close-ups of the ramp/bridge and the fan ----
            gg.OnHostMessage("{\"t\":\"newHole\",\"players\":\"p1|#FF5DA2;p2|#38E1FF\",\"max\":8,\"map\":2}");
            gg.OnHostMessage("{\"t\":\"setTurn\",\"id\":\"p1\"}");
            gg.OnHostMessage("{\"t\":\"aim\",\"angle\":0,\"power\":0}");
            gg.PreviewArrow();
            Shot(cam, "/tmp/golf-windrun.png", new Vector3(0f, 18.5f, -11.5f), new Vector3(0f, 0f, -2f), 58f);
            Shot(cam, "/tmp/golf-windrun-ramp.png", new Vector3(2.0f, 2.3f, -4.6f), new Vector3(3.7f, 0.25f, 0.6f), 52f);
            Shot(cam, "/tmp/golf-windrun-fan.png", new Vector3(2.6f, 2.6f, 0.2f), new Vector3(5.1f, 1.0f, 2.2f), 46f);
            Debug.Log("[GolfPreview] wrote /tmp/golf-windrun.png + -ramp + -fan");
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
