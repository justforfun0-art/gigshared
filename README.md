# gighour-shared

Kotlin Multiplatform shared core for GigHour — **Path A** (shared logic/data,
native UIs). One `:shared` module holds the domain models, repository contracts,
and the full data layer (Supabase + Ktor + SQLite cache); the Android app
(Gigand repo) and a SwiftUI iOS app (`iosApp/`) each provide native UI.

## Status

| Layer | State |
|---|---|
| Domain models (Tier 1 + 2) | ✅ shared, tested |
| 10 repository interfaces | ✅ shared |
| 10 repository impls (Ktor + Supabase + cache + server clock) | ✅ shared |
| Android target | ✅ compiles |
| iOS targets (arm64, simulator arm64, x64) | ✅ compile |
| `Shared.xcframework` | ✅ assembles (device + simulator) |
| iOS SwiftUI app | ✅ builds (DI + sample feature; `xcodebuild` → BUILD SUCCEEDED) |
| commonTest | ✅ 29/29 passing |

## Module map

```
shared/                  the KMP library
  src/commonMain/        models, repo interfaces + impls, Supabase/Ktor/cache/clock
  src/androidMain/        Android actuals (EncryptedSharedPreferences, drivers, Log)
  src/iosMain/            iOS actuals (Keychain, NativeSqliteDriver, NSLog)
  src/commonTest/         shared tests
iosApp/                  SwiftUI app consuming Shared.xcframework
```

## Docs

- **[DATA_LAYER_PLAN.md](DATA_LAYER_PLAN.md)** — how the data layer was ported
  (phases 0–6), the Retrofit→Ktor strategy, preserved audit invariants.
- **[IOS_INTEGRATION.md](IOS_INTEGRATION.md)** — how an iOS app consumes the
  module: framework build, DI wiring, what iOS must provide, interop notes.
- **[iosApp/README.md](iosApp/README.md)** — the SwiftUI app scaffold setup
  (XcodeGen, secrets, build).

## Toolchain (see gradle/libs.versions.toml for why)

Kotlin **2.1.20** (required for supabase-kt 3.0.3's iOS klibs), AGP **8.7.3**,
Gradle **8.9** (avoids the KMP `Type T` test-task bug), SQLDelight 2.0.2,
supabase-kt 3.0.3, Ktor 3.0.2. Intentionally decoupled from Gigand's toolchain.

## Common commands

```bash
./gradlew :shared:testDebugUnitTest                 # run shared tests
./gradlew :shared:compileKotlinIosSimulatorArm64    # iOS compile check
./gradlew :shared:assembleSharedXCFramework         # build the iOS framework
```

## What's NOT shared (per-platform)

UI (Compose / SwiftUI), push (FCM / APNs), foreground/background services,
payment SDK UI, the `ServerTimeService` *sync trigger* (the clock value is shared
via `SupabaseServerClock`), and a real `StatusChangeNotifier` (the no-op default
ships). Repo interfaces already exclude these.
