import SwiftUI

public struct StockDetailView: View {
    @Environment(\.dismiss) private var dismiss
    public let quote: StockQuote
    public let store: FinanceStore
    public let portfolioId: UUID?

    @State private var selectedTimeframe: ChartTimeframe = .oneDay
    @State private var chartPoints: [HistoricalPricePoint] = []
    @State private var isLoadingChart: Bool = true
    @State private var isLoadingStats: Bool = false
    @State private var scrubbedPoint: HistoricalPricePoint?
    @State private var liveQuote: StockQuote?
    @State private var showAddTransactionSheet: Bool = false
    @State private var transactionToEdit: Transaction?
    @State private var showAddedToPortfolioBanner: Bool = false

    public init(quote: StockQuote, store: FinanceStore, portfolioId: UUID? = nil) {
        self.quote = quote
        self.store = store
        self.portfolioId = portfolioId ?? store.currentPortfolio?.id
    }

    private var activePortfolio: Portfolio? {
        store.portfolio(for: portfolioId) ?? store.currentPortfolio
    }

    private var activeQuote: StockQuote {
        liveQuote ?? quote
    }

    private var activePrice: Double {
        scrubbedPoint?.price ?? activeQuote.regularMarketPrice
    }

    private var isPositive: Bool {
        if let first = chartPoints.first, let current = scrubbedPoint?.price ?? chartPoints.last?.price {
            return current >= first.price
        }
        return activeQuote.isPositive
    }

    private var calculatedChange: (amount: Double, percent: Double) {
        if let first = chartPoints.first, let current = scrubbedPoint?.price ?? chartPoints.last?.price {
            let diff = current - first.price
            let pct = first.price > 0 ? (diff / first.price) * 100 : 0
            return (diff, pct)
        }
        return (activeQuote.regularMarketChange, activeQuote.regularMarketChangePercent)
    }

    private var isIndexSymbol: Bool {
        activeQuote.symbol.hasPrefix("^") || activeQuote.symbol.hasSuffix("=X")
    }

    private var tickerHolding: Holding? {
        store.holding(forSymbol: activeQuote.symbol, portfolioId: activePortfolio?.id)
    }

    private var tickerTransactions: [Transaction] {
        store.transactionsForSymbol(activeQuote.symbol, portfolioId: activePortfolio?.id)
    }

    private var isTickerInActivePortfolio: Bool {
        store.isSymbolInPortfolio(activeQuote.symbol, portfolioId: activePortfolio?.id)
    }

    private var prefilledPriceInPortfolioCurrency: Double {
        let portfolioCurrency = activePortfolio?.currency ?? activeQuote.currency
        let fx = store.fxRate(from: activeQuote.currency, to: portfolioCurrency)
        return activeQuote.regularMarketPrice * fx
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Header Price & Change
                    VStack(alignment: .leading, spacing: 4) {
                        Text(activeQuote.companyName)
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Text(StockQuote.formatAmount(activePrice, currency: activeQuote.currency, isIndex: isIndexSymbol))
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)

                        HStack(spacing: 6) {
                            Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 13, weight: .bold))
                            Text("\(StockQuote.formatSignedAmount(calculatedChange.amount, currency: activeQuote.currency, isIndex: isIndexSymbol)) (\(String(format: "%@%.2f%%", calculatedChange.percent >= 0 ? "+" : "", calculatedChange.percent)))")
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            if let point = scrubbedPoint {
                                Text("• \(point.date.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("• \(selectedTimeframe.rawValue)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .foregroundColor(isPositive ? Color.green : Color.red)
                    }
                    .padding(.horizontal)

                    // Chart View
                    VStack(spacing: 12) {
                        if isLoadingChart && chartPoints.isEmpty {
                            ProgressView()
                                .frame(height: 240)
                                .frame(maxWidth: .infinity)
                        } else {
                            InteractiveChartView(
                                data: chartPoints,
                                timeframe: selectedTimeframe,
                                isPositive: isPositive,
                                onScrub: { point in
                                    scrubbedPoint = point
                                }
                            )
                            .frame(height: 240)
                            .padding(.horizontal, 4)
                        }

                        // Timeframe Selectors
                        HStack(spacing: 6) {
                            ForEach(ChartTimeframe.allCases) { tf in
                                Button(action: {
                                    selectedTimeframe = tf
                                }) {
                                    Text(tf.rawValue)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(selectedTimeframe == tf ? .white : .secondary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(selectedTimeframe == tf ? Color.blue : Color(UIColor.tertiarySystemFill))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Action Buttons (Add Ticker to Portfolio / Add Holding)
                    HStack(spacing: 12) {
                        Button(action: {
                            store.addTickerToPortfolio(activeQuote.symbol, portfolioId: activePortfolio?.id)
                            showAddedToPortfolioBanner = true
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: isTickerInActivePortfolio ? "checkmark.circle.fill" : "plus.square.on.square")
                                Text(isTickerInActivePortfolio ? "In Portfolio" : "Add Ticker")
                            }
                            .font(.subheadline.bold())
                            .foregroundColor(isTickerInActivePortfolio ? .green : .primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke((isTickerInActivePortfolio ? Color.green : Color.primary).opacity(0.18), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)

                        Button(action: {
                            showAddTransactionSheet = true
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                Text("Add Holding")
                            }
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.blue)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)

                    if showAddedToPortfolioBanner, let pName = activePortfolio?.name {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Added \(activeQuote.symbol) to \(pName)")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal)
                        .transition(.opacity)
                    }

                    // Position Summary for this Ticker
                    if let holding = tickerHolding {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Your Position")
                                    .font(.title3.bold())
                                if let p = activePortfolio {
                                    Text("• \(p.name) (\(p.currency))")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.secondary)
                                }
                            }

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                StatTile(title: "Shares", value: formatShares(holding.totalShares))
                                StatTile(title: "Avg Cost", value: StockQuote.formatAmount(holding.avgCostPerShare, currency: holding.currency))
                                StatTile(title: "Market Value", value: StockQuote.formatAmount(holding.currentValue, currency: holding.currency))
                                StatTile(
                                    title: "Total Return",
                                    value: "\(StockQuote.formatSignedAmount(holding.totalGainLoss, currency: holding.currency)) (\(String(format: "%@%.2f%%", holding.totalGainLoss >= 0 ? "+" : "", holding.totalGainLossPercent)))",
                                    valueColor: holding.totalGainLoss >= 0 ? .green : .red
                                )
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Key Statistics (Moved Above Transactions)
                    keyStatisticsSection

                    // Transactions Made for This Ticker Separately
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("\(activeQuote.symbol) Transactions")
                                .font(.title3.bold())

                            Text("(\(tickerTransactions.count))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Spacer()

                            Button(action: {
                                showAddTransactionSheet = true
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                    Text("Record")
                                }
                                .font(.caption.bold())
                                .foregroundColor(.blue)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.blue.opacity(0.12))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal)

                        if tickerTransactions.isEmpty {
                            VStack(spacing: 8) {
                                Text("No transactions recorded for \(activeQuote.symbol)\(activePortfolio.map { " in \($0.name)" } ?? "").")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)

                                Button("Record First Trade") {
                                    showAddTransactionSheet = true
                                }
                                .font(.caption.bold())
                                .buttonStyle(.bordered)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(UIColor.secondarySystemGroupedBackground))
                            )
                            .padding(.horizontal)
                        } else {
                            let txCurrency = activePortfolio?.currency ?? activeQuote.currency
                            VStack(spacing: 0) {
                                ForEach(tickerTransactions) { tx in
                                    let realized = store.realizedPnL(for: tx.id)
                                    HStack(alignment: .center, spacing: 10) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack(spacing: 6) {
                                                Text(tx.type.rawValue)
                                                    .font(.caption2.bold())
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(tx.type == .buy ? Color.blue.opacity(0.15) : Color.orange.opacity(0.15))
                                                    .foregroundColor(tx.type == .buy ? .blue : .orange)
                                                    .cornerRadius(4)

                                                Text(tx.date.formatted(date: .abbreviated, time: .omitted))
                                                    .font(.caption.weight(.semibold))

                                                if let pnl = realized {
                                                    Text(StockQuote.formatSignedAmount(pnl, currency: txCurrency))
                                                        .font(.caption2.bold())
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background((pnl >= 0 ? Color.green : Color.red).opacity(0.12))
                                                        .foregroundColor(pnl >= 0 ? .green : .red)
                                                        .cornerRadius(4)
                                                }
                                            }

                                            if !tx.notes.isEmpty {
                                                Text(tx.notes)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(2)
                                            }
                                        }

                                        Spacer()

                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text("\(formatShares(tx.shares)) sh @ \(StockQuote.formatAmount(tx.pricePerShare, currency: txCurrency))")
                                                .font(.caption.weight(.semibold))

                                            Text(StockQuote.formatAmount(tx.totalAmount, currency: txCurrency))
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }

                                        Button(role: .destructive) {
                                            store.deleteTransaction(id: tx.id)
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.caption)
                                                .foregroundColor(.red.opacity(0.8))
                                                .padding(.leading, 4)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        transactionToEdit = tx
                                    }

                                    if tx.id != tickerTransactions.last?.id {
                                        Divider()
                                            .padding(.leading, 14)
                                    }
                                }
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(UIColor.secondarySystemGroupedBackground))
                            )
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(activeQuote.symbol)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task(id: quote.symbol) {
                isLoadingStats = true
                var base = quote
                if quote.regularMarketPrice <= 0 || quote.marketCap == nil {
                    base = await YahooFinanceService.shared.fetchQuote(symbol: quote.symbol)
                    if !Task.isCancelled {
                        liveQuote = base
                    }
                }
                let enriched = await YahooFinanceService.shared.fetchDetailedStatistics(for: base)
                if !Task.isCancelled {
                    liveQuote = enriched
                    store.quotes[enriched.symbol] = enriched
                    isLoadingStats = false
                }
            }
            .task(id: selectedTimeframe) {
                await loadChartData()
            }
            .sheet(isPresented: $showAddTransactionSheet) {
                AddTransactionView(
                    prefilledSymbol: activeQuote.symbol,
                    prefilledPrice: prefilledPriceInPortfolioCurrency,
                    prefilledPortfolioId: activePortfolio?.id,
                    store: store
                )
            }
            .sheet(item: $transactionToEdit) { tx in
                AddTransactionView(existingTransaction: tx, store: store)
            }
        }
    }

    private var keyStatisticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Key Statistics")
                    .font(.title3.bold())

                if isLoadingStats {
                    ProgressView()
                        .scaleEffect(0.75)
                }

                Spacer()

                Text(activeQuote.currency)
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(UIColor.tertiarySystemFill))
                    .clipShape(Capsule())
            }
            .padding(.horizontal)

            // Valuation Multiples
            statGroupCard(title: "Valuation") {
                StatTile(title: "Market Cap", value: activeQuote.formattedMarketCap)
                StatTile(title: "P/E (TTM)", value: formatRatio(activeQuote.peRatio))
                StatTile(title: "Forward P/E", value: formatRatio(activeQuote.forwardPE))
                StatTile(title: "P/B Ratio", value: formatRatio(activeQuote.priceToBook))
                StatTile(title: "PEG Ratio", value: formatRatio(activeQuote.pegRatio))
                StatTile(title: "P/S Ratio", value: formatRatio(activeQuote.priceToSales))
                StatTile(title: "EV / EBITDA", value: formatRatio(activeQuote.evToEbitda))
                StatTile(
                    title: "Target Price",
                    value: activeQuote.targetMeanPrice.map {
                        StockQuote.formatAmount($0, currency: activeQuote.currency, isIndex: isIndexSymbol)
                    } ?? "N/A"
                )
            }

            // Fundamentals & Financial Health
            statGroupCard(title: "Fundamentals & Profitability") {
                StatTile(title: "EPS (TTM)", value: formatQuoteAmount(activeQuote.epsTTM))
                StatTile(title: "Forward EPS", value: formatQuoteAmount(activeQuote.epsForward))
                StatTile(title: "Book Value / Sh", value: formatQuoteAmount(activeQuote.bookValue))
                StatTile(title: "Dividend Yield", value: formatPercent(activeQuote.dividendYieldPercent))
                StatTile(title: "Profit Margin", value: formatPercent(activeQuote.profitMarginPercent))
                StatTile(title: "ROE", value: formatPercent(activeQuote.roePercent))
                StatTile(title: "Debt / Equity", value: formatPercent(activeQuote.debtToEquity))
                StatTile(title: "Beta", value: formatRatio(activeQuote.beta))
            }

            // Trading & Range
            statGroupCard(title: "Trading & Range") {
                StatTile(title: "Day Low", value: formatQuoteAmount(activeQuote.dayLow))
                StatTile(title: "Day High", value: formatQuoteAmount(activeQuote.dayHigh))
                StatTile(title: "52-Wk Low", value: formatQuoteAmount(activeQuote.fiftyTwoWeekLow))
                StatTile(title: "52-Wk High", value: formatQuoteAmount(activeQuote.fiftyTwoWeekHigh))
                StatTile(title: "Open", value: formatQuoteAmount(activeQuote.openPrice))
                StatTile(title: "Prev Close", value: formatQuoteAmount(activeQuote.previousClose))
                StatTile(title: "Volume", value: formatCompactVolume(activeQuote.regularMarketVolume))
                StatTile(title: "Avg Vol (3M)", value: formatCompactVolume(activeQuote.avgVolume3Month ?? 0))
                StatTile(title: "50-Day Avg", value: formatQuoteAmount(activeQuote.fiftyDayAverage))
                StatTile(title: "200-Day Avg", value: formatQuoteAmount(activeQuote.twoHundredDayAverage))
                if let rating = activeQuote.analystRating, !rating.isEmpty {
                    StatTile(title: "Analyst Rating", value: rating)
                }
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func statGroupCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                content()
            }
        }
        .padding(.horizontal)
    }

    private func formatRatio(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "N/A" }
        return String(format: "%.2f", value)
    }

    private func formatPercent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "N/A" }
        return String(format: "%.2f%%", value)
    }

    private func formatQuoteAmount(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "N/A" }
        return StockQuote.formatAmount(value, currency: activeQuote.currency, isIndex: isIndexSymbol)
    }

    private func formatCompactVolume(_ vol: Int64) -> String {
        guard vol > 0 else { return "N/A" }
        let d = Double(vol)
        if d >= 1_000_000_000 {
            return String(format: "%.2fB", d / 1_000_000_000)
        } else if d >= 1_000_000 {
            return String(format: "%.2fM", d / 1_000_000)
        } else if d >= 1_000 {
            return String(format: "%.1fK", d / 1_000)
        }
        return "\(vol.formatted())"
    }

    private func formatShares(_ shares: Double) -> String {
        if shares.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", shares)
        }
        return String(format: "%.2f", shares)
    }

    private func loadChartData() async {
        isLoadingChart = true
        let points = await YahooFinanceService.shared.fetchChart(symbol: quote.symbol, timeframe: selectedTimeframe)
        guard !Task.isCancelled else { return }
        chartPoints = points
        isLoadingChart = false
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
    }
}
