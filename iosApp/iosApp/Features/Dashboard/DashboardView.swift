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
    /// Threaded into the action-card carousel → ApplicationStatusView so its
    /// chat affordance works, matching the History list's navigation.
    private let messages: (any MessageRepository)?
    /// Employer Home action carousel needs the payments repo for "Process Payment".
    private let payments: (any PaymentRepository)?
    /// Kept for the employer Analytics sheet (Dashboard quick action).
    private let dashboardRepo: any DashboardRepository
    /// Employer Quick Actions switch tabs (RootView owns the selection).
    var onSelectTab: ((Int) -> Void)? = nil
    /// Opens the Applications tab pre-filtered to a specific tab (home tiles).
    /// "active" or "completed".
    var onShowApplications: ((String) -> Void)? = nil
    private let userPhone: String
    private let employeeId: String
    @State private var showNotifications = false
    /// Employer carousel: applicant detail + payments routing.
    @State private var employerDetailApp: Application?
    @State private var showPayments = false
    @State private var showAnalytics = false
    @State private var showPostJob = false
    /// Collapses the swipe section when the deck is empty (no jobs to swipe).
    @State private var swipeDeckEmpty = false

    init(dashboard: any DashboardRepository,
         referralRepo: any ReferralRepository,
         notifications: (any NotificationRepository)? = nil,
         swipeJobs: (any JobRepository)? = nil,
         applications: (any ApplicationRepository)? = nil,
         profile: (any ProfileRepository)? = nil,
         messages: (any MessageRepository)? = nil,
         payments: (any PaymentRepository)? = nil,
         onSelectTab: ((Int) -> Void)? = nil,
         onShowApplications: ((String) -> Void)? = nil,
         session: AuthData) {
        _viewModel = StateObject(wrappedValue: DashboardViewModel(
            dashboard: dashboard,
            referralRepo: referralRepo,
            jobs: swipeJobs,
            applications: applications,
            userId: session.userId,
            userType: session.userType
        ))
        self.dashboardRepo = dashboard
        self.onSelectTab = onSelectTab
        self.onShowApplications = onShowApplications
        self.notifications = notifications
        self.swipeJobs = swipeJobs
        self.applications = applications
        self.profile = profile
        self.messages = messages
        self.payments = payments
        self.userPhone = session.phone
        self.employeeId = session.userId
    }

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    actionSection
                    swipeSection
                    statsSection
                    if viewModel.isEmployer {
                        quickActions
                        recentJobsSection
                    }
                    if let insights = viewModel.insights, insights.totalJobs > 0 {
                        HiringHealthCard(insights: insights)
                    }
                    if let referral = viewModel.referral {
                        ReferralCard(info: referral)
                    }
                }
                .padding()
            }
            .navigationTitle(viewModel.isEmployer ? L("ios_hiring_overview") : L("ios_your_dashboard"))
            // Bell/messages/language now live in the global top bar (drawerToolbar).
            .drawerToolbar()
            .sheet(isPresented: $showNotifications) {
                if let notifications {
                    // NotificationsView brings its own NavigationStack; present it
                    // directly and dismiss via swipe-down (standard sheet gesture).
                    NotificationsView(notifications: notifications)
                }
            }
            // Employer carousel destinations.
            .sheet(item: $employerDetailApp) { app in
                NavigationStack {
                    ApplicationStatusView(application: app, messages: messages,
                                          myUserId: employeeId, applications: applications)
                }
            }
            .sheet(isPresented: $showPayments) {
                if let payments {
                    PaymentsView(payments: payments, employerId: employeeId,
                                 employerPhone: userPhone, employerName: "Employer")
                }
            }
            .sheet(isPresented: $showAnalytics) {
                if let swipeJobs, let applications {
                    AnalyticsView(jobs: swipeJobs, applications: applications,
                                  dashboard: dashboardRepo, employerId: employeeId)
                }
            }
            .sheet(isPresented: $showPostJob) {
                if let swipeJobs {
                    PostJobView(jobs: swipeJobs, employerId: employeeId) {
                        Task { await viewModel.load() }
                    }
                }
            }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
        }
    }

    /// Employee Home action-card carousel (Android ActionCardCarousel parity):
    /// in-flight applications that need attention, each tappable into the
    /// work-session screen. Employers don't get it (no worker lifecycle here).
    @ViewBuilder
    private var actionSection: some View {
        if let applications {
            if viewModel.isEmployer {
                EmployerActionCardCarousel(
                    applications: applications,
                    employerId: employeeId,
                    onOpenApplicant: { employerDetailApp = $0 },
                    onProcessPayment: { _ in showPayments = true }
                )
            } else {
                ActionCardCarousel(applications: applications, employeeId: employeeId, messages: messages)
            }
        }
    }

    // MARK: - Employer Quick Actions (Android dashboard parity)

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("quick_actions")).font(.headline)
            let cols = [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: cols, spacing: 12) {
                quickAction("plus", L("post_job"), L("create_new_listing"), GHTheme.hex(0xECFDF5), GHTheme.hex(0x059669)) { showPostJob = true }
                quickAction("person.2.fill", L("applicants"), L("review_applications"), GHTheme.hex(0xEFF6FF), GHTheme.hex(0x2563EB)) { onSelectTab?(2) }
                quickAction("creditcard.fill", L("payments"), L("manage_payments"), GHTheme.hex(0xFEF3C7), GHTheme.hex(0xD97706)) { onSelectTab?(3) }
                quickAction("chart.line.uptrend.xyaxis", L("nav_analytics"), L("view_insights"), GHTheme.hex(0xF5F3FF), GHTheme.hex(0x7C3AED)) { showAnalytics = true }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(GHTheme.outline, lineWidth: 1))
    }

    private func quickAction(_ icon: String, _ title: String, _ subtitle: String, _ bg: Color, _ iconBg: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.subheadline).foregroundStyle(.white)
                    .frame(width: 36, height: 36).background(iconBg, in: RoundedRectangle(cornerRadius: 10))
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(GHTheme.onBackground)
                Text(subtitle).font(.caption2).foregroundStyle(GHTheme.onSurfaceVariant).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(bg, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Employer Recent Jobs (Android dashboard parity)

    @ViewBuilder
    private var recentJobsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("your_recent_jobs")).font(.headline)
                Spacer()
                Button { onSelectTab?(1) } label: {
                    HStack(spacing: 2) { Text(L("view_all")); Image(systemName: "chevron.right").font(.caption) }
                        .font(.subheadline).foregroundStyle(GHTheme.tertiary)
                }
            }
            if viewModel.recentJobs.isEmpty {
                Text(L("ios_no_jobs_yet")).font(.subheadline).foregroundStyle(GHTheme.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 12)
            } else {
                ForEach(viewModel.recentJobs, id: \.id) { EmployerJobCard(job: $0) { onSelectTab?(1) } }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(GHTheme.outline, lineWidth: 1))
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
                JobSwipeView(jobs: swipeJobs, applications: applications,
                             employeeId: employeeId, profile: profile,
                             onContentEmptyChange: { empty in
                                 withAnimation(.easeInOut(duration: 0.2)) { swipeDeckEmpty = empty }
                             })
                    // Tall while there's a deck to swipe; compact when empty so
                    // the "all caught up" state doesn't leave a big void.
                    .frame(height: swipeDeckEmpty ? 220 : 460)
            }
        }
    }

    @ViewBuilder
    private var statsSection: some View {
        switch viewModel.stats {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
        case .employee(let s):
            // Tiles navigate like Android (employee tabs: 2=Applications, 3=Earnings).
            LazyVGrid(columns: columns, spacing: 12) {
                StatTile(title: "Applications", value: "\(s.totalApplications)", icon: "doc.text", tint: .blue) { onSelectTab?(2) }
                StatTile(title: "Active jobs", value: "\(viewModel.activeApplicationsCount ?? Int(s.activeJobs))", icon: "bolt", tint: .orange) { onShowApplications?("active") }
                StatTile(title: "Completed", value: "\(s.completedJobs)", icon: "checkmark.seal", tint: .green) { onShowApplications?("completed") }
                StatTile(title: "Earnings", value: "₹\(s.totalEarnings)", icon: "indianrupeesign.circle", tint: .green) { onSelectTab?(3) }
                StatTile(title: "Pending pay", value: "₹\(s.pendingPayments)", icon: "hourglass", tint: .amber) { onSelectTab?(3) }
                StatTile(title: "This month", value: "₹\(s.thisMonthEarnings)", icon: "calendar", tint: .purple) { onSelectTab?(3) }
            }
        case .employer(let s):
            // Tiles navigate like Android (employer tabs: 1=My Jobs, 2=Applications, 3=Payments).
            LazyVGrid(columns: columns, spacing: 12) {
                StatTile(title: "Active jobs", value: "\(s.activeJobs)", icon: "bolt", tint: .orange) { onSelectTab?(1) }
                StatTile(title: "All jobs", value: "\(s.totalJobs)", icon: "briefcase", tint: .blue) { onSelectTab?(1) }
                StatTile(title: "Applications", value: "\(s.totalApplications)", icon: "doc.text", tint: .blue) { onSelectTab?(2) }
                StatTile(title: "Pending review", value: "\(s.pendingReview)", icon: "person.crop.circle.badge.questionmark", tint: .amber) { onSelectTab?(2) }
                StatTile(title: "Hired", value: "\(s.hiredWorkers)", icon: "person.2", tint: .green) { onSelectTab?(2) }
                StatTile(title: "This month", value: "₹\(s.thisMonthSpent)", icon: "calendar", tint: .purple) { onSelectTab?(3) }
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
    /// Tapping navigates to the related tab (Android StatCard onClick). Optional.
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button { onTap?() } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon).font(.title3).foregroundStyle(tint)
                    Spacer()
                    if onTap != nil {
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(tint.opacity(0.6))
                    }
                }
                Text(value).font(.title2.weight(.bold)).lineLimit(1).minimumScaleFactor(0.6)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
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

/// A recent-job row on the employer dashboard (Android JobCard) — emerald
/// avatar initial, title, status pill, location/pay/date chips.
private struct EmployerJobCard: View {
    let job: Job
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [GHTheme.hex(0x10B981), GHTheme.hex(0x059669)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: 44, height: 44)
                    .overlay(Text(String(job.title.prefix(1)).uppercased()).font(.headline.weight(.bold)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(job.title).font(.subheadline.weight(.semibold)).foregroundStyle(GHTheme.onBackground).lineLimit(1)
                        Spacer()
                        statusPill
                    }
                    HStack(spacing: 10) {
                        if let loc = job.district ?? Optional(job.location), !loc.isEmpty {
                            Label(loc, systemImage: "mappin").font(.caption2).foregroundStyle(GHTheme.onSurfaceVariant).lineLimit(1)
                        }
                        if let pay = job.salaryRange, !pay.isEmpty {
                            Label(pay, systemImage: "indianrupeesign").font(.caption2).foregroundStyle(GHTheme.onSurfaceVariant).lineLimit(1)
                        }
                    }
                }
            }
            .padding(14)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(GHTheme.outline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var statusPill: some View {
        let active = job.isActive
        let (text, color) = active ? (L("status_active"), GHTheme.success) : (L("status_expired"), GHTheme.muted)
        return Text(text).font(.caption2.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}

/// Employer "Hiring Health" card (Android AnalyticsScreen insights section) —
/// fill rate, time-to-fill, hire no-show rate (red ≥20%), top district.
private struct HiringHealthCard: View {
    let insights: EmployerInsights

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("hiring_health_label")).font(.headline)
            VStack(spacing: 14) {
                metric(L("fill_rate_label"), "\(Int((insights.fillRate * 100).rounded()))%",
                       L("fill_rate_desc", Int(insights.filledJobs), Int(insights.totalJobs)))
                if let h = insights.avgFillHours?.doubleValue {
                    Divider()
                    metric(L("time_to_fill_label"), formatHours(h), L("time_to_fill_desc"))
                }
                if let r = insights.noShowRate?.doubleValue {
                    Divider()
                    metric(L("hire_no_show_label"), "\(Int((r * 100).rounded()))%",
                           L("hire_no_show_desc", Int(insights.hireNoShows), Int(insights.totalHires)),
                           valueColor: r >= 0.2 ? GHTheme.error : GHTheme.success)
                }
                if let d = insights.topDistrict, !d.isEmpty {
                    Divider()
                    metric(L("top_district_label"), d, L("top_district_desc"))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(GHTheme.outline, lineWidth: 1))
        }
    }

    private func metric(_ label: String, _ value: String, _ desc: String, valueColor: Color = GHTheme.onBackground) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(GHTheme.onBackground)
                Text(desc).font(.caption).foregroundStyle(GHTheme.onSurfaceVariant)
            }
            Spacer()
            Text(value).font(.title3.weight(.bold)).foregroundStyle(valueColor)
        }
    }

    private func formatHours(_ h: Double) -> String {
        if h < 1 { return "\(Int((h * 60).rounded()))m" }
        if h < 24 { return String(format: "%.1fh", h) }
        return String(format: "%.1fd", h / 24)
    }
}
