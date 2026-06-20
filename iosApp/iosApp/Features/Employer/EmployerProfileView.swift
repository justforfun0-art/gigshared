import SwiftUI
import Shared

/// Employer profile — port of Android's EmployerProfileScreen. Company identity
/// (avatar/name/industry + rating), headline stats (jobs / hires / this-month),
/// a Company Details card (about/industry/size/website/GST/address), settings
/// rows, and sign-out. Distinct from the worker-oriented ProfileView.
struct EmployerProfileView: View {
    let profileRepo: any ProfileRepository
    let dashboard: any DashboardRepository
    let notifications: (any NotificationRepository)?
    let jobs: any JobRepository
    let session: AuthData
    let onHelp: () -> Void
    let onSignOut: () -> Void
    /// Switch the root bottom-bar tab (My Jobs / Applications / Payments).
    let onSelectTab: (Int) -> Void

    @StateObject private var viewModel: EmployerProfileViewModel
    @State private var showSettings = false
    @State private var showNotifications = false
    @State private var showPostJob = false
    @State private var showEdit = false

    init(profileRepo: any ProfileRepository, dashboard: any DashboardRepository,
         jobs: any JobRepository,
         notifications: (any NotificationRepository)? = nil,
         session: AuthData, onHelp: @escaping () -> Void, onSignOut: @escaping () -> Void,
         onSelectTab: @escaping (Int) -> Void) {
        self.profileRepo = profileRepo
        self.dashboard = dashboard
        self.jobs = jobs
        self.notifications = notifications
        self.session = session
        self.onHelp = onHelp
        self.onSignOut = onSignOut
        self.onSelectTab = onSelectTab
        _viewModel = StateObject(wrappedValue: EmployerProfileViewModel(
            profileRepo: profileRepo, dashboard: dashboard, userId: session.userId
        ))
    }

    private var accent: Color { GHTheme.tertiary }

    var body: some View {
        NavigationStack {
            ZStack {
                GHTheme.pageGradient.ignoresSafeArea()
                if viewModel.isLoading {
                    ProgressView()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            identity
                            stats
                            totalSpentCard
                            quickActions
                            if let p = viewModel.profile { companyCard(p) }
                            settingsCard
                            logout
                        }
                        .padding(.horizontal, 20).padding(.vertical, 16)
                    }
                }
            }
            .navigationTitle(L("nav_profile"))
            .drawerToolbar()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showEdit = true } label: { Image(systemName: "pencil") }
                        .tint(accent)
                }
                if notifications != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showNotifications = true } label: { Image(systemName: "bell") }
                    }
                }
            }
            .sheet(isPresented: $showNotifications) {
                if let notifications { NotificationsView(notifications: notifications) }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(onNotifications: notifications != nil ? { showNotifications = true } : nil,
                             notificationsRepo: notifications, onLogout: onSignOut)
            }
            .sheet(isPresented: $showPostJob) {
                PostJobView(jobs: jobs, employerId: session.userId) { Task { await viewModel.load() } }
            }
            .sheet(isPresented: $showEdit) {
                EmployerProfileEditView(profileRepo: profileRepo, userId: session.userId) {
                    Task { await viewModel.load() }
                }
            }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
        }
    }

    private var identity: some View {
        HStack(spacing: 16) {
            let url = viewModel.profile?.profilePhotoUrl
            Group {
                if let url, let parsed = URL(string: url), !url.isEmpty {
                    AsyncImage(url: parsed) { $0.resizable().scaledToFill() } placeholder: { ProgressView() }
                        .frame(width: 80, height: 80).clipShape(Circle())
                } else {
                    Circle().fill(LinearGradient(colors: [GHTheme.hex(0x10B981), GHTheme.hex(0x059669)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 80, height: 80)
                        .overlay(Text(initials).font(.title.weight(.bold)).foregroundStyle(.white))
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.profile?.companyName ?? "—").font(.title2.weight(.bold))
                if let ind = viewModel.profile?.industry, !ind.isEmpty {
                    Text(ind).font(.subheadline).foregroundStyle(GHTheme.onSurfaceVariant)
                }
                if let r = viewModel.profile?.averageRating?.doubleValue, r > 0 {
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { i in
                            Image(systemName: r >= Double(i) ? "star.fill" : (r >= Double(i) - 0.5 ? "star.leadinghalf.filled" : "star"))
                                .font(.caption2).foregroundStyle(GHTheme.hex(0xF59E0B))
                        }
                        Text(String(format: "%.1f", r)).font(.caption.weight(.semibold))
                            .foregroundStyle(GHTheme.onSurfaceVariant).padding(.leading, 4)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var initials: String { String((viewModel.profile?.companyName ?? "?").prefix(2)).uppercased() }

    /// "Jun 2026" from an ISO/Postgres timestamp (Android's formatMemberSince).
    private func memberSince(_ createdAt: String?) -> String? {
        guard let createdAt, !createdAt.isEmpty,
              let d = ActiveJobBarViewModel.parseISO(createdAt) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM yyyy"
        return f.string(from: d)
    }

    private var stats: some View {
        HStack(spacing: 10) {
            stat("\(viewModel.totalJobs)", L("jobs_stat_label"))
            stat("\(viewModel.totalHires)", L("hires_label"))
            stat(Money.rupees(viewModel.thisMonthSpent, decimals: 0), L("this_month_label"))
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.weight(.heavy)).foregroundStyle(accent).lineLimit(1).minimumScaleFactor(0.6)
            Text(label.uppercased()).font(.system(size: 10, weight: .semibold)).kerning(0.5)
                .foregroundStyle(GHTheme.onSurfaceVariant).lineLimit(1)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12).padding(.horizontal, 10)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    // Emerald gradient "Total Spent" overview (Android's overview card).
    private var totalSpentCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("total_spent_label")).font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
                Text(Money.rupees(viewModel.totalSpent, decimals: 0))
                    .font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            Spacer()
            Image(systemName: "indianrupeesign.circle.fill")
                .font(.system(size: 32)).foregroundStyle(.white)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [GHTheme.hex(0x059669), GHTheme.hex(0x047857)],
                           startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    // 2×2 quick-action grid (My Jobs / Applications / Payments / Post Job).
    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(L("quick_actions_label"))
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    quickAction("briefcase", L("nav_my_jobs")) { onSelectTab(1) }
                    quickAction("person.2", L("applications_stat_label")) { onSelectTab(2) }
                }
                HStack(spacing: 10) {
                    quickAction("creditcard", L("nav_payments")) { onSelectTab(3) }
                    quickAction("plus.square.on.square", L("post_job_label")) { showPostJob = true }
                }
            }
        }
    }

    private func quickAction(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundStyle(accent).frame(width: 22)
                Text(label).font(.subheadline.weight(.medium)).foregroundStyle(GHTheme.onBackground)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.2), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func companyCard(_ p: EmployerProfile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel(L("company_details"))
            VStack(spacing: 0) {
                // SKIE renames Kotlin `description` → `description_` (clashes with NSObject.description).
                if let about = p.description_, !about.isEmpty { row("doc.text", L("about_section_label"), about); Divider() }
                row("briefcase", L("industry_label"), p.industry)
                if let s = p.companySize, !s.isEmpty { Divider(); row("person.3", L("company_size_label"), s) }
                if let w = p.website, !w.isEmpty { Divider(); row("globe", L("website_label"), w) }
                if let g = p.gstNumber, !g.isEmpty { Divider(); row("number", "GST", g) }
                if let a = p.address, !a.isEmpty { Divider(); row("mappin.and.ellipse", L("work_location_label"), a) }
                if let since = memberSince(p.createdAt) { Divider(); row("calendar", L("member_since_info_label"), since) }
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func row(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(accent).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(GHTheme.onSurfaceVariant)
                Text(value).font(.subheadline.weight(.medium)).foregroundStyle(GHTheme.onBackground)
            }
            Spacer()
        }
        .padding(.vertical, 10)
    }

    private var settingsCard: some View {
        VStack(spacing: 0) {
            sectionLabel(L("profile_settings"))
            VStack(spacing: 0) {
                settingsRow("gearshape", L("profile_settings")) { showSettings = true }
                Divider()
                settingsRow("questionmark.circle", L("profile_help"), onHelp)
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var logout: some View {
        Button(role: .destructive, action: onSignOut) {
            HStack { Spacer()
                Image(systemName: "rectangle.portrait.and.arrow.right"); Text(L("log_out")); Spacer() }
        }
        .tint(GHTheme.error).padding(.vertical, 4)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased()).font(.caption2.weight(.semibold)).kerning(0.6)
            .foregroundStyle(GHTheme.onSurfaceVariant)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 4)
    }

    private func settingsRow(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(GHTheme.onSurfaceVariant)
                Text(label).font(.subheadline.weight(.medium)).foregroundStyle(GHTheme.onBackground)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(GHTheme.hex(0x9CA3AF))
            }
            .padding(.horizontal, 16).padding(.vertical, 14).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

@MainActor
final class EmployerProfileViewModel: ObservableObject {
    @Published private(set) var isLoading = true
    @Published private(set) var profile: EmployerProfile?
    @Published private(set) var totalJobs = 0
    @Published private(set) var totalHires = 0
    @Published private(set) var thisMonthSpent = 0.0
    @Published private(set) var totalSpent = 0.0

    private let profileRepo: any ProfileRepository
    private let dashboard: any DashboardRepository
    private let userId: String

    init(profileRepo: any ProfileRepository, dashboard: any DashboardRepository, userId: String) {
        self.profileRepo = profileRepo
        self.dashboard = dashboard
        self.userId = userId
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        profile = try? await IosHelpersKt.getEmployerProfileOrThrow(profileRepo, userId: userId)
        if let s = try? await dashboard.getEmployerStatsOrThrow(employerId: userId) {
            totalJobs = Int(s.totalJobs)
            totalHires = Int(s.hiredWorkers)
            thisMonthSpent = Double(s.thisMonthSpent)
            totalSpent = Double(s.totalSpent)
        }
    }
}
