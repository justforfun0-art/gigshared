import SwiftUI
import Shared

/// `Job` carries a stable `id`, so it can drive `sheet(item:)`.
extension Job: Identifiable {}

/// Edit an existing job — port of Android's EditJobScreen. Pre-fills the form
/// from the job and persists via the new updateJob shim. Mirrors PostJobView's
/// layout (the create counterpart) with State/District menu pickers.
struct EditJobView: View {
    let jobs: any JobRepository
    let job: Job
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var description: String
    @State private var location: String
    @State private var salary: String
    @State private var state: String
    @State private var district: String
    @State private var jobDate: Date
    @State private var startTime: String
    @State private var endTime: String
    @State private var positions: Int
    @State private var skills: String
    @State private var mapLocation: String
    @State private var busy = false
    @State private var error: String?

    init(jobs: any JobRepository, job: Job, onSaved: @escaping () -> Void) {
        self.jobs = jobs
        self.job = job
        self.onSaved = onSaved
        _title = State(initialValue: job.title)
        _description = State(initialValue: job.description_)
        _location = State(initialValue: job.location)
        _salary = State(initialValue: job.salaryRange ?? "")
        _state = State(initialValue: job.state ?? "")
        _district = State(initialValue: job.district ?? "")
        _jobDate = State(initialValue: job.jobDate.flatMap { ActiveJobBarViewModel.parseISO(String($0.prefix(10))) } ?? Date())
        _startTime = State(initialValue: job.startTime ?? "")
        _endTime = State(initialValue: job.endTime ?? "")
        _positions = State(initialValue: Int(job.numPositions))
        _skills = State(initialValue: job.skillsRequired.joined(separator: ", "))
        _mapLocation = State(initialValue: job.workGoogleMapLocation ?? "")
    }

    private var accent: Color { GHTheme.tertiary }

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
                    menuPicker(L("state"), selection: $state, options: IndiaData.states) { district = "" }
                    menuPicker(L("district"), selection: $district,
                               options: IndiaData.districts(for: state), disabled: state.isEmpty)
                    DatePicker("Date", selection: $jobDate, displayedComponents: .date)
                    TextField("Start (HH:mm)", text: $startTime)
                    TextField("End (HH:mm)", text: $endTime)
                    Stepper("Positions: \(positions)", value: $positions, in: 1...50)
                }
                Section(L("work_location")) {
                    LocationPickerMap(locationString: $mapLocation)
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                Section(L("ios_skills_comma_separated")) {
                    TextField("e.g. lifting, packing", text: $skills)
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
            }
            .navigationTitle(L("edit_job_title"))
            .navigationBarTitleDisplayMode(.inline)
            .disabled(busy)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("cancel_filter")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else {
                        Button(L("save")) { Task { await save() } }
                            .disabled(title.isEmpty || description.isEmpty || location.isEmpty)
                            .tint(accent)
                    }
                }
            }
        }
    }

    private func save() async {
        busy = true; error = nil
        defer { busy = false }
        let skillList = skills.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        do {
            _ = try await IosHelpersKt.updateJobOrThrow(
                jobs,
                jobId: job.id,
                employerId: job.employerId,
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
                district: district.isEmpty ? nil : district,
                jobCategory: job.jobCategory,
                mapLocation: mapLocation.isEmpty ? nil : mapLocation
            )
            onSaved()
            dismiss()
        } catch {
            self.error = (error as NSError).localizedDescription
        }
    }

    @ViewBuilder
    private func menuPicker(_ label: String, selection: Binding<String>, options: [String],
                            disabled: Bool = false, onChange: (() -> Void)? = nil) -> some View {
        Menu {
            ForEach(options, id: \.self) { opt in
                Button(opt) { selection.wrappedValue = opt; onChange?() }
            }
        } label: {
            HStack {
                Text(label).foregroundStyle(GHTheme.onBackground)
                Spacer()
                Text(selection.wrappedValue.isEmpty ? L("ios_select") : selection.wrappedValue)
                    .foregroundStyle(selection.wrappedValue.isEmpty ? GHTheme.onSurfaceVariant : accent).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(GHTheme.onSurfaceVariant)
            }
            .contentShape(Rectangle())
        }
        .disabled(disabled)
    }

    private static func isoDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Kolkata")
        return f.string(from: date)
    }
}
