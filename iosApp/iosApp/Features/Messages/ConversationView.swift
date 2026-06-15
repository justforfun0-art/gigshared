import SwiftUI
import Shared

/// Chat thread UI: scrollable message bubbles (mine right/violet, theirs
/// left/gray), a bottom input bar, live updates via realtime.
struct ConversationView: View {
    @StateObject private var viewModel: ConversationViewModel
    let title: String

    init(repo: any MessageRepository, conversationId: String, myUserId: String,
         receiverId: String?, title: String) {
        _viewModel = StateObject(wrappedValue: ConversationViewModel(
            repo: repo, conversationId: conversationId, myUserId: myUserId, receiverId: receiverId
        ))
        self.title = title
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            inputBar
        }
        .background(GHTheme.pageGradient.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.start() }
        .alert("Message error", isPresented: errorBinding) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: { Text(viewModel.errorMessage ?? "") }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if viewModel.isLoading {
                        ProgressView().padding(.top, 40)
                    } else if viewModel.messages.isEmpty {
                        Text("Say hello 👋")
                            .font(.subheadline).foregroundStyle(.secondary).padding(.top, 60)
                    }
                    ForEach(viewModel.messages, id: \.id) { msg in
                        bubble(msg).id(msg.id)
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.messages.count) { _ in
                if let last = viewModel.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func bubble(_ msg: MessageRow) -> some View {
        let mine = msg.senderId == viewModel.myUserId
        return HStack {
            if mine { Spacer(minLength: 40) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
                Text(msg.content)
                    .font(.body)
                    .foregroundStyle(mine ? .white : GHTheme.onBackground)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(mine ? GHTheme.primary : Color(.secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 16))
                if let ts = msg.createdAt {
                    Text(Self.timeOnly(ts)).font(.caption2).foregroundStyle(.secondary)
                }
            }
            if !mine { Spacer(minLength: 40) }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Message…", text: $viewModel.draft, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color(.systemBackground), in: Capsule())
                .overlay(Capsule().stroke(GHTheme.outline, lineWidth: 1))
            Button {
                Task { await viewModel.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? GHTheme.primary : GHTheme.muted)
            }
            .disabled(!canSend)
        }
        .padding(12)
        .background(.ultraThinMaterial)
    }

    private var canSend: Bool {
        !viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isSending
    }

    /// "2026-06-15T12:32:00Z" → "12:32" (best-effort).
    static func timeOnly(_ raw: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        guard let date else { return "" }
        let out = DateFormatter(); out.dateFormat = "h:mm a"
        return out.string(from: date)
    }
}
