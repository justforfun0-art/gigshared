import Foundation
import Shared

/// Paged payout history with a status filter (Android WithdrawalsViewModel).
@MainActor
final class WithdrawalsViewModel: ObservableObject {
    enum State { case idle, loading, loaded, failed(String) }

    @Published private(set) var state: State = .idle
    @Published private(set) var items: [Payout] = []
    @Published private(set) var hasMore = false
    @Published var filter: PayoutStatus?

    private let payouts: any PayoutRepository
    private let pageSize: Int32 = 20
    private var loadingMore = false

    init(payouts: any PayoutRepository) { self.payouts = payouts }

    func load(reset: Bool) async {
        if reset { state = .loading } else {
            guard hasMore, !loadingMore else { return }
            loadingMore = true
        }
        defer { loadingMore = false }
        do {
            let offset = reset ? 0 : items.count
            let page = try await IosHelpersKt.getHistoryOrThrow(
                payouts, status: filter, limit: pageSize, offset: Int32(offset)
            )
            items = reset ? page.payouts : items + page.payouts
            hasMore = page.hasMore
            state = .loaded
        } catch {
            if reset { state = .failed((error as NSError).localizedDescription) }
        }
    }
}
