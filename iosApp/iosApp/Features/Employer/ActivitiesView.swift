import SwiftUI
import Shared

/// Employer Activities — port of Android's ActivitiesScreen. A reverse-chrono
/// timeline derived from the employer's jobs + applications (job posted,
/// application received, selected/rejected, work started/completed, payment).
/// Pure UI over existing shims (employer jobs + applications) — no new Kotlin.
struct ActivitiesView: View {
    let jobs: any JobRepository
    let applications: any ApplicationRepository
    let employerId: String

    @StateObject private var viewModel: ActivitiesViewModel

    init(jobs: any JobRepository, applications: any ApplicationRepository, employerId: String) {
        self.jobs = jobs
        self.applications = applications
        self.employerId = employerId
        _viewModel = StateObject(wrappedValue: ActivitiesViewModel(
            jobs: jobs, applications: applications, employerId: employerId))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GHTheme.pageGradient.ignoresSafeArea()
                content
            }
            .navigationTitle(L("activities_title"))
            .drawerToolbar()
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView()
        } else if viewModel.activities.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath").font(.largeTitle).foregroundStyle(.secondary)
                Text(L("no_activities_yet")).font(.headline)
                Text(L("no_activities_desc")).font(.subheadline).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.activities.enumerated()), id: \.element.id) { idx, act in
                        TimelineRow(activity: act,
                                    isFirst: idx == 0,
                                    isLast: idx == viewModel.activities.count - 1)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 16)
            }
        }
    }
}

private struct TimelineRow: View {
    let activity: ActivityItem
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Connector + dot
            VStack(spacing: 0) {
                Rectangle().fill(isFirst ? Color.clear : GHTheme.outline).frame(width: 2, height: 12)
                Circle().fill(activity.color.opacity(0.1)).frame(width: 32, height: 32)
                    .overlay(Image(systemName: activity.icon).font(.system(size: 14)).foregroundStyle(activity.color))
                if !isLast {
                    Rectangle().fill(GHTheme.outline).frame(width: 2).frame(maxHeight: .infinity)
                }
            }
            .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(activity.title).font(.subheadline.weight(.semibold)).foregroundStyle(GHTheme.onBackground)
                Text(activity.description).font(.caption).foregroundStyle(GHTheme.onSurfaceVariant)
                Text(String(activity.timestamp.prefix(10))).font(.caption2).foregroundStyle(GHTheme.hex(0x9CA3AF))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(GHTheme.outline, lineWidth: 1))
            .padding(.bottom, isLast ? 0 : 8)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct ActivityItem: Identifiable {
    let id: String
    let title: String
    let description: String
    let timestamp: String
    let icon: String
    let color: Color
}

@MainActor
final class ActivitiesViewModel: ObservableObject {
    @Published private(set) var isLoading = true
    @Published private(set) var activities: [ActivityItem] = []

    private let jobs: any JobRepository
    private let applications: any ApplicationRepository
    private let employerId: String

    init(jobs: any JobRepository, applications: any ApplicationRepository, employerId: String) {
        self.jobs = jobs
        self.applications = applications
        self.employerId = employerId
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        let jobList = (try? await IosHelpersKt.getEmployerJobsOrThrow(jobs, employerId: employerId)) ?? []
        let apps = (try? await IosHelpersKt.getEmployerApplicationsOrThrow(applications, employerId: employerId)) ?? []

        var items: [ActivityItem] = []

        for job in jobList {
            items.append(ActivityItem(
                id: "job_\(job.id)", title: "Job Posted",
                description: "\"\(job.title)\" was posted",
                timestamp: job.createdAt ?? "", icon: "briefcase.fill", color: GHTheme.hex(0x3B82F6)))
        }

        let selectedStatuses: Set<ApplicationStatus> = [.selected, .accepted, .workInProgress, .completionPending, .completed, .paymentPending]
        let startedStatuses: Set<ApplicationStatus> = [.workInProgress, .completionPending, .completed, .paymentPending]
        let completedStatuses: Set<ApplicationStatus> = [.completed, .paymentPending]

        for app in apps {
            let jobTitle = app.job?.title ?? "a job"
            let name: String = {
                let n = app.employeeProfile?.name ?? ""
                return n.isEmpty ? "An applicant" : n
            }()

            items.append(ActivityItem(
                id: "applied_\(app.id)", title: "Application Received",
                description: "\(name) applied for \"\(jobTitle)\"",
                timestamp: app.appliedAt ?? app.createdAt ?? "", icon: "person.badge.plus", color: GHTheme.hex(0x059669)))

            if selectedStatuses.contains(app.status) {
                items.append(ActivityItem(
                    id: "selected_\(app.id)", title: "Applicant Selected",
                    description: "\(name) was selected for \"\(jobTitle)\"",
                    timestamp: app.updatedAt ?? app.createdAt ?? "", icon: "checkmark.circle.fill", color: GHTheme.hex(0x14B8A6)))
            }
            if app.status == .rejected {
                items.append(ActivityItem(
                    id: "rejected_\(app.id)", title: "Applicant Rejected",
                    description: "\(name) was not selected for \"\(jobTitle)\"",
                    timestamp: app.updatedAt ?? app.createdAt ?? "", icon: "xmark.circle.fill", color: GHTheme.hex(0xEF4444)))
            }
            if startedStatuses.contains(app.status) {
                items.append(ActivityItem(
                    id: "started_\(app.id)", title: "Work Started",
                    description: "\(name) started work on \"\(jobTitle)\"",
                    timestamp: app.updatedAt ?? "", icon: "play.fill", color: GHTheme.hex(0xF59E0B)))
            }
            if completedStatuses.contains(app.status) {
                items.append(ActivityItem(
                    id: "completed_\(app.id)", title: "Work Completed",
                    description: "\(name) completed work on \"\(jobTitle)\"",
                    timestamp: app.updatedAt ?? "", icon: "checkmark.seal.fill", color: GHTheme.hex(0x8B5CF6)))
            }
            if let amt = app.paymentAmount?.doubleValue, app.paymentStatus == "completed" {
                items.append(ActivityItem(
                    id: "payment_\(app.id)", title: "Payment Processed",
                    description: "\(Money.rupees(amt, decimals: 0)) paid for \"\(jobTitle)\"",
                    timestamp: app.paymentDate ?? app.updatedAt ?? "", icon: "indianrupeesign.circle.fill", color: GHTheme.hex(0x059669)))
            }
        }

        activities = items.sorted { $0.timestamp > $1.timestamp }
    }
}
