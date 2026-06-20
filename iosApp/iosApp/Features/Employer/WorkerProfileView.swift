import SwiftUI
import Shared

/// Employer's view of a worker's full profile — port of Android's
/// EmployeeProfileViewScreen. Emerald gradient header (avatar/name/location +
/// rating), a stats row (jobs done / completion / member-since), bio, personal
/// details, skills, languages, and recent reviews. Opened from the applicants
/// list. Uses getEmployeeProfile + getEmployeeRating + getEmployeeReviews shims.
struct WorkerProfileView: View {
    let profileRepo: any ProfileRepository
    let employeeId: String

    @StateObject private var viewModel: WorkerProfileViewModel
    private var accent: Color { GHTheme.tertiary }

    init(profileRepo: any ProfileRepository, employeeId: String) {
        self.profileRepo = profileRepo
        self.employeeId = employeeId
        _viewModel = StateObject(wrappedValue: WorkerProfileViewModel(profileRepo: profileRepo, employeeId: employeeId))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GHTheme.pageGradient.ignoresSafeArea()
                content
            }
            .navigationTitle(L("worker_profile"))
            .navigationBarTitleDisplayMode(.inline)
            .task { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView()
        } else if let p = viewModel.profile {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header(p)
                    statsRow
                    if let bio = p.bio, !bio.isEmpty { card(L("about_section_label")) { paragraph(bio) } }
                    personalDetails(p)
                    if let skills = p.skills, !skills.isEmpty { card(L("skills_required_label")) { chips(skills) } }
                    if !viewModel.reviews.isEmpty { card(L("reviews")) { reviewsList } }
                }
                .padding(16)
            }
        } else {
            Text(viewModel.error ?? "Worker not found").foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ p: EmployeeProfile) -> some View {
        VStack(spacing: 8) {
            Circle().fill(Color.white.opacity(0.2)).frame(width: 80, height: 80)
                .overlay(Text(String(p.name.prefix(2)).uppercased()).font(.title.weight(.bold)).foregroundStyle(.white))
            Text(p.name).font(.title3.weight(.bold)).foregroundStyle(.white)
            Text("\(p.district), \(p.state)").font(.subheadline).foregroundStyle(.white.opacity(0.9))
            HStack(spacing: 4) {
                Image(systemName: "star.fill").foregroundStyle(GHTheme.hex(0xFFC107))
                Text(viewModel.averageRating > 0 ? String(format: "%.1f", viewModel.averageRating) : "—")
                    .font(.headline).foregroundStyle(.white)
                Text("(\(viewModel.totalReviews) \(L("reviews")))").font(.caption).foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(LinearGradient(colors: [GHTheme.hex(0x059669), GHTheme.hex(0x047857)],
                                   startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 16))
    }

    private var statsRow: some View {
        whiteCard {
            HStack {
                statItem("\(viewModel.jobsCompleted)", L("jobs_done"), "checkmark.circle")
                Spacer()
                statItem("\(viewModel.completionRate)%", L("completion_label"), "chart.line.uptrend.xyaxis")
                Spacer()
                statItem(viewModel.memberSince, L("member_since_info_label"), "calendar")
            }
        }
    }

    private func statItem(_ value: String, _ label: String, _ icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.subheadline).foregroundStyle(accent)
            Text(value).font(.subheadline.weight(.bold)).foregroundStyle(GHTheme.onBackground).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(GHTheme.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity)
    }

    private func personalDetails(_ p: EmployeeProfile) -> some View {
        card(L("personal_details_label")) {
            detail("person", L("gender_label"), p.gender.toDisplayString())
            if let e = p.email, !e.isEmpty { detail("envelope", L("email"), e) }
            detail("mappin.and.ellipse", L("location_label"), "\(p.district), \(p.state)")
            if let langs = p.languagesKnown, !langs.isEmpty { detail("globe", L("languages_label"), langs.joined(separator: ", ")) }
            if let h = p.preferredWorkingHours, !h.isEmpty { detail("clock", L("preferred_hours"), h) }
            if let f = p.fitnessLevel, !f.isEmpty { detail("figure.run", L("fitness_level"), f) }
            if let c = p.hasComputerKnowledge?.boolValue { detail("desktopcomputer", L("computer_skills"), c ? L("yes") : L("no")) }
        }
    }

    private var reviewsList: some View {
        ForEach(Array(viewModel.reviews.enumerated()), id: \.offset) { idx, r in
            if idx > 0 { Divider() }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(r.reviewerName).font(.subheadline.weight(.semibold)).foregroundStyle(GHTheme.onBackground)
                    Spacer()
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { i in
                            Image(systemName: i <= Int(r.rating) ? "star.fill" : "star")
                                .font(.caption2).foregroundStyle(GHTheme.hex(0xFFC107))
                        }
                    }
                }
                if !r.comment.isEmpty {
                    Text(r.comment).font(.caption).foregroundStyle(GHTheme.onSurfaceVariant)
                }
            }
        }
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func card<C: View>(_ title: String, @ViewBuilder _ body: () -> C) -> some View {
        whiteCard {
            Text(title).font(.headline.weight(.semibold)).foregroundStyle(GHTheme.onBackground)
            body()
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

    private func paragraph(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(GHTheme.onSurfaceVariant)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detail(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(accent).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(GHTheme.onSurfaceVariant)
                Text(value).font(.subheadline.weight(.medium)).foregroundStyle(GHTheme.onBackground)
            }
            Spacer()
        }
    }

    private func chips(_ items: [String]) -> some View {
        FlexChips(items: items, fg: accent, bg: accent.opacity(0.1))
    }
}

/// Lightweight wrapping chip layout (skills).
private struct FlexChips: View {
    let items: [String]
    let fg: Color
    let bg: Color

    var body: some View {
        // Three-per-row wrap — adequate for the typical handful of skills.
        let rows = stride(from: 0, to: items.count, by: 3).map { Array(items[$0..<min($0 + 3, items.count)]) }
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { item in
                        Text(item).font(.caption.weight(.medium)).foregroundStyle(fg)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(bg, in: Capsule())
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
final class WorkerProfileViewModel: ObservableObject {
    @Published private(set) var isLoading = true
    @Published private(set) var profile: EmployeeProfile?
    @Published private(set) var averageRating = 0.0
    @Published private(set) var totalReviews = 0
    @Published private(set) var jobsCompleted = 0
    @Published private(set) var completionRate = 0
    @Published private(set) var memberSince = "—"
    @Published private(set) var reviews: [EmployeeReview] = []
    @Published private(set) var error: String?

    private let profileRepo: any ProfileRepository
    private let employeeId: String

    init(profileRepo: any ProfileRepository, employeeId: String) {
        self.profileRepo = profileRepo
        self.employeeId = employeeId
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            profile = try await IosHelpersKt.getEmployeeProfileOrThrow(profileRepo, userId: employeeId)
        } catch {
            self.error = (error as NSError).localizedDescription
        }
        if let p = profile { memberSince = Self.memberSince(p.createdAt) }

        // Composite rating (avg + count) and the recent reviews list.
        if let r = try? await IosHelpersKt.getEmployeeRatingOrThrow(profileRepo, userId: employeeId) {
            averageRating = r.average
            totalReviews = Int(r.reviewCount)
            jobsCompleted = Int(r.sampleCount)
            if let cr = r.completionRate?.doubleValue { completionRate = Int((cr * 100).rounded()) }
        }
        reviews = (try? await IosHelpersKt.getEmployeeReviewsOrThrow(profileRepo, userId: employeeId)) ?? []
        if totalReviews == 0 { totalReviews = reviews.count }
    }

    private static func memberSince(_ createdAt: String?) -> String {
        guard let createdAt, !createdAt.isEmpty,
              let d = ActiveJobBarViewModel.parseISO(createdAt) else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM yyyy"
        return f.string(from: d)
    }
}
