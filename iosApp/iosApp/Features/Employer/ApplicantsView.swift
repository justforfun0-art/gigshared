import SwiftUI
import Shared

/// A String wrapped to satisfy `Identifiable` for `sheet(item:)`.
struct IdentifiedString: Identifiable { let id: String }

/// Applicants for a job: each row shows the worker + a context action based on
/// the application status (Review→select/reject, Accepted→start OTP,
/// CompletionPending→completion OTP, etc).
struct ApplicantsView: View {

    @StateObject private var viewModel: ApplicantsViewModel
    let job: Job
    /// Optional — when provided, tapping a worker opens their full profile.
    let profileRepo: (any ProfileRepository)?
    @State private var viewingWorkerId: String?

    init(applications: any ApplicationRepository, job: Job, profileRepo: (any ProfileRepository)? = nil) {
        _viewModel = StateObject(wrappedValue: ApplicantsViewModel(
            applications: applications, jobId: job.id, employerId: job.employerId
        ))
        self.job = job
        self.profileRepo = profileRepo
    }

    var body: some View {
        content
            .navigationTitle(job.title)
            .navigationBarTitleDisplayMode(.inline)
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .alert("Action failed", isPresented: errorBinding) {
                Button(L("ok"), role: .cancel) { viewModel.actionError = nil }
            } message: { Text(viewModel.actionError ?? "") }
            .alert("Share this OTP", isPresented: otpBinding) {
                Button(L("done"), role: .cancel) { viewModel.presentedOtp = nil }
            } message: { Text(viewModel.presentedOtp ?? "") }
            .sheet(item: $viewModel.verifyingCompletion) { app in
                CompletionCodeSheet(app: app, viewModel: viewModel)
            }
            .sheet(item: workerSheetBinding) { wrapped in
                if let profileRepo {
                    WorkerProfileView(profileRepo: profileRepo, employeeId: wrapped.id)
                }
            }
    }

    /// Wrap the worker-id String so it can drive `sheet(item:)`.
    private var workerSheetBinding: Binding<IdentifiedString?> {
        Binding(get: { viewingWorkerId.map(IdentifiedString.init) },
                set: { viewingWorkerId = $0?.id })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.actionError != nil }, set: { if !$0 { viewModel.actionError = nil } })
    }
    private var otpBinding: Binding<Bool> {
        Binding(get: { viewModel.presentedOtp != nil }, set: { if !$0 { viewModel.presentedOtp = nil } })
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Loading…")
        case .loaded(let apps):
            if apps.isEmpty {
                Text(L("no_applicants_yet")).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(apps, id: \.id) { app in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(app.employeeProfile?.name ?? "Applicant").font(.headline)
                            if let eid = app.employeeProfile?.userId, eid == viewModel.topMatchEmployeeId {
                                TopMatchBadge()
                            }
                            Spacer()
                            if profileRepo != nil, let eid = app.employeeProfile?.userId {
                                Button { viewingWorkerId = eid } label: {
                                    Image(systemName: "person.text.rectangle").foregroundStyle(GHTheme.tertiary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Text(app.status.toDisplayString()).font(.caption).foregroundStyle(.secondary)
                        // No-show risk flag (medium/high only).
                        if let risk = viewModel.noShowRiskByApp[app.id] {
                            NoShowRiskBadge(risk: risk)
                        }
                        // "Why ranked here" — mutual-fit breakdown.
                        if let eid = app.employeeProfile?.userId, let rank = viewModel.ranksByEmployee[eid],
                           !rank.breakdown.isEmpty {
                            RankBreakdown(rank: rank)
                        }
                        actions(for: app)
                    }
                    .padding(.vertical, 2)
                }
            }
        case .failed(let message):
            VStack(spacing: 12) {
                Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
                Button(L("retry_btn")) { Task { await viewModel.load() } }.buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private func actions(for app: Application) -> some View {
        let s = app.status
        HStack(spacing: 8) {
            if s == ApplicationStatus.applied || s == ApplicationStatus.shortlisted {
                Button(L("select")) { Task { await viewModel.select(app) } }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Button(L("reject"), role: .destructive) { Task { await viewModel.reject(app) } }
                    .buttonStyle(.bordered).controlSize(.small)
            } else if s == ApplicationStatus.accepted {
                Button(L("status_help_generate_start_otp")) { Task { await viewModel.generateStartOtp(app) } }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            } else if s == ApplicationStatus.workInProgress {
                Label(L("status_work_in_progress"), systemImage: "clock")
                    .font(.caption).foregroundStyle(.orange)
            } else if s == ApplicationStatus.completionPending {
                Button(L("status_help_enter_completion_code")) { viewModel.beginCompletionVerify(app) }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
    }
}

/// Modal where the employer types the 6-digit completion code the worker read
/// out, finishing the gig (`verifyCompletionOtp`).
private struct CompletionCodeSheet: View {
    let app: Application
    @ObservedObject var viewModel: ApplicantsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(app.employeeProfile?.name ?? "Worker").font(.headline)
                    Text(L("ios_ask_the_worker_for_their_completion_code"))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section {
                    TextField("6-digit code", text: $viewModel.completionInput)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .font(.title2.monospaced())
                }
                if let err = viewModel.actionError {
                    Section { Text(err).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle(L("ios_complete_gig"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("cancel_filter")) { viewModel.verifyingCompletion = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("payment_finish_btn")) { Task { await viewModel.submitCompletionCode() } }
                        .disabled(viewModel.isVerifying
                                  || viewModel.completionInput.trimmingCharacters(in: .whitespaces).count != 6)
                }
            }
        }
    }
}

// MARK: - Applicant intelligence badges (Android ApplicantsScreen parity)

/// ⭐ Top-match badge on the clear ranking leader.
private struct TopMatchBadge: View {
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "star.fill").font(.system(size: 10))
            Text(L("top_match")).font(.caption2.weight(.bold))
        }
        .foregroundStyle(GHTheme.hex(0x059669))
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(GHTheme.hex(0x059669).opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// No-show risk flag for a hired applicant (high=red, medium=amber) + history.
private struct NoShowRiskBadge: View {
    let risk: NoShowRisk
    var body: some View {
        let high = risk.band == "high"
        let tint = high ? GHTheme.hex(0xDC2626) : GHTheme.hex(0xB45309)
        let bg = high ? GHTheme.hex(0xFEF2F2) : GHTheme.hex(0xFFFBEB)
        return HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(tint)
            Text("\(high ? L("no_show_risk_high") : L("no_show_risk_medium")) · \(detail)")
                .font(.caption.weight(.medium)).foregroundStyle(tint)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(bg, in: RoundedRectangle(cornerRadius: 8))
    }
    private var detail: String {
        risk.priorCommitments > 0
            ? L("no_show_risk_history", Int(risk.priorNoShows), Int(risk.priorCommitments))
            : L("no_show_risk_new")
    }
}

/// Per-signal mutual-fit bars ("why ranked here").
private struct RankBreakdown: View {
    let rank: CandidateRank
    private static let rows: [(String, String)] = [
        ("reliability", "signal_reliability"), ("skillMatch", "signal_skill_match"),
        ("proximity", "signal_proximity"), ("rating", "signal_rating"),
        ("trackRecord", "signal_track_record"), ("responsiveness", "signal_responsiveness"),
    ]
    var body: some View {
        VStack(spacing: 3) {
            ForEach(Self.rows, id: \.0) { key, labelKey in
                if let v = rank.breakdown[key]?.doubleValue {
                    SignalBar(label: L(labelKey), fraction: min(max(v, 0), 1), color: GHTheme.hex(0x059669))
                }
            }
            if let pen = rank.breakdown["noShowPenalty"]?.doubleValue, pen > 0 {
                SignalBar(label: L("signal_no_show"), fraction: min(max(pen, 0), 1), color: GHTheme.hex(0xEF4444))
            }
        }
        .padding(.top, 6)
    }
}

private struct SignalBar: View {
    let label: String
    let fraction: Double
    let color: Color
    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.caption2).foregroundStyle(GHTheme.onSurfaceVariant)
                .frame(width: 96, alignment: .leading).lineLimit(1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(GHTheme.outline.opacity(0.5)).frame(height: 6)
                    Capsule().fill(color).frame(width: geo.size.width * fraction, height: 6)
                }
            }
            .frame(height: 6)
        }
    }
}

/// `Application` comes from the Kotlin framework without Swift's `Identifiable`;
/// its stable `id` lets it drive `sheet(item:)` / `ForEach`.
extension Application: Identifiable {}
