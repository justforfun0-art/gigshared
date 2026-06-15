import Foundation
import Shared

/// In-app notifications over the shared `NotificationRepository`.
@MainActor
final class NotificationsViewModel: ObservableObject {

    enum State {
        case idle, loading
        case loaded([NotificationItem])
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private let notifications: any NotificationRepository

    init(notifications: any NotificationRepository) {
        self.notifications = notifications
    }

    func load() async {
        state = .loading
        do {
            let page = try await IosHelpersKt.getNotificationsOrThrow(notifications, limit: 30, offset: 0)
            state = .loaded(page.items)
        } catch {
            state = .failed((error as NSError).localizedDescription)
        }
    }

    func markAllRead() async {
        _ = try? await notifications.markAllAsRead()
        await load()
    }
}
