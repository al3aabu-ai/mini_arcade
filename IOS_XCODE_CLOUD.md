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

## Mac Export Environment

1. Install Unity `6000.3.18f1` through Unity Hub.
2. Add the **iOS Build Support** module for that same editor version.
3. Install Xcode from the Mac App Store and open it once so it installs command
   line components.
4. Clone this repository on the Mac.
5. From the repository root, run:

```bash
chmod +x scripts/export-ios-xcode.sh
MINI_ARCADE_APPLE_TEAM_ID=YOURTEAMID ./scripts/export-ios-xcode.sh
```

The script exports the Unity iOS project to:

```text
Builds/iOS/MiniArcade-iOS
```

Optional environment variables:

```bash
UNITY_VERSION=6000.3.18f1
UNITY_APP="/Applications/Unity/Hub/Editor/6000.3.18f1/Unity.app/Contents/MacOS/Unity"
MINI_ARCADE_APPLE_TEAM_ID=YOURTEAMID
MINI_ARCADE_IOS_BUNDLE_ID=com.al3aa.miniArcade
MINI_ARCADE_IOS_VERSION=1.0
MINI_ARCADE_IOS_BUILD_NUMBER=1
MINI_ARCADE_IOS_EXPORT_PATH="$PWD/Builds/iOS/MiniArcade-iOS"
```

You can also export from the Unity menu:

```text
Mini Arcade -> Export iOS Xcode Project
```

After export:

1. Open `Builds/iOS/MiniArcade-iOS/Unity-iPhone.xcodeproj` in Xcode.
2. Confirm the Apple Team, Bundle Identifier, signing, capabilities, and
   deployment target.
3. Run on a real iPhone and test AirPlay/HDMI external display behavior.
4. Commit the exported Xcode project only if you want Xcode Cloud to build that
   generated iOS project directly.

## Xcode Cloud Options

### Option A: Commit the exported Xcode project

This is the simplest first setup.

- Export Unity to an iOS Xcode project on a Mac.
- Commit the generated Xcode project to GitHub, usually under `ios-unity/`.
- Configure Xcode Cloud from Xcode or App Store Connect to build that project.

Example export path for a project you intend to commit:

```bash
MINI_ARCADE_APPLE_TEAM_ID=YOURTEAMID \
MINI_ARCADE_IOS_EXPORT_PATH="$PWD/ios-unity/MiniArcade-iOS" \
./scripts/export-ios-xcode.sh
```

### Option B: Generate the Xcode project inside CI

This is cleaner long-term, but more setup.

- Xcode Cloud must install or access Unity.
- A Unity license/login flow must be available to the CI environment.
- The workflow runs Unity in batch mode to export iOS before Xcode archives.

For this prototype, use **Option A** first. It is easier to debug and avoids
fighting Unity licensing inside the cloud before the game is ready.

## Uploading to App Store Connect

App Store Connect details:

| Field | Value |
|---|---|
| Team ID | 9472PWTG9J |
| Bundle Identifier | com.al3aa.miniArcade |
| App Store Connect Apple ID | 6781736873 |

After exporting the Xcode project, archive and upload in one step:

```bash
# Option 1 – Apple ID + app-specific password (generate at appleid.apple.com)
export APPLE_ID_USERNAME="your@email.com"
export APPLE_ID_PASSWORD="xxxx-xxxx-xxxx-xxxx"
./scripts/upload-to-appstore.sh

# Option 2 – App Store Connect API key (recommended, no 2FA prompt)
export APP_STORE_CONNECT_API_KEY_ID="XXXXXXXXXX"
export APP_STORE_CONNECT_API_KEY_ISSUER="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export APP_STORE_CONNECT_API_KEY_PATH="/path/to/AuthKey_XXXXXXXXXX.p8"
./scripts/upload-to-appstore.sh
```

The script archives `Builds/iOS/MiniArcade-iOS/Unity-iPhone.xcodeproj`, exports it
with `scripts/ExportOptions-AppStore.plist`, and uploads directly to App Store Connect.
After upload completes, the build appears under **TestFlight** within a few minutes.
