# Activating iOS Push Notifications (FCM)

The iOS push pipeline is **fully coded and committed** but **inert** until the
Firebase SDK is linked. All Firebase calls are gated behind
`#if canImport(FirebaseMessaging)` (see `PushManager.swift`), so the app builds
and runs without it today. The moment FirebaseMessaging is linked, push
activates automatically — **no code changes needed**.

This doc is the ~5-minute Xcode + console checklist to flip it on.

---

## What's already done (in code)

| Piece | File |
|---|---|
| Token upsert → `user_fcm_tokens` (`platform="ios"`) | `shared/.../PushTokenRepositoryImpl.kt` + `registerTokenOrThrow` shim |
| Repo wired into the container | `iosApp/iosApp/AppContainer.swift` (`pushTokens`) |
| Permission request, FCM token capture, upload-on-login, foreground banners, tap routing | `iosApp/iosApp/Features/PushManager.swift` |
| APNs token forwarding | `iosApp/iosApp/Features/PushAppDelegate.swift` (`@UIApplicationDelegateAdaptor` in `GigHourApp.swift`) |
| `remote-notification` background mode + `FirebaseAppDelegateProxyEnabled=NO` | `iosApp/iosApp/Info.plist` |
| `aps-environment` entitlement | `iosApp/iosApp/iosApp.entitlements` |

The server send-path keys off the `user_fcm_tokens` row regardless of platform,
so once an iOS row exists, existing notifications deliver to the device.

---

## Prerequisites

- An **Apple Developer account** (paid) — APNs keys require it.
- The **Firebase project** already used by Android (so iOS shares the same
  Cloud Messaging backend / send logic).
- A **physical iPhone** (iOS 14+). APNs/FCM do **not** deliver to the iOS
  Simulator — registration silently no-ops there.

---

## Step 1 — Add the Firebase SDK (SPM, in Xcode) — ~2 min

1. Open `iosApp/iosApp.xcodeproj` in Xcode.
2. **File → Add Package Dependencies…**
3. Enter: `https://github.com/firebase/firebase-ios-sdk`
4. Dependency Rule: **Up to Next Major** (e.g. `11.0.0`).
5. Click **Add Package**. When prompted for products, check **only**:
   - ✅ **FirebaseMessaging**
   (SPM resolves the ~10 transitive products automatically — don't add them by
   hand.) Add it to the **iosApp** target.

> Why SPM and not by-hand pbxproj edits: Firebase pulls many transitive
> packages that only the SPM resolver wires correctly. Doing this in the GUI is
> the supported path; hand-editing the project file is error-prone.

## Step 2 — Add `GoogleService-Info.plist` — ~1 min

1. In the [Firebase Console](https://console.firebase.google.com) → your
   project → **Project Settings → General**.
2. Under **Your apps**, click **Add app → iOS**.
3. Bundle ID: use the iosApp target's bundle id (set via
   `PRODUCT_BUNDLE_IDENTIFIER`, e.g. `com.gighour.iosApp` — confirm in the
   target's **Build Settings**).
4. Download **`GoogleService-Info.plist`**.
5. Drag it into the Xcode Project Navigator, into the **iosApp** group:
   - ✅ **Copy items if needed**
   - ✅ Target membership: **iosApp**

## Step 3 — APNs Auth Key (.p8) — ~2 min

1. [Apple Developer](https://developer.apple.com/account) → **Certificates,
   Identifiers & Profiles → Keys → +**.
2. Name it (e.g. "GigHour APNs"), enable **Apple Push Notifications service
   (APNs)**, **Continue → Register**, then **Download** the `.p8` (you can only
   download it once — keep it safe). Note the **Key ID** and your **Team ID**.
3. Firebase Console → **Project Settings → Cloud Messaging → Apple app
   configuration → APNs Authentication Key → Upload**. Provide the `.p8`,
   **Key ID**, and **Team ID**.

## Step 4 — Enable the Push capability (signed builds)

1. Select the **iosApp** target → **Signing & Capabilities**.
2. Set your **Team** (signing must be on for APNs to work).
3. **+ Capability → Push Notifications** (this aligns with the
   `aps-environment` already in `iosApp.entitlements`).
4. **+ Capability → Background Modes →** check **Remote notifications**
   (already declared in Info.plist; the capability makes it explicit).

> The committed entitlement is `aps-environment = development`. For
> **TestFlight / App Store** builds, change it to `production` (or use separate
> Debug/Release entitlements).

---

## Step 5 — Verify

1. Build & run on a **real device**.
2. Accept the notification permission prompt at launch.
3. **Sign in.** `PushManager` caches the FCM token at launch and uploads it once
   the user id is known.
4. Confirm a row appears in Supabase:
   ```sql
   select user_id, platform, is_valid, updated_at
   from user_fcm_tokens
   where platform = 'ios';
   ```
5. Trigger a notification (e.g. an application status change for that user) and
   confirm it arrives. Tapping it posts `.pushNotificationTapped` with the
   payload — wire deep-link routing there if/when needed (Android routes the
   OTP push to the OTP section, for example).

---

## Troubleshooting

- **No token row after login** → not on a real device, permission denied, or
  signing/APNs key missing. Check Xcode console for `APNs registration failed`.
- **Token row exists but no delivery** → APNs key not uploaded to Firebase, or
  `aps-environment` mismatch (development key vs production build).
- **Build fails after adding SPM** → ensure only **FirebaseMessaging** was added
  to the iosApp target; let SPM resolve the rest. Clean build folder (⇧⌘K).
- **Firebase intercepting the delegate** → `FirebaseAppDelegateProxyEnabled` is
  intentionally `NO`; `PushAppDelegate` forwards the APNs token to
  `Messaging.messaging().apnsToken` itself.

---

## Reverting / building without Firebase

Remove the FirebaseMessaging package and the app still builds — `PushManager`
falls back to the no-op path (`#else`), requesting permission + registering for
remote notifications but uploading no token. Nothing else breaks.
