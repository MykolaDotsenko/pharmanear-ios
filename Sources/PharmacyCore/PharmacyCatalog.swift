import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum PharmacyCatalog {
    private struct Metadata: Decodable {
        let schema: Int
        let region: String
        let license: String
        let sourceDate: String
    }

    private static let day: TimeInterval = 86_400
    private static let refreshURL = URL(string: "https://pharmanear-web.vercel.app/data/current-finland-pharmacies.json")!

    public static func bundledData() throws -> Data {
        guard let url = Bundle.module.url(forResource: "finland-pharmacies", withExtension: "json") else {
            throw SearchError.invalidResponse
        }
        return try Data(contentsOf: url)
    }

    private static func metadata(_ data: Data) throws -> (Metadata, Date) {
        let meta = try JSONDecoder().decode(Metadata.self, from: data)
        guard meta.schema == 1, meta.region == "FI", meta.license == "ODbL-1.0",
              let date = ISO8601DateFormatter().date(from: meta.sourceDate) else {
            throw SearchError.invalidResponse
        }
        return (meta, date)
    }

    public static func search(_ data: Data, origin: Point, now: Date = Date()) throws -> SearchResult {
        let (meta, date) = try metadata(data)
        let age = now.timeIntervalSince(date)
        guard age >= -day, age <= 30 * day, origin.valid else {
            throw SearchError.invalidResponse
        }
        let pharmacies = try PharmacySearch.normalize(data, origin: origin).filter { $0.distance <= 30_000 }
        return SearchResult(pharmacies: pharmacies, radius: 30_000, covered: false, sourceDate: meta.sourceDate)
    }

    private static func refresh() async throws -> Data {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 4
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(from: refreshURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw SearchError.invalidResponse
        }
        return data
    }

    /// Search a bundled snapshot first. A refresh sends no origin coordinates.
    public static func lookup(origin: Point) async throws -> SearchResult {
        try Task.checkCancellation()
        if origin.valid, (59...71).contains(origin.lat), (19...33).contains(origin.lon) {
            let now = Date()
            var data = try? bundledData()
            let bundledDate = data.flatMap { try? metadata($0).1 }
            if bundledDate == nil || now.timeIntervalSince(bundledDate!) > 7 * day {
                if let latest = try? await refresh(),
                   let latestDate = try? metadata(latest).1,
                   (bundledDate == nil || latestDate > bundledDate!),
                   (try? search(latest, origin: origin, now: now)) != nil {
                    data = latest
                }
            }
            try Task.checkCancellation()
            if let data, let result = try? search(data, origin: origin, now: now), !result.pharmacies.isEmpty {
                return result
            }
        }
        return try await PharmacySearch.search(origin: origin, fetch: { try await OverpassClient.shared.fetch(query: $0) })
    }
}
