import SwiftUI
import Shared

/// In-app notifications list with mark-all-read.
struct NotificationsView: View {

    @StateObject private var viewModel: NotificationsViewModel

    init(notifications: any NotificationRepository) {
        _viewModel = StateObject(wrappedValue: NotificationsViewModel(notifications: notifications))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(L("profile_notifications"))
                .drawerToolbar()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L("mark_all_read")) { Task { await viewModel.markAllRead() } }
                    }
                }
                .task { await viewModel.load() }
                .refreshable { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Loading…")
        case .loaded(let items):
            if items.isEmpty {
                Text(L("ios_you_re_all_caught_up")).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(items, id: \.id) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(item.isRead ? Color.clear : Color.blue)
                            .frame(width: 8, height: 8)
                            .padding(.top, 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.subheadline.weight(item.isRead ? .regular : .semibold))
                            Text(item.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            Text(item.timeAgo).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        case .failed(let message):
            VStack(spacing: 12) {
                Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
                Button(L("retry_btn")) { Task { await viewModel.load() } }.buttonStyle(.borderedProminent)
            }
        }
    }
}
