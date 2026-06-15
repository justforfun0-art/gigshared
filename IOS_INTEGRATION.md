# iOS Integration Guide — `gighour-shared`

How a SwiftUI app consumes the shared KMP module. The shared module exposes the
whole domain + data layer (models, the 10 repositories, Supabase/Ktor/cache
wiring); the iOS app supplies a few platform pieces and the UI.

---

## 1. Build the framework

```bash
./gradlew :shared:assembleSharedXCFramework   # device + simulator slices (recommended)
# or a single slice:  ./gradlew :shared:linkDebugFrameworkIosSimulatorArm64
```

Output: `shared/build/XCFrameworks/release/Shared.xcframework` (slices:
`ios-arm64` device + `ios-arm64_x86_64-simulator`). The `iosApp/` scaffold
already references this. Kotlin types are exposed to Swift under the `Shared`
module name.

> VERIFIED (2026-06-15): all three iOS targets compile and
> `assembleSharedReleaseXCFramework` produces `Shared.xcframework` (device +
> simulator). Requires Kotlin 2.1.20 — supabase-kt 3.0.3's iOS klibs are built
> with Kotlin 2.1.0 and 2.0.21's Native compiler rejects them ("Incompatible ABI
> version"). The Keychain cinterop (`IosKeychain`) and `DriverFactory.ios` are
> compiled, not just written. The `iosApp/` SwiftUI scaffold (DI container +
> Find-Jobs sample) consumes it — see `iosApp/README.md`.

## 2. What iOS must provide (platform glue)

The shared layer is constructor-injected — no Hilt/Koin required. iOS supplies:

| Dependency | iOS implementation | Status |
|---|---|---|
| `BackendConfig` | build from Info.plist / xcconfig (supabaseUrl, anonKey, apiBaseUrl) | app provides |
| `SecureTokenStore` | `IosSecureTokenStore()` (Keychain) | ✅ in module |
| `SessionStore` | `IosSessionStore()` (Keychain) | ✅ in module, compiles |
| `DriverFactory` | `DriverFactory()` (NativeSqliteDriver) | ✅ in module, compiles |
| `ServerClock` | `SupabaseServerClock(supabase)` — call `syncServerTime()` on launch + periodically | ✅ in module |
| `StatusChangeNotifier` | `NoopStatusChangeNotifier` to start; later a real WhatsApp-token notifier | default ok |

`ServerClock` is now a shared `SupabaseServerClock` (port of Gigand's
ServerTimeService): it queries the `get_server_time` RPC and serves
`deviceClock + cachedOffset`. The app must drive `syncServerTime()` — once on
launch and on a refresh cadence — and surface a "syncing…" state off its
`isSynced` flow. Anti-tamper preserved: before the first sync the OrNull
accessors return null / the others throw; it NEVER falls back to a raw device
clock.

## 3. Wiring (Swift, conceptual)

```swift
import Shared

let config = BackendConfig(
    supabaseUrl: Secrets.supabaseUrl,
    supabaseAnonKey: Secrets.supabaseAnonKey,
    apiBaseUrl: Secrets.apiBaseUrl // ends in "/api/"
)

let tokenStore   = IosSecureTokenStore(service: "com.gighour.tokens")
let sessionStore = IosSessionStore(service: "com.gighour.session")
let supabase     = SupabaseProvider().create(config: config, tokenStore: tokenStore)
let api          = ApiClient(config: config, tokenStore: tokenStore, json: ApiClient.companion.DEFAULT_JSON)
let serverClock  = SupabaseServerClock(supabaseClient: supabase) // call syncServerTime() on launch
let jobCache     = SqlDelightJobCache(db: DriverFactoryKt.createGighourDb(factory: DriverFactory()))

// Repositories
let jobs      = JobRepositoryImpl(jobsApi: JobsApi(client: api), jobCache: jobCache,
                                  supabaseClient: supabase, serverClock: serverClock)
let auth      = AuthRepositoryImpl(authApi: AuthApi(client: api), sessionStore: sessionStore)
let apps      = ApplicationRepositoryImpl(applicationsApi: ApplicationsApi(client: api),
                                          supabaseClient: supabase,
                                          statusChangeNotifier: NoopStatusChangeNotifier())
let payments  = PaymentRepositoryImpl(paymentsApi: PaymentsApi(client: api),
                                      supabaseClient: supabase, sessionStore: sessionStore)
let profile   = ProfileRepositoryImpl(profileApi: ProfileApi(client: api), supabaseClient: supabase)
let dashboard = DashboardRepositoryImpl(supabaseClient: supabase, tokenStore: tokenStore)
let referral  = ReferralRepositoryImpl(supabaseClient: supabase)
let beneficiaries = BeneficiaryRepositoryImpl(beneficiariesApi: BeneficiariesApi(client: api))
let payouts   = PayoutRepositoryImpl(payoutsHistoryApi: PayoutsHistoryApi(client: api))
let notifications = NotificationRepositoryImpl(api: NotificationsApi(client: api), serverClock: serverClock)
```

Hold these in an app-level container; inject into SwiftUI view-models.

## 4. Calling suspend functions / Flows from Swift

- `suspend fun` → Swift async (`try await jobs.getJobs(...)`), or the
  completion-handler form KMP generates. Repos return Kotlin `Result<T>` — unwrap
  via `.getOrNull()` / check `.isSuccess`.
- `Flow` (`observeJobs`, `authDataFlow`, …) → collect via a small Swift bridge
  (e.g. SKIE, or a hand-rolled `Flow.collect` wrapper). Consider adding SKIE to
  the Gradle config for ergonomic async/AsyncSequence interop before building UI.

## 5. Things that stay native on iOS (not in `:shared`)

Same split as Android: all UI, push notifications (APNs), any foreground/
background work, the payment SDK UI (Cashfree), Places, and the `ServerClock`
sync mechanism. The repo interfaces already exclude these.

## 6. Repository surface (for reference)

10 interfaces in `com.gighour.shared.domain.repository`: Auth, Job, Application,
Profile, Payment, Payout, Beneficiary, Dashboard, Notification, Referral. Models
in `com.gighour.shared.domain.model`. All are `Result`/`Flow`-returning and
pure-Kotlin — identical contracts to the Android app.
