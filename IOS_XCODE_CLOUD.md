# iOS and Xcode Cloud Handoff

This Unity project is prepared for source control, but the iOS native build
still needs to be exported from Unity on a Mac. Windows can build and test the
Android/Editor prototype, but it cannot produce the final signed iOS archive.

## What Works Now

- The phone controller web app runs on iPhone Safari, Android Chrome, and
  desktop browsers when the Unity host serves `http://<host-ip>:8080`.
- The Unity host runs the game, room code, lobby, mini-game picker, mini-golf,
  bidding, and result flow.
- The Android APK can be rebuilt from this Unity project after closing the
  Unity editor.

## What Still Needs a Mac

1. Install Unity `6000.3.18f1` through Unity Hub.
2. Add the **iOS Build Support** module for that same editor version.
3. Open this project from the repository root.
4. Switch platform to **iOS** in Unity Build Settings.
5. Build/export the iOS Xcode project.
6. Open the exported project in Xcode.
7. Set the Apple Team, Bundle Identifier, signing, capabilities, and deployment
   target.
8. Run on a real iPhone and test AirPlay/HDMI external display behavior.
9. Commit the exported Xcode project only if you want Xcode Cloud to build that
   generated iOS project directly.

## Xcode Cloud Options

### Option A: Commit the exported Xcode project

This is the simplest first setup.

- Export Unity to an iOS Xcode project on a Mac.
- Commit the generated Xcode project to GitHub, usually under `ios-unity/`.
- Configure Xcode Cloud from Xcode or App Store Connect to build that project.

### Option B: Generate the Xcode project inside CI

This is cleaner long-term, but more setup.

- Xcode Cloud must install or access Unity.
- A Unity license/login flow must be available to the CI environment.
- The workflow runs Unity in batch mode to export iOS before Xcode archives.

For this prototype, use **Option A** first. It is easier to debug and avoids
fighting Unity licensing inside the cloud before the game is ready.
