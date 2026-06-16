import SwiftUI
import Shared

/// Home dashboard: role-appropriate stat tiles + a referral card. Mirrors the
/// web app's employee/employer dashboard headline numbers (server-aggregated).
struct DashboardView: View {

    @StateObject private var viewModel: DashboardViewModel
    /// When provided (employee Home, which has no Alerts tab), a bell toolbar
    /// button opens notifications as a sheet. Employer Home leaves this nil
    /// because it has its own Alerts tab.
    private let notifications: (any NotificationRepository)?
    /// Employee Home embeds the job-swipe deck (Android parity); nil for employer.
    private let swipeJobs: (any JobRepository)?
    private let applications: (any ApplicationRepository)?
    private let profile: (any ProfileRepository)?
    private let employeeId: String
    @State private var showNotifications = false

    init(dashboard: any DashboardRepository,
         referralRepo: any ReferralRepository,
         notifications: (any NotificationRepository)? = nil,
         swipeJobs: (any JobRepository)? = nil,
         applications: (any ApplicationRepository)? = nil,
         profile: (any ProfileRepository)? = nil,
         session: AuthData) {
        _viewModel = StateObject(wrappedValue: DashboardViewModel(
            dashboard: dashboard,
            referralRepo: referralRepo,
            userId: session.userId,
            userType: session.userType
        ))
        self.notifications = notifications
        self.swipeJobs = swipeJobs
        self.applications = applications
        self.profile = profile
        self.employeeId = session.userId
    }

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    swipeSection
                    statsSection
                    if let referral = viewModel.referral {
                        ReferralCard(info: referral)
                    }
                }
                .padding()
            }
            .navigationTitle(viewModel.isEmployer ? L("ios_hiring_overview") : L("ios_your_dashboard"))
            .drawerToolbar()
            .toolbar {
                if notifications != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showNotifications = true } label: {
                            Image(systemName: "bell")
                        }
                    }
                }
            }
            .sheet(isPresented: $showNotifications) {
                if let notifications {
                    // NotificationsView brings its own NavigationStack; present it
                    // directly and dismiss via swipe-down (standard sheet gesture).
                    NotificationsView(notifications: notifications)
                }
            }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
        }
    }

    /// Employee Home swipe deck (Android MiniSwipeWidget parity). Lives in a
    /// fixed-height frame so its horizontal drag gesture stays contained and
    /// doesn't fight the dashboard's vertical scroll.
    @ViewBuilder
    private var swipeSection: some View {
        if !viewModel.isEmployer, let swipeJobs, let applications {
            VStack(alignment: .leading, spacing: 10) {
                Label(L("swipe_to_apply"), systemImage: "hand.draw")
                    .font(.headline)
                JobSwipeView(jobs: swipeJobs, applications: applications, employeeId: employeeId, profile: profile)
                    .frame(height: 460)
            }
        }
    }

    @ViewBuilder
    private var statsSection: some View {
        switch viewModel.stats {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
        case .employee(let s):
            LazyVGrid(columns: columns, spacing: 12) {
                StatTile(title: "Applications", value: "\(s.totalApplications)", icon: "doc.text", tint: .blue)
                StatTile(title: "Active jobs", value: "\(s.activeJobs)", icon: "bolt", tint: .orange)
                StatTile(title: "Completed", value: "\(s.completedJobs)", icon: "checkmark.seal", tint: .green)
                StatTile(title: "Earnings", value: "₹\(s.totalEarnings)", icon: "indianrupeesign.circle", tint: .green)
                StatTile(title: "Pending pay", value: "₹\(s.pendingPayments)", icon: "hourglass", tint: .amber)
                StatTile(title: "This month", value: "₹\(s.thisMonthEarnings)", icon: "calendar", tint: .purple)
            }
        case .employer(let s):
            LazyVGrid(columns: columns, spacing: 12) {
                StatTile(title: "Active jobs", value: "\(s.activeJobs)", icon: "bolt", tint: .orange)
                StatTile(title: "All jobs", value: "\(s.totalJobs)", icon: "briefcase", tint: .blue)
                StatTile(title: "Applications", value: "\(s.totalApplications)", icon: "doc.text", tint: .blue)
                StatTile(title: "Pending review", value: "\(s.pendingReview)", icon: "person.crop.circle.badge.questionmark", tint: .amber)
                StatTile(title: "Hired", value: "\(s.hiredWorkers)", icon: "person.2", tint: .green)
                StatTile(title: "This month", value: "₹\(s.thisMonthSpent)", icon: "calendar", tint: .purple)
            }
        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.secondary)
                Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button(L("retry_btn")) { Task { await viewModel.load() } }.buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity).padding(.top, 40)
        }
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.title3).foregroundStyle(tint)
            Text(value).font(.title2.weight(.bold)).lineLimit(1).minimumScaleFactor(0.6)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct ReferralCard: View {
    let info: ReferralInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("ios_refer_earn"), systemImage: "gift")
                .font(.headline)
            Text("\(info.referralCount) friend\(info.referralCount == 1 ? "" : "s") joined with your code")
                .font(.subheadline).foregroundStyle(.secondary)
            if !info.referralCode.isEmpty {
                HStack {
                    Text(info.referralCode)
                        .font(.title3.monospaced().weight(.semibold))
                    Spacer()
                    ShareLink(item: "Join GigHour with my referral code: \(info.referralCode)") {
                        Label(L("earnings_share_action"), systemImage: "square.and.arrow.up")
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

private extension Color {
    /// SwiftUI has no `.amber`; map to a warm orange-yellow.
    static let amber = Color(red: 0.95, green: 0.6, blue: 0.1)
}
