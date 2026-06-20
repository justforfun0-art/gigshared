# Testing GigHour iOS on a Physical Device

The app runs on the iOS Simulator **unsigned** (that's how the build commands in
this repo use `CODE_SIGNING_ALLOWED=NO`). A **physical device requires real code
signing** — a Team, automatic provisioning, and the entitlements
(`aps-environment`, keychain group) backed by a profile.

This is the end-to-end checklist. Most of it is one-time setup.

---

## Prerequisites

- A Mac with **Xcode** (matching the iOS version on your device).
- An **Apple ID**. A free one works for personal on-device testing (apps expire
  after 7 days; re-run to reinstall). A paid **Apple Developer** account removes
  the expiry and is required for TestFlight/App Store and real APNs push.
- Your iPhone on **iOS 16.0+** (the app's deployment target).

---

## One-time setup

### 1. Set your signing team

Edit `iosApp/Config.xcconfig` (gitignored, already on your machine):

```
DEVELOPMENT_TEAM = ABCDE12345
PRODUCT_BUNDLE_IDENTIFIER = com.gighour.iosApp
```

- Find your **Team ID** at <https://developer.apple.com/account> → Membership.
- If `com.gighour.iosApp` is already taken under a different account, change the
  bundle id to something unique, e.g. `com.yourname.gighour`.
  > The widget extension derives its id as `<bundle-id>.GigHourWidgets`
  > automatically — no separate change needed.

### 2. Verify backend secrets

`Config.xcconfig` must contain real values (it's gitignored, so it isn't shared):

```
SUPABASE_URL      = https://<project>.supabase.co
SUPABASE_ANON_KEY = <anon key>
API_BASE_URL      = https://<host>/api/      // MUST end in /api/
```

These mirror Android's `local.properties`. If the file is missing or blank, the
app launches but can't reach the backend.

### 3. Build the shared KMP framework

The app **embeds** `Shared.xcframework`; it won't link without it.

```sh
cd /Users/sabar/StudioProjects/gighour-shared
./gradlew :shared:assembleSharedReleaseXCFramework
```

Re-run this whenever you change Kotlin in `shared/`. (Output:
`shared/build/XCFrameworks/release/Shared.xcframework`.)

### 4. Enable Developer Mode on the iPhone (iOS 16+)

Plug the phone in via USB, then on the device:
**Settings → Privacy & Security → Developer Mode → On** (the phone reboots).

---

## Run it (Xcode — recommended)

1. Open the project:
   ```sh
   open iosApp/iosApp.xcodeproj
   ```
2. Top bar: select the **iosApp** scheme and your **device** in the destination
   dropdown.
3. **iosApp target → Signing & Capabilities**:
   - ✅ **Automatically manage signing**
   - Pick your **Team**
   - Let Xcode generate the provisioning profile (it registers the bundle id +
     entitlements automatically).
   - Do the same for the **GigHourWidgetsExtension** target (same Team).
4. Press **⌘R** to build, install, and launch on the device.
5. First install only — trust the cert on the phone:
   **Settings → General → VPN & Device Management → [your Apple ID] → Trust**.

---

## Run it (command line — alternative)

```sh
# Build a signed device build (lets Xcode create/update the profile)
xcodebuild -project iosApp/iosApp.xcodeproj -scheme iosApp \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates build

# List devices, then install + launch
xcrun devicectl list devices
xcrun devicectl device install app --device <DEVICE_ID> <path-to>.app
xcrun devicectl device process launch --device <DEVICE_ID> com.gighour.iosApp
```

The GUI handles device signing far more smoothly — prefer Xcode unless you're
scripting CI.

---

## What works on device

Everything except push, out of the box: auth/OTP, jobs feed + search, swipe deck,
applications, work session + OTP, earnings/wallet, employer screens (My Jobs,
Job Details, Applicants, Payments, Analytics, Activities), profiles, and the
**Live Activity / Dynamic Island** (which only renders on a real device, not the
simulator).

**Push notifications need extra setup** — see [`PUSH_SETUP.md`](PUSH_SETUP.md)
(FirebaseMessaging SPM + `GoogleService-Info.plist` + APNs key). Until then the
app requests permission and registers, but no token is uploaded.

---

## Gotchas (specific to this project)

- **Forgot step 3?** Link errors about `Shared` → build the XCFramework first.
- **"Signing requires a development team"** → `DEVELOPMENT_TEAM` is blank in
  `Config.xcconfig`, or no Team selected in Signing & Capabilities.
- **"Failed to register bundle identifier"** → the id is taken; change
  `PRODUCT_BUNDLE_IDENTIFIER` in `Config.xcconfig` to a unique value.
- **Keychain errors (-34018) on device** → the entitlements file uses a literal
  keychain group for unsigned sim builds. On a signed device build this still
  works under automatic signing; if you hit issues, switch the group in
  `iosApp.entitlements` to `$(AppIdentifierPrefix)com.gighour.iosApp`.
- **App vanishes after ~7 days** → free Apple ID limitation; just re-run from
  Xcode to reinstall.
- **Wrong iOS APIs** → deployment target is **16.0**; avoid iOS 17+-only APIs.
