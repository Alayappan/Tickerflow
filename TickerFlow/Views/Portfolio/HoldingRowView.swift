import SwiftUI

public struct HoldingRowView: View {
    public let holding: Holding
    public var portfolioTotalValue: Double

    public init(holding: Holding, portfolioTotalValue: Double = 0) {
        self.holding = holding
        self.portfolioTotalValue = portfolioTotalValue
    }

    private var isGain: Bool {
        holding.totalGainLoss >= 0
    }

    private var isDayGain: Bool {
        holding.dayGainLoss >= 0
    }

    private var weightPercent: Double {
        guard portfolioTotalValue > 0 else { return 0 }
        return (holding.currentValue / portfolioTotalValue) * 100
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Left: Symbol, Weight Badge, Shares & Avg Cost
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(holding.symbol)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    if weightPercent > 0 {
                        Text(String(format: "%.1f%%", weightPercent))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(Capsule())
                    }
                }

                if !holding.companyName.isEmpty {
                    Text(holding.companyName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text("\(formatShares(holding.totalShares)) sh @ \(StockQuote.formatAmount(holding.avgCostPerShare, currency: holding.currency))")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.5))

                    Text(String(format: "Day %@%.2f%%", isDayGain ? "+" : "", holding.dayGainLossPercent))
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(isDayGain ? .green : .red)
                }
            }

            Spacer()

            // Right: Value & Total Return
            VStack(alignment: .trailing, spacing: 3) {
                Text(StockQuote.formatAmount(holding.currentValue, currency: holding.currency))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                HStack(spacing: 3) {
                    Image(systemName: isGain ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))

                    Text("\(StockQuote.formatSignedAmount(holding.totalGainLoss, currency: holding.currency)) (\(String(format: "%@%.2f%%", isGain ? "+" : "", holding.totalGainLossPercent)))")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(isGain ? Color.green : Color.red)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func formatShares(_ shares: Double) -> String {
        if shares.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", shares)
        }
        return String(format: "%.2f", shares)
    }
}
