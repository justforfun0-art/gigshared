import SwiftUI
import Shared

/// Post-a-job form → ApplicationRepository... actually JobRepository.createJob via shim.
struct PostJobView: View {

    let jobs: any JobRepository
    let employerId: String
    let onPosted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var location = ""
    @State private var salary = ""
    @State private var state = ""
    @State private var district = ""
    @State private var jobDate = Date()
    @State private var startTime = ""
    @State private var endTime = ""
    @State private var positions = 1
    @State private var skills = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(L("job_label")) {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical).lineLimit(2...5)
                    TextField("Location", text: $location)
                    TextField("Pay (e.g. ₹150/hr)", text: $salary)
                }
                Section(L("ios_where_when")) {
                    TextField("State", text: $state)
                    TextField("District", text: $district)
                    DatePicker("Date", selection: $jobDate, displayedComponents: .date)
                    TextField("Start (HH:mm)", text: $startTime)
                    TextField("End (HH:mm)", text: $endTime)
                    Stepper("Positions: \(positions)", value: $positions, in: 1...50)
                }
                Section(L("ios_skills_comma_separated")) {
                    TextField("e.g. lifting, packing", text: $skills)
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
            }
            .navigationTitle(L("onboarding_employer_title_3"))
            .disabled(busy)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("cancel_filter")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("ios_post")) { Task { await post() } }
                        .disabled(title.isEmpty || description.isEmpty || location.isEmpty)
                }
            }
        }
    }

    private func post() async {
        busy = true; error = nil
        defer { busy = false }
        let skillList = skills.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        do {
            _ = try await IosHelpersKt.createJobOrThrow(
                jobs,
                employerId: employerId,
                title: title,
                description: description,
                location: location,
                salaryRange: salary.isEmpty ? nil : salary,
                jobDate: Self.isoDate(jobDate),
                startTime: startTime.isEmpty ? nil : startTime,
                endTime: endTime.isEmpty ? nil : endTime,
                numPositions: Int32(positions),
                skillsRequired: skillList,
                state: state.isEmpty ? nil : state,
                district: district.isEmpty ? nil : district
            )
            onPosted()
            dismiss()
        } catch {
            self.error = (error as NSError).localizedDescription
        }
    }

    private static func isoDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Kolkata")
        return f.string(from: date)
    }
}
