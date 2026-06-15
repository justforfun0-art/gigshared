import Foundation
import Shared

/// Employee profile over the shared `ProfileRepository`. Loads the profile and
/// supports editing the user-facing fields + uploading a profile photo.
@MainActor
final class ProfileViewModel: ObservableObject {

    enum State {
        case idle, loading
        case loaded(EmployeeProfile?)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published var isEditing = false
    @Published var actionError: String?
    @Published private(set) var isSavingPhoto = false

    private let profileRepo: any ProfileRepository
    private let userId: String

    init(profileRepo: any ProfileRepository, userId: String) {
        self.profileRepo = profileRepo
        self.userId = userId
    }

    /// The currently loaded profile, if any (convenience for the edit sheet).
    var currentProfile: EmployeeProfile? {
        if case let .loaded(profile) = state { return profile }
        return nil
    }

    func load() async {
        state = .loading
        do {
            let profile = try await IosHelpersKt.getEmployeeProfileOrThrow(profileRepo, userId: userId)
            state = .loaded(profile)
        } catch {
            state = .failed((error as NSError).localizedDescription)
        }
    }

    /// Persist edited fields against the loaded profile, then refresh.
    func save(name: String, email: String, bio: String, skills: [String]) async -> Bool {
        guard let existing = currentProfile else { return false }
        actionError = nil
        do {
            let saved = try await IosHelpersKt.editEmployeeProfileOrThrow(
                profileRepo,
                existing: existing,
                name: name.trimmingCharacters(in: .whitespaces),
                email: email,
                bio: bio,
                skills: skills
            )
            state = .loaded(saved)
            return true
        } catch {
            actionError = (error as NSError).localizedDescription
            return false
        }
    }

    /// Upload a freshly picked image (JPEG bytes) and refresh so the new URL shows.
    func uploadPhoto(jpegData: Data) async {
        isSavingPhoto = true; actionError = nil
        defer { isSavingPhoto = false }
        do {
            _ = try await IosHelpersKt.uploadProfilePhotoBase64OrThrow(
                profileRepo,
                userId: userId,
                base64: jpegData.base64EncodedString()
            )
            await load() // pull the row again so profilePhotoUrl reflects the upload
        } catch {
            actionError = (error as NSError).localizedDescription
        }
    }
}
