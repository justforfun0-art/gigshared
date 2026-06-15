import Foundation
import Shared

/// One chat thread. Loads history, sends via the secure API, and streams new
/// messages over Supabase realtime (SKIE-bridged Flow → AsyncSequence). Marks
/// the thread read on open.
@MainActor
final class ConversationViewModel: ObservableObject {

    @Published private(set) var messages: [MessageRow] = []
    @Published var draft: String = ""
    @Published private(set) var isLoading = true
    @Published private(set) var isSending = false
    @Published var errorMessage: String?

    private let repo: any MessageRepository
    let conversationId: String
    let myUserId: String
    /// The other participant (receiver); derived server-side if nil.
    private let receiverId: String?
    private var observeTask: Task<Void, Never>?

    init(repo: any MessageRepository, conversationId: String, myUserId: String, receiverId: String?) {
        self.repo = repo
        self.conversationId = conversationId
        self.myUserId = myUserId
        self.receiverId = receiverId
    }

    deinit { observeTask?.cancel() }

    func start() async {
        await load()
        await markRead()
        observe()
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let rows = try await IosHelpersKt.getMessagesOrThrow(repo, conversationId: conversationId)
            messages = rows.sorted { ($0.createdAt ?? "") < ($1.createdAt ?? "") }
        } catch {
            errorMessage = (error as NSError).localizedDescription
        }
    }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        isSending = true
        draft = ""
        defer { isSending = false }
        do {
            let sent = try await IosHelpersKt.sendMessageOrThrow(
                repo, conversationId: conversationId, senderId: myUserId,
                content: text, receiverId: receiverId
            )
            appendIfNew(sent)
        } catch {
            errorMessage = (error as NSError).localizedDescription
            draft = text  // restore so the user doesn't lose it
        }
    }

    /// Subscribe to realtime inserts for this conversation.
    private func observe() {
        guard observeTask == nil else { return }
        observeTask = Task { [weak self] in
            guard let self else { return }
            for await msg in self.repo.observeMessages(conversationId: self.conversationId) {
                self.appendIfNew(msg)
                if msg.senderId != self.myUserId { await self.markRead() }
            }
        }
    }

    private func appendIfNew(_ msg: MessageRow) {
        guard !messages.contains(where: { $0.id == msg.id }) else { return }
        messages.append(msg)
        messages.sort { ($0.createdAt ?? "") < ($1.createdAt ?? "") }
    }

    private func markRead() async {
        try? await repo.markAsRead(conversationId: conversationId, userId: myUserId)
    }
}
