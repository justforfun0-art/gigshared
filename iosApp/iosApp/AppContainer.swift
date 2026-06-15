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

        self.auth = AuthRepositoryImpl(authApi: AuthApi(client: api), sessionStore: sessionStore)
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
        self.notifications = NotificationRepositoryImpl(api: NotificationsApi(client: api), serverClock: serverClock)
        self.referral = ReferralRepositoryImpl(supabaseClient: supabase)
    }

    /// Kick the server-time sync once on launch (repos that gate on the clock
    /// will block on awaitSync until this lands; never a device-clock fallback).
    func startServerTimeSync() {
        Task { _ = try? await serverClock.syncServerTime() }
    }
}
