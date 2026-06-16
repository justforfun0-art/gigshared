import SwiftUI
import Shared

/// The AI assistant chat (port of Android's AssistantScreen). Sends the user's
/// message to the shared AssistantEngine, which answers from app data / FAQ or
/// falls back to the Gemini-backed API. Shown as a sheet from the floating
/// assistant button.
struct AssistantView: View {
    @StateObject private var viewModel: AssistantViewModel
    let isEmployer: Bool

    init(engine: AssistantEngine, userId: String, isEmployer: Bool) {
        _viewModel = StateObject(wrappedValue: AssistantViewModel(
            engine: engine, userId: userId, isEmployer: isEmployer
        ))
        self.isEmployer = isEmployer
    }

    private var accent: Color { isEmployer ? GHTheme.tertiary : GHTheme.primary }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messageList
                quickChips
                inputBar
            }
            .background(GHTheme.pageGradient.ignoresSafeArea())
            .navigationTitle(L("ios_gighour_assistant"))
            .navigationBarTitleDisplayMode(.inline)
            .task { await viewModel.greet() }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.messages) { msg in
                        bubble(msg).id(msg.id)
                    }
                    if viewModel.isThinking {
                        HStack { thinkingBubble; Spacer() }
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

    private func bubble(_ msg: AssistantViewModel.Msg) -> some View {
        HStack {
            if msg.fromUser { Spacer(minLength: 40) }
            VStack(alignment: msg.fromUser ? .trailing : .leading, spacing: 6) {
                Text(msg.text)
                    .font(.body)
                    .foregroundStyle(msg.fromUser ? .white : GHTheme.onBackground)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(msg.fromUser ? accent : Color(.secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 16))
                if !msg.stats.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(Array(msg.stats.enumerated()), id: \.offset) { _, s in
                            HStack {
                                Text(s.label).font(.subheadline).foregroundStyle(GHTheme.onSurfaceVariant)
                                Spacer()
                                Text(s.value).font(.subheadline.weight(.semibold)).foregroundStyle(accent)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
            if !msg.fromUser { Spacer(minLength: 40) }
        }
    }

    private var thinkingBubble: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { _ in
                Circle().fill(GHTheme.muted).frame(width: 7, height: 7)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    /// Suggested prompts to get started.
    private var quickChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.suggestions, id: \.self) { s in
                    Button { Task { await viewModel.send(s) } } label: {
                        Text(s)
                            .font(.caption).foregroundStyle(accent)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(accent.opacity(0.12), in: Capsule())
                    }
                }
            }
            .padding(.horizontal).padding(.bottom, 6)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask me anything…", text: $viewModel.draft, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color(.systemBackground), in: Capsule())
                .overlay(Capsule().stroke(GHTheme.outline, lineWidth: 1))
            Button {
                Task { await viewModel.send(viewModel.draft) }
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 32)).foregroundStyle(accent)
            }
            .disabled(viewModel.draft.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isThinking)
        }
        .padding(12)
        .background(.ultraThinMaterial)
    }
}
