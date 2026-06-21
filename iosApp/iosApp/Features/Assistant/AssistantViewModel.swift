import Foundation
import Shared

/// Drives the assistant chat over the shared AssistantEngine.
@MainActor
final class AssistantViewModel: ObservableObject {

    struct Msg: Identifiable {
        let id = UUID()
        let text: String
        let fromUser: Bool
        var stats: [AssistantStat] = []
        /// A confirmable agentic action (e.g. "Apply to …"); cleared once tapped.
        var action: AssistantAction? = nil
    }

    @Published private(set) var messages: [Msg] = []
    @Published var draft: String = ""
    @Published private(set) var isThinking = false

    let suggestions: [String]

    private let engine: AssistantEngine
    private let userId: String
    private let isEmployer: Bool
    private var greeted = false

    init(engine: AssistantEngine, userId: String, isEmployer: Bool) {
        self.engine = engine
        self.userId = userId
        self.isEmployer = isEmployer
        self.suggestions = isEmployer
            ? ["My job posts", "My spending", "How it works"]
            : ["Apply to the best job for me", "My applications", "My earnings"]
    }

    /// Opening greeting (once).
    func greet() async {
        guard !greeted else { return }
        greeted = true
        await ask("hi")
    }

    func send(_ text: String) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !isThinking else { return }
        messages.append(Msg(text: t, fromUser: true))
        draft = ""
        await ask(t)
    }

    private func ask(_ text: String) async {
        isThinking = true
        defer { isThinking = false }
        do {
            let reply = try await engine.respond(userId: userId, isEmployer: isEmployer, message: text)
            messages.append(Msg(text: reply.text, fromUser: false, stats: reply.stats, action: reply.action))
        } catch {
            messages.append(Msg(text: "Sorry, I ran into a problem. Please try again.", fromUser: false))
        }
    }

    /// Run a confirmed agentic action (user tapped the action button).
    func confirm(_ action: AssistantAction, on messageId: UUID) async {
        guard !isThinking else { return }
        // Clear the button so it can't be double-tapped.
        if let i = messages.firstIndex(where: { $0.id == messageId }) { messages[i].action = nil }
        isThinking = true
        defer { isThinking = false }
        do {
            let reply = try await engine.executeAction(userId: userId, action: action)
            messages.append(Msg(text: reply.text, fromUser: false, stats: reply.stats))
        } catch {
            messages.append(Msg(text: "Sorry, that didn’t go through. Please try again.", fromUser: false))
        }
    }
}
