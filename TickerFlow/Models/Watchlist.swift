import Foundation

nonisolated public struct Watchlist: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var symbols: [String]
    public let createdAt: Date

    public init(id: UUID = UUID(), name: String, symbols: [String] = [], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.symbols = symbols
        self.createdAt = createdAt
    }
}
