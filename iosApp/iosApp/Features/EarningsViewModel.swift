import Foundation
import Shared

/// Employee earnings/payouts over the shared `PayoutRepository`.
@MainActor
final class EarningsViewModel: ObservableObject {

    enum State {
        case idle, loading
        case loaded(summary: PayoutSummary, payouts: [Payout])
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private let payouts: any PayoutRepository

    init(payouts: any PayoutRepository) {
        self.payouts = payouts
    }

    func load() async {
        state = .loading
        do {
            let page = try await IosHelpersKt.getHistoryOrThrow(payouts, status: nil, limit: 50, offset: 0)
            state = .loaded(summary: page.summary, payouts: page.payouts)
        } catch {
            state = .failed((error as NSError).localizedDescription)
        }
    }
}
