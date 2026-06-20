import SwiftUI
import Shared

/// Employee "Hawkeye" analytics — port of Android's HawkeyeScreen. Your
/// Performance (applied / completed / active / success-rate), an applications
/// breakdown by status, and a monthly-activity bar chart. Derived entirely from
/// the worker's own applications (existing getEmployeeApplications shim).
struct HawkeyeView: View {
    let applications: any ApplicationRepository
    let employeeId: String

    @StateObject private var viewModel: HawkeyeViewModel

    init(applications: any ApplicationRepository, employeeId: String) {
        self.applications = applications
        self.employeeId = employeeId
        _viewModel = StateObject(wrappedValue: HawkeyeViewModel(applications: applications, employeeId: employeeId))
    }

    private var accent: Color { GHTheme.hex(0x7C3AED) }

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
            .navigationTitle(L("hawkeye_analytics"))
            .drawerToolbar()
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionLabel("Your Performance")
                performanceGrid

                sectionLabel("Applications Breakdown")
                if viewModel.breakdown.isEmpty {
                    emptyHint("No applications yet")
                } else {
                    breakdownCard
                }

                sectionLabel("Monthly Activity")
                if viewModel.monthly.allSatisfy({ $0.count == 0 }) {
                    emptyHint("No activity data yet")
                } else {
                    monthlyCard
                }
            }
            .padding(16)
        }
    }

    private var performanceGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                stat("Jobs Applied", "\(viewModel.totalApplications)", "paperplane.fill", GHTheme.hex(0x7C3AED))
                stat("Completed", "\(viewModel.completedJobs)", "checkmark.seal.fill", GHTheme.hex(0x059669))
            }
            HStack(spacing: 12) {
                stat("Active", "\(viewModel.activeApplications)", "bolt.fill", GHTheme.hex(0xF59E0B))
                stat("Success Rate", "\(viewModel.successRate)%", "chart.bar.fill", GHTheme.hex(0x3B82F6))
            }
        }
    }

    private func stat(_ label: String, _ value: String, _ icon: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.title3).foregroundStyle(tint)
            Text(value).font(.title2.weight(.bold)).foregroundStyle(GHTheme.onBackground)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(GHTheme.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
    }

    private var breakdownCard: some View {
        whiteCard {
            ForEach(Array(viewModel.breakdown.enumerated()), id: \.offset) { idx, pair in
                if idx > 0 { Divider() }
                HStack {
                    Text(pair.0).font(.subheadline).foregroundStyle(GHTheme.onBackground)
                    Spacer()
                    Text("\(pair.1)").font(.subheadline.weight(.bold)).foregroundStyle(accent)
                }
            }
        }
    }

    private var monthlyCard: some View {
        whiteCard {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(viewModel.monthly, id: \.month) { m in
                    VStack(spacing: 4) {
                        Text("\(m.count)").font(.system(size: 9)).foregroundStyle(GHTheme.onSurfaceVariant)
                            .opacity(m.count > 0 ? 1 : 0)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(m.count > 0 ? accent : GHTheme.outline)
                            .frame(height: max(4, CGFloat(m.fraction) * 90))
                        Text(m.month).font(.system(size: 9)).foregroundStyle(GHTheme.onSurfaceVariant)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 130, alignment: .bottom)
        }
    }

    @ViewBuilder
    private func whiteCard<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(GHTheme.outline, lineWidth: 1))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.headline.weight(.semibold)).foregroundStyle(GHTheme.onBackground)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(GHTheme.onSurfaceVariant)
            .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 20)
    }
}

@MainActor
final class HawkeyeViewModel: ObservableObject {
    @Published private(set) var isLoading = true
    @Published private(set) var totalApplications = 0
    @Published private(set) var completedJobs = 0
    @Published private(set) var successRate = 0
    @Published private(set) var activeApplications = 0
    @Published private(set) var breakdown: [(String, Int)] = []
    @Published private(set) var monthly: [MonthlyData] = []

    struct MonthlyData { let month: String; let count: Int; let fraction: Double }

    private let applications: any ApplicationRepository
    private let employeeId: String

    init(applications: any ApplicationRepository, employeeId: String) {
        self.applications = applications
        self.employeeId = employeeId
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        let apps = (try? await IosHelpersKt.getEmployeeApplicationsOrThrow(applications, employeeId: employeeId)) ?? []
        totalApplications = apps.count
        completedJobs = apps.filter { $0.status == .completed }.count
        successRate = apps.isEmpty ? 0 : Int(Double(completedJobs) / Double(apps.count) * 100)
        activeApplications = apps.filter { $0.status.isActive() }.count

        // Status breakdown (label → count), most common first.
        var counts: [String: Int] = [:]
        for app in apps {
            counts[app.status.toDisplayString(), default: 0] += 1
        }
        breakdown = counts.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }

        monthly = Self.buildMonthly(apps)
    }

    private static func buildMonthly(_ apps: [Application]) -> [MonthlyData] {
        let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                     "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        var counts = [Int](repeating: 0, count: 12)
        for app in apps {
            guard let created = app.createdAt, created.count >= 7 else { continue }
            // "YYYY-MM-..." → month index from chars 5..6
            let start = created.index(created.startIndex, offsetBy: 5)
            let end = created.index(created.startIndex, offsetBy: 7)
            if let m = Int(created[start..<end]), m >= 1, m <= 12 { counts[m - 1] += 1 }
        }
        let maxCount = counts.max() ?? 1
        return names.enumerated().map { idx, name in
            MonthlyData(month: name, count: counts[idx],
                        fraction: maxCount > 0 ? Double(counts[idx]) / Double(maxCount) : 0)
        }
    }
}
