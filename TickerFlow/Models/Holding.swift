import Foundation

nonisolated public enum SupportedPortfolioCurrency: String, CaseIterable, Identifiable, Codable, Sendable {
    case usd = "USD"
    case inr = "INR"
    case eur = "EUR"
    case gbp = "GBP"
    case jpy = "JPY"
    case cad = "CAD"
    case aud = "AUD"
    case sgd = "SGD"
    case hkd = "HKD"
    case chf = "CHF"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .usd: return "USD ($)"
        case .inr: return "INR (₹)"
        case .eur: return "EUR (€)"
        case .gbp: return "GBP (£)"
        case .jpy: return "JPY (¥)"
        case .cad: return "CAD (CA$)"
        case .aud: return "AUD (A$)"
        case .sgd: return "SGD (S$)"
        case .hkd: return "HKD (HK$)"
        case .chf: return "CHF (Fr)"
        }
    }
}

nonisolated public struct Portfolio: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var currency: String
    public var trackedSymbols: [String]
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        currency: String = "USD",
        trackedSymbols: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.currency = currency.uppercased()
        self.trackedSymbols = Array(Set(trackedSymbols.map { $0.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) }))
            .filter { !$0.isEmpty }
            .sorted()
        self.createdAt = createdAt
    }
}

nonisolated public enum TransactionType: String, Codable, CaseIterable, Sendable {
    case buy = "BUY"
    case sell = "SELL"
}

nonisolated public struct Transaction: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var portfolioId: UUID?
    public let symbol: String
    public let companyName: String
    public let type: TransactionType
    public let shares: Double
    public let pricePerShare: Double
    public let date: Date
    public let notes: String

    public init(
        id: UUID = UUID(),
        portfolioId: UUID? = nil,
        symbol: String,
        companyName: String = "",
        type: TransactionType = .buy,
        shares: Double,
        pricePerShare: Double,
        date: Date = Date(),
        notes: String = ""
    ) {
        self.id = id
        self.portfolioId = portfolioId
        self.symbol = symbol.uppercased()
        self.companyName = companyName
        self.type = type
        self.shares = shares
        self.pricePerShare = pricePerShare
        self.date = date
        self.notes = notes
    }

    public var totalAmount: Double {
        shares * pricePerShare
    }
}

nonisolated public struct Holding: Identifiable, Codable, Equatable, Sendable {
    public var id: String {
        if let portfolioId {
            return "\(portfolioId.uuidString)-\(symbol)"
        }
        return symbol
    }
    public let portfolioId: UUID?
    public let symbol: String
    public var companyName: String
    public var totalShares: Double
    public var totalCostBasis: Double
    public var currentPrice: Double
    public var previousClosePrice: Double
    public var currency: String
    public var quoteCurrency: String

    public init(
        portfolioId: UUID? = nil,
        symbol: String,
        companyName: String = "",
        totalShares: Double = 0,
        totalCostBasis: Double = 0,
        currentPrice: Double = 0,
        previousClosePrice: Double = 0,
        currency: String = "USD",
        quoteCurrency: String? = nil
    ) {
        self.portfolioId = portfolioId
        self.symbol = symbol.uppercased()
        self.companyName = companyName
        self.totalShares = totalShares
        self.totalCostBasis = totalCostBasis
        self.currentPrice = currentPrice
        self.previousClosePrice = previousClosePrice
        self.currency = currency
        self.quoteCurrency = quoteCurrency ?? currency
    }

    public var avgCostPerShare: Double {
        totalShares > 0 ? (totalCostBasis / totalShares) : 0
    }

    public var currentValue: Double {
        totalShares * currentPrice
    }

    public var totalGainLoss: Double {
        currentValue - totalCostBasis
    }

    public var totalGainLossPercent: Double {
        totalCostBasis > 0 ? ((totalGainLoss / totalCostBasis) * 100) : 0
    }

    public var dayGainLoss: Double {
        let diff = currentPrice - (previousClosePrice > 0 ? previousClosePrice : currentPrice)
        return totalShares * diff
    }

    public var dayGainLossPercent: Double {
        if previousClosePrice > 0 {
            return ((currentPrice - previousClosePrice) / previousClosePrice) * 100
        }
        return 0
    }
}

nonisolated public enum HoldingSortOption: String, CaseIterable, Identifiable, Sendable {
    case valueDesc = "Value"
    case returnPercentDesc = "Return %"
    case returnAmountDesc = "Gain/Loss"
    case dayChangeDesc = "Day %"
    case symbolAsc = "Symbol"

    public var id: String { rawValue }
}

nonisolated public enum TransactionFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case buy = "Buys"
    case sell = "Sells"

    public var id: String { rawValue }
}

nonisolated public struct PortfolioBreakdown: Identifiable, Sendable {
    public var id: UUID { portfolio.id }
    public let portfolio: Portfolio
    public let nativeValue: Double
    public let overallCurrencyValue: Double
    public let unrealizedGainLossOverall: Double
    public let dayGainLossOverall: Double
    public let positionsCount: Int
    public let trackedTickersCount: Int
}

nonisolated public struct OverallPortfolioSummary: Sendable {
    public let currency: String
    public let totalValue: Double
    public let totalCostBasis: Double
    public let unrealizedGainLoss: Double
    public let unrealizedGainLossPercent: Double
    public let realizedGainLoss: Double
    public let netTotalGainLoss: Double
    public let dayGainLoss: Double
    public let dayGainLossPercent: Double
    public let portfolioCount: Int
    public let positionsCount: Int
    public let trackedTickersCount: Int
    public let breakdowns: [PortfolioBreakdown]

    public static let empty = OverallPortfolioSummary(
        currency: "USD",
        totalValue: 0,
        totalCostBasis: 0,
        unrealizedGainLoss: 0,
        unrealizedGainLossPercent: 0,
        realizedGainLoss: 0,
        netTotalGainLoss: 0,
        dayGainLoss: 0,
        dayGainLossPercent: 0,
        portfolioCount: 0,
        positionsCount: 0,
        trackedTickersCount: 0,
        breakdowns: []
    )
}

nonisolated public struct PortfolioAnalytics: Sendable {
    public let totalValue: Double
    public let totalCostBasis: Double
    public let unrealizedGainLoss: Double
    public let unrealizedGainLossPercent: Double
    public let realizedGainLoss: Double
    public let netTotalGainLoss: Double
    public let dayGainLoss: Double
    public let dayGainLossPercent: Double
    public let profitablePositionsCount: Int
    public let losingPositionsCount: Int
    public let winRatePercent: Double
    public let topGainer: Holding?
    public let topLoser: Holding?
    public let largestPosition: Holding?
    public let largestPositionWeight: Double
    public let totalBuysCount: Int
    public let totalSellsCount: Int
    public let totalBoughtVolume: Double
    public let totalSoldVolume: Double
    public let realizedPnLByTransactionId: [UUID: Double]

    public static let empty = PortfolioAnalytics(
        totalValue: 0,
        totalCostBasis: 0,
        unrealizedGainLoss: 0,
        unrealizedGainLossPercent: 0,
        realizedGainLoss: 0,
        netTotalGainLoss: 0,
        dayGainLoss: 0,
        dayGainLossPercent: 0,
        profitablePositionsCount: 0,
        losingPositionsCount: 0,
        winRatePercent: 0,
        topGainer: nil,
        topLoser: nil,
        largestPosition: nil,
        largestPositionWeight: 0,
        totalBuysCount: 0,
        totalSellsCount: 0,
        totalBoughtVolume: 0,
        totalSoldVolume: 0,
        realizedPnLByTransactionId: [:]
    )
}
