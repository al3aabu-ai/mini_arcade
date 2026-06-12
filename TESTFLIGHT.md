# Shipping Frantics to TestFlight

Everything in the repo is release-ready: app icon, iPhone-only target,
encryption-exempt flag, export options, and a one-command upload script.
Three account steps remain that only the Apple ID owner can do.

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
