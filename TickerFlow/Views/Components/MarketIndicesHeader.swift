import SwiftUI

public struct MarketIndicesHeader: View {
    public let indices: [MarketIndex]
    @Binding public var selectedRegion: MarketRegion
    public var onSelectIndex: ((MarketIndex) -> Void)?

    public init(
        indices: [MarketIndex],
        selectedRegion: Binding<MarketRegion>,
        onSelectIndex: ((MarketIndex) -> Void)? = nil
    ) {
        self.indices = indices
        self._selectedRegion = selectedRegion
        self.onSelectIndex = onSelectIndex
    }

    private var filteredIndices: [MarketIndex] {
        if selectedRegion == .all {
            return indices
        }
        return indices.filter { $0.region == selectedRegion }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Multi-region market tabs (Yahoo Finance style)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(MarketRegion.allCases) { region in
                        let isSelected = selectedRegion == region
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                selectedRegion = region
                            }
                        }) {
                            Text(region.rawValue)
                                .font(.caption.weight(isSelected ? .bold : .medium))
                                .foregroundColor(isSelected ? .primary : .secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? Color(UIColor.secondarySystemGroupedBackground) : Color.clear)
                                        .overlay(
                                            Capsule()
                                                .stroke(isSelected ? Color.primary.opacity(0.12) : Color.clear, lineWidth: 1)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }

            // Market Index Cards
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(filteredIndices) { item in
                        Button(action: {
                            onSelectIndex?(item)
                        }) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Text(item.name)
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)

                                    Spacer(minLength: 2)

                                    Text(item.regionBadge)
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.primary.opacity(0.06))
                                        .clipShape(Capsule())
                                }

                                HStack(alignment: .bottom, spacing: 6) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.formattedValue)
                                            .font(.system(size: 14, weight: .bold, design: .rounded))
                                            .foregroundColor(.primary)

                                        HStack(spacing: 2) {
                                            Image(systemName: item.isPositive ? "arrow.up.right" : "arrow.down.right")
                                                .font(.system(size: 9, weight: .bold))
                                            Text(item.formattedChangePercent)
                                                .font(.caption2.weight(.semibold))
                                        }
                                        .foregroundColor(item.isPositive ? Color.green : Color.red)
                                    }

                                    Spacer(minLength: 2)

                                    if !item.sparklinePrices.isEmpty {
                                        SparklineView(data: item.sparklinePrices, isPositive: item.isPositive)
                                            .frame(width: 44, height: 22)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(width: 158, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(UIColor.secondarySystemGroupedBackground))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 6)
            }
        }
    }
}
