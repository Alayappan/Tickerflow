import Foundation
import Observation

@Observable
@MainActor
public final class FinanceStore {
    public var activeProfile: UserProfile
    public var portfolios: [Portfolio] = []
    public var selectedPortfolioId: UUID?
    public var overallCurrency: String = "USD"
    public var transactions: [Transaction] = []
    public var quotes: [String: StockQuote] = [:]
    public var marketIndices: [MarketIndex] = []
    public var selectedMarketRegion: MarketRegion = .all

    public private(set) var holdings: [Holding] = []
    public private(set) var analytics: PortfolioAnalytics = .empty
    public private(set) var overallSummary: OverallPortfolioSummary = .empty
    public private(set) var overallHoldings: [Holding] = []
    public private(set) var overallAnalytics: PortfolioAnalytics = .empty

    public private(set) var portfolioHoldingsMap: [UUID: [Holding]] = [:]
    public private(set) var portfolioAnalyticsMap: [UUID: PortfolioAnalytics] = [:]

    public var searchResults: [StockQuote] = []
    public var isSearching: Bool = false
    public var isRefreshing: Bool = false
    public var selectedQuoteForDetail: StockQuote?

    private let financeService = YahooFinanceService.shared
    private let persistence = PersistenceService.shared

    private static let fallbackUSDPerUnit: [String: Double] = [
        "USD": 1.0,
        "INR": 1.0 / 84.4,
        "EUR": 1.08,
        "GBP": 1.27,
        "JPY": 1.0 / 154.0,
        "CAD": 1.0 / 1.39,
        "AUD": 1.0 / 1.53,
        "SGD": 1.0 / 1.34,
        "HKD": 1.0 / 7.78,
        "CHF": 1.13
    ]

    public init() {
        let savedProfile = persistence.loadProfile() ?? UserProfile.defaultGoogle
        self.activeProfile = savedProfile
        self.marketIndices = YahooFinanceService.defaultMarketIndices()
        self.loadDataForActiveProfile()

        Task {
            await self.refreshAllQuotes()
        }
    }

    // MARK: - Active Portfolio Helpers
    public var currentPortfolio: Portfolio? {
        guard let id = selectedPortfolioId else { return portfolios.first }
        return portfolios.first { $0.id == id } ?? portfolios.first
    }

    public var activePortfolioCurrency: String {
        currentPortfolio?.currency ?? "USD"
    }

    public func portfolio(for id: UUID?) -> Portfolio? {
        guard let id else { return currentPortfolio }
        return portfolios.first { $0.id == id }
    }

    public func setOverallCurrency(_ currency: String) {
        let code = currency.uppercased()
        guard code != overallCurrency else { return }
        overallCurrency = code
        recomputePortfolioState()
        saveCurrentProfileData()
    }

    // MARK: - Live FX Conversion
    public func fxRate(from sourceCurrency: String, to targetCurrency: String) -> Double {
        let src = sourceCurrency.uppercased()
        let dst = targetCurrency.uppercased()
        if src == dst { return 1.0 }
        let usdFromSrc = usdValue(ofOneUnitIn: src)
        let usdFromDst = usdValue(ofOneUnitIn: dst)
        guard usdFromDst > 0 else { return 1.0 }
        return usdFromSrc / usdFromDst
    }

    private func usdValue(ofOneUnitIn currency: String) -> Double {
        let code = currency.uppercased()
        if code == "USD" { return 1.0 }

        if code == "EUR", let eurUsd = quotes["EURUSD=X"]?.regularMarketPrice, eurUsd > 0 {
            return eurUsd
        }
        if let usdToCode = quotes["USD\(code)=X"]?.regularMarketPrice, usdToCode > 0 {
            return 1.0 / usdToCode
        }
        return Self.fallbackUSDPerUnit[code] ?? 1.0
    }

    // MARK: - Holdings & Analytics Calculation
    private func recomputePortfolioState() {
        var newHoldingsMap: [UUID: [Holding]] = [:]
        var newAnalyticsMap: [UUID: PortfolioAnalytics] = [:]
        var allRealizedPnLByTxId: [UUID: Double] = [:]

        var combinedOverallHoldings: [Holding] = []
        var totalOverallValue: Double = 0
        var totalOverallCost: Double = 0
        var totalOverallRealized: Double = 0
        var totalOverallDayGL: Double = 0
        var totalOverallBuysCount: Int = 0
        var totalOverallSellsCount: Int = 0
        var totalOverallBoughtVolume: Double = 0
        var totalOverallSoldVolume: Double = 0
        var breakdowns: [PortfolioBreakdown] = []

        let fallbackPortfolioId = portfolios.first?.id

        for portfolio in portfolios {
            let pTxs = transactions.filter { ($0.portfolioId ?? fallbackPortfolioId) == portfolio.id }
            let computed = computeState(for: pTxs, portfolioId: portfolio.id, targetCurrency: portfolio.currency)

            newHoldingsMap[portfolio.id] = computed.holdings
            newAnalyticsMap[portfolio.id] = computed.analytics
            for (txId, pnl) in computed.analytics.realizedPnLByTransactionId {
                allRealizedPnLByTxId[txId] = pnl
            }

            let fxToOverall = fxRate(from: portfolio.currency, to: overallCurrency)
            let pOverallValue = computed.analytics.totalValue * fxToOverall
            let pOverallCost = computed.analytics.totalCostBasis * fxToOverall
            let pOverallUnrealized = computed.analytics.unrealizedGainLoss * fxToOverall
            let pOverallRealized = computed.analytics.realizedGainLoss * fxToOverall
            let pOverallDayGL = computed.analytics.dayGainLoss * fxToOverall

            totalOverallValue += pOverallValue
            totalOverallCost += pOverallCost
            totalOverallRealized += pOverallRealized
            totalOverallDayGL += pOverallDayGL
            totalOverallBuysCount += computed.analytics.totalBuysCount
            totalOverallSellsCount += computed.analytics.totalSellsCount
            totalOverallBoughtVolume += computed.analytics.totalBoughtVolume * fxToOverall
            totalOverallSoldVolume += computed.analytics.totalSoldVolume * fxToOverall

            for h in computed.holdings {
                let convertedHolding = Holding(
                    portfolioId: portfolio.id,
                    symbol: h.symbol,
                    companyName: h.companyName,
                    totalShares: h.totalShares,
                    totalCostBasis: h.totalCostBasis * fxToOverall,
                    currentPrice: h.currentPrice * fxToOverall,
                    previousClosePrice: h.previousClosePrice * fxToOverall,
                    currency: overallCurrency,
                    quoteCurrency: h.quoteCurrency
                )
                combinedOverallHoldings.append(convertedHolding)
            }

            breakdowns.append(
                PortfolioBreakdown(
                    portfolio: portfolio,
                    nativeValue: computed.analytics.totalValue,
                    overallCurrencyValue: pOverallValue,
                    unrealizedGainLossOverall: pOverallUnrealized,
                    dayGainLossOverall: pOverallDayGL,
                    positionsCount: computed.holdings.count,
                    trackedTickersCount: portfolio.trackedSymbols.count
                )
            )
        }

        self.portfolioHoldingsMap = newHoldingsMap
        self.portfolioAnalyticsMap = newAnalyticsMap

        if let activeId = currentPortfolio?.id {
            self.holdings = newHoldingsMap[activeId] ?? []
            self.analytics = newAnalyticsMap[activeId] ?? .empty
        } else {
            self.holdings = []
            self.analytics = .empty
        }

        combinedOverallHoldings.sort { $0.currentValue > $1.currentValue }
        let overallUnrealized = totalOverallValue - totalOverallCost
        let overallUnrealizedPct = totalOverallCost > 0 ? (overallUnrealized / totalOverallCost) * 100 : 0
        let prevOverallTotal = totalOverallValue - totalOverallDayGL
        let overallDayPct = prevOverallTotal > 0 ? (totalOverallDayGL / prevOverallTotal) * 100 : 0

        let winners = combinedOverallHoldings.filter { $0.totalGainLoss >= 0 }.count
        let losers = combinedOverallHoldings.count - winners
        let winRate = combinedOverallHoldings.isEmpty ? 0 : (Double(winners) / Double(combinedOverallHoldings.count)) * 100
        let topGainer = combinedOverallHoldings.max { $0.totalGainLossPercent < $1.totalGainLossPercent }
        let topLoser = combinedOverallHoldings.min { $0.totalGainLossPercent < $1.totalGainLossPercent }
        let largest = combinedOverallHoldings.max { $0.currentValue < $1.currentValue }
        let largestWeight = (totalOverallValue > 0 && largest != nil) ? ((largest?.currentValue ?? 0) / totalOverallValue) * 100 : 0

        self.overallHoldings = combinedOverallHoldings
        self.overallAnalytics = PortfolioAnalytics(
            totalValue: totalOverallValue,
            totalCostBasis: totalOverallCost,
            unrealizedGainLoss: overallUnrealized,
            unrealizedGainLossPercent: overallUnrealizedPct,
            realizedGainLoss: totalOverallRealized,
            netTotalGainLoss: overallUnrealized + totalOverallRealized,
            dayGainLoss: totalOverallDayGL,
            dayGainLossPercent: overallDayPct,
            profitablePositionsCount: winners,
            losingPositionsCount: losers,
            winRatePercent: winRate,
            topGainer: topGainer,
            topLoser: topLoser,
            largestPosition: largest,
            largestPositionWeight: largestWeight,
            totalBuysCount: totalOverallBuysCount,
            totalSellsCount: totalOverallSellsCount,
            totalBoughtVolume: totalOverallBoughtVolume,
            totalSoldVolume: totalOverallSoldVolume,
            realizedPnLByTransactionId: allRealizedPnLByTxId
        )

        let totalUniqueTracked = Set(portfolios.flatMap(\.trackedSymbols)).count
        self.overallSummary = OverallPortfolioSummary(
            currency: overallCurrency,
            totalValue: totalOverallValue,
            totalCostBasis: totalOverallCost,
            unrealizedGainLoss: overallUnrealized,
            unrealizedGainLossPercent: overallUnrealizedPct,
            realizedGainLoss: totalOverallRealized,
            netTotalGainLoss: overallUnrealized + totalOverallRealized,
            dayGainLoss: totalOverallDayGL,
            dayGainLossPercent: overallDayPct,
            portfolioCount: portfolios.count,
            positionsCount: combinedOverallHoldings.count,
            trackedTickersCount: totalUniqueTracked,
            breakdowns: breakdowns
        )
    }

    private func computeState(
        for portfolioTransactions: [Transaction],
        portfolioId: UUID,
        targetCurrency: String
    ) -> (holdings: [Holding], analytics: PortfolioAnalytics) {
        var map: [String: (shares: Double, cost: Double, name: String)] = [:]
        var realizedByTxId: [UUID: Double] = [:]
        var totalRealized: Double = 0

        let chronological = portfolioTransactions.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            if $0.type != $1.type { return $0.type == .buy }
            return $0.id.uuidString < $1.id.uuidString
        }

        for tx in chronological {
            let sym = tx.symbol.uppercased()
            let current = map[sym] ?? (0, 0, tx.companyName)
            let name = current.name.isEmpty ? tx.companyName : current.name

            if tx.type == .buy {
                let newShares = current.shares + tx.shares
                let newCost = current.cost + (tx.shares * tx.pricePerShare)
                map[sym] = (newShares, newCost, name)
            } else {
                let avgCost = current.shares > 0 ? (current.cost / current.shares) : 0
                let matchedShares = min(current.shares, tx.shares)
                let realized = (tx.pricePerShare - avgCost) * matchedShares
                if matchedShares > 0 {
                    realizedByTxId[tx.id] = realized
                    totalRealized += realized
                }
                let newShares = max(0, current.shares - tx.shares)
                let newCost = max(0, newShares * avgCost)
                map[sym] = (newShares, newCost, name)
            }
        }

        let computedHoldings: [Holding] = map.compactMap { (symbol, data) -> Holding? in
            guard data.shares > 0.00001 else { return nil }
            let quote = quotes[symbol]
            let quoteCurrency = quote?.currency ?? targetCurrency
            let fx = fxRate(from: quoteCurrency, to: targetCurrency)
            let fallbackAvg = data.shares > 0 ? (data.cost / data.shares) : 0
            let price = quote.map { $0.regularMarketPrice * fx } ?? fallbackAvg
            let changeInPortfolioCurrency = (quote?.regularMarketChange ?? 0) * fx
            let prevClose = price - changeInPortfolioCurrency
            let companyName: String
            if let qName = quote?.companyName, !qName.isEmpty {
                companyName = qName
            } else {
                companyName = data.name
            }

            return Holding(
                portfolioId: portfolioId,
                symbol: symbol,
                companyName: companyName,
                totalShares: data.shares,
                totalCostBasis: data.cost,
                currentPrice: price,
                previousClosePrice: prevClose,
                currency: targetCurrency,
                quoteCurrency: quoteCurrency
            )
        }.sorted { $0.currentValue > $1.currentValue }

        let totalValue = computedHoldings.reduce(0) { $0 + $1.currentValue }
        let totalCost = computedHoldings.reduce(0) { $0 + $1.totalCostBasis }
        let unrealized = totalValue - totalCost
        let unrealizedPct = totalCost > 0 ? (unrealized / totalCost) * 100 : 0
        let dayGL = computedHoldings.reduce(0) { $0 + $1.dayGainLoss }
        let prevTotal = totalValue - dayGL
        let dayPct = prevTotal > 0 ? (dayGL / prevTotal) * 100 : 0

        let winners = computedHoldings.filter { $0.totalGainLoss >= 0 }.count
        let losers = computedHoldings.count - winners
        let winRate = computedHoldings.isEmpty ? 0 : (Double(winners) / Double(computedHoldings.count)) * 100

        let topGainer = computedHoldings.max { $0.totalGainLossPercent < $1.totalGainLossPercent }
        let topLoser = computedHoldings.min { $0.totalGainLossPercent < $1.totalGainLossPercent }
        let largest = computedHoldings.max { $0.currentValue < $1.currentValue }
        let largestWeight = (totalValue > 0 && largest != nil) ? ((largest?.currentValue ?? 0) / totalValue) * 100 : 0

        let buys = portfolioTransactions.filter { $0.type == .buy }
        let sells = portfolioTransactions.filter { $0.type == .sell }

        let portfolioAnalytics = PortfolioAnalytics(
            totalValue: totalValue,
            totalCostBasis: totalCost,
            unrealizedGainLoss: unrealized,
            unrealizedGainLossPercent: unrealizedPct,
            realizedGainLoss: totalRealized,
            netTotalGainLoss: unrealized + totalRealized,
            dayGainLoss: dayGL,
            dayGainLossPercent: dayPct,
            profitablePositionsCount: winners,
            losingPositionsCount: losers,
            winRatePercent: winRate,
            topGainer: topGainer,
            topLoser: topLoser,
            largestPosition: largest,
            largestPositionWeight: largestWeight,
            totalBuysCount: buys.count,
            totalSellsCount: sells.count,
            totalBoughtVolume: buys.reduce(0) { $0 + $1.totalAmount },
            totalSoldVolume: sells.reduce(0) { $0 + $1.totalAmount },
            realizedPnLByTransactionId: realizedByTxId
        )

        return (computedHoldings, portfolioAnalytics)
    }

    public func selectPortfolio(id: UUID) {
        selectedPortfolioId = id
        self.holdings = portfolioHoldingsMap[id] ?? []
        self.analytics = portfolioAnalyticsMap[id] ?? .empty
    }

    public func sortedHoldings(by option: HoldingSortOption, for portfolioId: UUID? = nil) -> [Holding] {
        let source: [Holding]
        if let pid = portfolioId {
            source = portfolioHoldingsMap[pid] ?? []
        } else {
            source = holdings
        }
        return sortHoldingsList(source, by: option)
    }

    private func sortHoldingsList(_ list: [Holding], by option: HoldingSortOption) -> [Holding] {
        switch option {
        case .valueDesc:
            return list
        case .returnPercentDesc:
            return list.sorted { $0.totalGainLossPercent > $1.totalGainLossPercent }
        case .returnAmountDesc:
            return list.sorted { $0.totalGainLoss > $1.totalGainLoss }
        case .dayChangeDesc:
            return list.sorted { $0.dayGainLossPercent > $1.dayGainLossPercent }
        case .symbolAsc:
            return list.sorted { $0.symbol < $1.symbol }
        }
    }

    public func holdings(for portfolioId: UUID?) -> [Holding] {
        guard let pid = portfolioId else { return overallHoldings }
        return portfolioHoldingsMap[pid] ?? []
    }

    public func analytics(for portfolioId: UUID?) -> PortfolioAnalytics {
        guard let pid = portfolioId else { return overallAnalytics }
        return portfolioAnalyticsMap[pid] ?? .empty
    }

    public func transactions(for portfolioId: UUID? = nil) -> [Transaction] {
        let targetId = portfolioId ?? currentPortfolio?.id
        guard let targetId else { return transactions }
        let fallbackId = portfolios.first?.id
        return transactions.filter { ($0.portfolioId ?? fallbackId) == targetId }
    }

    public func transactionsForSymbol(_ symbol: String, portfolioId: UUID? = nil) -> [Transaction] {
        let sym = symbol.uppercased()
        let base: [Transaction]
        if let portfolioId {
            let fallbackId = portfolios.first?.id
            base = transactions.filter { ($0.portfolioId ?? fallbackId) == portfolioId && $0.symbol.uppercased() == sym }
        } else {
            base = transactions.filter { $0.symbol.uppercased() == sym }
        }
        return base.sorted { $0.date > $1.date }
    }

    public func realizedPnL(for transactionId: UUID) -> Double? {
        overallAnalytics.realizedPnLByTransactionId[transactionId]
    }

    public func holding(forSymbol symbol: String, portfolioId: UUID? = nil) -> Holding? {
        let sym = symbol.uppercased()
        let pid = portfolioId ?? currentPortfolio?.id
        if let pid {
            return (portfolioHoldingsMap[pid] ?? []).first { $0.symbol == sym }
        }
        return overallHoldings.first { $0.symbol == sym }
    }

    public func trackedOnlySymbols(for portfolioId: UUID? = nil) -> [String] {
        guard let portfolio = portfolio(for: portfolioId) else { return [] }
        let activeSymbols = Set((portfolioHoldingsMap[portfolio.id] ?? []).map(\.symbol))
        return portfolio.trackedSymbols.filter { !activeSymbols.contains($0) }
    }

    public var totalPortfolioValue: Double { analytics.totalValue }
    public var totalCostBasis: Double { analytics.totalCostBasis }
    public var totalGainLoss: Double { analytics.unrealizedGainLoss }
    public var totalGainLossPercent: Double { analytics.unrealizedGainLossPercent }
    public var dayGainLoss: Double { analytics.dayGainLoss }
    public var dayGainLossPercent: Double { analytics.dayGainLossPercent }

    // MARK: - Profile Management
    public func switchProfile(to profile: UserProfile) {
        saveCurrentProfileData()

        activeProfile = profile
        persistence.saveProfile(profile)
        loadDataForActiveProfile()

        Task {
            await refreshAllQuotes()
        }
    }

    public func updateProfileEmail(_ newEmail: String, displayName: String, provider: AccountProvider) {
        activeProfile.email = newEmail
        activeProfile.displayName = displayName
        activeProfile.provider = provider
        activeProfile.lastSyncTime = Date()
        persistence.saveProfile(activeProfile)
        saveCurrentProfileData()
    }

    // MARK: - Multi-Portfolio CRUD
    @discardableResult
    public func createPortfolio(name: String, currency: String) -> Portfolio? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let created = Portfolio(name: trimmed, currency: currency.uppercased())
        portfolios.append(created)
        selectedPortfolioId = created.id
        recomputePortfolioState()
        saveCurrentProfileData()
        return created
    }

    public func updatePortfolio(id: UUID, name: String, currency: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = portfolios.firstIndex(where: { $0.id == id }) else { return }
        portfolios[idx].name = trimmed
        portfolios[idx].currency = currency.uppercased()
        recomputePortfolioState()
        saveCurrentProfileData()
    }

    public func deletePortfolio(id: UUID) {
        guard portfolios.count > 1 else { return }
        portfolios.removeAll { $0.id == id }
        transactions.removeAll { $0.portfolioId == id }
        if selectedPortfolioId == id {
            selectedPortfolioId = portfolios.first?.id
        }
        recomputePortfolioState()
        saveCurrentProfileData()
    }

    // MARK: - Portfolio Ticker Management
    public func addTickerToPortfolio(_ symbol: String, portfolioId: UUID? = nil) {
        let sym = symbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sym.isEmpty else { return }

        let targetId = portfolioId ?? selectedPortfolioId ?? portfolios.first?.id
        guard let tId = targetId,
              let idx = portfolios.firstIndex(where: { $0.id == tId }) else {
            let newPortfolio = Portfolio(name: "Main Portfolio", currency: "USD", trackedSymbols: [sym])
            portfolios.append(newPortfolio)
            selectedPortfolioId = newPortfolio.id
            recomputePortfolioState()
            saveCurrentProfileData()
            Task { await fetchSingleQuote(symbol: sym) }
            return
        }

        if !portfolios[idx].trackedSymbols.contains(sym) {
            portfolios[idx].trackedSymbols.append(sym)
            portfolios[idx].trackedSymbols.sort()
            recomputePortfolioState()
            saveCurrentProfileData()
            Task { await fetchSingleQuote(symbol: sym) }
        }
    }

    public func removeTickerFromPortfolio(_ symbol: String, portfolioId: UUID? = nil) {
        let sym = symbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let targetId = portfolioId ?? selectedPortfolioId ?? portfolios.first?.id
        guard let tId = targetId,
              let idx = portfolios.firstIndex(where: { $0.id == tId }) else { return }

        portfolios[idx].trackedSymbols.removeAll { $0 == sym }
        recomputePortfolioState()
        saveCurrentProfileData()
    }

    public func isSymbolInPortfolio(_ symbol: String, portfolioId: UUID? = nil) -> Bool {
        let sym = symbol.uppercased()
        guard let portfolio = portfolio(for: portfolioId) else { return false }
        if portfolio.trackedSymbols.contains(sym) { return true }
        return (portfolioHoldingsMap[portfolio.id] ?? []).contains { $0.symbol == sym }
    }

    // MARK: - Transaction Actions
    public func addTransaction(_ tx: Transaction) {
        let resolvedPortfolioId = tx.portfolioId ?? currentPortfolio?.id ?? portfolios.first?.id
        var normalizedTx = tx
        normalizedTx.portfolioId = resolvedPortfolioId

        transactions.append(normalizedTx)
        if let pid = resolvedPortfolioId,
           let idx = portfolios.firstIndex(where: { $0.id == pid }),
           !portfolios[idx].trackedSymbols.contains(normalizedTx.symbol) {
            portfolios[idx].trackedSymbols.append(normalizedTx.symbol)
            portfolios[idx].trackedSymbols.sort()
        }

        recomputePortfolioState()
        saveCurrentProfileData()
        Task {
            await fetchSingleQuote(symbol: normalizedTx.symbol)
        }
    }

    public func updateTransaction(_ tx: Transaction) {
        guard let idx = transactions.firstIndex(where: { $0.id == tx.id }) else { return }
        var normalizedTx = tx
        if normalizedTx.portfolioId == nil {
            normalizedTx.portfolioId = transactions[idx].portfolioId ?? currentPortfolio?.id ?? portfolios.first?.id
        }
        transactions[idx] = normalizedTx
        if let pid = normalizedTx.portfolioId,
           let pIdx = portfolios.firstIndex(where: { $0.id == pid }),
           !portfolios[pIdx].trackedSymbols.contains(normalizedTx.symbol) {
            portfolios[pIdx].trackedSymbols.append(normalizedTx.symbol)
            portfolios[pIdx].trackedSymbols.sort()
        }

        recomputePortfolioState()
        saveCurrentProfileData()
        Task {
            await fetchSingleQuote(symbol: normalizedTx.symbol)
        }
    }

    public func deleteTransaction(id: UUID) {
        transactions.removeAll { $0.id == id }
        recomputePortfolioState()
        saveCurrentProfileData()
    }

    public func deletePosition(symbol: String, portfolioId: UUID? = nil) {
        let sym = symbol.uppercased()
        let targetId = portfolioId ?? currentPortfolio?.id
        let fallbackId = portfolios.first?.id
        if let targetId {
            transactions.removeAll {
                $0.symbol.uppercased() == sym && ($0.portfolioId ?? fallbackId) == targetId
            }
            if let idx = portfolios.firstIndex(where: { $0.id == targetId }) {
                portfolios[idx].trackedSymbols.removeAll { $0 == sym }
            }
        } else {
            transactions.removeAll { $0.symbol.uppercased() == sym }
        }
        recomputePortfolioState()
        saveCurrentProfileData()
    }

    // MARK: - CSV Import & Export
    public func importCSV(text: String, portfolioId: UUID? = nil) -> FinancialCSVParser.ParseResult {
        let result = FinancialCSVParser.parseCSV(text: text)
        guard !result.transactions.isEmpty else { return result }

        let targetId = portfolioId ?? currentPortfolio?.id ?? portfolios.first?.id
        let pIdx = targetId.flatMap { id in portfolios.firstIndex(where: { $0.id == id }) }

        for var tx in result.transactions {
            tx.portfolioId = targetId
            transactions.append(tx)
            if let pIdx, !portfolios[pIdx].trackedSymbols.contains(tx.symbol) {
                portfolios[pIdx].trackedSymbols.append(tx.symbol)
            }
        }
        if let pIdx {
            portfolios[pIdx].trackedSymbols.sort()
        }

        recomputePortfolioState()
        saveCurrentProfileData()

        Task {
            await refreshAllQuotes()
        }
        return result
    }

    public func exportCurrentHoldingsCSV() -> String {
        FinancialCSVParser.exportHoldingsToCSV(holdings: holdings, sourceName: activeProfile.provider.rawValue)
    }

    public func clearAllProfileData() {
        transactions.removeAll()
        portfolios = [Portfolio(name: "Main Portfolio", currency: "USD", trackedSymbols: [])]
        selectedPortfolioId = portfolios.first?.id
        recomputePortfolioState()
        saveCurrentProfileData()
    }

    // MARK: - Market Networking
    public func loadIndices(forceRefresh: Bool = false) async {
        let indices = await financeService.fetchMarketIndices(forceRefresh: forceRefresh)
        self.marketIndices = indices
    }

    public func refreshAllQuotes() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        var symbolsToFetch = Set<String>()

        for portfolio in portfolios {
            for sym in portfolio.trackedSymbols { symbolsToFetch.insert(sym) }
        }
        for tx in transactions {
            symbolsToFetch.insert(tx.symbol)
        }

        let result = await financeService.fetchQuotesAndIndices(
            symbols: Array(symbolsToFetch),
            forceRefresh: true
        )
        for (sym, q) in result.quotes {
            quotes[sym] = q
        }
        marketIndices = result.indices
        recomputePortfolioState()
    }

    public func fetchSingleQuote(symbol: String) async {
        let quote = await financeService.fetchQuote(symbol: symbol)
        quotes[symbol.uppercased()] = quote
        recomputePortfolioState()
    }

    public func search(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        let results = await financeService.searchSymbols(query: trimmed)
        self.searchResults = results
        isSearching = false
    }

    // MARK: - Internal Storage
    private func saveCurrentProfileData() {
        persistence.savePortfolios(portfolios, forProfile: activeProfile.email)
        persistence.saveOverallCurrency(overallCurrency, forProfile: activeProfile.email)
        persistence.saveTransactions(transactions, forProfile: activeProfile.email)
    }

    private func loadDataForActiveProfile() {
        if let savedCurrency = persistence.loadOverallCurrency(forProfile: activeProfile.email) {
            self.overallCurrency = savedCurrency
        } else {
            self.overallCurrency = "USD"
        }

        if let savedPortfolios = persistence.loadPortfolios(forProfile: activeProfile.email), !savedPortfolios.isEmpty {
            self.portfolios = savedPortfolios
        } else {
            // Migrate any legacy watchlist symbols into the initial Main Portfolio
            let legacySymbols = (persistence.loadWatchlists(forProfile: activeProfile.email) ?? [])
                .flatMap(\.symbols)
            self.portfolios = [Portfolio(name: "Main Portfolio", currency: "USD", trackedSymbols: legacySymbols)]
        }
        self.selectedPortfolioId = portfolios.first?.id

        if var savedTx = persistence.loadTransactions(forProfile: activeProfile.email) {
            if let defaultId = portfolios.first?.id {
                for i in savedTx.indices where savedTx[i].portfolioId == nil {
                    savedTx[i].portfolioId = defaultId
                }
            }
            self.transactions = savedTx
        } else {
            self.transactions = []
        }

        recomputePortfolioState()
    }
}
