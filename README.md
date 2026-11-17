# TickerFlow

A native SwiftUI iOS portfolio tracking and analytics app with multi-portfolio, multi-currency support, live market data from Yahoo Finance, interactive charts, and CSV transaction import/export.

## Screenshots

<table>
  <tr>
    <td align="center">
      <strong>Portfolio Overview</strong><br />
      <img src="TickerFlow/screenshots/Screenshot%20iPhone%2017%2017-11-2026%20at%208.21.39%E2%80%AFAM.png" width="240" alt="Portfolio Overview" />
    </td>
    <td align="center">
      <strong>Holdings &amp; Returns</strong><br />
      <img src="TickerFlow/screenshots/Screenshot%20iPhone%2017%2017-11-2026%20at%208.22.23%E2%80%AFAM.png" width="240" alt="Holdings and Returns" />
    </td>
    <td align="center">
      <strong>P&amp;L Breakdown &amp; Performers</strong><br />
      <img src="TickerFlow/screenshots/Screenshot%20iPhone%2017%2017-11-2026%20at%208.21.44%E2%80%AFAM.png" width="240" alt="Portfolio Analytics Breakdown" />
    </td>
  </tr>
  <tr>
    <td align="center">
      <strong>Asset Allocation &amp; Return Chart</strong><br />
      <img src="TickerFlow/screenshots/Screenshot%20iPhone%2017%2017-11-2026%20at%208.21.51%E2%80%AFAM.png" width="240" alt="Asset Allocation and Return by Position" />
    </td>
    <td align="center">
      <strong>Interactive Stock Chart</strong><br />
      <img src="TickerFlow/screenshots/Screenshot%20iPhone%2017%2017-11-2026%20at%208.22.05%E2%80%AFAM.png" width="240" alt="Stock Detail Chart" />
    </td>
    <td align="center">
      <strong>Position &amp; Trade History</strong><br />
      <img src="TickerFlow/screenshots/Screenshot%20iPhone%2017%2017-11-2026%20at%208.22.13%E2%80%AFAM.png" width="240" alt="Stock Position and Trade History" />
    </td>
  </tr>
</table>

## Features

- **Multi-Portfolio & Multi-Currency Tracking**
  - Create and switch between multiple portfolios with independent base currencies (`USD`, `INR`, `EUR`, `GBP`, `JPY`, `CAD`, `AUD`, `SGD`, `HKD`, `CHF`).
  - **Overall Portfolio** rollup card converting holdings, day gains, unrealized P&L, and portfolio breakdowns into a selectable display currency using live FX rates (`=X` currency pairs).
  - Track symbols before opening a position (`Tracked Tickers`) with one-tap **Buy** prefill into the trade entry sheet.

- **Global Market Indices Ticker Strip**
  - Live scrollable header covering US (`S&P 500`, `Dow 30`, `Nasdaq`, `Russell 2000`, `VIX`), Europe (`FTSE 100`, `DAX`, `CAC 40`, `Euro Stoxx 50`), Asia (`Nikkei 225`, `NIFTY 50`, `SENSEX`, `Hang Seng`, `SSE Composite`), and Commodities/FX/Crypto (`Gold`, `Crude Oil`, `EUR/USD`, `USD/INR`, `Bitcoin`).

- **Holdings, Trades & CSV Import/Export**
  - Record **Buy** and **Sell** trades, edit existing transactions, and delete positions with automatic average-cost, realized P&L, and unrealized P&L recalculation.
  - Native file picker CSV import supporting **Yahoo Finance**, **Google Finance**, and generic finance CSV exports (`UTF-8`, `UTF-16`, `ISO-Latin-1`), plus portfolio holdings CSV export.
  - Search global equities, ETFs, indices, and NSE/BSE symbols (e.g., `AAPL`, `ITC.NS`, `TATAMOTORS.NS`).

- **Portfolio Analytics (`Analytics` Tab)**
  - **Scope Selector**: Analyze `Overall` across all portfolios or filter down to an individual portfolio.
  - **Performance & P&L Breakdown**: Invested cost, unrealized P&L, realized P&L, net total profit, and win rate.
  - **Top & Bottom Performers**: Segmented switch between all **Positive** and **Negative** performers with horizontal scrolling and rank badges.
  - **Asset Allocation**: Interactive Swift Charts donut (`SectorMark`) and position weights.
  - **Return by Position**: Scrollable and pinch/button-zoomable bar chart (`Return %` vs `Gain/Loss`) with tap-to-inspect position details.
  - **Portfolio Health & Activity**: Concentration warnings (`>35%` single-stock weight) and cumulative buy/sell trade volume.

- **Interactive Stock Detail View**
  - Interactive scrubbable price history chart across multiple timeframes (`1D`, `5D`, `1M`, `6M`, `YTD`, `1Y`, `5Y`, `MAX`).
  - Live market stats, quote breakdown, and per-symbol transaction history.

- **Local Persistence**
  - Zero third-party dependencies; portfolios, transactions, overall currency, and profile data are persisted locally as JSON in Application Support (`TickerFlowData`).

## Project Structure

```text
TickerFlow/
├── TickerFlow.xcodeproj
└── TickerFlow/
    ├── MyApp.swift
    ├── ContentView.swift
    ├── Assets.xcassets
    ├── screenshots/
    ├── Models/
    │   ├── Holding.swift               # Portfolio, Transaction, Holding, SupportedPortfolioCurrency, Analytics models
    │   ├── StockQuote.swift            # StockQuote, MarketIndex, HistoricalPricePoint, ChartTimeframe
    │   ├── UserProfile.swift           # User profile model
    │   └── Watchlist.swift             # Watchlist model
    ├── Services/
    │   ├── YahooFinanceService.swift   # Actor-based Yahoo Finance quote, search, chart, and FX fetcher
    │   ├── FinancialCSVParser.swift    # Yahoo/Google/generic CSV parser and exporter
    │   └── PersistenceService.swift    # JSON file persistence in Application Support
    ├── ViewModels/
    │   └── FinanceStore.swift          # @Observable @MainActor state store, FX math, holdings & analytics engine
    └── Views/
        ├── MainTabView.swift
        ├── Components/
        │   ├── ChangeBadgeView.swift
        │   ├── MarketIndicesHeader.swift
        │   └── SparklineView.swift
        ├── Detail/
        │   ├── InteractiveChartView.swift
        │   └── StockDetailView.swift
        ├── Portfolio/
        │   ├── PortfolioHomeView.swift
        │   ├── PortfolioAnalyticsView.swift
        │   ├── HoldingRowView.swift
        │   ├── AddTransactionView.swift
        │   └── CSVImportView.swift
        └── Watchlist/
            ├── SymbolSearchView.swift
            ├── WatchlistHomeView.swift
            └── WatchlistRowView.swift
```

## Requirements & Architecture

- **Platform**: iOS 18.5+
- **Language / Concurrency**: Swift 6 (`MainActor` default isolation, `Sendable` / `nonisolated` models, actor-isolated networking)
- **Frameworks**: `SwiftUI`, `Charts` (Swift Charts), `UniformTypeIdentifiers`, `Foundation`
- **External Dependencies**: None (pure Apple frameworks + direct Yahoo Finance `URLSession` client)

## Getting Started

1. Open `TickerFlow.xcodeproj` in Xcode.
2. Select an iOS 18.5+ Simulator or your connected iPhone target.
3. Build and run (`Cmd + R`).
4. Create a portfolio (or use the default portfolio), then tap **Add Ticker**, **Add Holding**, or **Import CSV** to start tracking positions.
