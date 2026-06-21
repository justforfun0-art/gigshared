import Foundation
import Shared

/// Dependency container wiring the shared KMP module. Build once at app launch
/// and inject the repositories into view-models. Mirrors IOS_INTEGRATION.md.
///
/// NOTE: `BackendConfig` values must come from a non-committed source
/// (xcconfig / Info.plist). `apiBaseUrl` must end in "/api/".
final class AppContainer {

    let config: BackendConfig
    // supabase-kt's client surfaces in Swift under its package-prefixed name.
    let supabase: any Supabase_ktSupabaseClient
    let api: ApiClient
    let tokenStore: any SecureTokenStore
    let sessionStore: any SessionStore
    let serverClock: SupabaseServerClock
    let jobCache: any JobCache

    // Repositories (shared) — interfaces surface as Swift protocols, hence `any`.
    let auth: any AuthRepository
    let jobs: any JobRepository
    let applications: any ApplicationRepository
    let profile: any ProfileRepository
    let payments: any PaymentRepository
    let payouts: any PayoutRepository
    let beneficiaries: any BeneficiaryRepository
    let dashboard: any DashboardRepository
    let notifications: any NotificationRepository
    let referral: any ReferralRepository
    let messages: any MessageRepository
    let savedSearches: any SavedSearchesRepository
    let pushTokens: any PushTokenRepository
    let jobExtract: any JobExtractRepository
    let match: any MatchRepository
    let forecast: any ForecastRepository
    let assistant: AssistantEngine

    init(config: BackendConfig) {
        self.config = config

        let tokenStore = IosSecureTokenStore(service: "com.gighour.tokens")
        let sessionStore = IosSessionStore(service: "com.gighour.session")
        self.tokenStore = tokenStore
        self.sessionStore = sessionStore

        self.supabase = SupabaseProvider.shared.create(config: config, tokenStore: tokenStore)
        self.api = ApiClient(config: config, tokenStore: tokenStore, json: ApiClient.companion.DEFAULT_JSON)
        self.serverClock = SupabaseServerClock(supabaseClient: supabase)

        // makeJobCache (IosHelpers.kt) supplies the default dispatcher internally,
        // so Swift needn't name a CoroutineDispatcher.
        let driver = DriverFactory()
        let cache = IosHelpersKt.makeJobCache(driverFactory: driver)
        self.jobCache = cache

        self.auth = AuthRepositoryImpl(authApi: AuthApi(client: api), sessionStore: sessionStore, secureTokenStore: tokenStore)
        self.jobs = JobRepositoryImpl(
            jobsApi: JobsApi(client: api),
            jobCache: jobCache,
            supabaseClient: supabase,
            serverClock: serverClock
        )
        self.applications = ApplicationRepositoryImpl(
            applicationsApi: ApplicationsApi(client: api),
            supabaseClient: supabase,
            statusChangeNotifier: NoopStatusChangeNotifier.shared
        )
        self.profile = ProfileRepositoryImpl(profileApi: ProfileApi(client: api), supabaseClient: supabase)
        self.payments = PaymentRepositoryImpl(
            paymentsApi: PaymentsApi(client: api),
            supabaseClient: supabase,
            sessionStore: sessionStore
        )
        self.payouts = PayoutRepositoryImpl(payoutsHistoryApi: PayoutsHistoryApi(client: api))
        self.beneficiaries = BeneficiaryRepositoryImpl(beneficiariesApi: BeneficiariesApi(client: api))
        self.dashboard = DashboardRepositoryImpl(supabaseClient: supabase, tokenStore: tokenStore)
        self.notifications = NotificationRepositoryImpl(api: NotificationsApi(client: api), serverClock: serverClock, prefsApi: NotificationPreferencesApi(client: api))
        self.referral = ReferralRepositoryImpl(supabaseClient: supabase)
        self.messages = MessageRepositoryImpl(supabaseClient: supabase, messagesApi: MessagesApi(client: api))
        self.savedSearches = SavedSearchesRepositoryImpl(api: SavedSearchesApi(client: api))
        self.pushTokens = PushTokenRepositoryImpl(supabaseClient: supabase)
        self.jobExtract = JobExtractRepositoryImpl(api: JobExtractApi(client: api))
        self.match = MatchRepositoryImpl(api: MatchApi(client: api))
        self.forecast = ForecastRepositoryImpl(api: ForecastApi(client: api))
        self.assistant = AssistantEngine(
            jobs: jobs,
            applications: applications,
            profile: profile,
            dashboard: dashboard,
            assistantApi: AssistantApi(client: api)
        )
    }

    /// Kick the server-time sync once on launch (repos that gate on the clock
    /// will block on awaitSync until this lands; never a device-clock fallback).
    func startServerTimeSync() {
        Task { _ = try? await serverClock.syncServerTime() }
    }

    /// Backfill the SecureTokenStore (which ApiClient/Supabase read for the
    /// bearer + RLS) from the persisted session on launch. Needed for sessions
    /// created before the secure-store was wired in verifyOtp — and harmless
    /// otherwise — so an already-logged-in user's data syncs without re-login.
    /// Also mints a fresh Supabase token so RLS queries resolve auth.uid().
    func backfillSecureTokensFromSession() {
        Task {
            let existing = try? await tokenStore.getAuthToken()
            if existing == nil, let token = try? await sessionStore.getToken() {
                try? await tokenStore.setAuthToken(token: token)
            }
            if let userId = try? await sessionStore.getUserId() {
                try? await tokenStore.setUserId(userId: userId)
            }
            // Mint/refresh the Supabase JWT into the secure store for RLS.
            _ = try? await auth.refreshSupabaseToken()
        }
    }
}
