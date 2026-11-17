import SwiftUI

public struct SymbolSearchView: View {
    @Environment(\.dismiss) private var dismiss
    public let store: FinanceStore

    @State private var targetPortfolioId: UUID?
    @State private var searchText: String = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedQuoteForDetail: StockQuote?
    @State private var tradePrefill: TradePrefill?

    private struct TradePrefill: Identifiable {
        let id = UUID()
        let symbol: String
        let price: Double?
    }

    public init(store: FinanceStore, targetPortfolioId: UUID? = nil) {
        self.store = store
        _targetPortfolioId = State(initialValue: targetPortfolioId ?? store.currentPortfolio?.id)
    }

    private var activePortfolio: Portfolio? {
        store.portfolio(for: targetPortfolioId) ?? store.currentPortfolio
    }

    public var body: some View {
        NavigationStack {
            List {
                if !store.portfolios.isEmpty {
                    Section {
                        Picker("Target Portfolio", selection: Binding(
                            get: { activePortfolio?.id ?? store.portfolios[0].id },
                            set: { targetPortfolioId = $0 }
                        )) {
                            ForEach(store.portfolios) { portfolio in
                                Text("\(portfolio.name) (\(portfolio.currency))").tag(portfolio.id)
                            }
                        }
                    }
                }

                if store.isSearching {
                    HStack {
                        Spacer()
                        ProgressView("Searching market tickers...")
                            .padding()
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                } else if !store.searchResults.isEmpty {
                    Section("Search Results") {
                        ForEach(store.searchResults) { quote in
                            tickerRow(
                                symbol: quote.symbol,
                                subtitle: quote.companyName,
                                onTapRow: {
                                    selectedQuoteForDetail = quote
                                },
                                onAddHolding: {
                                    tradePrefill = TradePrefill(symbol: quote.symbol, price: quote.regularMarketPrice > 0 ? quote.regularMarketPrice : nil)
                                }
                            )
                        }
                    }
                } else if searchText.isEmpty {
                    Section("Popular Global & Indian Tickers") {
                        ForEach(["AAPL", "NVDA", "MSFT", "TCS.NS", "INFY.NS", "HDFCBANK.NS", "ITC.NS", "RELIANCE.NS", "SPY", "BTC-USD"], id: \.self) { sym in
                            tickerRow(
                                symbol: sym,
                                subtitle: store.quotes[sym]?.companyName ?? "",
                                onTapRow: {
                                    Task {
                                        let q = await YahooFinanceService.shared.fetchQuote(symbol: sym)
                                        selectedQuoteForDetail = q
                                    }
                                },
                                onAddHolding: {
                                    Task {
                                        let q = await YahooFinanceService.shared.fetchQuote(symbol: sym)
                                        tradePrefill = TradePrefill(symbol: sym, price: q.regularMarketPrice > 0 ? q.regularMarketPrice : nil)
                                    }
                                }
                            )
                        }
                    }
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .searchable(text: $searchText, prompt: "Search ticker (e.g. AAPL, TCS.NS, INFY.NS)")
            .onChange(of: searchText) { _, newValue in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    if !Task.isCancelled {
                        await store.search(query: newValue)
                    }
                }
            }
            .navigationTitle("Add Ticker to Portfolio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $selectedQuoteForDetail) { quote in
                StockDetailView(quote: quote, store: store, portfolioId: activePortfolio?.id)
            }
            .sheet(item: $tradePrefill) { item in
                AddTransactionView(
                    prefilledSymbol: item.symbol,
                    prefilledPrice: item.price,
                    prefilledPortfolioId: activePortfolio?.id,
                    store: store
                )
            }
        }
    }

    @ViewBuilder
    private func tickerRow(
        symbol: String,
        subtitle: String,
        onTapRow: @escaping () -> Void,
        onAddHolding: @escaping () -> Void
    ) -> some View {
        let alreadyAdded = store.isSymbolInPortfolio(symbol, portfolioId: activePortfolio?.id)

        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(symbol)
                    .font(.headline)
                    .foregroundColor(.primary)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button(action: {
                store.addTickerToPortfolio(symbol, portfolioId: activePortfolio?.id)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: alreadyAdded ? "checkmark" : "plus")
                    Text(alreadyAdded ? "Added" : "Ticker")
                }
                .font(.caption.bold())
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background((alreadyAdded ? Color.green : Color.blue).opacity(0.14))
                .foregroundColor(alreadyAdded ? .green : .blue)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            Button(action: onAddHolding) {
                HStack(spacing: 4) {
                    Image(systemName: "briefcase.fill")
                    Text("Buy")
                }
                .font(.caption.bold())
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTapRow)
    }
}
