# iosApp — GigHour iOS (SwiftUI)

A native SwiftUI app over the shared KMP core (`:shared`). Same domain models,
repositories, Supabase/Ktor wiring, and SQLite cache the Android app uses — only
the UI is native. See `../IOS_INTEGRATION.md` for the full contract.

## Layout

```
iosApp/
├── project.yml                 # XcodeGen spec → generates iosApp.xcodeproj
├── Config.xcconfig.example     # copy → Config.xcconfig (gitignored), fill secrets
└── iosApp/
    ├── GigHourApp.swift        # @main; builds AppContainer, starts time sync
    ├── AppContainer.swift      # DI — wires all 10 shared repos
    └── Features/
        ├── JobFeedViewModel.swift  # sample VM over JobRepository (suspend + Result bridging)
        └── JobFeedView.swift       # sample SwiftUI screen
```

> A ready-to-open `iosApp.xcodeproj` is **already committed** (hand-written, not
> generated) and **builds green** for the simulator — `just open iosApp.xcodeproj`
> after steps 1–2. The `project.yml` (XcodeGen) is kept as an alternative way to
> regenerate it.

## First-time setup

1. **Build the framework** (from repo root):
   ```bash
   ./gradlew :shared:assembleSharedXCFramework
   ```
   → `shared/build/XCFrameworks/release/Shared.xcframework`.

2. **Secrets**: `cp Config.xcconfig.example Config.xcconfig` and fill in the
   Supabase URL/key + API base URL. (`apiBaseUrl` must end in `/api/`.)

3. **Open** `iosApp.xcodeproj` in Xcode and run (or regenerate via
   `xcodegen generate`). The project has a pre-build script that re-assembles the
   XCFramework each Xcode build, so Swift always links fresh Kotlin.

### Build notes (already wired in the committed project)

- **`-lsqlite3`**: the SQLDelight native driver references SQLite C symbols, so
  the app target links `libsqlite3` (`OTHER_LDFLAGS = -lsqlite3`). Without it you
  get `Undefined symbol: _sqlite3_bind_*`.
- **Deployment target iOS 16**: the sample UI avoids iOS-17-only APIs
  (`ContentUnavailableView`) so it builds on 16+.

Verified: `xcodebuild ... -sdk iphonesimulator build` → **BUILD SUCCEEDED**,
producing `iosApp.app` with `Shared.framework` embedded.

## What's wired vs. what's next

- ✅ Wired: DI container, all 10 repositories, server-time sync, one sample
  feature (Find Jobs) end-to-end.
- ⏭️ Next: auth/OTP gate, the remaining screens, and a **Flow bridge**. The
  sample uses plain `suspend`/`Result`. For `observe*` Flows (`observeJobs`,
  `authDataFlow`, realtime status) and ergonomic async, add **SKIE**
  (https://skie.touchlab.co) to `shared/build.gradle.kts` — it generates Swift
  `AsyncSequence` + typed `Result`/sealed-class wrappers.

## Interop notes

- Kotlin `suspend fun` → Swift `async` (`try await repo.method(...)`).
- Repos return Kotlin `Result<T>`: unwrap via `.getOrNull()` / `.exceptionOrNull()`
  (see `JobFeedViewModel`).
- `companion object` members → `Type.companion.MEMBER` (e.g.
  `ApiClient.companion.DEFAULT_JSON`).
- `object` singletons → `Type.shared` (e.g. `SupabaseProvider.shared`,
  `NoopStatusChangeNotifier.shared`).
- The app must implement nothing in the data layer — `ServerClock` is the shared
  `SupabaseServerClock`; only an optional real `StatusChangeNotifier` (for
  WhatsApp-token notifications) would replace `NoopStatusChangeNotifier` later.
