import SwiftUI

public struct ChangeBadgeView: View {
    public let text: String
    public let isPositive: Bool
    public var fontSize: CGFloat = 13
    public var horizontalPadding: CGFloat = 8
    public var verticalPadding: CGFloat = 4

    public init(text: String, isPositive: Bool, fontSize: CGFloat = 13, horizontalPadding: CGFloat = 8, verticalPadding: CGFloat = 4) {
        self.text = text
        self.isPositive = isPositive
        self.fontSize = fontSize
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
    }

    public var body: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isPositive ? Color(red: 0.05, green: 0.75, blue: 0.45) : Color(red: 0.95, green: 0.25, blue: 0.28))
            )
    }
}
