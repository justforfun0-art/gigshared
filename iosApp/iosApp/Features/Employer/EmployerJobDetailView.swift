import SwiftUI
import Shared

/// Employer's full job-detail screen — port of Android's EmployerJobDetailsScreen.
/// Job summary, salary summary, a clickable application-overview grid (each tile
/// opens a filtered applicant sheet), description, skills, work timing, location,
/// and preferences. Edit/Delete via the toolbar menu (delete guarded once a
/// worker has progressed). Pure UI over existing shims.
struct EmployerJobDetailView: View {
    let jobs: any JobRepository
    let applications: any ApplicationRepository
    let job: Job
    let profileRepo: (any ProfileRepository)?

    @StateObject private var viewModel: EmployerJobDetailViewModel
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var overviewFilter: OverviewFilter?

    private var accent: Color { GHTheme.hex(0x059669) }

    init(jobs: any JobRepository, applications: any ApplicationRepository, job: Job,
         profileRepo: (any ProfileRepository)? = nil) {
        self.jobs = jobs
        self.applications = applications
        self.job = job
        self.profileRepo = profileRepo
        _viewModel = StateObject(wrappedValue: EmployerJobDetailViewModel(
            jobs: jobs, applications: applications, job: job))
    }

    var body: some View {
        ZStack {
            GHTheme.pageGradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    summaryCard
                    salaryCard
                    overviewCard
                    if !job.description_.isEmpty { card(L("job_description")) { paragraph(job.description_) } }
                    if !job.skillsRequired.isEmpty { card(L("skills_required_label")) { skillChips(job.skillsRequired) } }
                    if hasTimes { card(L("work_timing")) { timingRow } }
                    if !locationLines.isEmpty { card(L("work_location")) { locationBlock } }
                    if hasPreferences { card(L("preferences_label")) { preferencesBlock } }
                }
                .padding(16)
            }
        }
        .navigationTitle(L("job_details"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showEdit = true } label: { Label(L("edit"), systemImage: "pencil") }
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Label(L("delete"), systemImage: "trash")
                    }.disabled(viewModel.deleteLocked)
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .sheet(isPresented: $showEdit) {
            EditJobView(jobs: jobs, job: job) { Task { await viewModel.load() } }
        }
        .sheet(item: $overviewFilter) { filter in
            ApplicantsSheet(title: filter.title, applications: viewModel.applications(for: filter))
        }
        .alert(L("delete_job_title"), isPresented: $showDeleteConfirm) {
            Button(L("cancel_filter"), role: .cancel) {}
            Button(L("delete"), role: .destructive) { Task { await viewModel.delete() } }
        } message: { Text(L("delete_job_confirm")) }
        .alert(L("cannot_delete_job_title"), isPresented: $viewModel.cannotDelete) {
            Button(L("ok"), role: .cancel) {}
        } message: { Text(L("cannot_delete_job_msg")) }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 14).fill(GHTheme.hex(0xECFDF5)).frame(width: 56, height: 56)
                .overlay(Image(systemName: "briefcase.fill").font(.title3).foregroundStyle(accent))
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text(job.title).font(.headline).foregroundStyle(GHTheme.onBackground)
                    Spacer()
                    pill(job.isActive ? L("status_active") : L("status_pending"),
                         job.isActive ? accent : GHTheme.hex(0xD97706),
                         job.isActive ? GHTheme.hex(0xECFDF5) : GHTheme.hex(0xFEF3C7))
                }
                if let loc = summaryLocation { meta("mappin.circle", loc, accent: false) }
                HStack(spacing: 16) {
                    if let pay = job.salaryRange, !pay.isEmpty { meta("indianrupeesign", pay, accent: true) }
                    if let d = fullDate { meta("calendar", d, accent: false) }
                }
                meta("clock", durationLabel ?? "—", accent: false)
                meta("person.2", positionsText, accent: false)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(GHTheme.outline, lineWidth: 1))
    }

    private var salaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("salary_summary")).font(.headline).foregroundStyle(GHTheme.onBackground)
            VStack(spacing: 0) {
                summaryRow(L("hourly_rate"), job.salaryRange ?? "—", bold: false)
                Divider()
                summaryRow(L("work_duration"), job.workDuration ?? durationLabel ?? "—", bold: false)
                Divider()
                summaryRow(L("total_salary"), totalSalary ?? "—", bold: true, color: accent)
            }
            .padding(.horizontal, 16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(GHTheme.outline, lineWidth: 1))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GHTheme.hex(0xECFDF5), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(GHTheme.hex(0xA7F3D0), lineWidth: 1))
    }

    private var overviewCard: some View {
        let c = viewModel.counts
        return VStack(alignment: .leading, spacing: 12) {
            Text(L("application_overview")).font(.headline).foregroundStyle(GHTheme.onBackground)
            HStack(spacing: 12) {
                statTile("\(c.total)", L("jobdetails_stat_total"), GHTheme.hex(0xF1F5F9), GHTheme.onBackground) { overviewFilter = .all }
                statTile("\(c.pending)", L("jobdetails_stat_pending"), GHTheme.hex(0xFEF3C7), GHTheme.hex(0xD97706)) { overviewFilter = .pending }
            }
            HStack(spacing: 12) {
                statTile("\(c.selected)", L("jobdetails_stat_selected"), GHTheme.hex(0xEEF2FF), GHTheme.hex(0x4F46E5)) { overviewFilter = .selected }
                statTile("\(c.working)", L("jobdetails_stat_working"), GHTheme.hex(0xECFDF5), accent) { overviewFilter = .working }
            }
            statTile("\(c.completed)", L("jobdetails_stat_completed"), GHTheme.hex(0xECFDF5), accent, wide: true) { overviewFilter = .completed }
            statTile("\(c.filled)/\(Int(job.numPositions))", L("jobdetails_stat_positions"),
                     c.filled >= Int(job.numPositions) ? GHTheme.hex(0xF1F5F9) : GHTheme.hex(0xFEF3C7),
                     c.filled >= Int(job.numPositions) ? GHTheme.onBackground : GHTheme.hex(0xD97706), wide: true) { overviewFilter = .positions }

            NavigationLink {
                ApplicantsView(applications: applications, job: job, profileRepo: profileRepo)
            } label: {
                HStack { Image(systemName: "person.2.fill"); Text(L("view_all_applicants")).fontWeight(.semibold) }
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(GHTheme.hex(0x10B981), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(GHTheme.outline, lineWidth: 1))
    }

    // MARK: - Detail cards

    private var timingRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(L("start_time_label")).font(.caption).foregroundStyle(GHTheme.onSurfaceVariant)
                Text(job.startTime.flatMap(Self.to12h) ?? "—").font(.subheadline.weight(.semibold)).foregroundStyle(GHTheme.onBackground)
            }
            Spacer()
            Image(systemName: "arrow.right").foregroundStyle(GHTheme.onSurfaceVariant)
            Spacer()
            VStack(alignment: .leading, spacing: 2) {
                Text(L("end_time_label")).font(.caption).foregroundStyle(GHTheme.onSurfaceVariant)
                Text(job.endTime.flatMap(Self.to12h) ?? "—").font(.subheadline.weight(.semibold)).foregroundStyle(GHTheme.onBackground)
            }
        }
    }

    private var locationBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(locationLines.enumerated()), id: \.offset) { idx, line in
                Text(line)
                    .font(idx == 0 ? .subheadline.weight(.medium) : .caption)
                    .foregroundStyle(idx == 0 ? GHTheme.onBackground : GHTheme.onSurfaceVariant)
            }
        }
    }

    private var preferencesBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let g = job.genderPreference, g != "ANY", !g.isEmpty {
                preferenceLine("person", L("gender_label"), g)
            }
            if let langs = job.languagePreference, !langs.isEmpty {
                preferenceLine("globe", L("languages_label"), langs.joined(separator: ", "))
            }
        }
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func card<C: View>(_ title: String, @ViewBuilder _ body: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).foregroundStyle(GHTheme.onBackground)
            body()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(GHTheme.outline, lineWidth: 1))
    }

    private func paragraph(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(GHTheme.onSurfaceVariant)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryRow(_ label: String, _ value: String, bold: Bool, color: Color = GHTheme.onBackground) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(GHTheme.onBackground)
            Spacer()
            Text(value).font(.subheadline.weight(bold ? .bold : .semibold)).foregroundStyle(color)
        }
        .padding(.vertical, 14)
    }

    private func statTile(_ value: String, _ label: String, _ bg: Color, _ fg: Color, wide: Bool = false,
                          _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(value).font(.title2.weight(.bold)).foregroundStyle(fg)
                Text(label).font(.caption).foregroundStyle(GHTheme.onSurfaceVariant)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(bg, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func pill(_ text: String, _ fg: Color, _ bg: Color) -> some View {
        Text(text).font(.caption2.weight(.semibold)).foregroundStyle(fg)
            .padding(.horizontal, 10).padding(.vertical, 4).background(bg, in: Capsule())
    }

    private func meta(_ icon: String, _ text: String, accent isAccent: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(isAccent ? accent : GHTheme.onSurfaceVariant)
            Text(text).font(.subheadline).foregroundStyle(isAccent ? accent : GHTheme.onBackground)
                .fontWeight(isAccent ? .semibold : .regular)
        }
    }

    private func preferenceLine(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(accent).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(GHTheme.onSurfaceVariant)
                Text(value).font(.subheadline).foregroundStyle(GHTheme.onBackground)
            }
        }
    }

    private func skillChips(_ skills: [String]) -> some View {
        let rows = stride(from: 0, to: skills.count, by: 3).map { Array(skills[$0..<min($0 + 3, skills.count)]) }
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { skill in
                        Text(skill).font(.caption.weight(.medium)).foregroundStyle(GHTheme.hex(0x065F46))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(GHTheme.hex(0xA7F3D0), in: Capsule())
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Derived

    private var summaryLocation: String? {
        let ds = [job.district, job.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        return ds.isEmpty ? (job.location.isEmpty ? nil : job.location) : ds
    }

    private var locationLines: [String] {
        let primary = (job.workAddress?.isEmpty == false ? job.workAddress : nil) ?? (job.location.isEmpty ? nil : job.location)
        let ds = [job.district, job.state].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        return [primary, ds.isEmpty || ds == primary ? nil : ds].compactMap { $0 }
    }

    private var hasTimes: Bool { (job.startTime?.isEmpty == false) || (job.endTime?.isEmpty == false) }
    private var hasPreferences: Bool {
        (job.genderPreference != nil && job.genderPreference != "ANY" && job.genderPreference?.isEmpty == false) ||
        (job.languagePreference?.isEmpty == false)
    }

    private var positionsText: String {
        job.numPositions > 1 ? "\(viewModel.counts.filled)/\(Int(job.numPositions)) positions filled" : "1 position"
    }

    private var durationLabel: String? {
        if let wd = job.workDuration, !wd.isEmpty { return wd }
        return Self.computeDuration(job.startTime, job.endTime)
    }

    private var fullDate: String? {
        guard let raw = job.jobDate, let d = ActiveJobBarViewModel.parseISO(String(raw.prefix(10))) else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "d MMM yyyy"
        return f.string(from: d)
    }

    private var totalSalary: String? {
        guard let rate = Self.parseHourlyRate(job.salaryRange),
              let hours = Self.parseDurationHours(job.workDuration, job.startTime, job.endTime) else { return nil }
        return Money.rupees(rate * hours, decimals: 0)
    }

    // MARK: - Static helpers

    static func to12h(_ t: String) -> String? {
        let parts = t.split(separator: ":").compactMap { Int($0) }
        guard let h = parts.first else { return nil }
        let m = parts.count > 1 ? parts[1] : 0
        let suffix = h >= 12 ? "PM" : "AM"
        let h12 = h % 12 == 0 ? 12 : h % 12
        return String(format: "%d:%02d %@", h12, m, suffix)
    }

    static func computeDuration(_ start: String?, _ end: String?) -> String? {
        guard let s = start, let e = end, !s.isEmpty, !e.isEmpty else { return nil }
        let sp = s.split(separator: ":").compactMap { Int($0) }
        let ep = e.split(separator: ":").compactMap { Int($0) }
        guard let sh = sp.first, let eh = ep.first else { return nil }
        var mins = (eh * 60 + (ep.count > 1 ? ep[1] : 0)) - (sh * 60 + (sp.count > 1 ? sp[1] : 0))
        if mins < 0 { mins += 24 * 60 }
        let h = mins / 60, m = mins % 60
        return m == 0 ? "\(h) hours" : "\(h)h \(m)m"
    }

    static func parseHourlyRate(_ salary: String?) -> Double? {
        guard let s = salary else { return nil }
        return Double(s.filter { $0.isNumber || $0 == "." })
    }

    static func parseDurationHours(_ workDuration: String?, _ start: String?, _ end: String?) -> Double? {
        guard let dur = computeDuration(start, end) ?? workDuration else { return nil }
        // Reuse the same h/m parse for the "Nh Mm" / "N hours" forms.
        if let plain = dur.range(of: #"^(\d+(?:\.\d+)?)\s*hours?$"#, options: .regularExpression) {
            return Double(dur[plain].filter { $0.isNumber || $0 == "." })
        }
        var hours = 0.0
        if let hm = dur.range(of: #"(\d+)\s*h"#, options: .regularExpression) {
            hours += Double(dur[hm].filter { $0.isNumber }) ?? 0
        }
        if let mm = dur.range(of: #"(\d+)\s*m"#, options: .regularExpression) {
            hours += (Double(dur[mm].filter { $0.isNumber }) ?? 0) / 60.0
        }
        return hours > 0 ? hours : nil
    }
}

/// Which overview tile was tapped → filters the applicant sheet.
enum OverviewFilter: String, Identifiable {
    case all, pending, selected, working, completed, positions
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return L("applicants_page_title")
        case .pending: return L("jobdetails_stat_pending")
        case .selected: return L("jobdetails_stat_selected")
        case .working: return L("jobdetails_stat_working")
        case .completed: return L("jobdetails_stat_completed")
        case .positions: return L("jobdetails_filled_positions_title")
        }
    }
}

/// A read-only applicant list shown when an overview tile is tapped.
private struct ApplicantsSheet: View {
    let title: String
    let applications: [Application]

    var body: some View {
        NavigationStack {
            Group {
                if applications.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.questionmark").font(.largeTitle).foregroundStyle(.secondary)
                        Text(L("no_applicants")).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(applications, id: \.id) { app in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(app.employeeProfile?.name ?? "Applicant").font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(app.status.toDisplayString()).font(.caption2.weight(.semibold))
                                    .foregroundStyle(GHTheme.tertiary)
                            }
                            if let loc = [app.employeeProfile?.district, app.employeeProfile?.state]
                                .compactMap({ $0 }).filter({ !$0.isEmpty }).first {
                                Text(loc).font(.caption).foregroundStyle(GHTheme.onSurfaceVariant)
                            }
                        }
                        .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

@MainActor
final class EmployerJobDetailViewModel: ObservableObject {
    @Published private(set) var apps: [Application] = []
    @Published var cannotDelete = false

    private let jobs: any JobRepository
    private let applicationsRepo: any ApplicationRepository
    private let job: Job

    init(jobs: any JobRepository, applications: any ApplicationRepository, job: Job) {
        self.jobs = jobs
        self.applicationsRepo = applications
        self.job = job
    }

    func load() async {
        apps = (try? await IosHelpersKt.getApplicationsForJobOrThrow(applicationsRepo, jobId: job.id)) ?? []
    }

    private static let filledStatuses: Set<ApplicationStatus> = [
        .accepted, .otpRequested, .workInProgress, .completionPending, .paymentPending, .completed, .hired,
    ]
    private static let lockedStatuses: Set<ApplicationStatus> = [
        .accepted, .otpRequested, .workInProgress, .completionPending, .paymentPending, .completed, .hired,
    ]

    var deleteLocked: Bool { apps.contains { Self.lockedStatuses.contains($0.status) } }

    var counts: (total: Int, pending: Int, selected: Int, working: Int, completed: Int, filled: Int) {
        (apps.count,
         apps.filter { $0.status == .applied || $0.status == .shortlisted }.count,
         apps.filter { [.selected, .accepted, .otpRequested].contains($0.status) }.count,
         apps.filter { [.workInProgress, .completionPending].contains($0.status) }.count,
         apps.filter { [.completed, .paymentPending].contains($0.status) }.count,
         apps.filter { Self.filledStatuses.contains($0.status) }.count)
    }

    func applications(for filter: OverviewFilter) -> [Application] {
        switch filter {
        case .all: return apps
        case .pending: return apps.filter { $0.status == .applied || $0.status == .shortlisted }
        case .selected: return apps.filter { [.selected, .accepted, .otpRequested].contains($0.status) }
        case .working: return apps.filter { [.workInProgress, .completionPending].contains($0.status) }
        case .completed: return apps.filter { [.completed, .paymentPending].contains($0.status) }
        case .positions: return apps.filter { Self.filledStatuses.contains($0.status) }
        }
    }

    func delete() async {
        do {
            try await IosHelpersKt.deleteJobOrThrow(jobs, jobId: job.id)
        } catch {
            let ns = error as NSError
            if let kt = ns.userInfo["KotlinException"] as? KotlinThrowable,
               IosHelpersKt.isJobHasApplicantsError(error: kt) {
                cannotDelete = true
            }
        }
    }
}
