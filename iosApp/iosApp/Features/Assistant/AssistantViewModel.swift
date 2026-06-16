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
            : ["My applications", "My earnings", "Find jobs near me"]
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
            messages.append(Msg(text: reply.text, fromUser: false, stats: reply.stats))
        } catch {
            messages.append(Msg(text: "Sorry, I ran into a problem. Please try again.", fromUser: false))
        }
    }
}
