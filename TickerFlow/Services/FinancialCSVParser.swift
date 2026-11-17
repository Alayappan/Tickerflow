import Foundation

public struct FinancialCSVParser {

    public struct ParseResult {
        public let transactions: [Transaction]
        public let detectedSource: String
        public let errors: [String]
    }

    public static func parseCSV(text: String) -> ParseResult {
        let sanitizedText = text.replacingOccurrences(of: "\u{FEFF}", with: "")
        let lines = sanitizedText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard lines.count > 1 else {
            return ParseResult(transactions: [], detectedSource: "Unknown", errors: ["CSV file is empty or missing headers"])
        }

        let rawHeader = lines[0].lowercased()
        let headers = parseCSVLine(lines[0]).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")
                .lowercased()
        }

        var symbolIndex = -1
        var sharesIndex = -1
        var purchasePriceIndex = -1
        var genericPriceIndex = -1
        var currentPriceIndex = -1
        var nameIndex = -1
        var tradeDateIndex = -1
        var quoteDateIndex = -1
        var commissionIndex = -1
        var commentIndex = -1
        var transactionTypeIndex = -1
        var detected = "Generic Finance CSV"

        if rawHeader.contains("yahoo")
            || (rawHeader.contains("purchase price") && (rawHeader.contains("trade date") || rawHeader.contains("current price")))
            || (rawHeader.contains("current price") && rawHeader.contains("quantity") && rawHeader.contains("transaction type")) {
            detected = "Yahoo Finance Portfolio CSV"
        } else if rawHeader.contains("google") || (rawHeader.contains("shares") && rawHeader.contains("cost basis")) {
            detected = "Google Finance Portfolio CSV"
        }

        for (idx, h) in headers.enumerated() {
            if h == "symbol" || h == "ticker" || h.contains("symbol") {
                if symbolIndex == -1 { symbolIndex = idx }
            } else if h == "quantity" || h == "shares" || h == "qty" || h.contains("quantity") || h.contains("share") {
                if sharesIndex == -1 { sharesIndex = idx }
            } else if h == "purchase price" || h == "avg price" || h == "average cost" || h == "cost basis"
                        || h.contains("purchase price") || h.contains("avg price") || h.contains("cost basis") {
                if purchasePriceIndex == -1 { purchasePriceIndex = idx }
            } else if h == "current price" || h.contains("current price") {
                if currentPriceIndex == -1 { currentPriceIndex = idx }
            } else if h == "price" || (h.contains("price") && !h.contains("limit")) {
                if genericPriceIndex == -1 { genericPriceIndex = idx }
            } else if h == "name" || h == "company" || h == "company name" || h.contains("company") || h.contains("name") {
                if nameIndex == -1 { nameIndex = idx }
            } else if h == "trade date" || h.contains("trade date") {
                if tradeDateIndex == -1 { tradeDateIndex = idx }
            } else if h == "date" {
                if quoteDateIndex == -1 { quoteDateIndex = idx }
            } else if h == "commission" || h.contains("commission") || h == "fee" || h == "fees" {
                if commissionIndex == -1 { commissionIndex = idx }
            } else if h == "comment" || h == "comments" || h == "note" || h == "notes" {
                if commentIndex == -1 { commentIndex = idx }
            } else if h == "transaction type" || h == "type" || h == "action" || h == "side" {
                if transactionTypeIndex == -1 { transactionTypeIndex = idx }
            }
        }

        let priceIndex = purchasePriceIndex != -1
            ? purchasePriceIndex
            : (genericPriceIndex != -1 ? genericPriceIndex : currentPriceIndex)

        guard symbolIndex != -1, sharesIndex != -1, priceIndex != -1 else {
            return ParseResult(
                transactions: [],
                detectedSource: detected,
                errors: ["Could not detect required columns (Symbol, Shares/Quantity, Purchase Price). Found: \(headers.joined(separator: ", "))"]
            )
        }

        var results: [Transaction] = []
        var errors: [String] = []

        for rowIdx in 1..<lines.count {
            let row = parseCSVLine(lines[rowIdx])
            guard row.count > max(symbolIndex, sharesIndex) else {
                continue
            }

            let rawSymbol = cleanField(row[symbolIndex])
            let rawShares = cleanNumericString(row[sharesIndex])
            let rawPrimaryPrice = priceIndex < row.count ? cleanNumericString(row[priceIndex]) : ""
            let rawFallbackPrice = (currentPriceIndex != -1 && currentPriceIndex < row.count)
                ? cleanNumericString(row[currentPriceIndex])
                : ""
            let rawPrice = rawPrimaryPrice.isEmpty ? rawFallbackPrice : rawPrimaryPrice

            // Yahoo Finance exports include watchlist-only symbols with blank Quantity and Purchase Price
            if rawShares.isEmpty && rawPrimaryPrice.isEmpty {
                continue
            }

            guard !rawSymbol.isEmpty,
                  let parsedShares = Double(rawShares),
                  parsedShares != 0,
                  let price = Double(rawPrice),
                  price >= 0 else {
                errors.append("Row \(rowIdx + 1): Invalid data (\(lines[rowIdx]))")
                continue
            }

            let rawTxType = (transactionTypeIndex != -1 && transactionTypeIndex < row.count)
                ? cleanField(row[transactionTypeIndex]).lowercased()
                : ""

            let txType: TransactionType
            let shares: Double
            if rawTxType == "sell" || rawTxType == "s" || rawTxType.contains("sell") || rawTxType.contains("short") {
                txType = .sell
                shares = abs(parsedShares)
            } else if parsedShares < 0 {
                txType = .sell
                shares = abs(parsedShares)
            } else {
                txType = .buy
                shares = parsedShares
            }

            let name = (nameIndex != -1 && nameIndex < row.count) ? cleanField(row[nameIndex]) : ""

            let tradeDate: Date
            if tradeDateIndex != -1, tradeDateIndex < row.count, let parsed = parseDate(cleanField(row[tradeDateIndex])) {
                tradeDate = parsed
            } else if tradeDateIndex == -1, quoteDateIndex != -1, quoteDateIndex < row.count, let parsed = parseDate(cleanField(row[quoteDateIndex])) {
                tradeDate = parsed
            } else {
                tradeDate = Date()
            }

            let commission: Double
            if commissionIndex != -1, commissionIndex < row.count {
                commission = Double(cleanNumericString(row[commissionIndex])) ?? 0
            } else {
                commission = 0
            }

            let comment = (commentIndex != -1 && commentIndex < row.count) ? cleanField(row[commentIndex]) : ""
            let notes: String
            if !comment.isEmpty && commission > 0 {
                notes = "\(comment) (Commission: $\(String(format: "%.2f", commission)))"
            } else if !comment.isEmpty {
                notes = comment
            } else if commission > 0 {
                notes = "Imported from \(detected) (Commission: $\(String(format: "%.2f", commission)))"
            } else {
                notes = "Imported from \(detected)"
            }

            let tx = Transaction(
                symbol: rawSymbol,
                companyName: name,
                type: txType,
                shares: shares,
                pricePerShare: price,
                date: tradeDate,
                notes: notes
            )
            results.append(tx)
        }

        return ParseResult(transactions: results, detectedSource: detected, errors: errors)
    }

    private static func cleanField(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanNumericString(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseDate(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }
        let formats = [
            "yyyyMMdd",
            "yyyy-MM-dd",
            "yyyy/MM/dd",
            "MM/dd/yyyy",
            "MM-dd-yyyy"
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    private static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var insideQuotes = false

        for char in line {
            if char == "\"" {
                insideQuotes.toggle()
            } else if char == "," && !insideQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current)
        return fields
    }

    public static func exportHoldingsToCSV(holdings: [Holding], sourceName: String) -> String {
        var csv = "Symbol,Name,Shares,Average Cost,Current Price,Market Value,Total Gain/Loss\n"
        for h in holdings {
            let line = "\(h.symbol),\"\(h.companyName)\",\(h.totalShares),\(h.avgCostPerShare),\(h.currentPrice),\(h.currentValue),\(h.totalGainLoss)\n"
            csv.append(line)
        }
        return csv
    }
}
