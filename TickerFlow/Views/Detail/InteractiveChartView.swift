import SwiftUI
import Charts

public struct InteractiveChartView: View {
    public let data: [HistoricalPricePoint]
    public let timeframe: ChartTimeframe
    public let isPositive: Bool
    public var onScrub: ((HistoricalPricePoint?) -> Void)?

    @State private var selectedPoint: HistoricalPricePoint?

    public init(
        data: [HistoricalPricePoint],
        timeframe: ChartTimeframe,
        isPositive: Bool,
        onScrub: ((HistoricalPricePoint?) -> Void)? = nil
    ) {
        self.data = data
        self.timeframe = timeframe
        self.isPositive = isPositive
        self.onScrub = onScrub
    }

    private var themeColor: Color {
        isPositive ? Color(red: 0.05, green: 0.75, blue: 0.45) : Color(red: 0.95, green: 0.25, blue: 0.28)
    }

    private var minPrice: Double {
        (data.map { $0.price }.min() ?? 0) * 0.995
    }

    private var maxPrice: Double {
        (data.map { $0.price }.max() ?? 100) * 1.005
    }

    public var body: some View {
        VStack(spacing: 8) {
            Chart {
                ForEach(data) { pt in
                    AreaMark(
                        x: .value("Date", pt.date),
                        yStart: .value("Min", minPrice),
                        yEnd: .value("Price", pt.price)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [themeColor.opacity(0.35), themeColor.opacity(0.01)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Date", pt.date),
                        y: .value("Price", pt.price)
                    )
                    .foregroundStyle(themeColor)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }

                if let selected = selectedPoint {
                    RuleMark(x: .value("Selected Date", selected.date))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .foregroundStyle(Color.secondary)

                    PointMark(
                        x: .value("Selected Date", selected.date),
                        y: .value("Selected Price", selected.price)
                    )
                    .symbolSize(70)
                    .foregroundStyle(themeColor)
                }
            }
            .chartYScale(domain: minPrice...maxPrice)
            .chartYAxis(.hidden)
            .chartXAxis(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let originX = value.location.x
                                    guard originX >= 0 && originX <= geometry.size.width else { return }
                                    if let date: Date = proxy.value(atX: originX) {
                                        // Find nearest point
                                        let nearest = data.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
                                        selectedPoint = nearest
                                        onScrub?(nearest)
                                    }
                                }
                                .onEnded { _ in
                                    selectedPoint = nil
                                    onScrub?(nil)
                                }
                        )
                }
            }
        }
    }
}
