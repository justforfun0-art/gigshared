# Shared Data Layer — Implementation Plan

Status: **Phase 0–6 DONE (2026-06-15), test-green (28/28). DATA LAYER COMPLETE.**
ALL 10 repos ported to commonMain + a SQLDelight job cache replacing
NoopJobCache. Only the iOS actuals/app and wiring Gigand :app onto :shared
remain (both deferred per the iOS-first decision / need the Apple toolchain).

## Decisions (locked 2026-06-14)
- **iOS-first.** Gigand `:app` keeps its current Retrofit/Supabase impls
  untouched; the shared impls target iOS now and `:app` migrates onto `:shared`
  later, once proven (the §5.5 recommendation). Two impls coexist meanwhile.
- This pass scoped to **Phase 0 + Phase 1 only**, then reassess before the
  Retrofit→Ktor work.

## Done so far
- Phase 0 infra (commonMain): `BackendConfig`, `SupabaseProvider` (builds the
  client from config + token callback; tolerant JSON), `SecureTokenStore`
  interface, `expect object Logger`. Android actuals: `Logger.android`,
  `AndroidSecureTokenStore` (EncryptedSharedPreferences, needs new
  `androidx.security:security-crypto` dep). iOS actuals: `Logger.ios` (NSLog),
  `IosSecureTokenStore` (Keychain — **written but NOT iOS-compiled here**; needs
  an Apple-toolchain pass).
- Phase 1 repos (commonMain): `DashboardRepositoryImpl`, `ReferralRepositoryImpl`
  ported verbatim except Log→Logger, AuthPreferences→SecureTokenStore,
  SecurityException→IllegalStateException.
- Phase 2 (commonMain): `JobRepositoryImpl` (first Retrofit→Ktor proof). New
  shared infra it introduced:
  - `data/remote/ApiClient` — Ktor client replacing Retrofit+OkHttp: engine
    auto-selected (okhttp/darwin), base URL from config, `applyAuth(builder)`
    adds `Authorization: Bearer` + the `auth_token/user_id/sb_access_token`
    cookie trio, `captureRotatedSbToken(resp)` mirrors the Set-Cookie sb-token
    refresh hook. `expectSuccess=false` so callers inspect `body.success`.
  - `data/remote/JobsApi` — Ktor port of every Retrofit JobsApi route (same
    paths/params/bodies). Gson `@SerializedName(alternate)` → kotlinx
    `@JsonNames("data","job")` on JobResponse.job.
  - `data/ServerClock` — abstraction over ServerTimeService (returns
    kotlinx.datetime; honours never-device-time). `data/local/JobCache` +
    `NoopJobCache` — Room replaced by a no-op cache for now (offline fallbacks
    become empty; `observeJobs` emits nothing until a real cache lands Phase 6).
  - Extended `SecureTokenStore` with the app `authToken` (was only Supabase
    token + userId) — both actuals updated.
- Phase 3 (commonMain): the three Retrofit-only repos → Ktor.
  - `BeneficiariesApi` (routes under `payouts/...`, NOT `secure/`),
    `PayoutsHistoryApi` (`payouts/history`), `NotificationsApi`
    (`secure/notifications`; @HTTP DELETE → plain Ktor delete w/ query params).
  - `BeneficiaryRepositoryImpl`, `PayoutRepositoryImpl`,
    `NotificationRepositoryImpl`. Transport difference handled: Retrofit
    `Response<T>` (isSuccessful/errorBody) → Ktor returns body directly
    (expectSuccess=false), so success is read off the body's `success`/`error`
    fields instead of HTTP status. NotificationRepository's java SimpleDateFormat
    ISO parse + java.util time-ago → kotlinx.datetime `Instant.parse` (with a
    UTC-append fallback for offset-less strings); time-ago thresholds + type map
    unchanged. Added `ServerClock.serverNowMillisOrNull()` (display-only device
    fallback, never for timing/payment/expiry).
- Phase 4 (commonMain): Auth. New `data/local/SessionStore` (full auth-session
  abstraction over AuthPreferences — distinct from the narrow SecureTokenStore;
  owns AuthData + reactive authDataFlow + Supabase token) with android actual
  `AndroidSessionStore` (EncryptedSharedPreferences; `initialized`-deferred-gated
  flow so no transient logged-out emit; in-memory mirrors; DISTINCT prefs file
  `gighour_shared_session`; omits Gigand's legacy DataStore migration — :app
  concern). `data/remote/AuthApi` (Ktor; auth/otp/send, auth/otp/verify,
  auth/sb-token; returns `HttpResult<T>` = status+body so the repo can replicate
  the `code==400 → "Invalid or expired OTP"` fallback even though Ktor doesn't
  throw on non-2xx). `AuthRepositoryImpl`. PRESERVED AUDIT FIXES: verifyOtp saves
  inside withContext(NonCancellable) (project_employer_login_5554), post-save
  token refresh best-effort, rate-limit body surfaced. iOS SessionStore actual
  still TODO (Keychain) — flagged.
- Phase 5 (commonMain): the 3 big mixed repos.
  - Ktor APIs: `ProfileApi` (secure/profiles; @SerializedName→@SerialName incl.
    `data` + snake_case), `PaymentsApi` (payments/create-order, payments/verify),
    `ApplicationsApi` (secure/applications + secure/work-sessions). updateStatus
    + workSessionAction + payment routes return HttpResult so the repo reads the
    server error off the body on non-2xx.
  - Repos: Profile, Payment, Application. PRESERVED INVARIANTS:
    • Payment verifyPayment gates STRICTLY on order_status==PAID (NOT ||SUCCESS)
      — the double-charge audit fix (project_payment_flow_audit); test asserts
      SUCCESS-without-PAID → false. Employer-id session guard kept.
    • Application keeps SupervisorJob notifScope, rpcJson lenient decoder, the
      constraint-name embeds, patchStatus re-fetch-with-joins. WhatsApp service →
      [StatusChangeNotifier] (NoopStatusChangeNotifier default; delivery stays
      per-platform). System.currentTimeMillis → kotlinx Clock (Payment orderId).
  - Added Supabase Storage (provider install + supabase-storage dep) for
    Profile photo upload.
- Phase 5 verified: `compileKotlinMetadata` + `compileDebugKotlinAndroid` green;
  24/24 commonTest pass (PaymentVerifyTest guards the PAID-only gate). iOS target
  NOT compiled (Auth-module SettingsSessionManager also can't init in plain JVM
  unit tests — tests that need a SupabaseClient build a postgrest-only one).
- Phase 6 (commonMain): SQLDelight job cache replacing NoopJobCache.
  - `.sq` schema `JobCache.sq` (pkg com.gighour.shared.db, db name GighourDb):
    each Job stored as a LOSSLESS kotlinx-JSON blob + denormalized
    id/employer_id/is_active/title/description/job_date/created_at/cached_at
    columns for indexable filter/order. Fixes Gigand's Room comma-join that lost
    commas inside list values (test asserts a "welding, advanced" skill survives).
  - `expect class DriverFactory` + actuals: Android (AndroidSqliteDriver+Context),
    iOS (NativeSqliteDriver). `SqlDelightJobCache : JobCache` (asFlow observeAll,
    transaction upsert, deleteOlderThan for the 24h cleanup parity).
  - Deps added: sqldelight plugin 2.0.2 + runtime/coroutines/android-driver/
    native-driver, sqlite-driver in androidUnitTest. BUILD FIX: the sqldelight
    plugin's KGP pull broke the target-level `compilerOptions{jvmTarget}` DSL →
    switched the androidTarget JVM-17 setting to the legacy
    `compilations.all{kotlinOptions.jvmTarget="17"}` form.
  - To use: `SqlDelightJobCache(createGighourDb(driverFactory))` in place of
    NoopJobCache when constructing JobRepositoryImpl.
- Verified: `compileKotlinMetadata` + `compileDebugKotlinAndroid` green;
  28/28 commonTest pass (SqlDelightJobCacheTest: lossless round-trip,
  active-filter + created-DESC order, LIKE search, deleteOlderThan + clear, on a
  JVM in-memory SQLite). iOS target NOT compiled.

---

This plan covers moving the *concrete repository
implementations* into the shared KMP module.

---

## 1. What Gigand's data layer actually looks like

The current Android data layer is a **hybrid**, not pure-Supabase:

| Source | Used for | KMP-portable? |
|---|---|---|
| `SupabaseClient` (postgrest/realtime/storage) | most **reads**, RPC calls, realtime | ✅ supabase-kt is KMP, iOS targets exist |
| Retrofit `*Api` → Next.js `/api/secure/*` | most **writes/mutations**, OTP, payments | ❌ Retrofit is JVM-only |
| `EncryptedSharedPreferences` / DataStore | token + session at rest | ❌ Android Keystore, needs expect/actual |
| Room (`JobDao`, `GigHourDatabase`) | local job cache | ❌ Room is Android-only |
| `BuildConfig` | Supabase URL/key, base URL | ❌ Android-gen, needs config injection |

Per-impl split (Api refs vs Supabase refs), from the source:

- Supabase-only: **Dashboard**, **Referral**
- Retrofit-Api-only: **Auth**, **Beneficiary**, **Notification**, **Payout**
- Mixed: **Application** (16 api / 19 sb), **Job** (9 / 9), **Payment** (4 / 3), **Profile** (8 / 5)

The Supabase client is built with a per-request JWT callback:
`accessToken = { authPreferences.getSupabaseToken() }` (token minted by the
Next.js `/api/auth/sb-token`, used by PostgREST for RLS).

**Implication:** a clean "lift the impls into commonMain" is *not* possible as-is.
The Retrofit half and the Android storage/cache half must be re-platformed first.

---

## 2. Target architecture

```
commonMain
├── domain/                      ← DONE (models + repo interfaces)
├── data/
│   ├── SupabaseProvider         ← builds SupabaseClient from injected config
│   ├── BackendConfig            ← data class: supabaseUrl, anonKey, apiBaseUrl
│   ├── remote/                  ← Ktor-based client for the Next.js /api/secure/* routes
│   │   └── *Api (Ktor)          ← replaces Retrofit interfaces
│   ├── repository/              ← concrete *RepositoryImpl in commonMain
│   └── local/                   ← expect/actual: SecureTokenStore, (later) cache
├── expect SecureTokenStore      ← actual: Keystore (android) / Keychain (ios)
└── expect AppLog / config glue

androidMain
├── actual SecureTokenStore  → EncryptedSharedPreferences
└── actual config            → BuildConfig

iosMain
├── actual SecureTokenStore  → Keychain
└── actual config            → from Info.plist / build settings
```

Key decisions:
- **Retrofit → Ktor.** Rewrite the `*Api` interfaces as Ktor `HttpClient` calls
  (Ktor is already a dep, with okhttp/darwin engines wired). This is the biggest
  single chunk of work and the main behavioural-risk surface (must preserve every
  route, query param, body shape, and the auth header).
- **No Hilt in commonMain.** Repos take constructor params (SupabaseClient,
  Ktor client, SecureTokenStore, a clock). Android keeps Hilt and provides these;
  iOS wires them by hand or with Koin. The interfaces don't change.
- **Drop Room from the shared layer initially.** The Room job-cache is an
  optimization, not core. Shared impls can skip local caching at first (return
  straight from network); re-add a multiplatform cache (SQLDelight) later if
  needed. This keeps the first cut small.
- **Config injection replaces BuildConfig.** A `BackendConfig` data class passed
  in at construction; each platform fills it from its own build system.
- **Clock:** repos that need "today in India" (Job, Application expiry, dashboard)
  take a `suspend () -> LocalDateTime` or a small `ServerClock` interface — the
  Tier-2 models already use `kotlinx.datetime.LocalDateTime`. `ServerTimeService`
  itself (the anti-tamper FGS-backed sync) stays per-platform; only the clock
  *value* crosses into shared code. Honour the existing rule: never fall back to
  device time — pass null / block when unsynced (see project_server_time memory).

---

## 3. Phased rollout (each phase compiles + tests green before the next)

**Phase 0 — Infra (no repos yet).**
- `BackendConfig`, `SupabaseProvider` (commonMain) — build the client from config
  with the `accessToken` callback delegating to `SecureTokenStore`.
- `expect class SecureTokenStore` + android actual (wrap existing
  EncryptedSharedPreferences) + ios actual (Keychain).
- A commonMain Ktor `ApiClient` wrapper: base URL from config, auth header from
  the token store, JSON = the same tolerant `Json { ignoreUnknownKeys; isLenient }`.
- Test: provider builds; token store round-trips on android unit test.

**Phase 1 — Supabase-only repos (lowest risk).** `DashboardRepository`,
`ReferralRepository`. Pure postgrest/RPC reads, no Retrofit. Proves the
SupabaseProvider + decode path end-to-end. Port verbatim, swap DI for ctor.

**Phase 2 — Read-heavy mixed repo as the Ktor proof.** `JobRepository`.
Reads already use Supabase (port directly); the handful of Retrofit writes
(create/update/delete/toggle) become the first Ktor `*Api` rewrites. Validates the
Retrofit→Ktor pattern on a contained surface before the big ones.

**Phase 3 — Retrofit-only repos → Ktor.** `Beneficiary`, `Payout`,
`Notification`. Straight API rewrites, no Supabase mixing. Mechanical once the
Ktor `ApiClient` pattern is set.

**Phase 4 — Auth.** `AuthRepository` + token/session wiring. Highest-care:
OTP send/verify, the sb-token mint, `hasCachedSupabaseToken`, logout. Depends on
SecureTokenStore (Phase 0). Mind the prior auth bugs (double-verify,
NonCancellable session save — see project_auth_session_audit memory).

**Phase 5 — The big mixed repos.** `Application` (16 api/19 sb),
`Payment` (4/3), `Profile` (8/5). Most surface area; do last when the patterns
are proven. Payment must preserve the double-charge / double-verify guards
(project_payment_flow_audit memory).

**Phase 6 — Optional: multiplatform local cache (SQLDelight)** to restore the
Room job-cache, if the no-cache cut proves too slow on iOS.

---

## 4. Realtime, services, and what stays Android-only

- **Realtime** (`observe*` Flows) — supabase-kt Realtime is KMP, so the Flow-
  returning methods can move. But the channel-lifecycle/leak fixes
  (project_race_conditions_audit) must be re-verified in the shared impls.
- **Stays per-platform (NOT shared):** FCM/`GigHourMessagingService`, all
  foreground services (`WorkShiftLiveService`, live notifications), Cashfree SDK
  payment UI, `NoShowDetector`, `ServerTimeService` sync mechanism, Places SDK,
  the assistant engine, Room. These are platform glue; the repo *interfaces*
  already exclude them.

---

## 5. Risks / open questions

1. **Retrofit→Ktor is real rewriting, not porting.** ~12 `*Api` files (only the
   ~10 repo-backing ones matter). Every route/param/body must match the Next.js
   contract exactly — this is where behavioural drift would hide. Mitigation:
   one shared `ApiClient` + a request per old method, reviewed against the
   Retrofit annotations side-by-side; cover with tests against recorded responses.
2. **Gson vs kotlinx.** Retrofit DTOs use Gson `@SerializedName`; Ktor path uses
   kotlinx `@SerialName`. The request/response DTOs need re-annotating (some use
   Gson `alternate` names — must be preserved as kotlinx alternatives).
3. **Token refresh / 401 handling** currently lives in the OkHttp interceptor
   (NetworkModule). Must be reimplemented as a Ktor plugin (auth/refresh).
4. **`BuildConfig` secrets.** Supabase keys come from BuildConfig today; iOS needs
   its own secure-ish config source. Decide: xcconfig/Info.plist injection.
5. **Decision needed:** keep Gigand `:app` on its current Retrofit impls until
   iOS ships (two impls coexist, `:app` ignores `:shared` data layer for now), OR
   migrate `:app` onto the shared impls as we go (riskier, but no duplication).
   Recommend **the former** — ship shared impls for iOS first, migrate `:app`
   later once proven, to avoid destabilizing the live Android app.

---

## 6. Recommended first action

Phase 0 + Phase 1 together: stand up `SupabaseProvider` + `SecureTokenStore`
(expect/actual) + port the two Supabase-only repos (Dashboard, Referral). Small,
end-to-end, and de-risks the whole client/decode/token path before any
Retrofit→Ktor work. Everything else builds on it.
