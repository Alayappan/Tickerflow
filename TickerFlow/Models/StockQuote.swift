import Foundation

nonisolated public struct StockQuote: Identifiable, Codable, Equatable, Sendable {
    public var id: String { symbol }
    public let symbol: String
    public let companyName: String
    public var regularMarketPrice: Double
    public var regularMarketChange: Double
    public var regularMarketChangePercent: Double
    public var currency: String
    public var regularMarketVolume: Int64
    public var marketCap: Double?
    public var peRatio: Double?
    public var forwardPE: Double?
    public var priceToBook: Double?
    public var pegRatio: Double?
    public var priceToSales: Double?
    public var evToEbitda: Double?
    public var epsTTM: Double?
    public var epsForward: Double?
    public var bookValue: Double?
    public var dividendYieldPercent: Double?
    public var beta: Double?
    public var profitMarginPercent: Double?
    public var roePercent: Double?
    public var debtToEquity: Double?
    public var dayHigh: Double?
    public var dayLow: Double?
    public var openPrice: Double?
    public var previousClose: Double?
    public var avgVolume3Month: Int64?
    public var fiftyDayAverage: Double?
    public var twoHundredDayAverage: Double?
    public var targetMeanPrice: Double?
    public var analystRating: String?
    public var fiftyTwoWeekHigh: Double?
    public var fiftyTwoWeekLow: Double?
    public var sparklinePrices: [Double]
    public var lastUpdated: Date

    public init(
        symbol: String,
        companyName: String,
        regularMarketPrice: Double,
        regularMarketChange: Double,
        regularMarketChangePercent: Double,
        currency: String = "USD",
        regularMarketVolume: Int64 = 0,
        marketCap: Double? = nil,
        peRatio: Double? = nil,
        forwardPE: Double? = nil,
        priceToBook: Double? = nil,
        pegRatio: Double? = nil,
        priceToSales: Double? = nil,
        evToEbitda: Double? = nil,
        epsTTM: Double? = nil,
        epsForward: Double? = nil,
        bookValue: Double? = nil,
        dividendYieldPercent: Double? = nil,
        beta: Double? = nil,
        profitMarginPercent: Double? = nil,
        roePercent: Double? = nil,
        debtToEquity: Double? = nil,
        dayHigh: Double? = nil,
        dayLow: Double? = nil,
        openPrice: Double? = nil,
        previousClose: Double? = nil,
        avgVolume3Month: Int64? = nil,
        fiftyDayAverage: Double? = nil,
        twoHundredDayAverage: Double? = nil,
        targetMeanPrice: Double? = nil,
        analystRating: String? = nil,
        fiftyTwoWeekHigh: Double? = nil,
        fiftyTwoWeekLow: Double? = nil,
        sparklinePrices: [Double] = [],
        lastUpdated: Date = Date()
    ) {
        self.symbol = symbol
        self.companyName = companyName
        self.regularMarketPrice = regularMarketPrice
        self.regularMarketChange = regularMarketChange
        self.regularMarketChangePercent = regularMarketChangePercent
        self.currency = currency
        self.regularMarketVolume = regularMarketVolume
        self.marketCap = marketCap
        self.peRatio = peRatio
        self.forwardPE = forwardPE
        self.priceToBook = priceToBook
        self.pegRatio = pegRatio
        self.priceToSales = priceToSales
        self.evToEbitda = evToEbitda
        self.epsTTM = epsTTM
        self.epsForward = epsForward
        self.bookValue = bookValue
        self.dividendYieldPercent = dividendYieldPercent
        self.beta = beta
        self.profitMarginPercent = profitMarginPercent
        self.roePercent = roePercent
        self.debtToEquity = debtToEquity
        self.dayHigh = dayHigh
        self.dayLow = dayLow
        self.openPrice = openPrice
        self.previousClose = previousClose
        self.avgVolume3Month = avgVolume3Month
        self.fiftyDayAverage = fiftyDayAverage
        self.twoHundredDayAverage = twoHundredDayAverage
        self.targetMeanPrice = targetMeanPrice
        self.analystRating = analystRating
        self.fiftyTwoWeekHigh = fiftyTwoWeekHigh
        self.fiftyTwoWeekLow = fiftyTwoWeekLow
        self.sparklinePrices = sparklinePrices
        self.lastUpdated = lastUpdated
    }

    public var isPositive: Bool {
        regularMarketChange >= 0
    }

    public var formattedPrice: String {
        Self.formatAmount(regularMarketPrice, currency: currency, isIndex: symbol.hasPrefix("^"))
    }

    public var formattedChange: String {
        Self.formatSignedAmount(regularMarketChange, currency: currency, isIndex: symbol.hasPrefix("^"))
    }

    public var formattedChangePercent: String {
        let prefix = regularMarketChangePercent >= 0 ? "+" : ""
        return String(format: "%@%.2f%%", prefix, regularMarketChangePercent)
    }

    public var formattedMarketCap: String {
        guard let cap = marketCap, cap > 0 else { return "N/A" }
        let symbolPrefix = Self.currencySymbol(for: currency)
        if cap >= 1_000_000_000_000 {
            return String(format: "%@%.2fT", symbolPrefix, cap / 1_000_000_000_000)
        } else if cap >= 1_000_000_000 {
            return String(format: "%@%.2fB", symbolPrefix, cap / 1_000_000_000)
        } else if cap >= 1_000_000 {
            return String(format: "%@%.2fM", symbolPrefix, cap / 1_000_000)
        }
        return String(format: "%@%.0f", symbolPrefix, cap)
    }

    private static let formatterLock = NSLock()
    private nonisolated(unsafe) static var cachedCurrencySymbols: [String: String] = [:]
    private nonisolated(unsafe) static var cachedAmountFormatters: [String: NumberFormatter] = [:]

    public static func currencySymbol(for currencyCode: String) -> String {
        formatterLock.lock()
        defer { formatterLock.unlock() }

        if let cached = cachedCurrencySymbols[currencyCode] {
            return cached
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        let symbol = formatter.currencySymbol ?? "$"
        cachedCurrencySymbols[currencyCode] = symbol
        return symbol
    }

    public static func formatAmount(_ value: Double, currency: String, isIndex: Bool = false) -> String {
        let key = "\(isIndex ? "idx" : currency)-2"
        formatterLock.lock()
        let formatter: NumberFormatter
        if let cached = cachedAmountFormatters[key] {
            formatter = cached
        } else {
            let f = NumberFormatter()
            f.numberStyle = isIndex ? .decimal : .currency
            if !isIndex {
                f.currencyCode = currency
            }
            f.maximumFractionDigits = 2
            f.minimumFractionDigits = 2
            cachedAmountFormatters[key] = f
            formatter = f
        }
        let result = formatter.string(from: NSNumber(value: value))
        formatterLock.unlock()
        return result ?? String(format: isIndex ? "%.2f" : "$%.2f", value)
    }

    public static func formatSignedAmount(_ value: Double, currency: String, isIndex: Bool = false) -> String {
        let sign = value >= 0 ? "+" : "-"
        let formatted = formatAmount(abs(value), currency: currency, isIndex: isIndex)
        return "\(sign)\(formatted)"
    }
}

nonisolated public struct HistoricalPricePoint: Identifiable, Codable, Equatable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let price: Double
    public let volume: Int64

    public init(date: Date, price: Double, volume: Int64 = 0) {
        self.date = date
        self.price = price
        self.volume = volume
    }
}

nonisolated public enum ChartTimeframe: String, CaseIterable, Identifiable, Codable, Sendable {
    case oneDay = "1D"
    case fiveDays = "5D"
    case oneMonth = "1M"
    case sixMonths = "6M"
    case oneYear = "1Y"
    case allTime = "ALL"

    public var id: String { rawValue }
}

nonisolated public enum MarketRegion: String, CaseIterable, Identifiable, Codable, Sendable {
    case all = "All"
    case us = "US"
    case europe = "Europe"
    case asia = "Asia"
    case commodities = "Commodities & FX"

    public var id: String { rawValue }
}

nonisolated public struct MarketIndex: Identifiable, Codable, Equatable, Sendable {
    public var id: String { symbol }
    public let symbol: String
    public let name: String
    public let region: MarketRegion
    public let regionBadge: String
    public let currency: String
    public let value: Double
    public let change: Double
    public let changePercent: Double
    public let sparklinePrices: [Double]

    public init(
        symbol: String,
        name: String,
        region: MarketRegion = .us,
        regionBadge: String = "US",
        currency: String = "USD",
        value: Double,
        change: Double,
        changePercent: Double,
        sparklinePrices: [Double] = []
    ) {
        self.symbol = symbol
        self.name = name
        self.region = region
        self.regionBadge = regionBadge
        self.currency = currency
        self.value = value
        self.change = change
        self.changePercent = changePercent
        self.sparklinePrices = sparklinePrices
    }

    public var isPositive: Bool { change >= 0 }

    public var formattedValue: String {
        let decimals = value < 10 ? 4 : 2
        if decimals == 2 {
            return StockQuote.formatAmount(value, currency: currency, isIndex: true)
        }
        return String(format: "%.4f", value)
    }

    public var formattedChange: String {
        let prefix = change >= 0 ? "+" : ""
        let decimals = value < 10 ? "%.4f" : "%.2f"
        let changeText = String(format: "\(prefix)\(decimals)", change)
        let pctText = String(format: "\(prefix)%.2f%%", changePercent)
        return "\(changeText) (\(pctText))"
    }

    public var formattedChangePercent: String {
        let prefix = changePercent >= 0 ? "+" : ""
        return String(format: "%@%.2f%%", prefix, changePercent)
    }
}
