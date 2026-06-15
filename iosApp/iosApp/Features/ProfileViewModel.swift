import Foundation
import Shared

/// Employee profile over the shared `ProfileRepository` (read-only for now).
@MainActor
final class ProfileViewModel: ObservableObject {

    enum State {
        case idle, loading
        case loaded(EmployeeProfile?)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private let profileRepo: any ProfileRepository
    private let userId: String

    init(profileRepo: any ProfileRepository, userId: String) {
        self.profileRepo = profileRepo
        self.userId = userId
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
}
