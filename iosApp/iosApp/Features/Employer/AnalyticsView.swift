import SwiftUI
import Shared

/// Employer Analytics — port of Android's AnalyticsScreen. This-month gradient
/// stat cards (jobs/applications/hired/completed), server-computed Hiring Health
/// (fill rate / time-to-fill / no-show / top district), performance metrics, a
/// spending hero, and a top-categories breakdown. All data comes from existing
/// shims (employer jobs + applications + insights) — no new Kotlin.
struct AnalyticsView: View {
    let jobs: any JobRepository
    let applications: any ApplicationRepository
    let dashboard: any DashboardRepository
    let employerId: String

    @StateObject private var viewModel: AnalyticsViewModel

    init(jobs: any JobRepository, applications: any ApplicationRepository,
         dashboard: any DashboardRepository, employerId: String) {
        self.jobs = jobs
        self.applications = applications
        self.dashboard = dashboard
        self.employerId = employerId
        _viewModel = StateObject(wrappedValue: AnalyticsViewModel(
            jobs: jobs, applications: applications, dashboard: dashboard, employerId: employerId))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GHTheme.pageGradient.ignoresSafeArea()
                if viewModel.isLoading {
                    ProgressView()
                } else {
                    content
                }
            }
            .navigationTitle(L("analytics_title"))
            .drawerToolbar()
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionLabel(L("this_month_label"))
                statGrid

                if let insights = viewModel.insights, insights.totalJobs > 0 {
                    sectionLabel(L("hiring_health_label"))
                    hiringHealth(insights)
                }

                sectionLabel(L("performance_label"))
                performanceCard

                sectionLabel(L("spending_label"))
                spendingCard

                if !viewModel.topCategories.isEmpty {
                    sectionLabel(L("top_job_categories"))
                    categoriesCard
                }
            }
            .padding(16)
        }
    }

    // 2×2 gradient stat cards.
    private var statGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                gradientStat("Jobs Posted", "\(viewModel.jobsPosted)", "briefcase.fill",
                             [GHTheme.hex(0x059669), GHTheme.hex(0x047857)])
                gradientStat("Applications", "\(viewModel.totalApplications)", "person.2.fill",
                             [GHTheme.hex(0x3B82F6), GHTheme.hex(0x1D4ED8)])
            }
            HStack(spacing: 12) {
                gradientStat("Workers Hired", "\(viewModel.workersHired)", "checkmark.circle.fill",
                             [GHTheme.hex(0x14B8A6), GHTheme.hex(0x0D9488)])
                gradientStat("Jobs Completed", "\(viewModel.jobsCompleted)", "checkmark.seal.fill",
                             [GHTheme.hex(0x8B5CF6), GHTheme.hex(0x6D28D9)])
            }
        }
    }

    private func gradientStat(_ title: String, _ value: String, _ icon: String, _ colors: [Color]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Circle().fill(Color.white.opacity(0.2)).frame(width: 36, height: 36)
                .overlay(Image(systemName: icon).font(.system(size: 18)).foregroundStyle(.white))
            Text(value).font(.title2.weight(.bold)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(title).font(.caption2).foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 16))
    }

    private func hiringHealth(_ insights: EmployerInsights) -> some View {
        whiteCard {
            metricRow(L("fill_rate_label"), "\(Int((insights.fillRate * 100).rounded()))%",
                      "\(insights.filledJobs)/\(insights.totalJobs) jobs filled")
            if let h = insights.avgFillHours?.doubleValue {
                Divider()
                metricRow(L("time_to_fill_label"), Self.formatHours(h), "Average time to fill a job")
            }
            if let r = insights.noShowRate?.doubleValue {
                Divider()
                metricRow(L("hire_no_show_label"), "\(Int((r * 100).rounded()))%",
                          "\(insights.hireNoShows)/\(insights.totalHires) hires no-showed",
                          valueColor: r >= 0.2 ? GHTheme.hex(0xEF4444) : GHTheme.tertiary)
            }
            if let d = insights.topDistrict {
                Divider()
                metricRow(L("top_district_label"), d, "Where you hire most")
            }
        }
    }

    private var performanceCard: some View {
        whiteCard {
            metricRow(L("avg_response_time"), viewModel.avgResponseTime, "Time to respond to applications")
            Divider()
            metricRow(L("application_rate"), "\(viewModel.applicationRate)%", "Jobs receiving applications")
            Divider()
            metricRow(L("completion_rate_label"), "\(viewModel.completionRate)%", "Jobs completed successfully")
            Divider()
            metricRow(L("avg_rating_given"), String(format: "%.1f", viewModel.avgRatingGiven), "Your rating to workers")
        }
    }

    private var spendingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("total_spent_this_month")).font(.caption).foregroundStyle(.white.opacity(0.85))
            Text(Money.rupees(Double(viewModel.totalSpent), decimals: 0))
                .font(.system(size: 28, weight: .bold)).foregroundStyle(.white)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("avg_per_job_label")).font(.caption2).foregroundStyle(.white.opacity(0.8))
                    Text(Money.rupees(Double(viewModel.avgPerJob), decimals: 0))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("vs Last Month").font(.caption2).foregroundStyle(.white.opacity(0.8))
                    Text("\(viewModel.spendingChange >= 0 ? "+" : "")\(viewModel.spendingChange)%")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [GHTheme.hex(0x059669), GHTheme.hex(0x047857)],
                                   startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 16))
    }

    private var categoriesCard: some View {
        whiteCard {
            ForEach(Array(viewModel.topCategories.enumerated()), id: \.offset) { idx, pair in
                if idx > 0 { Divider() }
                HStack {
                    Text(pair.0).font(.subheadline).foregroundStyle(GHTheme.onBackground).lineLimit(1)
                    Spacer()
                    Text("\(pair.1) jobs").font(.subheadline.weight(.semibold)).foregroundStyle(GHTheme.tertiary)
                }
            }
        }
    }

    // MARK: - Shared bits

    @ViewBuilder
    private func whiteCard<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 14) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(GHTheme.outline, lineWidth: 1))
    }

    private func metricRow(_ label: String, _ value: String, _ desc: String,
                           valueColor: Color = GHTheme.tertiary) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline.weight(.medium)).foregroundStyle(GHTheme.onBackground)
                Text(desc).font(.caption2).foregroundStyle(GHTheme.onSurfaceVariant)
            }
            Spacer()
            Text(value).font(.headline.weight(.bold)).foregroundStyle(valueColor)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.headline.weight(.semibold)).foregroundStyle(GHTheme.onBackground)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func formatHours(_ hours: Double) -> String {
        hours < 1.0 ? "\(Int((hours * 60).rounded()))m" : String(format: "%.1fh", hours)
    }
}

@MainActor
final class AnalyticsViewModel: ObservableObject {
    @Published private(set) var isLoading = true
    @Published private(set) var jobsPosted = 0
    @Published private(set) var totalApplications = 0
    @Published private(set) var workersHired = 0
    @Published private(set) var jobsCompleted = 0
    @Published private(set) var completionRate = 0
    @Published private(set) var totalSpent = 0
    @Published private(set) var avgPerJob = 0
    @Published private(set) var topCategories: [(String, Int)] = []
    @Published private(set) var insights: EmployerInsights?

    // Placeholder metrics (Android shows these as defaults — not yet computed).
    let avgResponseTime = "-"
    let applicationRate = 0
    let avgRatingGiven = 0.0
    let spendingChange = 0

    private let jobs: any JobRepository
    private let applications: any ApplicationRepository
    private let dashboard: any DashboardRepository
    private let employerId: String

    init(jobs: any JobRepository, applications: any ApplicationRepository,
         dashboard: any DashboardRepository, employerId: String) {
        self.jobs = jobs
        self.applications = applications
        self.dashboard = dashboard
        self.employerId = employerId
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        let jobList = (try? await IosHelpersKt.getEmployerJobsOrThrow(jobs, employerId: employerId)) ?? []
        let apps = (try? await IosHelpersKt.getEmployerApplicationsOrThrow(applications, employerId: employerId)) ?? []
        insights = try? await IosHelpersKt.getEmployerInsightsOrThrow(dashboard, employerId: employerId)

        let hiredStatuses: Set<ApplicationStatus> = [
            .selected, .accepted, .otpRequested, .workInProgress,
            .completionPending, .paymentPending, .completed,
        ]
        let completed = apps.filter { $0.status == .completed }
        let hired = apps.filter { hiredStatuses.contains($0.status) }
        let paid = apps.filter { $0.paymentAmount != nil && !($0.paymentDate ?? "").isEmpty }
        let spent = paid.reduce(0.0) { $0 + ($1.paymentAmount?.doubleValue ?? 0) }

        jobsPosted = jobList.count
        totalApplications = apps.count
        workersHired = hired.count
        jobsCompleted = completed.count
        completionRate = hired.isEmpty ? 0 : Int((Double(completed.count) * 100.0 / Double(hired.count)).rounded())
        totalSpent = Int(spent)
        avgPerJob = paid.isEmpty ? 0 : Int(spent / Double(paid.count))

        var categoryMap: [String: Int] = [:]
        for job in jobList {
            let cat = job.jobCategory ?? "Other"
            categoryMap[cat, default: 0] += 1
        }
        topCategories = categoryMap.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }
    }
}
