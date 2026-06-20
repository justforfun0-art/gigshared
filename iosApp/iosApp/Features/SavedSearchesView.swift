import SwiftUI
import Shared

/// Employee saved searches — port of Android's SavedSearchesScreen. Lists the
/// worker's saved job searches (from the secure/saved-searches REST route),
/// each tappable to re-run in JobSearch, with swipe-to-delete. Uses the new
/// SavedSearches shims.
struct SavedSearchesView: View {
    let savedSearches: any SavedSearchesRepository
    /// Re-run a saved search by seeding the JobSearch screen.
    let onRunSearch: (String) -> Void

    @StateObject private var viewModel: SavedSearchesViewModel
    private var accent: Color { GHTheme.hex(0x8B5CF6) }

    init(savedSearches: any SavedSearchesRepository, onRunSearch: @escaping (String) -> Void) {
        self.savedSearches = savedSearches
        self.onRunSearch = onRunSearch
        _viewModel = StateObject(wrappedValue: SavedSearchesViewModel(savedSearches: savedSearches))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GHTheme.pageGradient.ignoresSafeArea()
                content
            }
            .navigationTitle(L("saved_searches_title"))
            .drawerToolbar()
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView()
        } else if viewModel.searches.isEmpty {
            VStack(spacing: 8) {
                Circle().fill(accent.opacity(0.15)).frame(width: 72, height: 72)
                    .overlay(Image(systemName: "bookmark").font(.system(size: 30)).foregroundStyle(accent))
                Text(L("no_saved_searches")).font(.headline)
                Text(L("no_saved_searches_desc")).font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.horizontal, 32)
        } else {
            List {
                ForEach(viewModel.searches, id: \.id) { s in
                    SavedSearchRow(search: s, accent: accent)
                        .contentShape(Rectangle())
                        .onTapGesture { onRunSearch(s.name) }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions {
                            Button(role: .destructive) { Task { await viewModel.delete(s.id) } } label: {
                                Label(L("delete"), systemImage: "trash")
                            }
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

private struct SavedSearchRow: View {
    let search: SavedSearch
    let accent: Color

    private var location: String? {
        [search.district, search.state].compactMap { $0 }.filter { !$0.isEmpty }.first
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10).fill(GHTheme.hex(0xEDE9FE)).frame(width: 36, height: 36)
                .overlay(Image(systemName: "magnifyingglass").font(.system(size: 16)).foregroundStyle(accent))
            VStack(alignment: .leading, spacing: 4) {
                Text(search.name).font(.subheadline.weight(.semibold)).foregroundStyle(GHTheme.onBackground)
                HStack(spacing: 8) {
                    if let loc = location {
                        Text(loc).font(.caption).foregroundStyle(GHTheme.onSurfaceVariant)
                    }
                    Text("\(Int(search.useCount)) uses").font(.caption2.weight(.medium))
                        .foregroundStyle(GHTheme.hex(0x6D28D9))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(GHTheme.hex(0xEDE9FE), in: Capsule())
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(GHTheme.hex(0x9CA3AF))
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(GHTheme.outline, lineWidth: 1))
    }
}

@MainActor
final class SavedSearchesViewModel: ObservableObject {
    @Published private(set) var isLoading = true
    @Published private(set) var searches: [SavedSearch] = []

    private let savedSearches: any SavedSearchesRepository

    init(savedSearches: any SavedSearchesRepository) { self.savedSearches = savedSearches }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        searches = (try? await IosHelpersKt.listSavedSearchesOrThrow(savedSearches)) ?? []
    }

    func delete(_ id: String) async {
        // Optimistic remove, then persist.
        let previous = searches
        searches.removeAll { $0.id == id }
        do {
            try await IosHelpersKt.deleteSavedSearchOrThrow(savedSearches, id: id)
        } catch {
            searches = previous  // restore on failure
        }
    }
}
