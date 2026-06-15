import SwiftUI
import Shared

/// Employee profile detail + the sign-out action (replaces the old Account tab).
struct ProfileView: View {

    @StateObject private var viewModel: ProfileViewModel
    let session: AuthData
    let onSignOut: () -> Void

    init(profileRepo: any ProfileRepository, session: AuthData, onSignOut: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: ProfileViewModel(profileRepo: profileRepo, userId: session.userId))
        self.session = session
        self.onSignOut = onSignOut
    }

    var body: some View {
        NavigationStack {
            Form {
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
            .task { await viewModel.load() }
        }
    }
}
