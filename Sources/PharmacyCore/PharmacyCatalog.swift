import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Finds pharmacies in a national OpenStreetMap snapshot on the device; searches live only when the
/// snapshot cannot serve the area. Coordinates never leave the device for a catalog search.
///
/// The bundled snapshot is decoded once. When it is more than a week old the catalog asks the web app
/// for a newer one, keeps it in memory for later searches, and does not ask again for an hour after a
/// failed attempt. A snapshot older than 30 days is never used.
public actor PharmacyCatalog {
    typealias Download = @Sendable (URL) async throws -> (Data, URLResponse)
    typealias LiveSearch = @Sendable (Point) async throws -> SearchResult

    public static let shared = PharmacyCatalog()

    /// Same-origin route on the web deployment that serves the newest published snapshot.
    static let refreshURL = URL(string: "https://pharmanear-web.vercel.app/data/current-finland-pharmacies.json")!
    static let searchRadius = 30_000
    static let day: TimeInterval = 86_400
    static let maximumAge = 30 * day
    static let refreshAge = 7 * day
    static let refreshRetryInterval: TimeInterval = 3_600

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 4
        return URLSession(configuration: configuration)
    }()

    private let loadBundled: @Sendable () throws -> Data
    private let download: Download
    private let live: LiveSearch
    private let now: @Sendable () -> Date

    private var snapshot: Snapshot?
    private var didLoadBundled = false
    private var lastRefreshAttempt: Date?

    init(
        loadBundled: @escaping @Sendable () throws -> Data = { try PharmacyCatalog.bundledData() },
        download: @escaping Download = { url in try await PharmacyCatalog.session.data(from: url) },
        live: @escaping LiveSearch = { origin in
            try await PharmacySearch.search(origin: origin) { try await OverpassClient.shared.fetch(query: $0) }
        },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.loadBundled = loadBundled
        self.download = download
        self.live = live
        self.now = now
    }

    public static func bundledData() throws -> Data {
        guard let url = Bundle.module.url(forResource: "finland-pharmacies", withExtension: "json") else {
            throw SearchError.invalidResponse
        }
        return try Data(contentsOf: url)
    }

    public func lookup(origin: Point) async throws -> SearchResult {
        guard origin.isValid else { throw SearchError.invalidLocation }
        try Task.checkCancellation()
        if Self.isInFinland(origin), let snapshot = await usableSnapshot() {
            let result = snapshot.search(from: origin)
            if !result.pharmacies.isEmpty { return result }
        }
        try Task.checkCancellation()
        return try await live(origin)
    }

    static func isInFinland(_ point: Point) -> Bool {
        (59...71).contains(point.lat) && (19...33).contains(point.lon)
    }

    private func usableSnapshot() async -> Snapshot? {
        if !didLoadBundled {
            didLoadBundled = true
            snapshot = try? Snapshot(data: loadBundled())
        }
        let date = now()
        let current = snapshot.flatMap { $0.isUsable(at: date) ? $0 : nil }
        guard needsRefresh(current, at: date) else { return current }

        lastRefreshAttempt = date
        let latest = await latestSnapshot()
        if Task.isCancelled {
            // A cancelled search says nothing about the network, so the next search may try again.
            if lastRefreshAttempt == date { lastRefreshAttempt = nil }
            return current
        }
        guard let latest, latest.isUsable(at: date), latest.sourceDate > (current?.sourceDate ?? .distantPast)
        else { return current }
        snapshot = latest
        return latest
    }

    private func needsRefresh(_ current: Snapshot?, at date: Date) -> Bool {
        let isStale = current.map { date.timeIntervalSince($0.sourceDate) > Self.refreshAge } ?? true
        let mayRetry = lastRefreshAttempt.map { date.timeIntervalSince($0) >= Self.refreshRetryInterval } ?? true
        return isStale && mayRetry
    }

    /// The refresh request carries no coordinates: it is the same fixed URL for everyone.
    private func latestSnapshot() async -> Snapshot? {
        guard let (data, response) = try? await download(Self.refreshURL),
            (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return try? Snapshot(data: data)
    }
}

/// A decoded, validated catalog file.
struct Snapshot: Sendable {
    let sourceDate: Date
    let sourceDateText: String
    private let pharmacies: [MappedPharmacy]

    private struct File: Decodable {
        let schema: Int
        let region: String
        let license: String
        let sourceDate: String
        let elements: [OSMElement.Lenient]
    }

    init(data: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: data)
        guard file.schema == 1, file.region == "FI", file.license == "ODbL-1.0",
            let date = ISO8601DateFormatter().date(from: file.sourceDate)
        else { throw SearchError.invalidResponse }
        let pharmacies = OSMElement.pharmacies(in: file.elements)
        guard !pharmacies.isEmpty else { throw SearchError.invalidResponse }

        sourceDate = date
        sourceDateText = file.sourceDate
        self.pharmacies = pharmacies
    }

    /// Up to a day in the future tolerates clock skew; never older than 30 days.
    func isUsable(at date: Date) -> Bool {
        let age = date.timeIntervalSince(sourceDate)
        return age >= -PharmacyCatalog.day && age <= PharmacyCatalog.maximumAge
    }

    /// Coverage is not claimed: the snapshot has no pharmacies across the border, so near it a closer one
    /// can be missing. The interface states the catalog's scope instead.
    func search(from origin: Point) -> SearchResult {
        let nearby = PharmacySearch.rank(pharmacies, from: origin)
            .filter { $0.distance <= Double(PharmacyCatalog.searchRadius) }
        return SearchResult(
            pharmacies: nearby, radius: PharmacyCatalog.searchRadius, covered: false,
            sourceDate: sourceDateText)
    }
}
