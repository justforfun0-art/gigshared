import SwiftUI
import Shared

/// Job detail + Apply, with pre-apply intelligence (Android JobDetailsScreen
/// parity): a hire-odds hint (predict_application_success) and a schedule-
/// conflict warning (check_schedule_conflict), both fetched on appear and shown
/// only before the worker applies.
struct JobDetailView: View {

    let job: Job
    let applications: any ApplicationRepository
    let employeeId: String

    @State private var applyState: ApplyState = .idle
    @State private var odds: ApplicationOdds?
    @State private var conflict: ScheduleConflict?
    @State private var loadedIntel = false

    enum ApplyState: Equatable {
        case idle, applying, applied, failed(String)
    }

    private var hasApplied: Bool { applyState == .applied }

    var body: some View {
        Form {
            Section {
                Text(job.title).font(.title3.bold())
                Text(job.location).foregroundStyle(.secondary)
            }

            // Pre-apply intelligence (hidden once applied).
            if !hasApplied {
                if let conflict {
                    Section { ScheduleConflictWarning(conflict: conflict) }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                if let odds {
                    Section { HireOddsHint(odds: odds) }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            Section(L("details")) {
                if let salary = job.salaryRange { LabeledContent("Pay", value: salary) }
                if let date = job.jobDate { LabeledContent("Date", value: date.prefix10) }
                if let start = job.startTime { LabeledContent("Start", value: start) }
                if let end = job.endTime { LabeledContent("End", value: end) }
                LabeledContent("Positions", value: "\(job.numPositions)")
            }
            if !job.skillsRequired.isEmpty {
                Section(L("skills")) {
                    Text(job.skillsRequired.joined(separator: ", "))
                }
            }
            Section {
                applyButton
            }
        }
        .navigationTitle(L("job_label"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadIntel() }
    }

    @ViewBuilder
    private var applyButton: some View {
        switch applyState {
        case .applied:
            Label(L("timeline_applied"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .applying:
            HStack { ProgressView(); Text(L("ios_applying")) }
        default:
            Button(L("ios_apply_for_this_job")) { Task { await apply() } }
                .frame(maxWidth: .infinity)
            if case .failed(let message) = applyState {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func apply() async {
        applyState = .applying
        do {
            _ = try await IosHelpersKt.applyToJobOrThrow(applications, jobId: job.id, employeeId: employeeId)
            applyState = .applied
        } catch {
            applyState = .failed((error as NSError).localizedDescription)
        }
    }

    /// Fetch hire-odds + schedule-conflict once (best-effort; both hide on fail).
    private func loadIntel() async {
        guard !loadedIntel else { return }
        loadedIntel = true
        async let oddsResult = try? IosHelpersKt.predictApplicationSuccessOrThrow(
            applications, jobId: job.id, workerId: employeeId)
        async let conflictResult = try? IosHelpersKt.checkScheduleConflictOrThrow(
            applications, jobId: job.id, workerId: employeeId)
        odds = await oddsResult
        conflict = await conflictResult
    }
}

// MARK: - Hire-odds hint (Android HireOddsHint)

/// Pre-apply hire-odds hint. Competition is the headline driver; subtext nudges
/// "apply early" when the job is crowded. Colour follows the band.
private struct HireOddsHint: View {
    let odds: ApplicationOdds

    private var style: (tint: Color, bg: Color, emoji: String) {
        switch odds.band {
        case "high": return (GHTheme.hex(0x047857), GHTheme.hex(0xECFDF5), "🟢")
        case "low":  return (GHTheme.hex(0xB45309), GHTheme.hex(0xFFFBEB), "🔴")
        default:     return (GHTheme.hex(0xB45309), GHTheme.hex(0xFFFBEB), "🟡")
        }
    }
    private var pct: Int { Int((odds.probability * 100).rounded()) }
    private var crowded: Bool { odds.applicants > odds.positions }

    var body: some View {
        let s = style
        VStack(alignment: .leading, spacing: 4) {
            Text("\(s.emoji) " + L("hire_odds_title", pct))
                .font(.subheadline.weight(.bold)).foregroundStyle(s.tint)
            Text(L("hire_odds_competition", odds.applicants, odds.positions))
                .font(.caption).foregroundStyle(GHTheme.hex(0x374151))
            if crowded {
                Text(L("hire_odds_apply_early"))
                    .font(.caption.weight(.medium)).foregroundStyle(s.tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(s.bg, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Schedule-conflict warning (Android ScheduleConflictWarning)

/// Warns the job overlaps an existing commitment — applying risks a double-book
/// (and a no-show that hurts the worker's reliability).
private struct ScheduleConflictWarning: View {
    let conflict: ScheduleConflict

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.subheadline).foregroundStyle(GHTheme.hex(0xDC2626))
            VStack(alignment: .leading, spacing: 2) {
                Text(L("schedule_conflict_title"))
                    .font(.subheadline.weight(.bold)).foregroundStyle(GHTheme.hex(0x991B1B))
                Text(L("schedule_conflict_detail", conflict.title ?? L("another_job"), window))
                    .font(.caption).foregroundStyle(GHTheme.hex(0x374151))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(GHTheme.hex(0xFEF2F2), in: RoundedRectangle(cornerRadius: 10))
    }

    /// "Jun 18 · 1:15 PM – 5:00 PM" — date · time window, parts dropped if absent.
    private var window: String {
        let times = [conflict.startTime, conflict.endTime]
            .compactMap { $0.flatMap(Self.to12h) }
            .joined(separator: " – ")
        return [conflict.date, times.isEmpty ? nil : times]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// "13:15:00" → "1:15 PM"; falls back to HH:mm on parse failure.
    private static func to12h(_ t: String) -> String? {
        let parts = t.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        let h = parts[0], m = parts[1]
        let ampm = h < 12 ? "AM" : "PM"
        let h12 = h % 12 == 0 ? 12 : h % 12
        return String(format: "%d:%02d %@", h12, m, ampm)
    }
}

private extension String {
    var prefix10: String { String(prefix(10)) }
}
