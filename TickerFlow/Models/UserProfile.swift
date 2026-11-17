import Foundation

nonisolated public enum AccountProvider: String, Codable, CaseIterable, Sendable {
    case google = "Google Finance"
    case yahoo = "Yahoo Finance"
    case guest = "Guest"

    public var iconName: String {
        switch self {
        case .google: return "g.circle.fill"
        case .yahoo: return "y.circle.fill"
        case .guest: return "person.crop.circle"
        }
    }

    public var providerColorHex: String {
        switch self {
        case .google: return "#4285F4"
        case .yahoo: return "#6001D2"
        case .guest: return "#8E8E93"
        }
    }
}

nonisolated public struct UserProfile: Identifiable, Codable, Equatable, Sendable {
    public var id: String { email }
    public var email: String
    public var displayName: String
    public var provider: AccountProvider
    public var lastSyncTime: Date

    public init(
        email: String,
        displayName: String,
        provider: AccountProvider,
        lastSyncTime: Date = Date()
    ) {
        self.email = email
        self.displayName = displayName
        self.provider = provider
        self.lastSyncTime = lastSyncTime
    }

    public static let defaultGoogle = UserProfile(
        email: "investor@gmail.com",
        displayName: "Google Investor",
        provider: .google
    )

    public static let defaultYahoo = UserProfile(
        email: "trader@yahoo.com",
        displayName: "Yahoo Trader",
        provider: .yahoo
    )
}
