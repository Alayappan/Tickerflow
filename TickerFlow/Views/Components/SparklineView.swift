import SwiftUI

public struct SparklineView: View {
    public let data: [Double]
    public let isPositive: Bool

    public init(data: [Double], isPositive: Bool) {
        self.data = data
        self.isPositive = isPositive
    }

    private var lineColor: Color {
        isPositive ? Color.green : Color.red
    }

    public var body: some View {
        GeometryReader { geometry in
            if data.count >= 2 {
                let minVal = data.min() ?? 0
                let maxVal = data.max() ?? 1
                let range = max(maxVal - minVal, 0.0001)

                let points = data.enumerated().map { idx, val -> CGPoint in
                    let x = CGFloat(idx) / CGFloat(data.count - 1) * geometry.size.width
                    let y = (1.0 - CGFloat((val - minVal) / range)) * geometry.size.height
                    return CGPoint(x: x, y: y)
                }

                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: geometry.size.height))
                        for pt in points {
                            path.addLine(to: pt)
                        }
                        path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [lineColor.opacity(0.22), lineColor.opacity(0.01)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    Path { path in
                        for (idx, pt) in points.enumerated() {
                            if idx == 0 {
                                path.move(to: pt)
                            } else {
                                path.addLine(to: pt)
                            }
                        }
                    }
                    .stroke(lineColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 1)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
        }
    }
}
