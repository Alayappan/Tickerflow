import SwiftUI

public struct WatchlistHomeView: View {
    public let store: FinanceStore

    public init(store: FinanceStore) {
        self.store = store
    }

    public var body: some View {
        PortfolioAnalyticsTabView(store: store)
    }
}
