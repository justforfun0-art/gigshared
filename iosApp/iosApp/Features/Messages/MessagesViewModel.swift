import Foundation
import Shared

/// The conversations inbox. Loads the user's conversations, then enriches each
/// with the other participant's name/avatar and a last-message + unread summary.
@MainActor
final class MessagesViewModel: ObservableObject {

    struct Row: Identifiable {
        let id: String              // conversation id
        let otherUserId: String
        let name: String
        let photoUrl: String?
        let lastMessage: String
        let lastMessageAt: String?
        let unread: Int
    }

    enum State { case idle, loading, loaded([Row]), failed(String) }
    @Published private(set) var state: State = .idle

    private let repo: any MessageRepository
    let myUserId: String

    init(repo: any MessageRepository, myUserId: String) {
        self.repo = repo
        self.myUserId = myUserId
    }

    func load() async {
        state = .loading
        do {
            let convos = try await IosHelpersKt.getConversationsOrThrow(repo, userId: myUserId)
            if convos.isEmpty { state = .loaded([]); return }

            let ids = convos.map(\.id)
            let summaries = try await IosHelpersKt.getConversationSummariesList(
                repo, conversationIds: ids, viewerUserId: myUserId
            )
            let summaryById = Dictionary(uniqueKeysWithValues: summaries.map { ($0.conversationId, $0) })

            var rows: [Row] = []
            for convo in convos {
                let other = convo.employeeId == myUserId ? convo.employerId : convo.employeeId
                let info = try? await IosHelpersKt.participantInfoOrNull(repo, userId: other)
                let s = summaryById[convo.id]
                rows.append(Row(
                    id: convo.id,
                    otherUserId: other,
                    name: info?.name ?? "User",
                    photoUrl: info?.photoUrl,
                    lastMessage: s?.lastMessage ?? "",
                    lastMessageAt: s?.lastMessageAt,
                    unread: Int(s?.unreadCount ?? 0)
                ))
            }
            // Most recent first.
            rows.sort { ($0.lastMessageAt ?? "") > ($1.lastMessageAt ?? "") }
            state = .loaded(rows)
        } catch {
            state = .failed((error as NSError).localizedDescription)
        }
    }
}
