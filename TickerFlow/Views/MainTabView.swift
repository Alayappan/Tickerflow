import SwiftUI

public struct MainTabView: View {
    @State private var store = FinanceStore()
    @State private var selectedTab: Int = 0

    public init() {}

    public var body: some View {
        TabView(selection: $selectedTab) {
            PortfolioHomeView(store: store)
                .tabItem {
                    Label("Portfolio", systemImage: "briefcase.fill")
                }
                .tag(0)

            PortfolioAnalyticsTabView(store: store)
                .tabItem {
                    Label("Analytics", systemImage: "chart.bar.xaxis")
                }
                .tag(1)
        }
        .tint(.blue)
    }
}
