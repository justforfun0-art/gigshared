import SwiftUI
import PhotosUI
import Shared

/// Employee profile detail + edit + photo upload + sign-out.
struct ProfileView: View {

    @StateObject private var viewModel: ProfileViewModel
    let session: AuthData
    let onSignOut: () -> Void

    @State private var photoItem: PhotosPickerItem?

    init(profileRepo: any ProfileRepository, session: AuthData, onSignOut: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: ProfileViewModel(profileRepo: profileRepo, userId: session.userId))
        self.session = session
        self.onSignOut = onSignOut
    }

    var body: some View {
        NavigationStack {
            Form {
                photoSection

                Section("Account") {
                    LabeledContent("Phone", value: session.phone)
                    if let type = session.userType {
                        LabeledContent("Role", value: type)
                    }
                }

                switch viewModel.state {
                case .idle, .loading:
                    ProgressView()
                case .loaded(let profile):
                    if let p = profile {
                        Section("Profile") {
                            LabeledContent("Name", value: p.name)
                            LabeledContent("Gender", value: p.gender.toDisplayString())
                            LabeledContent("District", value: p.district)
                            LabeledContent("State", value: p.state)
                            if let email = p.email { LabeledContent("Email", value: email) }
                            if let bio = p.bio, !bio.isEmpty { LabeledContent("Bio", value: bio) }
                            if let skills = p.skills, !skills.isEmpty {
                                LabeledContent("Skills", value: skills.joined(separator: ", "))
                            }
                        }
                    } else {
                        Section { Text("No profile yet").foregroundStyle(.secondary) }
                    }
                case .failed(let message):
                    Section { Text(message).foregroundStyle(.secondary) }
                }

                Section {
                    Button("Sign out", role: .destructive, action: onSignOut)
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                if viewModel.currentProfile != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Edit") { viewModel.isEditing = true }
                    }
                }
            }
            .sheet(isPresented: $viewModel.isEditing) {
                if let profile = viewModel.currentProfile {
                    EditProfileSheet(profile: profile, viewModel: viewModel)
                }
            }
            .task { await viewModel.load() }
            .alert("Something went wrong", isPresented: errorBinding) {
                Button("OK", role: .cancel) { viewModel.actionError = nil }
            } message: { Text(viewModel.actionError ?? "") }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.actionError != nil }, set: { if !$0 { viewModel.actionError = nil } })
    }

    @ViewBuilder
    private var photoSection: some View {
        Section {
            HStack(spacing: 16) {
                avatar
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.currentProfile?.name ?? "—").font(.headline)
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Text(viewModel.isSavingPhoto ? "Uploading…" : "Change photo")
                            .font(.subheadline)
                    }
                    .disabled(viewModel.isSavingPhoto)
                }
                Spacer()
            }
        }
        // Single-parameter onChange for iOS 16 compatibility (the two-param
        // form is iOS 17+; deployment target is 16.0).
        .onChange(of: photoItem) { newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    await viewModel.uploadPhoto(jpegData: data)
                }
                photoItem = nil
            }
        }
    }

    @ViewBuilder
    private var avatar: some View {
        let url = viewModel.currentProfile?.profilePhotoUrl
        if viewModel.isSavingPhoto {
            ProgressView().frame(width: 64, height: 64)
        } else if let url, let parsed = URL(string: url) {
            AsyncImage(url: parsed) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ProgressView()
            }
            .frame(width: 64, height: 64)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable().scaledToFit()
                .frame(width: 64, height: 64)
                .foregroundStyle(.secondary)
        }
    }
}

/// Edit sheet for the user-facing profile fields (name/email/bio/skills).
/// Immutable identity fields (dob, gender, state, district) are shown read-only.
private struct EditProfileSheet: View {
    let profile: EmployeeProfile
    @ObservedObject var viewModel: ProfileViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var email: String
    @State private var bio: String
    @State private var skillsText: String
    @State private var isSaving = false

    init(profile: EmployeeProfile, viewModel: ProfileViewModel) {
        self.profile = profile
        self.viewModel = viewModel
        _name = State(initialValue: profile.name)
        _email = State(initialValue: profile.email ?? "")
        _bio = State(initialValue: profile.bio ?? "")
        _skillsText = State(initialValue: (profile.skills ?? []).joined(separator: ", "))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }
                Section("Bio") {
                    TextField("Tell employers about yourself", text: $bio, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section("Skills") {
                    TextField("Comma-separated (e.g. Cooking, Driving)", text: $skillsText, axis: .vertical)
                        .lineLimit(1...3)
                }
                Section("Not editable here") {
                    LabeledContent("Gender", value: profile.gender.toDisplayString())
                    LabeledContent("District", value: profile.district)
                    LabeledContent("State", value: profile.state)
                }
            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let skills = skillsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let ok = await viewModel.save(name: name, email: email, bio: bio, skills: skills)
        if ok { dismiss() }
    }
}
