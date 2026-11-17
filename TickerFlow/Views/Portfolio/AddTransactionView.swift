import SwiftUI

public struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    public let store: FinanceStore
    public let existingTransaction: Transaction?

    @State private var selectedPortfolioId: UUID?
    @State private var symbol: String
    @State private var type: TransactionType
    @State private var sharesText: String
    @State private var priceText: String
    @State private var date: Date
    @State private var notes: String
    @State private var errorMessage: String?

    public init(
        prefilledSymbol: String = "",
        prefilledPrice: Double? = nil,
        prefilledType: TransactionType = .buy,
        prefilledPortfolioId: UUID? = nil,
        existingTransaction: Transaction? = nil,
        store: FinanceStore
    ) {
        self.store = store
        self.existingTransaction = existingTransaction
        if let existing = existingTransaction {
            _selectedPortfolioId = State(initialValue: existing.portfolioId ?? store.currentPortfolio?.id)
            _symbol = State(initialValue: existing.symbol)
            _type = State(initialValue: existing.type)
            _sharesText = State(initialValue: Self.cleanNumberText(existing.shares))
            _priceText = State(initialValue: String(format: "%.2f", existing.pricePerShare))
            _date = State(initialValue: existing.date)
            _notes = State(initialValue: existing.notes)
        } else {
            _selectedPortfolioId = State(initialValue: prefilledPortfolioId ?? store.currentPortfolio?.id)
            _symbol = State(initialValue: prefilledSymbol)
            _type = State(initialValue: prefilledType)
            _sharesText = State(initialValue: "")
            if let price = prefilledPrice, price > 0 {
                _priceText = State(initialValue: String(format: "%.2f", price))
            } else {
                _priceText = State(initialValue: "")
            }
            _date = State(initialValue: Date())
            _notes = State(initialValue: "")
        }
    }

    private var targetPortfolio: Portfolio? {
        store.portfolio(for: selectedPortfolioId) ?? store.currentPortfolio
    }

    private var targetCurrency: String {
        targetPortfolio?.currency ?? "USD"
    }

    private static func cleanNumberText(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.4f", value).replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
    }

    private var calculatedTotal: Double {
        let shares = Double(sharesText) ?? 0
        let price = Double(priceText) ?? 0
        return shares * price
    }

    private var convertedLiveQuotePrice: Double? {
        let sym = symbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sym.isEmpty, let quote = store.quotes[sym], quote.regularMarketPrice > 0 else { return nil }
        let fx = store.fxRate(from: quote.currency, to: targetCurrency)
        return quote.regularMarketPrice * fx
    }

    public var body: some View {
        NavigationStack {
            Form {
                if !store.portfolios.isEmpty {
                    Section("Portfolio") {
                        Picker("Portfolio", selection: Binding(
                            get: { targetPortfolio?.id ?? store.portfolios[0].id },
                            set: { selectedPortfolioId = $0 }
                        )) {
                            ForEach(store.portfolios) { portfolio in
                                Text("\(portfolio.name) (\(portfolio.currency))").tag(portfolio.id)
                            }
                        }
                    }
                }

                Section("Holding / Trade Information") {
                    Picker("Transaction Type", selection: $type) {
                        Text("Buy").tag(TransactionType.buy)
                        Text("Sell").tag(TransactionType.sell)
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("Symbol")
                        Spacer()
                        TextField("e.g. AAPL, TCS.NS", text: $symbol)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }

                    HStack {
                        Text("Shares")
                        Spacer()
                        TextField("0", text: $sharesText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    HStack {
                        Text("Price (\(targetCurrency))")
                        Spacer()
                        TextField("0.00", text: $priceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }

                    if let livePrice = convertedLiveQuotePrice {
                        HStack {
                            Text("Live Market Price")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("Use \(StockQuote.formatAmount(livePrice, currency: targetCurrency))") {
                                priceText = String(format: "%.2f", livePrice)
                            }
                            .font(.caption.bold())
                        }
                    }

                    DatePicker("Trade Date", selection: $date, displayedComponents: .date)
                }

                Section("Summary") {
                    HStack {
                        Text("Total Amount")
                            .fontWeight(.medium)
                        Spacer()
                        Text(StockQuote.formatAmount(calculatedTotal, currency: targetCurrency))
                            .font(.headline)
                            .foregroundColor(type == .buy ? .primary : .green)
                    }
                }

                Section("Notes (Optional)") {
                    TextField("Broker notes, commission, strategy...", text: $notes)
                }

                if let err = errorMessage {
                    Section {
                        Text(err)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(existingTransaction == nil ? "Add Holding / Trade" : "Edit Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTransaction()
                    }
                    .disabled(symbol.trimmingCharacters(in: .whitespaces).isEmpty || (Double(sharesText) ?? 0) <= 0)
                }
            }
        }
    }

    private func saveTransaction() {
        let sym = symbol.uppercased().trimmingCharacters(in: .whitespaces)
        guard !sym.isEmpty else {
            errorMessage = "Please enter a valid stock symbol."
            return
        }
        guard let shares = Double(sharesText), shares > 0 else {
            errorMessage = "Please enter a valid number of shares."
            return
        }
        guard let price = Double(priceText), price >= 0 else {
            errorMessage = "Please enter a valid price per share."
            return
        }

        let tx = Transaction(
            id: existingTransaction?.id ?? UUID(),
            portfolioId: targetPortfolio?.id,
            symbol: sym,
            companyName: existingTransaction?.companyName ?? store.quotes[sym]?.companyName ?? "",
            type: type,
            shares: shares,
            pricePerShare: price,
            date: date,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        if existingTransaction != nil {
            store.updateTransaction(tx)
        } else {
            store.addTransaction(tx)
        }
        dismiss()
    }
}
