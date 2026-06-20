import SwiftUI
import Shared

/// Employer profile edit form — port of Android's EmployerProfileEditScreen.
/// Loads the existing profile, lets the employer edit company info + location
/// (industry / company-size / state / district via menus, the rest as text),
/// and saves via create/update. Company name + industry are required.
struct EmployerProfileEditView: View {
    let profileRepo: any ProfileRepository
    let userId: String
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: EmployerProfileEditViewModel

    init(profileRepo: any ProfileRepository, userId: String, onSaved: @escaping () -> Void) {
        self.profileRepo = profileRepo
        self.userId = userId
        self.onSaved = onSaved
        _viewModel = StateObject(wrappedValue: EmployerProfileEditViewModel(profileRepo: profileRepo, userId: userId))
    }

    private var accent: Color { GHTheme.tertiary }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    form
                }
            }
            .navigationTitle(L("edit_profile"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("cancel_filter")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Button(L("save")) { Task { await save() } }
                            .disabled(!viewModel.isFormValid)
                            .tint(accent)
                    }
                }
            }
        }
    }

    private var form: some View {
        Form {
            Section(L("company_information")) {
                TextField(L("company_name_required"), text: $viewModel.companyName)
                menuPicker(L("industry_required"), selection: $viewModel.industry, options: IndiaData.industries)
                menuPicker(L("company_size"), selection: $viewModel.companySize, options: IndiaData.companySizes, allowEmpty: true)
                TextField(L("website"), text: $viewModel.website)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField(L("company_description"), text: $viewModel.description, axis: .vertical).lineLimit(3...5)
            }

            Section(L("location_label")) {
                menuPicker(L("state"), selection: $viewModel.state, options: IndiaData.states, allowEmpty: true) {
                    // Reset district when the state changes.
                    viewModel.district = ""
                }
                menuPicker(L("district"), selection: $viewModel.district,
                           options: IndiaData.districts(for: viewModel.state), allowEmpty: true,
                           disabled: viewModel.state.isEmpty)
                TextField(L("full_address"), text: $viewModel.address, axis: .vertical).lineLimit(2...3)
            }

            if let error = viewModel.error {
                Section { Text(error).foregroundStyle(.red).font(.footnote) }
            }
        }
        .disabled(viewModel.isSaving)
        .task { await viewModel.load() }
    }

    private func save() async {
        if await viewModel.save() {
            onSaved()
            dismiss()
        }
    }

    // A read-only field that opens a Menu of options (mirrors Android's ExposedDropdownMenuBox).
    @ViewBuilder
    private func menuPicker(_ label: String, selection: Binding<String>, options: [String],
                            allowEmpty: Bool = false, disabled: Bool = false,
                            onChange: (() -> Void)? = nil) -> some View {
        Menu {
            ForEach(options, id: \.self) { opt in
                Button(opt) { selection.wrappedValue = opt; onChange?() }
            }
        } label: {
            HStack {
                Text(label).foregroundStyle(GHTheme.onBackground)
                Spacer()
                Text(selection.wrappedValue.isEmpty ? L("ios_select") : selection.wrappedValue)
                    .foregroundStyle(selection.wrappedValue.isEmpty ? GHTheme.onSurfaceVariant : accent)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(GHTheme.onSurfaceVariant)
            }
            .contentShape(Rectangle())
        }
        .disabled(disabled)
    }
}

@MainActor
final class EmployerProfileEditViewModel: ObservableObject {
    @Published var companyName = ""
    @Published var industry = ""
    @Published var companySize = ""
    @Published var website = ""
    @Published var description = ""
    @Published var state = ""
    @Published var district = ""
    @Published var address = ""

    @Published private(set) var isLoading = true
    @Published private(set) var isSaving = false
    @Published var error: String?

    private let profileRepo: any ProfileRepository
    private let userId: String
    private var existing: EmployerProfile?

    init(profileRepo: any ProfileRepository, userId: String) {
        self.profileRepo = profileRepo
        self.userId = userId
    }

    var isFormValid: Bool {
        !companyName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !industry.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func load() async {
        guard existing == nil else { return }  // load once
        isLoading = true
        defer { isLoading = false }
        if let p = try? await IosHelpersKt.getEmployerProfileOrThrow(profileRepo, userId: userId) {
            existing = p
            companyName = p.companyName
            industry = p.industry
            companySize = p.companySize ?? ""
            website = p.website ?? ""
            // SKIE renames Kotlin `description` → `description_`.
            description = p.description_ ?? ""
            state = p.state ?? ""
            district = p.district ?? ""
            address = p.address ?? ""
        }
    }

    /// Returns true on a successful save.
    func save() async -> Bool {
        guard isFormValid else { error = "Please fill in all required fields"; return false }
        isSaving = true; error = nil
        defer { isSaving = false }

        func nilIfBlank(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? nil : t
        }

        let profile = EmployerProfile(
            profileId: existing?.profileId ?? UUID().uuidString,
            userId: userId,
            companyName: companyName.trimmingCharacters(in: .whitespaces),
            industry: industry.trimmingCharacters(in: .whitespaces),
            companySize: nilIfBlank(companySize),
            website: nilIfBlank(website),
            description: nilIfBlank(description),
            state: nilIfBlank(state),
            district: nilIfBlank(district),
            address: nilIfBlank(address),
            profilePhotoUrl: existing?.profilePhotoUrl,
            gstNumber: existing?.gstNumber,
            googleMapLocation: existing?.googleMapLocation,
            averageRating: existing?.averageRating,
            totalReviews: existing?.totalReviews,
            createdAt: existing?.createdAt,
            updatedAt: existing?.updatedAt
        )

        do {
            if existing != nil {
                _ = try await IosHelpersKt.updateEmployerProfileOrThrow(profileRepo, profile: profile)
            } else {
                _ = try await IosHelpersKt.createEmployerProfileOrThrow(profileRepo, profile: profile)
            }
            return true
        } catch {
            self.error = (error as NSError).localizedDescription
            return false
        }
    }
}
