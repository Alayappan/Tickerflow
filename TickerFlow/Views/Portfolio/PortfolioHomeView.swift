import SwiftUI

public struct PortfolioHomeView: View {
    public let store: FinanceStore

    private enum PortfolioSubView: String, CaseIterable, Identifiable {
        case positions = "Holdings & Tickers"
        case transactions = "All Trades"
        var id: String { rawValue }
    }

    @State private var selectedSubView: PortfolioSubView = .positions
    @State private var holdingSortOption: HoldingSortOption = .valueDesc
    @State private var transactionFilter: TransactionFilter = .all
    @State private var transactionSearch: String = ""

    @State private var showAddTickerSheet: Bool = false
    @State private var addTradeConfig: AddTradeSheetConfig?
    @State private var transactionToEdit: Transaction?
    @State private var showImportCSVSheet: Bool = false
    @State private var showClearConfirmation: Bool = false

    @State private var showCreatePortfolioSheet: Bool = false
    @State private var portfolioToEdit: Portfolio?
    @State private var detailSelection: DetailSelection?

    private struct AddTradeSheetConfig: Identifiable {
        let id = UUID()
        let symbol: String
        let price: Double?
        let portfolioId: UUID?
    }

    private struct DetailSelection: Identifiable {
        let id = UUID()
        let quote: StockQuote
        let portfolioId: UUID?
    }

    public init(store: FinanceStore) {
        self.store = store
    }

    private var activePortfolio: Portfolio? {
        store.currentPortfolio
    }

    private var activeCurrency: String {
        activePortfolio?.currency ?? "USD"
    }

    private var sortedHoldings: [Holding] {
        store.sortedHoldings(by: holdingSortOption, for: activePortfolio?.id)
    }

    private var trackedOnlySymbols: [String] {
        store.trackedOnlySymbols(for: activePortfolio?.id)
    }

    private var portfolioTransactions: [Transaction] {
        store.transactions(for: activePortfolio?.id)
    }

    private var filteredTransactions: [Transaction] {
        let sorted = portfolioTransactions.sorted { $0.date > $1.date }
        let typeFiltered = sorted.filter { tx in
            switch transactionFilter {
            case .all: return true
            case .buy: return tx.type == .buy
            case .sell: return tx.type == .sell
            }
        }
        let query = transactionSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return typeFiltered }
        return typeFiltered.filter {
            $0.symbol.localizedCaseInsensitiveContains(query) ||
            $0.companyName.localizedCaseInsensitiveContains(query) ||
            $0.notes.localizedCaseInsensitiveContains(query)
        }
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 1. Overall Portfolio at Top
                    overallPortfolioCard

                    // 2. Multi-Portfolio Selector Strip
                    portfolioSelectorStrip

                    // 3. Selected Portfolio Card
                    if let portfolio = activePortfolio {
                        selectedPortfolioCard(for: portfolio)
                    }

                    // 4. Direct Actions (Add Ticker / Add Holding / Import CSV)
                    actionButtonsRow

                    // 5. Holdings & Tickers vs All Trades Picker
                    Picker("Portfolio View", selection: $selectedSubView) {
                        ForEach(PortfolioSubView.allCases) { view in
                            Text(view.rawValue).tag(view)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    switch selectedSubView {
                    case .positions:
                        holdingsAndTickersSection
                    case .transactions:
                        transactionsSection
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Portfolio")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(action: {
                            showCreatePortfolioSheet = true
                        }) {
                            Label("New Portfolio", systemImage: "folder.badge.plus")
                        }

                        if let current = activePortfolio {
                            Button(action: {
                                portfolioToEdit = current
                            }) {
                                Label("Edit \"\(current.name)\"", systemImage: "pencil")
                            }
                        }

                        Divider()

                        if !store.holdings.isEmpty {
                            ShareLink(
                                item: store.exportCurrentHoldingsCSV(),
                                preview: SharePreview("TickerFlow_Holdings.csv")
                            ) {
                                Label("Export Holdings CSV", systemImage: "square.and.arrow.up")
                            }
                        }

                        Button(action: {
                            showImportCSVSheet = true
                        }) {
                            Label("Import CSV", systemImage: "square.and.arrow.down")
                        }

                        if !store.transactions.isEmpty || store.portfolios.count > 1 {
                            Divider()
                            Button(role: .destructive, action: {
                                showClearConfirmation = true
                            }) {
                                Label("Clear All Portfolio Data", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .refreshable {
                await store.refreshAllQuotes()
            }
            .confirmationDialog("Clear Portfolio Data?", isPresented: $showClearConfirmation, titleVisibility: .visible) {
                Button("Delete All Portfolios & Trades", role: .destructive) {
                    store.clearAllProfileData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes all saved portfolios, tickers, and transactions from this device.")
            }
            .sheet(isPresented: $showAddTickerSheet) {
                SymbolSearchView(store: store, targetPortfolioId: activePortfolio?.id)
            }
            .sheet(item: $addTradeConfig) { config in
                AddTransactionView(
                    prefilledSymbol: config.symbol,
                    prefilledPrice: config.price,
                    prefilledPortfolioId: config.portfolioId,
                    store: store
                )
            }
            .sheet(item: $transactionToEdit) { tx in
                AddTransactionView(existingTransaction: tx, store: store)
            }
            .sheet(isPresented: $showImportCSVSheet) {
                CSVImportView(store: store)
            }
            .sheet(isPresented: $showCreatePortfolioSheet) {
                PortfolioEditorSheet(store: store, existingPortfolio: nil)
            }
            .sheet(item: $portfolioToEdit) { portfolio in
                PortfolioEditorSheet(store: store, existingPortfolio: portfolio)
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

    // MARK: - 1. Overall Portfolio Card (Top)
    private var overallPortfolioCard: some View {
        let overall = store.overallSummary
        let isOverallGain = overall.unrealizedGainLoss >= 0
        let isOverallDayGain = overall.dayGainLoss >= 0

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(.caption.bold())
                        .foregroundColor(.blue)
                    Text("Overall Portfolio")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Menu {
                    ForEach(SupportedPortfolioCurrency.allCases) { currency in
                        Button {
                            store.setOverallCurrency(currency.rawValue)
                        } label: {
                            HStack {
                                Text(currency.displayName)
                                if overall.currency == currency.rawValue {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(overall.currency)
                            .font(.caption.bold())
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(Capsule())
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text(StockQuote.formatAmount(overall.totalValue, currency: overall.currency))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Spacer()

                if overall.totalCostBasis > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Invested")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(StockQuote.formatAmount(overall.totalCostBasis, currency: overall.currency))
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Return")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    HStack(spacing: 3) {
                        Image(systemName: isOverallGain ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 11, weight: .bold))
                        Text("\(StockQuote.formatSignedAmount(overall.unrealizedGainLoss, currency: overall.currency)) (\(String(format: "%@%.2f%%", isOverallGain ? "+" : "", overall.unrealizedGainLossPercent)))")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundColor(isOverallGain ? .green : .red)
                }

                Divider()
                    .frame(height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Day Return")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    HStack(spacing: 3) {
                        Image(systemName: isOverallDayGain ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 11, weight: .bold))
                        Text("\(StockQuote.formatSignedAmount(overall.dayGainLoss, currency: overall.currency)) (\(String(format: "%@%.2f%%", isOverallDayGain ? "+" : "", overall.dayGainLossPercent)))")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundColor(isOverallDayGain ? .green : .red)
                }
            }

            HStack(spacing: 8) {
                Text("\(overall.portfolioCount) \(overall.portfolioCount == 1 ? "Portfolio" : "Portfolios") • \(overall.positionsCount) Holdings • \(overall.trackedTickersCount) Tickers")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.secondary)

                Spacer()

                if overall.realizedGainLoss != 0 {
                    Text("Realized: \(StockQuote.formatSignedAmount(overall.realizedGainLoss, currency: overall.currency))")
                        .font(.caption2.bold())
                        .foregroundColor(overall.realizedGainLoss >= 0 ? .green : .red)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.12), Color(UIColor.secondarySystemGroupedBackground)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.blue.opacity(0.22), lineWidth: 1)
                )
        )
        .padding(.horizontal)
    }

    // MARK: - 2. Multi-Portfolio Selector Strip
    private var portfolioSelectorStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.portfolios) { portfolio in
                    let isSelected = (activePortfolio?.id == portfolio.id)
                    let posCount = store.portfolioHoldingsMap[portfolio.id]?.count ?? 0

                    Button(action: {
                        store.selectPortfolio(id: portfolio.id)
                    }) {
                        HStack(spacing: 6) {
                            Text(portfolio.name)
                                .font(.subheadline)
                                .fontWeight(isSelected ? .bold : .medium)

                            Text(portfolio.currency)
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(isSelected ? Color.white.opacity(0.24) : Color.primary.opacity(0.08))
                                .clipShape(Capsule())

                            if posCount > 0 {
                                Text("\(posCount)")
                                    .font(.caption2)
                                    .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
                            }
                        }
                        .foregroundColor(isSelected ? .white : .primary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.blue : Color(UIColor.secondarySystemGroupedBackground))
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            portfolioToEdit = portfolio
                        } label: {
                            Label("Edit Portfolio", systemImage: "pencil")
                        }

                        if store.portfolios.count > 1 {
                            Button(role: .destructive) {
                                store.deletePortfolio(id: portfolio.id)
                            } label: {
                                Label("Delete Portfolio", systemImage: "trash")
                            }
                        }
                    }
                }

                Button(action: {
                    showCreatePortfolioSheet = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("New Portfolio")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .strokeBorder(Color.blue.opacity(0.45), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
        }
    }

    // MARK: - 3. Selected Portfolio Card
    private func selectedPortfolioCard(for portfolio: Portfolio) -> some View {
        let stats = store.analytics(for: portfolio.id)
        let isGain = stats.unrealizedGainLoss >= 0
        let isDayGain = stats.dayGainLoss >= 0

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(portfolio.name)
                            .font(.headline.bold())
                        Text(portfolio.currency)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12))
                            .foregroundColor(.blue)
                            .clipShape(Capsule())
                    }

                    Text(StockQuote.formatAmount(stats.totalValue, currency: portfolio.currency))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                }

                Spacer()

                Button {
                    portfolioToEdit = portfolio
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Invested")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(StockQuote.formatAmount(stats.totalCostBasis, currency: portfolio.currency))
                        .font(.caption.weight(.semibold))
                }

                Divider().frame(height: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Return")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(StockQuote.formatSignedAmount(stats.unrealizedGainLoss, currency: portfolio.currency)) (\(String(format: "%@%.2f%%", isGain ? "+" : "", stats.unrealizedGainLossPercent)))")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(isGain ? .green : .red)
                }

                Divider().frame(height: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Day")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(String(format: "%@%.2f%%", isDayGain ? "+" : "", stats.dayGainLossPercent))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(isDayGain ? .green : .red)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
        )
        .padding(.horizontal)
    }

    // MARK: - 4. Action Buttons
    private var actionButtonsRow: some View {
        HStack(spacing: 8) {
            Button(action: {
                showAddTickerSheet = true
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass.circle.fill")
                    Text("Add Ticker")
                }
                .font(.caption.bold())
                .foregroundColor(.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.blue.opacity(0.12))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)

            Button(action: {
                addTradeConfig = AddTradeSheetConfig(
                    symbol: "",
                    price: nil,
                    portfolioId: activePortfolio?.id
                )
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Holding")
                }
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.blue)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)

            Button(action: {
                showImportCSVSheet = true
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "square.and.arrow.down")
                    Text("Import CSV")
                }
                .font(.caption.bold())
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
    }

    // MARK: - 5A. Holdings & Tracked Tickers Section
    private var holdingsAndTickersSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Holdings Header
            HStack {
                Text("Holdings")
                    .font(.title3.bold())

                Text("(\(sortedHoldings.count))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                if !sortedHoldings.isEmpty {
                    Menu {
                        ForEach(HoldingSortOption.allCases) { option in
                            Button(action: {
                                holdingSortOption = option
                            }) {
                                HStack {
                                    Text(option.rawValue)
                                    if holdingSortOption == option {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.arrow.down")
                            Text(holdingSortOption.rawValue)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal)

            if sortedHoldings.isEmpty && trackedOnlySymbols.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "briefcase")
                        .font(.system(size: 46))
                        .foregroundColor(.secondary)
                        .padding(.top, 20)

                    Text("No Tickers or Holdings in \(activePortfolio?.name ?? "Portfolio")")
                        .font(.headline)

                    Text("Tap Add Ticker to track symbols in this portfolio, Add Holding to record a buy/sell trade, or Import CSV to import from a file.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 26)

                    HStack(spacing: 10) {
                        Button("Add Ticker") {
                            showAddTickerSheet = true
                        }
                        .font(.caption.bold())
                        .buttonStyle(.bordered)

                        Button("Import CSV") {
                            showImportCSVSheet = true
                        }
                        .font(.caption.bold())
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.bottom, 20)
                }
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(UIColor.secondarySystemGroupedBackground))
                )
                .padding(.horizontal)
            } else {
                if !sortedHoldings.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(sortedHoldings) { holding in
                            let txCount = store.transactionsForSymbol(holding.symbol, portfolioId: activePortfolio?.id).count
                            VStack(spacing: 0) {
                                HStack(spacing: 6) {
                                    HoldingRowView(holding: holding, portfolioTotalValue: store.analytics(for: activePortfolio?.id).totalValue)

                                    VStack(alignment: .trailing, spacing: 4) {
                                        Image(systemName: "chevron.right")
                                            .font(.caption2.bold())
                                            .foregroundColor(.secondary.opacity(0.6))
                                        if txCount > 0 {
                                            Text("\(txCount) tx")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundColor(.blue)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(Color.blue.opacity(0.1))
                                                .clipShape(Capsule())
                                        }
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    openQuoteDetail(for: holding.symbol, portfolioId: activePortfolio?.id)
                                }
                                .contextMenu {
                                    Button {
                                        openQuoteDetail(for: holding.symbol, portfolioId: activePortfolio?.id)
                                    } label: {
                                        Label("View \(holding.symbol) Transactions", systemImage: "list.bullet.rectangle")
                                    }

                                    Button {
                                        addTradeConfig = AddTradeSheetConfig(
                                            symbol: holding.symbol,
                                            price: holding.currentPrice,
                                            portfolioId: activePortfolio?.id
                                        )
                                    } label: {
                                        Label("Add Holding / Trade", systemImage: "plus.circle")
                                    }

                                    Button(role: .destructive) {
                                        store.deletePosition(symbol: holding.symbol, portfolioId: activePortfolio?.id)
                                    } label: {
                                        Label("Delete \(holding.symbol) Position", systemImage: "trash")
                                    }
                                }
                            }

                            if holding.id != sortedHoldings.last?.id {
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(UIColor.secondarySystemGroupedBackground))
                    )
                    .padding(.horizontal)
                }

                // Tracked Tickers Added to Portfolio (without active shares yet)
                if !trackedOnlySymbols.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Tracked Tickers")
                                .font(.headline)
                            Text("(\(trackedOnlySymbols.count))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("Tap to view or add holding")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)

                        VStack(spacing: 0) {
                            ForEach(trackedOnlySymbols, id: \.self) { sym in
                                let quote = store.quotes[sym]
                                let quoteCurrency = quote?.currency ?? activeCurrency
                                let fx = store.fxRate(from: quoteCurrency, to: activeCurrency)
                                let priceInPortfolioCurrency = (quote?.regularMarketPrice ?? 0) * fx
                                let changePct = quote?.regularMarketChangePercent ?? 0
                                let isPos = changePct >= 0

                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(sym)
                                            .font(.system(size: 15, weight: .bold, design: .rounded))
                                        Text(quote?.companyName ?? "Tap to inspect")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    if let q = quote, q.regularMarketPrice > 0 {
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(StockQuote.formatAmount(priceInPortfolioCurrency, currency: activeCurrency))
                                                .font(.subheadline.bold())
                                            Text(String(format: "%@%.2f%%", isPos ? "+" : "", changePct))
                                                .font(.caption2.weight(.semibold))
                                                .foregroundColor(isPos ? .green : .red)
                                        }
                                    }

                                    Button {
                                        addTradeConfig = AddTradeSheetConfig(
                                            symbol: sym,
                                            price: priceInPortfolioCurrency > 0 ? priceInPortfolioCurrency : nil,
                                            portfolioId: activePortfolio?.id
                                        )
                                    } label: {
                                        HStack(spacing: 3) {
                                            Image(systemName: "plus")
                                            Text("Buy")
                                        }
                                        .font(.caption2.bold())
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(Color.blue)
                                        .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    openQuoteDetail(for: sym, portfolioId: activePortfolio?.id)
                                }
                                .contextMenu {
                                    Button {
                                        openQuoteDetail(for: sym, portfolioId: activePortfolio?.id)
                                    } label: {
                                        Label("View Details & Transactions", systemImage: "chart.line.uptrend.xyaxis")
                                    }

                                    Button(role: .destructive) {
                                        store.removeTickerFromPortfolio(sym, portfolioId: activePortfolio?.id)
                                    } label: {
                                        Label("Remove \(sym)", systemImage: "trash")
                                    }
                                }

                                if sym != trackedOnlySymbols.last {
                                    Divider()
                                        .padding(.leading, 16)
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color(UIColor.secondarySystemGroupedBackground))
                        )
                        .padding(.horizontal)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - 5B. All Trades Section
    private var transactionsSection: some View {
        let stats = store.analytics(for: activePortfolio?.id)
        return VStack(alignment: .leading, spacing: 12) {
            if portfolioTransactions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 42))
                        .foregroundColor(.secondary)
                        .padding(.top, 18)

                    Text("No Trades in \(activePortfolio?.name ?? "Portfolio")")
                        .font(.headline)

                    Text("Add a holding manually or import a CSV to record buy/sell transactions.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 18)
                }
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(UIColor.secondarySystemGroupedBackground))
                )
                .padding(.horizontal)
            } else {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Trades")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(portfolioTransactions.count)")
                            .font(.subheadline.bold())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bought")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(StockQuote.formatAmount(stats.totalBoughtVolume, currency: activeCurrency))
                            .font(.subheadline.bold())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sold")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(StockQuote.formatAmount(stats.totalSoldVolume, currency: activeCurrency))
                            .font(.subheadline.bold())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(UIColor.secondarySystemGroupedBackground))
                )
                .padding(.horizontal)

                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(TransactionFilter.allCases) { filter in
                            let isSelected = transactionFilter == filter
                            Button(action: {
                                transactionFilter = filter
                            }) {
                                Text(filter.rawValue)
                                    .font(.caption.weight(isSelected ? .bold : .medium))
                                    .foregroundColor(isSelected ? .white : .primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(isSelected ? Color.blue : Color(UIColor.secondarySystemGroupedBackground))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                        Text("\(filteredTransactions.count) shown")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Filter by symbol or note...", text: $transactionSearch)
                            .font(.subheadline)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        if !transactionSearch.isEmpty {
                            Button(action: { transactionSearch = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(UIColor.secondarySystemGroupedBackground))
                    )
                }
                .padding(.horizontal)

                if filteredTransactions.isEmpty {
                    Text("No matching transactions.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                } else {
                    VStack(spacing: 0) {
                        ForEach(filteredTransactions) { tx in
                            let realizedPnL = stats.realizedPnLByTransactionId[tx.id]

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

                                        Text(tx.symbol)
                                            .font(.subheadline.bold())

                                        if let pnl = realizedPnL {
                                            Text(StockQuote.formatSignedAmount(pnl, currency: activeCurrency))
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background((pnl >= 0 ? Color.green : Color.red).opacity(0.12))
                                                .foregroundColor(pnl >= 0 ? .green : .red)
                                                .cornerRadius(4)
                                        }
                                    }

                                    HStack(spacing: 6) {
                                        Text(tx.date.formatted(date: .abbreviated, time: .omitted))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)

                                        if !tx.notes.isEmpty {
                                            Text("• \(tx.notes)")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(formatShares(tx.shares)) sh @ \(StockQuote.formatAmount(tx.pricePerShare, currency: activeCurrency))")
                                        .font(.caption.weight(.medium))

                                    Text(StockQuote.formatAmount(tx.totalAmount, currency: activeCurrency))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                Button(role: .destructive) {
                                    store.deleteTransaction(id: tx.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                        .foregroundColor(.red.opacity(0.8))
                                        .padding(.leading, 6)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                transactionToEdit = tx
                            }

                            if tx.id != filteredTransactions.last?.id {
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(UIColor.secondarySystemGroupedBackground))
                    )
                    .padding(.horizontal)
                }
            }
        }
    }

    private func formatShares(_ shares: Double) -> String {
        if shares.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", shares)
        }
        return String(format: "%.2f", shares)
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

private struct PortfolioEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let store: FinanceStore
    let existingPortfolio: Portfolio?

    @State private var name: String
    @State private var currency: String

    init(store: FinanceStore, existingPortfolio: Portfolio?) {
        self.store = store
        self.existingPortfolio = existingPortfolio
        _name = State(initialValue: existingPortfolio?.name ?? "")
        _currency = State(initialValue: existingPortfolio?.currency ?? "USD")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Portfolio Details") {
                    TextField("Portfolio Name (e.g. India NSE, US Core)", text: $name)

                    Picker("Base Currency", selection: $currency) {
                        ForEach(SupportedPortfolioCurrency.allCases) { curr in
                            Text(curr.displayName).tag(curr.rawValue)
                        }
                    }
                }

                if let existing = existingPortfolio, store.portfolios.count > 1 {
                    Section {
                        Button(role: .destructive) {
                            store.deletePortfolio(id: existing.id)
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Text("Delete Portfolio")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(existingPortfolio == nil ? "New Portfolio" : "Edit Portfolio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let existing = existingPortfolio {
                            store.updatePortfolio(id: existing.id, name: name, currency: currency)
                        } else {
                            store.createPortfolio(name: name, currency: currency)
                        }
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
