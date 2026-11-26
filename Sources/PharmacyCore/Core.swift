import Foundation

public struct Point: Equatable, Sendable, Codable {
    public let lat: Double
    public let lon: Double

    public init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }

    public var valid: Bool {
        lat.isFinite && lon.isFinite && abs(lat) <= 90 && abs(lon) <= 180
    }

    public var approximate: Point {
        Point(lat: (lat * 100).rounded() / 100, lon: (lon * 100).rounded() / 100)
    }

    public func distance(to other: Point) -> Double {
        let radians = Double.pi / 180
        let latitude = (other.lat - lat) * radians
        let longitude = (other.lon - lon) * radians
        let haversine = pow(sin(latitude / 2), 2)
            + cos(lat * radians) * cos(other.lat * radians) * pow(sin(longitude / 2), 2)
        return 2 * 6_371_008.8 * asin(sqrt(max(0, min(1, haversine))))
    }
}

public struct Pharmacy: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let address: String
    public let point: Point
    public let distance: Double
    public let hours: String

    public init(id: String, name: String, address: String, point: Point, distance: Double, hours: String = "") {
        self.id = id
        self.name = name
        self.address = address
        self.point = point
        self.distance = distance
        self.hours = hours
    }
}

public struct SearchResult: Sendable {
    public let pharmacies: [Pharmacy]
    public let radius: Int
    public let covered: Bool

    public var visiblePharmacies: [Pharmacy] { Array(pharmacies.prefix(20)) }
}

public enum SearchError: Error, Equatable {
    case invalidLocation
    case invalidResponse
}

/// The search domain has no dependencies on SwiftUI or URLSession.
public enum PharmacySearch {
    public static let radii = [3_000, 10_000, 30_000]
    public static let cities: [(String, Point)] = [
        ("Turku", Point(lat: 60.4518, lon: 22.2666)),
        ("Helsinki", Point(lat: 60.1699, lon: 24.9384)),
        ("Tampere", Point(lat: 61.4978, lon: 23.7610)),
        ("Oulu", Point(lat: 65.0121, lon: 25.4651)),
        ("Vaasa", Point(lat: 63.0951, lon: 21.6165))
    ]

    public static func query(center: Point, radius: Int) throws -> String {
        guard center.valid, radii.contains(radius) else {
            throw SearchError.invalidLocation
        }
        return "[out:json][timeout:15];nwr[\"amenity\"=\"pharmacy\"](around:\(radius),\(center.lat),\(center.lon));out center;"
    }

    private struct Payload: Decodable {
        let elements: [DecodedElement]
        let remark: String?
    }

    private struct DecodedElement: Decodable {
        let value: Element?

        init(from decoder: Decoder) {
            value = try? Element(from: decoder)
        }
    }

    private struct Element: Decodable {
        let type: String
        let id: Int64
        let lat: Double?
        let lon: Double?
        let center: Point?
        let tags: [String: String]?
    }

    private static func decode(_ data: Data) throws -> Payload {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.remark == nil else { throw SearchError.invalidResponse }
        return payload
    }

    static func validatePayload(_ data: Data) throws {
        _ = try decode(data)
    }

    private static func pharmacy(from element: Element, origin: Point) -> Pharmacy? {
        guard ["node", "way", "relation"].contains(element.type),
              let latitude = element.lat ?? element.center?.lat,
              let longitude = element.lon ?? element.center?.lon,
              let tags = element.tags,
              tags["amenity"] == "pharmacy" else {
            return nil
        }
        let point = Point(lat: latitude, lon: longitude)
        guard point.valid else { return nil }

        return Pharmacy(
            id: "\(element.type)/\(element.id)",
            name: tags["name"] ?? "",
            address: ["addr:street", "addr:housenumber", "addr:city"]
                .compactMap { tags[$0] }.joined(separator: " "),
            point: point,
            distance: origin.distance(to: point),
            hours: String((tags["opening_hours"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
        )
    }

    public static func normalize(_ data: Data, origin: Point) throws -> [Pharmacy] {
        guard origin.valid else { throw SearchError.invalidLocation }
        let payload = try decode(data)
        var seen = Set<String>()
        var pharmacies: [Pharmacy] = []

        for item in payload.elements {
            guard let element = item.value,
                  let pharmacy = pharmacy(from: element, origin: origin),
                  seen.insert(pharmacy.id).inserted else { continue }
            pharmacies.append(pharmacy)
        }
        return pharmacies.sorted {
            $0.distance == $1.distance ? $0.id < $1.id : $0.distance < $1.distance
        }
    }

    public static func search(
        origin: Point,
        fetch: @Sendable (String) async throws -> Data
    ) async throws -> SearchResult {
        guard origin.valid else { throw SearchError.invalidLocation }
        let center = origin.approximate
        let roundingOffset = origin.distance(to: center)
        var pharmacies: [Pharmacy] = []

        for radius in radii {
            try Task.checkCancellation()
            let data = try await fetch(query(center: center, radius: radius))
            try Task.checkCancellation()
            pharmacies = try normalize(data, origin: origin)

            // Only a mapped result strictly inside the rounded area proves coverage.
            if let nearest = pharmacies.first,
               nearest.distance + roundingOffset < Double(radius) {
                return SearchResult(pharmacies: pharmacies, radius: radius, covered: true)
            }
        }

        return SearchResult(pharmacies: pharmacies, radius: 30_000, covered: false)
    }
}
