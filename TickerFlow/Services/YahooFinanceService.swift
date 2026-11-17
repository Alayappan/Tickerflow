import Foundation

public actor YahooFinanceService {
    public static let shared = YahooFinanceService()

    private let session: URLSession
    private var quoteCache: [String: (quote: StockQuote, fetchedAt: Date)] = [:]
    private var indicesCache: (indices: [MarketIndex], fetchedAt: Date)?
    private var chartCache: [String: (points: [HistoricalPricePoint], fetchedAt: Date)] = [:]

    private var cachedCrumb: (value: String, fetchedAt: Date)?
    private var crumbCooldownUntil: Date = .distantPast
    private var networkCooldownUntil: Date = .distantPast
    private var hasWarmConnection: Bool = false
    private var crumbTask: Task<String?, Never>?
    private var inFlightIndicesTask: Task<[MarketIndex], Never>?
    private var inFlightChartTasks: [String: Task<[HistoricalPricePoint]?, Never>] = [:]

    private static let yahooHosts = [
        "query1.finance.yahoo.com",
        "query2.finance.yahoo.com"
    ]
    private var preferredHostIndex: Int = 0
    private static let browserUserAgent = "Mozilla/5.0"

    private typealias IndexDefinition = (symbol: String, name: String, region: MarketRegion, badge: String, currency: String, fallbackVal: Double, fallbackChg: Double, fallbackPct: Double)

    private static let indexDefinitions: [IndexDefinition] = [
        // US Markets
        ("^GSPC", "S&P 500", .us, "US", "USD", 5893.62, 24.31, 0.41),
        ("^DJI", "Dow 30", .us, "US", "USD", 43444.99, -120.45, -0.28),
        ("^IXIC", "Nasdaq", .us, "US", "USD", 18780.05, 110.22, 0.59),
        ("^RUT", "Russell 2000", .us, "US", "USD", 2310.88, 8.75, 0.38),
        ("^VIX", "VIX", .us, "US", "USD", 14.85, -0.62, -4.01),
        // Europe Markets
        ("^FTSE", "FTSE 100", .europe, "UK", "GBP", 8149.27, 31.40, 0.39),
        ("^GDAXI", "DAX", .europe, "DE", "EUR", 19210.81, 88.15, 0.46),
        ("^FCHI", "CAC 40", .europe, "FR", "EUR", 7311.80, -18.25, -0.25),
        ("^STOXX50E", "Euro Stoxx 50", .europe, "EU", "EUR", 4824.50, 19.60, 0.41),
        // Asia Markets
        ("^N225", "Nikkei 225", .asia, "JP", "JPY", 38642.91, 215.40, 0.56),
        ("^NSEI", "NIFTY 50", .asia, "IN", "INR", 24188.65, 142.30, 0.59),
        ("^BSESN", "SENSEX", .asia, "IN", "INR", 79586.44, 412.80, 0.52),
        ("^HSI", "Hang Seng", .asia, "HK", "HKD", 19426.34, -95.12, -0.49),
        ("000001.SS", "SSE Composite", .asia, "CN", "CNY", 3330.73, 16.85, 0.51),
        // Commodities & FX
        ("GC=F", "Gold", .commodities, "CMD", "USD", 2572.40, 14.80, 0.58),
        ("CL=F", "Crude Oil", .commodities, "CMD", "USD", 68.42, -0.84, -1.21),
        ("EURUSD=X", "EUR/USD", .commodities, "FX", "USD", 1.0542, 0.0028, 0.27),
        ("USDINR=X", "USD/INR", .commodities, "FX", "INR", 84.38, -0.06, -0.07),
        ("BTC-USD", "Bitcoin", .commodities, "CRY", "USD", 91450.00, 1850.00, 2.06)
    ]

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.urlCache = nil
            config.httpMaximumConnectionsPerHost = 2
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 25
            config.waitsForConnectivity = false
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.httpCookieAcceptPolicy = .always
            config.httpShouldSetCookies = true
            config.httpAdditionalHeaders = [
                "User-Agent": Self.browserUserAgent,
                "Accept": "*/*",
                "Accept-Language": "en-US,en;q=0.9"
            ]
            self.session = URLSession(configuration: config)
        }
    }

    public nonisolated static func defaultMarketIndices() -> [MarketIndex] {
        indexDefinitions.map { def in
            MarketIndex(
                symbol: def.symbol,
                name: def.name,
                region: def.region,
                regionBadge: def.badge,
                currency: def.currency,
                value: def.fallbackVal,
                change: def.fallbackChg,
                changePercent: def.fallbackPct,
                sparklinePrices: makeSparkline(basePrice: def.fallbackVal, isPositive: def.fallbackChg >= 0)
            )
        }
    }

    // MARK: - Market Indices & Unified Batch Refresh
    public func fetchMarketIndices(forceRefresh: Bool = false) async -> [MarketIndex] {
        if forceRefresh {
            networkCooldownUntil = .distantPast
            crumbCooldownUntil = .distantPast
        }
        if !forceRefresh,
           let cached = indicesCache,
           Date().timeIntervalSince(cached.fetchedAt) < 30 {
            return cached.indices
        }

        if let existingTask = inFlightIndicesTask {
            return await existingTask.value
        }

        let task = Task<[MarketIndex], Never> {
            await self.performFetchMarketIndices()
        }
        inFlightIndicesTask = task
        let result = await task.value
        inFlightIndicesTask = nil
        return result
    }

    private static let fxRateSymbols: [String] = [
        "USDINR=X", "USDEUR=X", "USDGBP=X", "USDJPY=X",
        "USDCAD=X", "USDAUD=X", "USDSGD=X", "USDHKD=X", "USDCHF=X"
    ]

    public func fetchQuotesAndIndices(
        symbols: [String],
        forceRefresh: Bool = false
    ) async -> (quotes: [String: StockQuote], indices: [MarketIndex]) {
        if forceRefresh {
            networkCooldownUntil = .distantPast
            crumbCooldownUntil = .distantPast
        }

        let cleanedUserSymbols = Array(Set(symbols.map {
            $0.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        })).filter { !$0.isEmpty }

        let indexSymbols = Self.indexDefinitions.map(\.symbol)
        let combinedSymbols = Array(Set(cleanedUserSymbols + indexSymbols + Self.fxRateSymbols))
        let now = Date()

        var resolvedMap: [String: StockQuote] = [:]
        var toFetch: [String] = []

        for sym in combinedSymbols {
            if !forceRefresh, let cached = quoteCache[sym], now.timeIntervalSince(cached.fetchedAt) < 20 {
                resolvedMap[sym] = cached.quote
            } else {
                toFetch.append(sym)
            }
        }

        if !toFetch.isEmpty {
            let batchResults = await fetchLiveQuotesBatchFromYahoo(symbols: toFetch)
            for (sym, quote) in batchResults {
                resolvedMap[sym] = quote
                quoteCache[sym] = (quote, Date())
            }

            let remaining = toFetch.filter { resolvedMap[$0] == nil }
            if !remaining.isEmpty {
                let chartResults = await fetchLiveQuotesViaChartConcurrently(symbols: remaining)
                for (sym, quote) in chartResults {
                    resolvedMap[sym] = quote
                    quoteCache[sym] = (quote, Date())
                }
            }
        }

        var userQuotes: [String: StockQuote] = [:]
        for sym in cleanedUserSymbols {
            let quote = resolvedMap[sym] ?? quoteCache[sym]?.quote ?? generateRealisticQuote(symbol: sym)
            userQuotes[sym] = quote
            if quoteCache[sym] == nil {
                quoteCache[sym] = (quote, Date())
            }
        }
        for fxSym in Self.fxRateSymbols {
            if let fxQuote = resolvedMap[fxSym] ?? quoteCache[fxSym]?.quote {
                userQuotes[fxSym] = fxQuote
            }
        }

        let indices = buildMarketIndices(from: resolvedMap)
        indicesCache = (indices, Date())
        return (userQuotes, indices)
    }

    private func performFetchMarketIndices() async -> [MarketIndex] {
        let symbols = Self.indexDefinitions.map(\.symbol)
        let now = Date()
        var liveMap: [String: StockQuote] = [:]
        var missingFromCache: [String] = []

        for sym in symbols {
            if let cached = quoteCache[sym], now.timeIntervalSince(cached.fetchedAt) < 20 {
                liveMap[sym] = cached.quote
            } else {
                missingFromCache.append(sym)
            }
        }

        if !missingFromCache.isEmpty {
            let batchMap = await fetchLiveQuotesBatchFromYahoo(symbols: missingFromCache)
            for (sym, quote) in batchMap {
                liveMap[sym] = quote
                quoteCache[sym] = (quote, now)
            }

            let stillMissing = missingFromCache.filter { liveMap[$0] == nil }
            if !stillMissing.isEmpty {
                let chartQuotes = await fetchLiveQuotesViaChartConcurrently(symbols: stillMissing)
                for (sym, quote) in chartQuotes {
                    liveMap[sym] = quote
                    quoteCache[sym] = (quote, now)
                }
            }
        }

        let result = buildMarketIndices(from: liveMap)
        indicesCache = (result, Date())
        return result
    }

    private func buildMarketIndices(from liveMap: [String: StockQuote]) -> [MarketIndex] {
        Self.indexDefinitions.map { def in
            if let live = liveMap[def.symbol], live.regularMarketPrice > 0 {
                return MarketIndex(
                    symbol: def.symbol,
                    name: def.name,
                    region: def.region,
                    regionBadge: def.badge,
                    currency: live.currency,
                    value: live.regularMarketPrice,
                    change: live.regularMarketChange,
                    changePercent: live.regularMarketChangePercent,
                    sparklinePrices: live.sparklinePrices
                )
            }
            return MarketIndex(
                symbol: def.symbol,
                name: def.name,
                region: def.region,
                regionBadge: def.badge,
                currency: def.currency,
                value: def.fallbackVal,
                change: def.fallbackChg,
                changePercent: def.fallbackPct,
                sparklinePrices: Self.makeSparkline(basePrice: def.fallbackVal, isPositive: def.fallbackChg >= 0)
            )
        }
    }

    // MARK: - Fetch Single Quote
    public func fetchQuote(symbol: String) async -> StockQuote {
        let sym = symbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let cached = quoteCache[sym], Date().timeIntervalSince(cached.fetchedAt) < 20 {
            return cached.quote
        }
        let batch = await fetchLiveQuotesBatchFromYahoo(symbols: [sym])
        if let live = batch[sym] {
            quoteCache[sym] = (live, Date())
            return live
        }
        if let live = await fetchLiveQuoteViaChartFromYahoo(symbol: sym) {
            quoteCache[sym] = (live, Date())
            return live
        }
        return generateRealisticQuote(symbol: sym)
    }

    // MARK: - Fetch Multiple Quotes (Batch)
    public func fetchQuotes(symbols: [String], forceRefresh: Bool = false) async -> [String: StockQuote] {
        if forceRefresh {
            networkCooldownUntil = .distantPast
            crumbCooldownUntil = .distantPast
        }
        let uniqueSymbols = Array(Set(symbols.map { $0.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) }))
            .filter { !$0.isEmpty }
        guard !uniqueSymbols.isEmpty else { return [:] }

        var results: [String: StockQuote] = [:]
        var toFetch: [String] = []
        let now = Date()

        for sym in uniqueSymbols {
            if !forceRefresh, let cached = quoteCache[sym], now.timeIntervalSince(cached.fetchedAt) < 20 {
                results[sym] = cached.quote
            } else {
                toFetch.append(sym)
            }
        }

        guard !toFetch.isEmpty else { return results }

        let batchResults = await fetchLiveQuotesBatchFromYahoo(symbols: toFetch)
        for (sym, quote) in batchResults {
            results[sym] = quote
            quoteCache[sym] = (quote, Date())
        }

        let remaining = toFetch.filter { results[$0] == nil }
        if !remaining.isEmpty {
            let chartResults = await fetchLiveQuotesViaChartConcurrently(symbols: remaining)
            for sym in remaining {
                let quote = chartResults[sym] ?? quoteCache[sym]?.quote ?? generateRealisticQuote(symbol: sym)
                results[sym] = quote
                quoteCache[sym] = (quote, Date())
            }
        }

        return results
    }

    // MARK: - Fetch Chart Data
    public func fetchChart(symbol: String, timeframe: ChartTimeframe) async -> [HistoricalPricePoint] {
        let sym = symbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let cacheKey = "\(sym)-\(timeframe.rawValue)"
        let ttl: TimeInterval = timeframe == .oneDay ? 20 : 60

        if let cached = chartCache[cacheKey], Date().timeIntervalSince(cached.fetchedAt) < ttl {
            return cached.points
        }

        if let existing = inFlightChartTasks[cacheKey] {
            if let points = await existing.value, !points.isEmpty {
                return points
            }
            return generateRealisticChart(symbol: sym, timeframe: timeframe)
        }

        let task = Task<[HistoricalPricePoint]?, Never> {
            await self.fetchLiveChartFromYahoo(symbol: sym, timeframe: timeframe)
        }
        inFlightChartTasks[cacheKey] = task
        let livePoints = await task.value
        inFlightChartTasks[cacheKey] = nil

        if let livePoints, !livePoints.isEmpty {
            chartCache[cacheKey] = (livePoints, Date())
            if timeframe == .oneDay, let existing = quoteCache[sym] {
                var updated = existing.quote
                updated.sparklinePrices = livePoints.map(\.price)
                quoteCache[sym] = (updated, existing.fetchedAt)
            }
            return livePoints
        }
        return generateRealisticChart(symbol: sym, timeframe: timeframe)
    }

    // MARK: - Search Symbols
    public func searchSymbols(query: String) async -> [StockQuote] {
        let trimmed = query.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }

        // Try Yahoo search API directly
        if let results = await fetchLiveSearch(query: trimmed), !results.isEmpty {
            return results
        }

        // Built-in catalog of common securities
        let catalog = [
            ("AAPL", "Apple Inc.", 228.45, 1.85, 0.82),
            ("MSFT", "Microsoft Corp.", 425.20, -2.10, -0.49),
            ("GOOGL", "Alphabet Inc.", 176.80, 2.40, 1.38),
            ("AMZN", "Amazon.com Inc.", 205.15, 3.25, 1.61),
            ("NVDA", "NVIDIA Corp.", 144.90, 4.10, 2.91),
            ("TSLA", "Tesla Inc.", 338.75, -5.20, -1.51),
            ("META", "Meta Platforms Inc.", 578.40, 6.80, 1.19),
            ("NFLX", "Netflix Inc.", 842.10, -4.50, -0.53),
            ("AMD", "Advanced Micro Devices", 142.30, 2.80, 2.01),
            ("BRK-B", "Berkshire Hathaway", 468.20, 1.15, 0.25),
            ("JPM", "JPMorgan Chase & Co.", 242.60, 1.90, 0.79),
            ("V", "Visa Inc.", 308.10, 0.75, 0.24),
            ("SPY", "SPDR S&P 500 ETF", 588.50, 2.50, 0.43),
            ("QQQ", "Invesco QQQ Trust", 504.30, 3.10, 0.62),
            ("RELIANCE.NS", "Reliance Industries Ltd.", 1285.40, 14.20, 1.12),
            ("TCS.NS", "Tata Consultancy Services", 4120.75, -18.50, -0.45),
            ("ASML.AS", "ASML Holding N.V.", 645.80, 9.40, 1.48),
            ("SAP.DE", "SAP SE", 224.30, 3.10, 1.40),
            ("AZN.L", "AstraZeneca PLC", 10340.00, 85.00, 0.83),
            ("7203.T", "Toyota Motor Corp.", 2715.00, 32.00, 1.19),
            ("TSM", "Taiwan Semiconductor", 191.40, 4.15, 2.22),
            ("BTC-USD", "Bitcoin USD", 91450.00, 1850.00, 2.06),
            ("ETH-USD", "Ethereum USD", 3120.00, 45.00, 1.46)
        ]

        let matched = catalog.filter { $0.0.contains(trimmed) || $0.1.localizedCaseInsensitiveContains(trimmed) }
        return matched.map { item in
            StockQuote(
                symbol: item.0,
                companyName: item.1,
                regularMarketPrice: item.2,
                regularMarketChange: item.3,
                regularMarketChangePercent: item.4,
                currency: inferredCurrency(for: item.0),
                sparklinePrices: Self.makeSparkline(basePrice: item.2, isPositive: item.3 >= 0)
            )
        }
    }

    // MARK: - Direct Yahoo URL Helpers
    private func makeYahooURL(host: String, path: String, queryItems: [URLQueryItem]) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = queryItems
        return components.url
    }

    private func makeRequest(url: URL, timeout: TimeInterval = 12, accept: String = "*/*") -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.assumesHTTP3Capable = false
        request.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        return request
    }

    private func performWithHostFallback(
        path: String,
        queryItems: [URLQueryItem],
        timeout: TimeInterval = 12,
        accept: String = "*/*"
    ) async -> (Data, HTTPURLResponse)? {
        if Date() < networkCooldownUntil {
            return nil
        }
        let hostCount = Self.yahooHosts.count
        var sawTransportFailure = false
        for offset in 0..<hostCount {
            let hostIdx = (preferredHostIndex + offset) % hostCount
            let host = Self.yahooHosts[hostIdx]
            guard let url = makeYahooURL(host: host, path: path, queryItems: queryItems) else { continue }
            let request = makeRequest(url: url, timeout: timeout, accept: accept)
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { continue }
                hasWarmConnection = true
                networkCooldownUntil = .distantPast
                if http.statusCode == 200 {
                    preferredHostIndex = hostIdx
                    return (data, http)
                }
                if http.statusCode == 401 || http.statusCode == 403 {
                    return (data, http)
                }
            } catch {
                sawTransportFailure = true
                continue
            }
        }
        if sawTransportFailure {
            hasWarmConnection = false
            networkCooldownUntil = Date().addingTimeInterval(15)
        }
        return nil
    }

    private func hasValidYahooSessionCookie() -> Bool {
        guard let cookies = session.configuration.httpCookieStorage?.cookies else { return false }
        let now = Date()
        return cookies.contains { cookie in
            cookie.name == "A3"
                && cookie.domain.contains("yahoo.com")
                && (cookie.expiresDate.map { $0 > now } ?? true)
        }
    }

    private func seedYahooSessionCookie() async -> Bool {
        let cookieSeedURLs = [
            "https://fc.yahoo.com",
            "https://guce.yahoo.com/consent"
        ]
        for urlString in cookieSeedURLs {
            guard let url = URL(string: urlString) else { continue }
            var req = makeRequest(url: url, timeout: 12)
            req.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
            do {
                _ = try await session.data(for: req)
                if hasValidYahooSessionCookie() {
                    return true
                }
            } catch {
                continue
            }
        }
        return hasValidYahooSessionCookie()
    }

    private func ensureCrumb(forceRefresh: Bool = false) async -> String? {
        if !forceRefresh,
           let cached = cachedCrumb,
           Date().timeIntervalSince(cached.fetchedAt) < 1800 {
            return cached.value
        }

        if !forceRefresh, Date() < crumbCooldownUntil {
            return nil
        }

        if let existing = crumbTask {
            return await existing.value
        }

        let task = Task<String?, Never> {
            let hadCookie = !forceRefresh && hasValidYahooSessionCookie()
            if !hadCookie {
                guard await seedYahooSessionCookie() else {
                    return nil
                }
            }

            var responsePair = await performWithHostFallback(
                path: "/v1/test/getcrumb",
                queryItems: [],
                timeout: 12
            )

            // If a reused cookie expired/was rejected, re-seed and retry crumb once
            if hadCookie, let http = responsePair?.1, (http.statusCode == 401 || http.statusCode == 403) {
                if await seedYahooSessionCookie() {
                    responsePair = await performWithHostFallback(
                        path: "/v1/test/getcrumb",
                        queryItems: [],
                        timeout: 12
                    )
                }
            }

            guard let (data, response) = responsePair, response.statusCode == 200 else {
                return nil
            }

            let raw = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !raw.isEmpty,
                  !raw.hasPrefix("<"),
                  !raw.localizedCaseInsensitiveContains("Too Many Requests") else {
                return nil
            }
            return raw
        }

        crumbTask = task
        let value = await task.value
        crumbTask = nil

        if let value {
            cachedCrumb = (value, Date())
            crumbCooldownUntil = .distantPast
        } else {
            cachedCrumb = nil
            crumbCooldownUntil = Date().addingTimeInterval(60)
        }
        return value
    }

    private func fetchLiveQuotesBatchFromYahoo(symbols: [String]) async -> [String: StockQuote] {
        guard !symbols.isEmpty else { return [:] }
        guard var crumb = await ensureCrumb() else { return [:] }

        var allQuotes: [String: StockQuote] = [:]
        let chunkSize = 50

        for start in stride(from: 0, to: symbols.count, by: chunkSize) {
            let chunk = Array(symbols[start..<min(start + chunkSize, symbols.count)])
            let joinedSymbols = chunk.joined(separator: ",")

            var responsePair = await performWithHostFallback(
                path: "/v7/finance/quote",
                queryItems: [
                    URLQueryItem(name: "symbols", value: joinedSymbols),
                    URLQueryItem(name: "crumb", value: crumb)
                ],
                timeout: 12
            )

            if let http = responsePair?.1, (http.statusCode == 401 || http.statusCode == 403) {
                if let freshCrumb = await ensureCrumb(forceRefresh: true) {
                    crumb = freshCrumb
                    responsePair = await performWithHostFallback(
                        path: "/v7/finance/quote",
                        queryItems: [
                            URLQueryItem(name: "symbols", value: joinedSymbols),
                            URLQueryItem(name: "crumb", value: crumb)
                        ],
                        timeout: 12
                    )
                }
            }

            guard let (data, http) = responsePair,
                  http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let quoteResponse = json["quoteResponse"] as? [String: Any],
                  let results = quoteResponse["result"] as? [[String: Any]] else {
                continue
            }

            for item in results {
                guard let rawSymbol = item["symbol"] as? String else { continue }
                let sym = rawSymbol.uppercased()
                let price = (item["regularMarketPrice"] as? NSNumber)?.doubleValue ?? 0
                guard price > 0 else { continue }

                let change = (item["regularMarketChange"] as? NSNumber)?.doubleValue ?? 0
                let changePct = (item["regularMarketChangePercent"] as? NSNumber)?.doubleValue ?? 0
                let name = (item["shortName"] as? String)
                    ?? (item["longName"] as? String)
                    ?? (item["displayName"] as? String)
                    ?? sym
                let currency = (item["currency"] as? String) ?? inferredCurrency(for: sym)
                let volume = (item["regularMarketVolume"] as? NSNumber)?.int64Value ?? 0
                let marketCap = (item["marketCap"] as? NSNumber)?.doubleValue
                let peRatio = (item["trailingPE"] as? NSNumber)?.doubleValue
                    ?? (item["forwardPE"] as? NSNumber)?.doubleValue
                let forwardPE = (item["forwardPE"] as? NSNumber)?.doubleValue
                let priceToBook = (item["priceToBook"] as? NSNumber)?.doubleValue
                let epsTTM = (item["epsTrailingTwelveMonths"] as? NSNumber)?.doubleValue
                let epsForward = (item["epsForward"] as? NSNumber)?.doubleValue
                let bookValue = (item["bookValue"] as? NSNumber)?.doubleValue
                let divYieldPct = (item["dividendYield"] as? NSNumber)?.doubleValue
                    ?? ((item["trailingAnnualDividendYield"] as? NSNumber)?.doubleValue).map { $0 * 100 }
                let dayHigh = (item["regularMarketDayHigh"] as? NSNumber)?.doubleValue
                let dayLow = (item["regularMarketDayLow"] as? NSNumber)?.doubleValue
                let openPrice = (item["regularMarketOpen"] as? NSNumber)?.doubleValue
                let previousClose = (item["regularMarketPreviousClose"] as? NSNumber)?.doubleValue
                let avgVolume3M = (item["averageDailyVolume3Month"] as? NSNumber)?.int64Value
                let fiftyDayAvg = (item["fiftyDayAverage"] as? NSNumber)?.doubleValue
                let twoHundredDayAvg = (item["twoHundredDayAverage"] as? NSNumber)?.doubleValue
                let analystRating = item["averageAnalystRating"] as? String
                let high52 = (item["fiftyTwoWeekHigh"] as? NSNumber)?.doubleValue
                let low52 = (item["fiftyTwoWeekLow"] as? NSNumber)?.doubleValue

                let sparkline: [Double]
                if let existingSparkline = quoteCache[sym]?.quote.sparklinePrices,
                   !existingSparkline.isEmpty {
                    sparkline = existingSparkline
                } else {
                    sparkline = Self.makeSparkline(basePrice: price, isPositive: change >= 0)
                }

                let existingCached = quoteCache[sym]?.quote
                allQuotes[sym] = StockQuote(
                    symbol: sym,
                    companyName: name,
                    regularMarketPrice: price,
                    regularMarketChange: change,
                    regularMarketChangePercent: changePct,
                    currency: currency,
                    regularMarketVolume: volume,
                    marketCap: marketCap,
                    peRatio: peRatio,
                    forwardPE: forwardPE,
                    priceToBook: priceToBook,
                    pegRatio: existingCached?.pegRatio,
                    priceToSales: existingCached?.priceToSales,
                    evToEbitda: existingCached?.evToEbitda,
                    epsTTM: epsTTM,
                    epsForward: epsForward,
                    bookValue: bookValue,
                    dividendYieldPercent: divYieldPct,
                    beta: existingCached?.beta,
                    profitMarginPercent: existingCached?.profitMarginPercent,
                    roePercent: existingCached?.roePercent,
                    debtToEquity: existingCached?.debtToEquity,
                    dayHigh: dayHigh,
                    dayLow: dayLow,
                    openPrice: openPrice,
                    previousClose: previousClose,
                    avgVolume3Month: avgVolume3M,
                    fiftyDayAverage: fiftyDayAvg,
                    twoHundredDayAverage: twoHundredDayAvg,
                    targetMeanPrice: existingCached?.targetMeanPrice,
                    analystRating: analystRating ?? existingCached?.analystRating,
                    fiftyTwoWeekHigh: high52,
                    fiftyTwoWeekLow: low52,
                    sparklinePrices: sparkline
                )
            }
        }

        return allQuotes
    }

    public func fetchDetailedStatistics(for quote: StockQuote) async -> StockQuote {
        let sym = quote.symbol.uppercased()
        var base = quoteCache[sym]?.quote ?? quote
        networkCooldownUntil = .distantPast
        crumbCooldownUntil = .distantPast

        guard var crumb = await ensureCrumb() else { return base }
        let encodedSym = sym.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sym
        let path = "/v10/finance/quoteSummary/\(encodedSym)"
        let query = [
            URLQueryItem(name: "modules", value: "defaultKeyStatistics,summaryDetail,financialData"),
            URLQueryItem(name: "crumb", value: crumb)
        ]

        var responsePair = await performWithHostFallback(path: path, queryItems: query, timeout: 12)
        if let http = responsePair?.1, (http.statusCode == 401 || http.statusCode == 403) {
            if let freshCrumb = await ensureCrumb(forceRefresh: true) {
                crumb = freshCrumb
                responsePair = await performWithHostFallback(
                    path: path,
                    queryItems: [
                        URLQueryItem(name: "modules", value: "defaultKeyStatistics,summaryDetail,financialData"),
                        URLQueryItem(name: "crumb", value: crumb)
                    ],
                    timeout: 12
                )
            }
        }

        guard let (data, http) = responsePair,
              http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let summary = json["quoteSummary"] as? [String: Any],
              let results = summary["result"] as? [[String: Any]],
              let first = results.first else {
            return base
        }

        let keyStats = first["defaultKeyStatistics"] as? [String: Any] ?? [:]
        let summaryDetail = first["summaryDetail"] as? [String: Any] ?? [:]
        let financialData = first["financialData"] as? [String: Any] ?? [:]

        func rawDouble(_ dict: [String: Any], _ key: String) -> Double? {
            if let sub = dict[key] as? [String: Any], let num = sub["raw"] as? NSNumber {
                return num.doubleValue
            }
            if let num = dict[key] as? NSNumber {
                return num.doubleValue
            }
            return nil
        }

        func rawInt64(_ dict: [String: Any], _ key: String) -> Int64? {
            if let sub = dict[key] as? [String: Any], let num = sub["raw"] as? NSNumber {
                return num.int64Value
            }
            if let num = dict[key] as? NSNumber {
                return num.int64Value
            }
            return nil
        }

        if let val = rawDouble(summaryDetail, "marketCap") { base.marketCap = val }
        if let val = rawDouble(summaryDetail, "trailingPE") { base.peRatio = val }
        if let val = rawDouble(keyStats, "forwardPE") ?? rawDouble(summaryDetail, "forwardPE") { base.forwardPE = val }
        if let val = rawDouble(keyStats, "priceToBook") { base.priceToBook = val }
        if let val = rawDouble(keyStats, "pegRatio") ?? rawDouble(keyStats, "trailingPegRatio") { base.pegRatio = val }
        if let val = rawDouble(keyStats, "priceToSalesTrailing12Months") ?? rawDouble(summaryDetail, "priceToSalesTrailing12Months") {
            base.priceToSales = val
        }
        if let val = rawDouble(keyStats, "enterpriseToEbitda") { base.evToEbitda = val }
        if let val = rawDouble(keyStats, "trailingEps") { base.epsTTM = val }
        if let val = rawDouble(keyStats, "forwardEps") { base.epsForward = val }
        if let val = rawDouble(keyStats, "bookValue") { base.bookValue = val }
        if let val = rawDouble(summaryDetail, "dividendYield") {
            base.dividendYieldPercent = val * 100
        } else if let val = rawDouble(summaryDetail, "trailingAnnualDividendYield") {
            base.dividendYieldPercent = val * 100
        }
        if let val = rawDouble(keyStats, "beta") ?? rawDouble(summaryDetail, "beta") { base.beta = val }
        if let val = rawDouble(financialData, "profitMargins") ?? rawDouble(keyStats, "profitMargins") {
            base.profitMarginPercent = val * 100
        }
        if let val = rawDouble(financialData, "returnOnEquity") { base.roePercent = val * 100 }
        if let val = rawDouble(financialData, "debtToEquity") { base.debtToEquity = val }
        if let val = rawDouble(summaryDetail, "dayHigh") { base.dayHigh = val }
        if let val = rawDouble(summaryDetail, "dayLow") { base.dayLow = val }
        if let val = rawDouble(summaryDetail, "open") { base.openPrice = val }
        if let val = rawDouble(summaryDetail, "previousClose") { base.previousClose = val }
        if let val = rawInt64(summaryDetail, "averageVolume") { base.avgVolume3Month = val }
        if let val = rawDouble(summaryDetail, "fiftyDayAverage") { base.fiftyDayAverage = val }
        if let val = rawDouble(summaryDetail, "twoHundredDayAverage") { base.twoHundredDayAverage = val }
        if let val = rawDouble(summaryDetail, "fiftyTwoWeekHigh") { base.fiftyTwoWeekHigh = val }
        if let val = rawDouble(summaryDetail, "fiftyTwoWeekLow") { base.fiftyTwoWeekLow = val }
        if let val = rawDouble(financialData, "targetMeanPrice") { base.targetMeanPrice = val }
        if base.analystRating == nil, let rec = financialData["recommendationKey"] as? String, !rec.isEmpty {
            base.analystRating = rec.replacingOccurrences(of: "_", with: " ").capitalized
        }

        quoteCache[sym] = (base, Date())
        return base
    }

    private func fetchLiveQuotesViaChartConcurrently(symbols: [String]) async -> [String: StockQuote] {
        guard !symbols.isEmpty else { return [:] }
        var map: [String: StockQuote] = [:]
        var remainingSymbols = symbols

        if !hasWarmConnection, let probeSymbol = remainingSymbols.first {
            remainingSymbols.removeFirst()
            if let probeQuote = await fetchLiveQuoteViaChartFromYahoo(symbol: probeSymbol) {
                map[probeSymbol] = probeQuote
            } else if Date() < networkCooldownUntil {
                return map
            }
        }

        guard !remainingSymbols.isEmpty else { return map }
        let maxConcurrent = 3

        await withTaskGroup(of: (String, StockQuote?).self) { group in
            var index = 0
            while index < min(maxConcurrent, remainingSymbols.count) {
                let sym = remainingSymbols[index]
                group.addTask {
                    let quote = await self.fetchLiveQuoteViaChartFromYahoo(symbol: sym)
                    return (sym, quote)
                }
                index += 1
            }

            while let (sym, quote) = await group.next() {
                if let quote {
                    map[sym] = quote
                }
                if index < remainingSymbols.count, Date() >= networkCooldownUntil {
                    let nextSym = remainingSymbols[index]
                    group.addTask {
                        let nextQuote = await self.fetchLiveQuoteViaChartFromYahoo(symbol: nextSym)
                        return (nextSym, nextQuote)
                    }
                    index += 1
                }
            }
        }
        return map
    }

    private func fetchLiveQuoteViaChartFromYahoo(symbol: String) async -> StockQuote? {
        guard let (data, response) = await performWithHostFallback(
            path: "/v8/finance/chart/\(symbol)",
            queryItems: [
                URLQueryItem(name: "interval", value: "5m"),
                URLQueryItem(name: "range", value: "1d")
            ],
            timeout: 12
        ), response.statusCode == 200 else {
            return nil
        }

        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let chart = json?["chart"] as? [String: Any],
                  let results = chart["result"] as? [[String: Any]],
                  let first = results.first,
                  let meta = first["meta"] as? [String: Any] else {
                return nil
            }

            let price = (meta["regularMarketPrice"] as? NSNumber)?.doubleValue ?? 0
            guard price > 0 else { return nil }

            let prevClose = (meta["previousClose"] as? NSNumber)?.doubleValue
                ?? (meta["chartPreviousClose"] as? NSNumber)?.doubleValue
                ?? price
            let change = price - prevClose
            let changePct = (meta["regularMarketChangePercent"] as? NSNumber)?.doubleValue
                ?? (prevClose > 0 ? (change / prevClose) * 100 : 0)
            let name = (meta["shortName"] as? String)
                ?? (meta["longName"] as? String)
                ?? (meta["symbol"] as? String)
                ?? symbol
            let currency = (meta["currency"] as? String) ?? inferredCurrency(for: symbol)
            let volume = (meta["regularMarketVolume"] as? NSNumber)?.int64Value ?? 0
            let high52 = (meta["fiftyTwoWeekHigh"] as? NSNumber)?.doubleValue
            let low52 = (meta["fiftyTwoWeekLow"] as? NSNumber)?.doubleValue

            var sparkline: [Double] = []
            if let indicators = first["indicators"] as? [String: Any],
               let quote = (indicators["quote"] as? [[String: Any]])?.first,
               let closes = quote["close"] as? [Any] {
                for item in closes {
                    if let val = (item as? NSNumber)?.doubleValue {
                        sparkline.append(val)
                    }
                }
            }

            if sparkline.isEmpty {
                sparkline = Self.makeSparkline(basePrice: price, isPositive: change >= 0)
            }

            let existing = quoteCache[symbol]?.quote
            return StockQuote(
                symbol: symbol,
                companyName: name,
                regularMarketPrice: price,
                regularMarketChange: change,
                regularMarketChangePercent: changePct,
                currency: currency,
                regularMarketVolume: volume > 0 ? volume : (existing?.regularMarketVolume ?? 0),
                marketCap: existing?.marketCap,
                peRatio: existing?.peRatio,
                forwardPE: existing?.forwardPE,
                priceToBook: existing?.priceToBook,
                pegRatio: existing?.pegRatio,
                priceToSales: existing?.priceToSales,
                evToEbitda: existing?.evToEbitda,
                epsTTM: existing?.epsTTM,
                epsForward: existing?.epsForward,
                bookValue: existing?.bookValue,
                dividendYieldPercent: existing?.dividendYieldPercent,
                beta: existing?.beta,
                profitMarginPercent: existing?.profitMarginPercent,
                roePercent: existing?.roePercent,
                debtToEquity: existing?.debtToEquity,
                dayHigh: (meta["regularMarketDayHigh"] as? NSNumber)?.doubleValue ?? existing?.dayHigh,
                dayLow: (meta["regularMarketDayLow"] as? NSNumber)?.doubleValue ?? existing?.dayLow,
                openPrice: existing?.openPrice,
                previousClose: prevClose,
                avgVolume3Month: existing?.avgVolume3Month,
                fiftyDayAverage: existing?.fiftyDayAverage,
                twoHundredDayAverage: existing?.twoHundredDayAverage,
                targetMeanPrice: existing?.targetMeanPrice,
                analystRating: existing?.analystRating,
                fiftyTwoWeekHigh: high52 ?? existing?.fiftyTwoWeekHigh,
                fiftyTwoWeekLow: low52 ?? existing?.fiftyTwoWeekLow,
                sparklinePrices: sparkline
            )
        } catch {
            return nil
        }
    }

    private func fetchLiveChartFromYahoo(symbol: String, timeframe: ChartTimeframe) async -> [HistoricalPricePoint]? {
        let (range, interval) = yahooParams(for: timeframe)
        guard let (data, response) = await performWithHostFallback(
            path: "/v8/finance/chart/\(symbol)",
            queryItems: [
                URLQueryItem(name: "range", value: range),
                URLQueryItem(name: "interval", value: interval)
            ],
            timeout: 12
        ), response.statusCode == 200 else {
            return nil
        }

        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let chart = json?["chart"] as? [String: Any],
                  let results = chart["result"] as? [[String: Any]],
                  let first = results.first,
                  let timestamps = first["timestamp"] as? [Int],
                  let indicators = first["indicators"] as? [String: Any],
                  let quotes = indicators["quote"] as? [[String: Any]],
                  let firstQuote = quotes.first,
                  let closes = firstQuote["close"] as? [Any] else {
                return nil
            }

            let volumes = firstQuote["volume"] as? [Any]
            var points: [HistoricalPricePoint] = []
            let count = min(timestamps.count, closes.count)
            points.reserveCapacity(count)

            for i in 0..<count {
                if let priceNum = closes[i] as? NSNumber {
                    let date = Date(timeIntervalSince1970: TimeInterval(timestamps[i]))
                    let vol: Int64
                    if let volumes, i < volumes.count, let volNum = volumes[i] as? NSNumber {
                        vol = volNum.int64Value
                    } else {
                        vol = 0
                    }
                    points.append(HistoricalPricePoint(date: date, price: priceNum.doubleValue, volume: vol))
                }
            }
            return points
        } catch {
            return nil
        }
    }

    private func fetchLiveSearch(query: String) async -> [StockQuote]? {
        networkCooldownUntil = .distantPast
        guard let (data, response) = await performWithHostFallback(
            path: "/v1/finance/search",
            queryItems: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "quotesCount", value: "10")
            ],
            timeout: 10
        ), response.statusCode == 200 else {
            return nil
        }

        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let quotes = json?["quotes"] as? [[String: Any]] else { return nil }

            var orderedSymbols: [String] = []
            var nameBySymbol: [String: String] = [:]
            for item in quotes {
                if let rawSym = item["symbol"] as? String {
                    let sym = rawSym.uppercased()
                    if nameBySymbol[sym] == nil {
                        orderedSymbols.append(sym)
                        nameBySymbol[sym] = (item["shortname"] as? String)
                            ?? (item["longname"] as? String)
                            ?? sym
                    }
                }
            }

            guard !orderedSymbols.isEmpty else { return nil }

            let liveBatch = await fetchLiveQuotesBatchFromYahoo(symbols: orderedSymbols)
            return orderedSymbols.map { sym in
                if let live = liveBatch[sym] {
                    quoteCache[sym] = (live, Date())
                    return live
                }
                if let cached = quoteCache[sym] {
                    return cached.quote
                }
                return StockQuote(
                    symbol: sym,
                    companyName: nameBySymbol[sym] ?? sym,
                    regularMarketPrice: 0,
                    regularMarketChange: 0,
                    regularMarketChangePercent: 0,
                    currency: inferredCurrency(for: sym)
                )
            }
        } catch {
            return nil
        }
    }

    private func yahooParams(for timeframe: ChartTimeframe) -> (range: String, interval: String) {
        switch timeframe {
        case .oneDay: return ("1d", "5m")
        case .fiveDays: return ("5d", "15m")
        case .oneMonth: return ("1mo", "1d")
        case .sixMonths: return ("6mo", "1d")
        case .oneYear: return ("1y", "1wk")
        case .allTime: return ("max", "1mo")
        }
    }

    // MARK: - Realistic Fallbacks
    private func generateRealisticQuote(symbol: String) -> StockQuote {
        let seed = abs(symbol.hashValue) % 1000
        let basePrice = 50.0 + Double(seed) * 0.4
        let isPositive = (seed % 2 == 0)
        let changeMagnitude = Double(seed % 35) * 0.1 + 0.35
        let change = isPositive ? changeMagnitude : -changeMagnitude
        let changePct = (change / basePrice) * 100

        let names: [String: String] = [
            "AAPL": "Apple Inc.",
            "MSFT": "Microsoft Corp.",
            "GOOGL": "Alphabet Inc.",
            "AMZN": "Amazon.com Inc.",
            "NVDA": "NVIDIA Corp.",
            "TSLA": "Tesla Inc.",
            "META": "Meta Platforms Inc.",
            "SPY": "SPDR S&P 500 ETF",
            "QQQ": "Invesco QQQ Trust",
            "BTC-USD": "Bitcoin USD",
            "^GSPC": "S&P 500",
            "^DJI": "Dow Jones Industrial Average",
            "^IXIC": "NASDAQ Composite",
            "^RUT": "Russell 2000",
            "^VIX": "CBOE Volatility Index",
            "^FTSE": "FTSE 100",
            "^GDAXI": "DAX Performance Index",
            "^FCHI": "CAC 40",
            "^STOXX50E": "EURO STOXX 50",
            "^N225": "Nikkei 225",
            "^NSEI": "NIFTY 50",
            "^BSESN": "S&P BSE SENSEX",
            "^HSI": "Hang Seng Index",
            "000001.SS": "SSE Composite Index",
            "GC=F": "Gold Futures",
            "CL=F": "Crude Oil Futures",
            "EURUSD=X": "EUR/USD",
            "USDINR=X": "USD/INR",
            "RELIANCE.NS": "Reliance Industries Ltd.",
            "TCS.NS": "Tata Consultancy Services",
            "ASML.AS": "ASML Holding N.V.",
            "SAP.DE": "SAP SE",
            "AZN.L": "AstraZeneca PLC",
            "7203.T": "Toyota Motor Corp.",
            "TSM": "Taiwan Semiconductor"
        ]

        let name = names[symbol] ?? "\(symbol)"

        return StockQuote(
            symbol: symbol,
            companyName: name,
            regularMarketPrice: basePrice,
            regularMarketChange: change,
            regularMarketChangePercent: changePct,
            currency: inferredCurrency(for: symbol),
            regularMarketVolume: Int64(seed * 45000 + 1_200_000),
            marketCap: Double(seed) * 2_500_000_000 + 40_000_000_000,
            peRatio: 18.0 + Double(seed % 40),
            fiftyTwoWeekHigh: basePrice * 1.25,
            fiftyTwoWeekLow: basePrice * 0.78,
            sparklinePrices: Self.makeSparkline(basePrice: basePrice, isPositive: isPositive)
        )
    }

    private func inferredCurrency(for symbol: String) -> String {
        if symbol.hasSuffix(".NS") || symbol.hasSuffix(".BO") || symbol == "^NSEI" || symbol == "^BSESN" || symbol == "USDINR=X" {
            return "INR"
        } else if symbol.hasSuffix(".L") || symbol == "^FTSE" {
            return "GBP"
        } else if symbol.hasSuffix(".AS") || symbol.hasSuffix(".DE") || symbol.hasSuffix(".PA") || symbol == "^GDAXI" || symbol == "^FCHI" || symbol == "^STOXX50E" {
            return "EUR"
        } else if symbol.hasSuffix(".T") || symbol == "^N225" {
            return "JPY"
        } else if symbol.hasSuffix(".HK") || symbol == "^HSI" {
            return "HKD"
        } else if symbol.hasSuffix(".SS") || symbol.hasSuffix(".SZ") {
            return "CNY"
        }
        return "USD"
    }

    private nonisolated static func makeSparkline(basePrice: Double, isPositive: Bool) -> [Double] {
        var points: [Double] = []
        var cur = basePrice * (isPositive ? 0.98 : 1.02)
        points.append(cur)
        for i in 1...16 {
            let drift = isPositive ? 0.002 : -0.002
            let noise = Double((i * 13) % 7 - 3) * 0.0015
            cur = cur * (1.0 + drift + noise)
            points.append(cur)
        }
        points.append(basePrice)
        return points
    }

    private func generateRealisticChart(symbol: String, timeframe: ChartTimeframe) -> [HistoricalPricePoint] {
        let (count, timeStep): (Int, TimeInterval) = {
            switch timeframe {
            case .oneDay: return (30, 15 * 60)
            case .fiveDays: return (40, 2 * 3600)
            case .oneMonth: return (30, 24 * 3600)
            case .sixMonths: return (60, 3 * 24 * 3600)
            case .oneYear: return (52, 7 * 24 * 3600)
            case .allTime: return (70, 30 * 24 * 3600)
            }
        }()

        let seed = abs(symbol.hashValue) % 100
        var price = 100.0 + Double(seed) * 1.5
        var result: [HistoricalPricePoint] = []
        let now = Date()

        for i in (0..<count).reversed() {
            let date = now.addingTimeInterval(-Double(i) * timeStep)
            let wiggle = Double(((i * 17 + seed) % 11) - 5) * 0.006
            let trend = 0.001
            price = max(1.0, price * (1.0 + trend + wiggle))
            result.append(HistoricalPricePoint(date: date, price: price))
        }
        return result
    }
}
