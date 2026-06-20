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
    /// Headline stats for the profile (metric tiles + earnings + level), pulled
    /// from the dashboard aggregate — matches Android's EmployeeProfileViewModel.
    @Published private(set) var stats: EmployeeDashboardStats?

    private let profileRepo: any ProfileRepository
    /// Optional so the profile still works if stats can't be fetched.
    private let dashboard: (any DashboardRepository)?
    private let userId: String

    init(profileRepo: any ProfileRepository,
         dashboard: (any DashboardRepository)? = nil,
         userId: String) {
        self.profileRepo = profileRepo
        self.dashboard = dashboard
        self.userId = userId
    }

    /// Real worker rating, averaged from the `reviews` table (reviewee_id =
    /// userId). 0 with ratingCount == 0 means "no reviews yet" → the UI hides
    /// the star row.
    @Published private(set) var rating: Double = 0
    @Published private(set) var ratingCount: Int = 0

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
        // Stats are best-effort — a failure here shouldn't blank the profile.
        if let dashboard {
            stats = try? await dashboard.getEmployeeStatsOrThrow(userId: userId)
        }
        // Composite GigHour Score (best-effort). hasRating==false → provisional
        // worker with no track record → keep rating 0 so the star row hides.
        if let r = try? await IosHelpersKt.getEmployeeRatingOrThrow(profileRepo, userId: userId), r.hasRating {
            rating = r.average
            ratingCount = Int(r.reviewCount)
        } else {
            rating = 0
            ratingCount = 0
        }
    }

    /// Persist edited fields against the loaded profile, then refresh.
    func save(name: String, email: String, bio: String, skills: [String],
              dob: String? = nil, gender: String? = nil,
              stateName: String? = nil, district: String? = nil) async -> Bool {
        guard let existing = currentProfile else { return false }
        actionError = nil
        do {
            let saved = try await IosHelpersKt.editEmployeeProfileOrThrow(
                profileRepo,
                existing: existing,
                name: name.trimmingCharacters(in: .whitespaces),
                email: email,
                bio: bio,
                skills: skills,
                dob: dob,
                gender: gender,
                state: stateName,
                district: district
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
