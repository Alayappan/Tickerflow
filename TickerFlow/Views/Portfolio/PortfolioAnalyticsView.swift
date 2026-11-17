import SwiftUI
import Charts

public struct PortfolioAnalyticsTabView: View {
    public let store: FinanceStore

    /// `nil` means Overall across all portfolios; non-nil filters to a specific portfolio
    @State private var selectedScopePortfolioId: UUID?
    @State private var detailSelection: DetailSelection?

    private struct DetailSelection: Identifiable {
        let id = UUID()
        let quote: StockQuote
        let portfolioId: UUID?
    }

    public init(store: FinanceStore) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Scope Selector (Overall vs Individual Portfolio)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            let isOverall = selectedScopePortfolioId == nil
                            Button {
                                selectedScopePortfolioId = nil
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "globe")
                                        .font(.caption2)
                                    Text("Overall")
                                        .font(.subheadline.weight(isOverall ? .bold : .medium))
                                    Text(store.overallCurrency)
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(isOverall ? Color.white.opacity(0.24) : Color.primary.opacity(0.08))
                                        .clipShape(Capsule())
                                }
                                .foregroundColor(isOverall ? .white : .primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule()
                                        .fill(isOverall ? Color.blue : secondaryGroupedBackgroundColor)
                                )
                            }
                            .buttonStyle(.plain)

                            ForEach(store.portfolios) { portfolio in
                                let isSelected = selectedScopePortfolioId == portfolio.id
                                Button {
                                    selectedScopePortfolioId = portfolio.id
                                } label: {
                                    HStack(spacing: 5) {
                                        Text(portfolio.name)
                                            .font(.subheadline.weight(isSelected ? .bold : .medium))
                                        Text(portfolio.currency)
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(isSelected ? Color.white.opacity(0.24) : Color.primary.opacity(0.08))
                                            .clipShape(Capsule())
                                    }
                                    .foregroundColor(isSelected ? .white : .primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule()
                                            .fill(isSelected ? Color.blue : secondaryGroupedBackgroundColor)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Multi-Portfolio Split Card when viewing Overall
                    if selectedScopePortfolioId == nil && store.portfolios.count > 1 {
                        multiPortfolioBreakdownCard
                    }

                    PortfolioAnalyticsView(
                        store: store,
                        scopePortfolioId: selectedScopePortfolioId
                    ) { symbol, holdingPortfolioId in
                        openQuoteDetail(for: symbol, portfolioId: holdingPortfolioId ?? selectedScopePortfolioId)
                    }

                    // Global Market Indices Pulse
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Global Markets & FX")
                            .font(.headline)
                            .padding(.horizontal)

                        MarketIndicesHeader(
                            indices: store.marketIndices,
                            selectedRegion: Binding(
                                get: { store.selectedMarketRegion },
                                set: { store.selectedMarketRegion = $0 }
                            )
                        ) { index in
                            let quote = store.quotes[index.symbol] ?? StockQuote(
                                symbol: index.symbol,
                                companyName: index.name,
                                regularMarketPrice: index.value,
                                regularMarketChange: index.change,
                                regularMarketChangePercent: index.changePercent,
                                currency: index.currency,
                                sparklinePrices: index.sparklinePrices
                            )
                            detailSelection = DetailSelection(quote: quote, portfolioId: selectedScopePortfolioId)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical)
            }
            .navigationTitle("Portfolio Analytics")
            .refreshable {
                await store.refreshAllQuotes()
            }
            .sheet(item: $detailSelection) { selection in
                StockDetailView(
                    quote: selection.quote,
                    store: store,
                    portfolioId: selection.portfolioId
                )
            }
        }
    }

    private var secondaryGroupedBackgroundColor: Color {
        #if canImport(UIKit)
        Color(UIColor.secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    private var multiPortfolioBreakdownCard: some View {
        let overall = store.overallSummary
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Portfolios Breakdown")
                    .font(.headline)
                Spacer()
                Text("Converted to \(overall.currency)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ForEach(overall.breakdowns) { item in
                let weight = overall.totalValue > 0 ? (item.overallCurrencyValue / overall.totalValue) * 100 : 0
                Button {
                    selectedScopePortfolioId = item.portfolio.id
                } label: {
                    VStack(spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(item.portfolio.name)
                                        .font(.subheadline.bold())
                                        .foregroundColor(.primary)
                                    Text(item.portfolio.currency)
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.12))
                                        .foregroundColor(.blue)
                                        .clipShape(Capsule())
                                }
                                Text("\(item.positionsCount) holdings • \(item.trackedTickersCount) tickers")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(StockQuote.formatAmount(item.overallCurrencyValue, currency: overall.currency))
                                    .font(.subheadline.bold())
                                    .foregroundColor(.primary)
                                if item.portfolio.currency != overall.currency {
                                    Text(StockQuote.formatAmount(item.nativeValue, currency: item.portfolio.currency))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.06))
                                Capsule()
                                    .fill(Color.blue)
                                    .frame(width: max(4, geo.size.width * CGFloat(min(1, weight / 100))))
                            }
                        }
                        .frame(height: 5)
                    }
                }
                .buttonStyle(.plain)

                if item.id != overall.breakdowns.last?.id {
                    Divider()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(secondaryGroupedBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
        .padding(.horizontal)
    }

    private func openQuoteDetail(for symbol: String, portfolioId: UUID?) {
        if let existing = store.quotes[symbol.uppercased()] {
            detailSelection = DetailSelection(quote: existing, portfolioId: portfolioId)
            return
        }
        Task {
            let q = await YahooFinanceService.shared.fetchQuote(symbol: symbol)
            detailSelection = DetailSelection(quote: q, portfolioId: portfolioId)
        }
    }
}

public struct PortfolioAnalyticsView: View {
    public let store: FinanceStore
    public let scopePortfolioId: UUID?
    public var onSelectSymbol: (String, UUID?) -> Void

    @State private var performerSegment: PerformerSegment = .positive
    @State private var returnChartMetric: ReturnMetric = .percent
    @State private var visibleBarCount: Int = 8
    @State private var pinchBaseBarCount: Int?
    @State private var selectedReturnBarLabel: String?

    private enum PerformerSegment: String, CaseIterable, Identifiable {
        case positive = "Positive"
        case negative = "Negative"
        var id: String { rawValue }
    }

    private enum ReturnMetric: String, CaseIterable, Identifiable {
        case percent = "Return %"
        case amount = "Gain/Loss"
        var id: String { rawValue }
    }

    private struct ReturnBarItem: Identifiable {
        let id: String
        let label: String
        let holding: Holding
        let portfolioName: String?
        let displayValue: Double
    }

    public init(
        store: FinanceStore,
        scopePortfolioId: UUID? = nil,
        onSelectSymbol: @escaping (String, UUID?) -> Void
    ) {
        self.store = store
        self.scopePortfolioId = scopePortfolioId
        self.onSelectSymbol = onSelectSymbol
    }

    private var holdings: [Holding] {
        store.holdings(for: scopePortfolioId)
    }

    private var stats: PortfolioAnalytics {
        store.analytics(for: scopePortfolioId)
    }

    private var displayCurrency: String {
        if let pid = scopePortfolioId, let p = store.portfolio(for: pid) {
            return p.currency
        }
        return store.overallCurrency
    }

    private var hasTransactions: Bool {
        if let pid = scopePortfolioId {
            return !store.transactions(for: pid).isEmpty
        }
        return !store.transactions.isEmpty
    }

    private var chartPalette: [Color] {
        [.blue, .teal, .indigo, .orange, .purple, .mint, .pink, .cyan]
    }

    public var body: some View {
        VStack(spacing: 16) {
            if holdings.isEmpty && !hasTransactions {
                emptyAnalyticsState
            } else {
                performanceBreakdownCard

                if !holdings.isEmpty {
                    topMoversCard
                    allocationCard
                    returnComparisonCard
                    diversificationCard
                }
            }
        }
    }

    private var secondaryGroupedBackgroundColor: Color {
        #if canImport(UIKit)
        Color(UIColor.secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    // MARK: - Empty State
    private var emptyAnalyticsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 42))
                .foregroundColor(.secondary)
                .padding(.top, 18)

            Text("No Portfolio Data to Analyze")
                .font(.headline)

            Text("Add holdings or import a CSV in the Portfolio tab to unlock return attribution, allocation weights, and realized P&L analytics.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(secondaryGroupedBackgroundColor)
        )
        .padding(.horizontal)
    }

    // MARK: - 1. Performance & P&L Breakdown
    private var performanceBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Performance & P&L Breakdown")
                    .font(.headline)
                Spacer()
                Text(displayCurrency)
                    .font(.caption2.bold())
                    .foregroundColor(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(Capsule())
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                AnalyticsMetricTile(
                    title: "Invested Cost",
                    value: StockQuote.formatAmount(stats.totalCostBasis, currency: displayCurrency),
                    subtitle: "\(holdings.count) active positions"
                )
                AnalyticsMetricTile(
                    title: "Unrealized P&L",
                    value: StockQuote.formatSignedAmount(stats.unrealizedGainLoss, currency: displayCurrency),
                    subtitle: String(format: "%@%.2f%%", stats.unrealizedGainLossPercent >= 0 ? "+" : "", stats.unrealizedGainLossPercent),
                    valueColor: stats.unrealizedGainLoss >= 0 ? .green : .red
                )
                AnalyticsMetricTile(
                    title: "Realized P&L",
                    value: StockQuote.formatSignedAmount(stats.realizedGainLoss, currency: displayCurrency),
                    subtitle: "\(stats.totalSellsCount) closed/partial sells",
                    valueColor: stats.realizedGainLoss >= 0 ? .green : .red
                )
                AnalyticsMetricTile(
                    title: "Net Total Profit",
                    value: StockQuote.formatSignedAmount(stats.netTotalGainLoss, currency: displayCurrency),
                    subtitle: "Win rate \(String(format: "%.0f%%", stats.winRatePercent)) (\(stats.profitablePositionsCount)W / \(stats.losingPositionsCount)L)",
                    valueColor: stats.netTotalGainLoss >= 0 ? .green : .red
                )
            }
        }
        .padding(16)
        .background(cardBackground)
        .padding(.horizontal)
    }

    // MARK: - 2. Top & Bottom Performers
    private var positivePerformers: [Holding] {
        holdings
            .filter { $0.totalGainLoss >= 0 }
            .sorted {
                if $0.totalGainLossPercent != $1.totalGainLossPercent {
                    return $0.totalGainLossPercent > $1.totalGainLossPercent
                }
                return $0.totalGainLoss > $1.totalGainLoss
            }
    }

    private var negativePerformers: [Holding] {
        holdings
            .filter { $0.totalGainLoss < 0 }
            .sorted {
                if $0.totalGainLossPercent != $1.totalGainLossPercent {
                    return $0.totalGainLossPercent < $1.totalGainLossPercent
                }
                return $0.totalGainLoss < $1.totalGainLoss
            }
    }

    private var topMoversCard: some View {
        let positives = positivePerformers
        let negatives = negativePerformers
        let activePerformers = performerSegment == .positive ? positives : negatives
        let isPositive = performerSegment == .positive

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Top & Bottom Performers")
                    .font(.headline)

                Spacer()

                if activePerformers.count > 2 {
                    Text("Swipe • \(activePerformers.count)")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Capsule())
                }
            }

            Picker("Performer Type", selection: $performerSegment) {
                Text("Positive (\(positives.count))").tag(PerformerSegment.positive)
                Text("Negative (\(negatives.count))").tag(PerformerSegment.negative)
            }
            .pickerStyle(.segmented)

            if activePerformers.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: isPositive ? "arrow.up.right.circle" : "arrow.down.right.circle")
                        .foregroundColor(.secondary)
                    Text(isPositive ? "No positive performers in this scope." : "No negative performers in this scope.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(Array(activePerformers.enumerated()), id: \.element.id) { index, holding in
                            let portfolioLabel = scopePortfolioId == nil
                                ? store.portfolio(for: holding.portfolioId)?.name
                                : nil
                            PerformerCard(
                                rank: index + 1,
                                holding: holding,
                                portfolioName: portfolioLabel,
                                accentColor: isPositive ? .green : .red
                            ) {
                                onSelectSymbol(holding.symbol, holding.portfolioId)
                            }
                            .frame(width: 156)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(16)
        .background(cardBackground)
        .padding(.horizontal)
    }

    // MARK: - 3. Asset Allocation Donut + Weights
    private var allocationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Asset Allocation")
                    .font(.headline)
                Spacer()
                Text("By Market Value")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ZStack {
                Chart(Array(holdings.enumerated()), id: \.element.id) { index, holding in
                    SectorMark(
                        angle: .value("Value", max(holding.currentValue, 0.01)),
                        innerRadius: .ratio(0.66),
                        angularInset: 1.5
                    )
                    .cornerRadius(5)
                    .foregroundStyle(chartPalette[index % chartPalette.count])
                }
                .frame(height: 190)

                VStack(spacing: 2) {
                    Text("Total Value")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(StockQuote.formatAmount(stats.totalValue, currency: displayCurrency))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
            }

            VStack(spacing: 10) {
                ForEach(Array(holdings.enumerated()), id: \.element.id) { index, holding in
                    let weight = stats.totalValue > 0 ? (holding.currentValue / stats.totalValue) * 100 : 0
                    let color = chartPalette[index % chartPalette.count]
                    let portfolioLabel = scopePortfolioId == nil ? store.portfolio(for: holding.portfolioId)?.name : nil

                    Button(action: {
                        onSelectSymbol(holding.symbol, holding.portfolioId)
                    }) {
                        VStack(spacing: 4) {
                            HStack {
                                Circle()
                                    .fill(color)
                                    .frame(width: 8, height: 8)
                                Text(holding.symbol)
                                    .font(.caption.bold())
                                    .foregroundColor(.primary)
                                if let pLabel = portfolioLabel {
                                    Text(pLabel)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                } else if !holding.companyName.isEmpty {
                                    Text(holding.companyName)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(String(format: "%.1f%%", weight))
                                    .font(.caption.bold())
                                    .foregroundColor(.primary)
                                Text(StockQuote.formatAmount(holding.currentValue, currency: holding.currency))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.primary.opacity(0.06))
                                    Capsule()
                                        .fill(color)
                                        .frame(width: max(4, geo.size.width * CGFloat(min(1, weight / 100))))
                                }
                            }
                            .frame(height: 5)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(cardBackground)
        .padding(.horizontal)
    }

    // MARK: - 4. Return Comparison Bar Chart
    private var returnBarItems: [ReturnBarItem] {
        let symbolCounts = Dictionary(grouping: holdings, by: { $0.symbol }).mapValues(\.count)
        return holdings.map { holding in
            let pName = scopePortfolioId == nil ? store.portfolio(for: holding.portfolioId)?.name : nil
            let hasDuplicate = (symbolCounts[holding.symbol] ?? 1) > 1
            let label: String
            if hasDuplicate, let pName {
                let shortPortfolio = String(pName.prefix(6))
                label = "\(holding.symbol) (\(shortPortfolio))"
            } else {
                label = holding.symbol
            }
            let value: Double
            switch returnChartMetric {
            case .percent:
                value = holding.totalGainLossPercent
            case .amount:
                let fx = store.fxRate(from: holding.currency, to: displayCurrency)
                value = holding.totalGainLoss * fx
            }
            return ReturnBarItem(
                id: holding.id,
                label: label,
                holding: holding,
                portfolioName: pName,
                displayValue: value
            )
        }
        .sorted { $0.displayValue > $1.displayValue }
    }

    private var returnComparisonCard: some View {
        let items = returnBarItems
        let totalCount = items.count
        let minVisible = min(4, max(1, totalCount))
        let maxVisible = max(minVisible, totalCount)
        let effectiveVisible = min(max(visibleBarCount, minVisible), maxVisible)
        let isZoomedOutToAll = effectiveVisible >= totalCount
        let selectedItem = items.first { $0.label == selectedReturnBarLabel }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Return by Position")
                    .font(.headline)

                if totalCount > 0 {
                    Text("\(totalCount)")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.07))
                        .clipShape(Capsule())
                }

                Spacer()

                Picker("Metric", selection: $returnChartMetric) {
                    ForEach(ReturnMetric.allCases) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 165)
            }

            // Zoom & Scroll Controls (essential when holding many tickers)
            if totalCount > 4 {
                HStack(spacing: 8) {
                    Text(isZoomedOutToAll ? "Showing all \(totalCount)" : "Showing \(effectiveVisible) of \(totalCount) • Swipe to scroll")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Spacer()

                    HStack(spacing: 4) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                visibleBarCount = max(minVisible, effectiveVisible - max(2, effectiveVisible / 3))
                            }
                        } label: {
                            Image(systemName: "plus.magnifyingglass")
                                .font(.caption.bold())
                                .frame(width: 28, height: 24)
                                .background(Color.primary.opacity(0.07))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .disabled(effectiveVisible <= minVisible)
                        .opacity(effectiveVisible <= minVisible ? 0.4 : 1)

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                visibleBarCount = min(maxVisible, effectiveVisible + max(2, effectiveVisible / 2))
                            }
                        } label: {
                            Image(systemName: "minus.magnifyingglass")
                                .font(.caption.bold())
                                .frame(width: 28, height: 24)
                                .background(Color.primary.opacity(0.07))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .disabled(isZoomedOutToAll)
                        .opacity(isZoomedOutToAll ? 0.4 : 1)

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                visibleBarCount = isZoomedOutToAll ? min(8, totalCount) : totalCount
                            }
                        } label: {
                            Text(isZoomedOutToAll ? "Focus 8" : "Fit All")
                                .font(.caption2.bold())
                                .foregroundColor(.blue)
                                .padding(.horizontal, 8)
                                .frame(height: 24)
                                .background(Color.blue.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Selected Position Inspector Banner
            if let item = selectedItem {
                let isGain = item.displayValue >= 0
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(item.holding.symbol)
                                .font(.subheadline.bold())
                            if let pName = item.portfolioName {
                                Text("• \(pName)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        HStack(spacing: 8) {
                            Text(String(format: "%@%.2f%%", item.holding.totalGainLossPercent >= 0 ? "+" : "", item.holding.totalGainLossPercent))
                                .font(.caption.bold())
                                .foregroundColor(item.holding.totalGainLossPercent >= 0 ? .green : .red)

                            Text(StockQuote.formatSignedAmount(item.holding.totalGainLoss, currency: item.holding.currency))
                                .font(.caption)
                                .foregroundColor(isGain ? .green : .red)

                            Text("• Val \(StockQuote.formatAmount(item.holding.currentValue, currency: item.holding.currency))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Button("Open") {
                        onSelectSymbol(item.holding.symbol, item.holding.portfolioId)
                    }
                    .font(.caption2.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.primary.opacity(0.05))
                )
            }

            Chart(items) { item in
                RuleMark(y: .value("Break-even", 0))
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                let isSelected = selectedReturnBarLabel == nil || selectedReturnBarLabel == item.label
                BarMark(
                    x: .value("Symbol", item.label),
                    y: .value(returnChartMetric.rawValue, item.displayValue)
                )
                .foregroundStyle(item.displayValue >= 0 ? Color.green.gradient : Color.red.gradient)
                .opacity(isSelected ? 1.0 : 0.4)
                .cornerRadius(4)
                .annotation(position: item.displayValue >= 0 ? .top : .bottom, spacing: 3) {
                    if effectiveVisible <= 10 {
                        Text(formatCompactBarAnnotation(item.displayValue))
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundColor(item.displayValue >= 0 ? .green : .red)
                    }
                }
            }
            .frame(height: 265)
            .chartScrollableAxes(totalCount > effectiveVisible ? .horizontal : [])
            .chartXVisibleDomain(length: effectiveVisible)
            .chartXSelection(value: $selectedReturnBarLabel)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine()
                    if let text = value.as(String.self) {
                        AxisValueLabel(
                            text,
                            collisionResolution: effectiveVisible > 14
                                ? .greedy(priority: 1, minimumSpacing: 4)
                                : .automatic,
                            orientation: .verticalReversed
                        )
                        .font(.system(size: 10, weight: .medium))
                    }
                }
            }
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let base = pinchBaseBarCount ?? effectiveVisible
                        if pinchBaseBarCount == nil {
                            pinchBaseBarCount = effectiveVisible
                        }
                        let proposed = Int((Double(base) / max(0.3, Double(value.magnification))).rounded())
                        visibleBarCount = min(maxVisible, max(minVisible, proposed))
                    }
                    .onEnded { _ in
                        pinchBaseBarCount = nil
                    }
            )
            .onChange(of: scopePortfolioId) { _, _ in
                selectedReturnBarLabel = nil
            }
            .onChange(of: returnChartMetric) { _, _ in
                selectedReturnBarLabel = nil
            }
        }
        .padding(16)
        .background(cardBackground)
        .padding(.horizontal)
    }

    private func formatCompactBarAnnotation(_ value: Double) -> String {
        switch returnChartMetric {
        case .percent:
            return String(format: "%@%.1f%%", value >= 0 ? "+" : "", value)
        case .amount:
            let absVal = abs(value)
            let sign = value >= 0 ? "+" : "-"
            if absVal >= 1_000_000 {
                return String(format: "%@%.1fM", sign, absVal / 1_000_000)
            } else if absVal >= 1_000 {
                return String(format: "%@%.1fK", sign, absVal / 1_000)
            }
            return String(format: "%@%.0f", sign, absVal)
        }
    }

    // MARK: - 5. Diversification & Trade Activity
    private var diversificationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Portfolio Health & Activity")
                .font(.headline)

            if let largest = stats.largestPosition {
                let concentrated = stats.largestPositionWeight > 35
                HStack(spacing: 10) {
                    Image(systemName: concentrated ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                        .foregroundColor(concentrated ? .orange : .green)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Largest Position: \(largest.symbol) (\(String(format: "%.1f%%", stats.largestPositionWeight)))")
                            .font(.subheadline.weight(.semibold))
                        Text(concentrated ? "High single-stock concentration (>35%). Consider diversifying across regions or sectors." : "Well-balanced position sizing across \(holdings.count) holdings.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill((concentrated ? Color.orange : Color.green).opacity(0.08))
                )
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Buys (\(stats.totalBuysCount))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(StockQuote.formatAmount(stats.totalBoughtVolume, currency: displayCurrency))
                        .font(.subheadline.bold())
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                    .frame(height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Sells (\(stats.totalSellsCount))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(StockQuote.formatAmount(stats.totalSoldVolume, currency: displayCurrency))
                        .font(.subheadline.bold())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(cardBackground)
        .padding(.horizontal)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(secondaryGroupedBackgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }
}

private struct AnalyticsMetricTile: View {
    let title: String
    let value: String
    let subtitle: String
    var valueColor: Color = .primary

    private var tileBackgroundColor: Color {
        #if canImport(UIKit)
        Color(UIColor.tertiarySystemGroupedBackground)
        #else
        Color(nsColor: .underPageBackgroundColor)
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tileBackgroundColor)
        )
    }
}

private struct PerformerCard: View {
    let rank: Int
    let holding: Holding
    let portfolioName: String?
    let accentColor: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text("#\(rank)")
                        .font(.caption2.bold())
                        .foregroundColor(accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accentColor.opacity(0.14))
                        .clipShape(Capsule())

                    Spacer()

                    if let portfolioName, !portfolioName.isEmpty {
                        Text(portfolioName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Text(holding.symbol)
                    .font(.headline.bold())
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if !holding.companyName.isEmpty {
                    Text(holding.companyName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Text(String(format: "%@%.2f%%", holding.totalGainLossPercent >= 0 ? "+" : "", holding.totalGainLossPercent))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(accentColor)

                Text(StockQuote.formatSignedAmount(holding.totalGainLoss, currency: holding.currency))
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(accentColor.opacity(0.9))
                    .lineLimit(1)

                Text("Val \(StockQuote.formatAmount(holding.currentValue, currency: holding.currency))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accentColor.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(accentColor.opacity(0.18), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
