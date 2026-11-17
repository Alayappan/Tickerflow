import SwiftUI

public struct WatchlistRowView: View {
    public let quote: StockQuote

    public init(quote: StockQuote) {
        self.quote = quote
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Left: Symbol & Name
            VStack(alignment: .leading, spacing: 3) {
                Text(quote.symbol)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text(quote.companyName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 95, alignment: .leading)

            // Middle: Sparkline
            SparklineView(data: quote.sparklinePrices, isPositive: quote.isPositive)
                .frame(height: 30)
                .padding(.horizontal, 6)

            // Right: Price & Change Pill
            VStack(alignment: .trailing, spacing: 4) {
                Text(quote.formattedPrice)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                ChangeBadgeView(
                    text: quote.formattedChangePercent,
                    isPositive: quote.isPositive,
                    fontSize: 12,
                    horizontalPadding: 6,
                    verticalPadding: 3
                )
            }
            .frame(width: 85, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
