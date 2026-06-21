import SwiftUI
import Shared

/// Post-a-job form → ApplicationRepository... actually JobRepository.createJob via shim.
struct PostJobView: View {

    let jobs: any JobRepository
    let employerId: String
    /// Optional — enables the ✨ AI auto-fill from the description.
    var jobExtract: (any JobExtractRepository)? = nil
    let onPosted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var location = ""
    @State private var salary = ""
    @State private var state = ""
    @State private var district = ""
    @State private var mapLocation = ""
    @State private var jobDate = Date()
    @State private var startTime = ""
    @State private var endTime = ""
    @State private var positions = 1
    @State private var skills = ""
    @State private var busy = false
    @State private var error: String?
    // AI auto-fill (extract-job).
    @State private var aiBusy = false
    @State private var suggestion: JobSuggestion?
    @State private var category = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(L("job_label")) {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical).lineLimit(2...5)
                    if jobExtract != nil {
                        Button { Task { await autoFill() } } label: {
                            HStack {
                                if aiBusy { ProgressView() }
                                else { Image(systemName: "sparkles") }
                                Text(L("ai_autofill")).fontWeight(.medium)
                            }.foregroundStyle(GHTheme.hex(0x7C3AED))
                        }
                        .disabled(aiBusy || description.trimmingCharacters(in: .whitespaces).count < 8)
                    }
                    if let s = suggestion { suggestionCard(s) }
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
                Section(L("work_location")) {
                    LocationPickerMap(locationString: $mapLocation)
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
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

    /// Call the AI to suggest category/skills/title/description from the free text.
    private func autoFill() async {
        guard let jobExtract else { return }
        aiBusy = true; error = nil
        defer { aiBusy = false }
        do {
            suggestion = try await IosHelpersKt.extractJobOrThrow(jobExtract, text: description)
        } catch {
            self.error = (error as NSError).localizedDescription
        }
    }

    /// A card showing the AI suggestions with one-tap "Apply".
    @ViewBuilder
    private func suggestionCard(_ s: JobSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L("ai_suggestions"), systemImage: "sparkles")
                .font(.caption.weight(.semibold)).foregroundStyle(GHTheme.hex(0x7C3AED))
            if let c = s.category, !c.isEmpty { rowLine(L("category_label"), c) }
            if !s.skills.isEmpty { rowLine(L("skills"), s.skills.joined(separator: ", ")) }
            if let t = s.title, !t.isEmpty { rowLine("Title", t) }
            Button(L("apply_suggestions")) { applySuggestion(s) }
                .font(.caption.weight(.semibold)).buttonStyle(.borderedProminent)
                .tint(GHTheme.hex(0x7C3AED)).controlSize(.small)
        }
        .padding(10)
        .background(GHTheme.hex(0xF5F3FF), in: RoundedRectangle(cornerRadius: 10))
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    private func rowLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label + ":").font(.caption.weight(.medium)).foregroundStyle(GHTheme.onSurfaceVariant)
            Text(value).font(.caption).foregroundStyle(GHTheme.onBackground)
            Spacer(minLength: 0)
        }
    }

    private func applySuggestion(_ s: JobSuggestion) {
        if let t = s.title, !t.isEmpty, title.isEmpty { title = t }
        if let c = s.category, !c.isEmpty { category = c }
        if !s.skills.isEmpty { skills = s.skills.joined(separator: ", ") }
        // SKIE renames the Kotlin `description` field → `description_`.
        if let d = s.description_, !d.isEmpty { description = d }
        suggestion = nil
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
                district: district.isEmpty ? nil : district,
                mapLocation: mapLocation.isEmpty ? nil : mapLocation,
                jobCategory: category.isEmpty ? nil : category
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
