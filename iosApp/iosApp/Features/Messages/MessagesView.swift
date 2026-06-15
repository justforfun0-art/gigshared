import SwiftUI
import Shared

/// Conversations inbox — a list of chats with the other participant's avatar,
/// name, last-message preview, and an unread badge. Tapping a row opens the
/// chat thread.
struct MessagesView: View {
    @StateObject private var viewModel: MessagesViewModel
    private let repo: any MessageRepository

    init(repo: any MessageRepository, myUserId: String) {
        _viewModel = StateObject(wrappedValue: MessagesViewModel(repo: repo, myUserId: myUserId))
        self.repo = repo
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GHTheme.pageGradient.ignoresSafeArea()
                content
            }
            .navigationTitle("Messages")
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Loading…")
        case .loaded(let rows):
            if rows.isEmpty {
                placeholder
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(rows) { row in
                            NavigationLink {
                                ConversationView(repo: repo, conversationId: row.id,
                                                 myUserId: viewModel.myUserId,
                                                 receiverId: row.otherUserId, title: row.name)
                            } label: {
                                conversationRow(row)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        case .failed(let message):
            VStack(spacing: 12) {
                Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
                Button("Retry") { Task { await viewModel.load() } }
                    .buttonStyle(.borderedProminent).tint(GHTheme.primary)
            }
        }
    }

    private func conversationRow(_ row: MessagesViewModel.Row) -> some View {
        GHCard {
            HStack(spacing: 12) {
                avatar(row)
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.name).font(.headline).foregroundStyle(GHTheme.onBackground).lineLimit(1)
                    Text(row.lastMessage.isEmpty ? "No messages yet" : row.lastMessage)
                        .font(.subheadline).foregroundStyle(GHTheme.onSurfaceVariant).lineLimit(1)
                }
                Spacer()
                if row.unread > 0 {
                    Text("\(row.unread)")
                        .font(.caption2.weight(.bold)).foregroundStyle(.white)
                        .frame(minWidth: 20).padding(.vertical, 3).padding(.horizontal, 6)
                        .background(GHTheme.primary, in: Capsule())
                }
            }
        }
    }

    @ViewBuilder
    private func avatar(_ row: MessagesViewModel.Row) -> some View {
        if let url = row.photoUrl, let parsed = URL(string: url) {
            AsyncImage(url: parsed) { $0.resizable().scaledToFill() } placeholder: { Color(.secondarySystemBackground) }
                .frame(width: 44, height: 44).clipShape(Circle())
        } else {
            Circle().fill(GHTheme.primaryContainer).frame(width: 44, height: 44)
                .overlay(Text(initials(row.name)).font(.subheadline.weight(.semibold)).foregroundStyle(GHTheme.primary))
        }
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? "?"
        let second = parts.dropFirst().first?.first.map(String.init) ?? ""
        return (first + second).uppercased()
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right").font(.largeTitle).foregroundStyle(.secondary)
            Text("No conversations yet").font(.headline)
            Text("Messages with employers show up here.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }
}
