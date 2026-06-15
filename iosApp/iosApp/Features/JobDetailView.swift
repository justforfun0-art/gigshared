import SwiftUI
import Shared

/// Job detail + Apply. Applies via the shared ApplicationRepository using the
/// signed-in worker's id.
struct JobDetailView: View {

    let job: Job
    let applications: any ApplicationRepository
    let employeeId: String

    @State private var applyState: ApplyState = .idle

    enum ApplyState: Equatable {
        case idle, applying, applied, failed(String)
    }

    var body: some View {
        Form {
            Section {
                Text(job.title).font(.title3.bold())
                Text(job.location).foregroundStyle(.secondary)
            }
            Section("Details") {
                if let salary = job.salaryRange { LabeledContent("Pay", value: salary) }
                if let date = job.jobDate { LabeledContent("Date", value: date.prefix10) }
                if let start = job.startTime { LabeledContent("Start", value: start) }
                if let end = job.endTime { LabeledContent("End", value: end) }
                LabeledContent("Positions", value: "\(job.numPositions)")
            }
            if !job.skillsRequired.isEmpty {
                Section("Skills") {
                    Text(job.skillsRequired.joined(separator: ", "))
                }
            }
            Section {
                applyButton
            }
        }
        .navigationTitle("Job")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var applyButton: some View {
        switch applyState {
        case .applied:
            Label("Applied", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .applying:
            HStack { ProgressView(); Text("Applying…") }
        default:
            Button("Apply for this job") { Task { await apply() } }
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
}

private extension String {
    var prefix10: String { String(prefix(10)) }
}
