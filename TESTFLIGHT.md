# Shipping Frantics to TestFlight

> **Status (June 2026):** account enrolled ✅, app record "Frantics" created ✅,
> API key working ✅, Apple Distribution certificate + "Frantics AppStore"
> profile created via the ASC API ✅, signed IPA exported ✅ — but Apple now
> **requires the iOS 26 SDK (Xcode 26)** for all uploads, and this Mac
> (2019 Intel MBP, max macOS Sequoia, 16 GB free disk) can't reasonably host
> it. **Use Xcode Cloud instead** — Apple's CI builds with the current SDK and
> uploads to TestFlight automatically.

## Recommended path: Xcode Cloud (no local Xcode upgrade)

One-time setup in the browser (~15 min):

1. appstoreconnect.apple.com → **Apps → Frantics → Xcode Cloud → Get Started**.
2. Connect source control: **GitHub** → grant access to
   `al3aabu-ai/franticc-game` (installs the Xcode Cloud GitHub app).
3. It detects the `Frantics` scheme (already shared in the repo). Create the
   default **Archive – iOS** workflow on branch `main`, environment =
   **latest Xcode (26.x)**, post-action **TestFlight Internal Testing**.
4. Start the first build. Every future `git push` to `main` rebuilds and
   ships to TestFlight automatically.

Free tier: 25 compute-hours/month — dozens of builds. Signing is cloud-managed
by Xcode Cloud; no local certificates needed. Build status is visible in the
Xcode Cloud tab (and via the ASC API).

## Legacy path: local archive + upload (kept for reference)

Works only on a Mac whose Xcode meets Apple's current minimum-SDK rule.

## One-time setup (you)

**1. Join the Apple Developer Program** — TestFlight requires the paid tier.
   - developer.apple.com/programs → Enroll with `abdulellahhm@gmail.com`
     ($99/year). Approval is usually minutes-to-48h.
   - Note your **new Team ID** afterwards (developer.apple.com → Membership).
     The current `9472PWTG9J` is the free personal team; the paid team gets a
     different ID.

**2. Create the app record** — appstoreconnect.apple.com → My Apps → **+** →
   New App: platform iOS, name "Frantics" (pick an alternate if taken, e.g.
   "Frantics Party"), language, bundle ID `com.frantics.party` (register it at
   developer.apple.com → Identifiers if it isn't in the dropdown), SKU
   `frantics-001`.

**3. Generate an API key** so uploads run headless — App Store Connect →
   Users and Access → Integrations → Team Keys → Generate (role: **App
   Manager**). Download the `.p8` (only downloadable once), note the
   **Key ID** and **Issuer ID**.

## Every release (one command)

```bash
TEAM_ID=<paid team id> \
ASC_KEY_ID=<key id> \
ASC_ISSUER_ID=<issuer id> \
ASC_KEY_PATH=~/keys/AuthKey_XXXX.p8 \
./scripts/release-testflight.sh
```

The script archives, signs with cloud-managed distribution certificates
(`-allowProvisioningUpdates`), uploads, and stamps a clock-based build number
so re-runs never collide. ~10 minutes after upload the build shows under
**TestFlight** in App Store Connect.

## Inviting players

- **Internal testers** (up to 100, instant): TestFlight tab → Internal Testing
  → add testers by Apple ID email. No review needed.
- **External testers** (up to 10,000, public link): needs a brief Beta App
  Review the first time (~1 day).
- Testers install the **TestFlight app**, accept the invite, and get Frantics
  with automatic update prompts on every new build.

## Already handled in the repo

- 1024px opaque marketing icon (`Assets.xcassets/AppIcon`), original art
- `ITSAppUsesNonExemptEncryption = false` (skips the export-compliance prompt)
- iPhone-only device family (avoids iPad orientation validation)
- `ios/ExportOptions.plist` (app-store-connect method, auto signing, upload)
- Release archive verified to build (`xcodebuild archive` passes)

## Gotcha to expect

The game needs a reachable server. For TestFlight friends outside your WiFi,
deploy `server/` (see README → Deploy) and set the `wss://` address in the
app's ⚙️ settings — or keep parties on the same WiFi with the Mac's LAN
address. A future improvement is baking a default production server URL into
the app before uploading.
