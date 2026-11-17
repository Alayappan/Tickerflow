import Foundation

public final class PersistenceService: @unchecked Sendable {
    public static let shared = PersistenceService()

    private let fileManager = FileManager.default
    private let writeQueue = DispatchQueue(label: "com.tickerflow.persistence.write", qos: .utility)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    private var directoryURL: URL {
        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return appSupport
        }
        if let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            return docs
        }
        return fileManager.temporaryDirectory
    }

    private func fileURL(for name: String) -> URL {
        let dir = directoryURL.appendingPathComponent("TickerFlowData", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent(name)
    }

    public func saveWatchlists(_ watchlists: [Watchlist], forProfile email: String) {
        let safeName = sanitizeFilename("watchlists_\(email).json")
        save(watchlists, to: fileURL(for: safeName))
    }

    public func loadWatchlists(forProfile email: String) -> [Watchlist]? {
        let safeName = sanitizeFilename("watchlists_\(email).json")
        return load(from: fileURL(for: safeName))
    }

    public func savePortfolios(_ portfolios: [Portfolio], forProfile email: String) {
        let safeName = sanitizeFilename("portfolios_\(email).json")
        save(portfolios, to: fileURL(for: safeName))
    }

    public func loadPortfolios(forProfile email: String) -> [Portfolio]? {
        let safeName = sanitizeFilename("portfolios_\(email).json")
        return load(from: fileURL(for: safeName))
    }

    public func saveOverallCurrency(_ currency: String, forProfile email: String) {
        let safeName = sanitizeFilename("overall_currency_\(email).json")
        save(currency, to: fileURL(for: safeName))
    }

    public func loadOverallCurrency(forProfile email: String) -> String? {
        let safeName = sanitizeFilename("overall_currency_\(email).json")
        return load(from: fileURL(for: safeName))
    }

    public func saveTransactions(_ transactions: [Transaction], forProfile email: String) {
        let safeName = sanitizeFilename("transactions_\(email).json")
        save(transactions, to: fileURL(for: safeName))
    }

    public func loadTransactions(forProfile email: String) -> [Transaction]? {
        let safeName = sanitizeFilename("transactions_\(email).json")
        return load(from: fileURL(for: safeName))
    }

    public func saveProfile(_ profile: UserProfile) {
        save(profile, to: fileURL(for: "active_profile.json"))
    }

    public func loadProfile() -> UserProfile? {
        return load(from: fileURL(for: "active_profile.json"))
    }

    private func save<T: Encodable & Sendable>(_ object: T, to url: URL) {
        writeQueue.async { [encoder] in
            do {
                let data = try encoder.encode(object)
                try data.write(to: url, options: [.atomic])
            } catch {
                print("Failed to save to \(url): \(error)")
            }
        }
    }

    private func load<T: Decodable>(from url: URL) -> T? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(T.self, from: data)
        } catch {
            print("Failed to decode from \(url): \(error)")
            return nil
        }
    }

    private func sanitizeFilename(_ name: String) -> String {
        name.replacingOccurrences(of: "@", with: "_at_")
            .replacingOccurrences(of: ".", with: "_")
    }
}
