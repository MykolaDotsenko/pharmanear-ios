import Foundation

public struct Point: Equatable, Sendable, Codable {
    public let lat: Double
    public let lon: Double

    public init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }

    public var isValid: Bool {
        lat.isFinite && lon.isFinite && abs(lat) <= 90 && abs(lon) <= 180
    }

    /// Two decimals: roughly 1 km. The only precision that ever leaves the device.
    public var approximate: Point {
        Point(lat: (lat * 100).rounded() / 100, lon: (lon * 100).rounded() / 100)
    }

    /// Great-circle distance in metres (haversine, mean Earth radius).
    public func distance(to other: Point) -> Double {
        let radians = Double.pi / 180
        let latitude = (other.lat - lat) * radians
        let longitude = (other.lon - lon) * radians
        let haversine =
            pow(sin(latitude / 2), 2)
            + cos(lat * radians) * cos(other.lat * radians) * pow(sin(longitude / 2), 2)
        return 2 * 6_371_008.8 * asin(sqrt(max(0, min(1, haversine))))
    }
}

/// The five city centres a search can start from when location is unavailable.
public enum City: String, CaseIterable, Identifiable, Sendable {
    case turku = "Turku"
    case helsinki = "Helsinki"
    case tampere = "Tampere"
    case oulu = "Oulu"
    case vaasa = "Vaasa"

    public var id: Self { self }

    public var centre: Point {
        switch self {
        case .turku: Point(lat: 60.4518, lon: 22.2666)
        case .helsinki: Point(lat: 60.1699, lon: 24.9384)
        case .tampere: Point(lat: 61.4978, lon: 23.7610)
        case .oulu: Point(lat: 65.0121, lon: 25.4651)
        case .vaasa: Point(lat: 63.0951, lon: 21.6165)
        }
    }
}

/// A pharmacy as mapped in OpenStreetMap, before a search gives it a distance.
struct MappedPharmacy: Equatable, Sendable {
    let id: String
    let name: String
    let address: String
    let point: Point
    let hours: String

    func ranked(from origin: Point) -> Pharmacy {
        Pharmacy(
            id: id, name: name, address: address, point: point,
            distance: origin.distance(to: point), hours: hours)
    }
}

public struct Pharmacy: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let address: String
    public let point: Point
    /// Straight-line distance from the search origin, in metres.
    public let distance: Double
    /// The OSM `opening_hours` value as mapped; unverified.
    public let hours: String

    public init(
        id: String, name: String, address: String, point: Point, distance: Double, hours: String = ""
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.point = point
        self.distance = distance
        self.hours = hours
    }
}

public struct SearchResult: Equatable, Sendable {
    public static let visibleLimit = 20

    public let pharmacies: [Pharmacy]
    public let radius: Int
    /// True when the first result is proven to be the nearest mapped pharmacy.
    public let covered: Bool
    /// The catalog's OpenStreetMap extract date, or nil for a live search.
    public let sourceDate: String?

    public init(pharmacies: [Pharmacy], radius: Int, covered: Bool, sourceDate: String? = nil) {
        self.pharmacies = pharmacies
        self.radius = radius
        self.covered = covered
        self.sourceDate = sourceDate
    }

    public var visiblePharmacies: [Pharmacy] { Array(pharmacies.prefix(Self.visibleLimit)) }
}

public enum SearchError: Error, Equatable {
    case invalidLocation
    case invalidResponse
}

/// OpenStreetMap elements as Overpass and the catalog encode them.
enum OSMElement {
    /// Decodes one element without failing the whole payload when it is malformed.
    struct Lenient: Decodable {
        let element: Element?

        init(from decoder: Decoder) {
            element = try? Element(from: decoder)
        }
    }

    struct Element: Decodable {
        let type: String
        let id: Int64
        let lat: Double?
        let lon: Double?
        let center: Point?
        let tags: [String: String]?
    }

    /// Valid pharmacies only, first occurrence of each OSM object.
    static func pharmacies(in elements: [Lenient]) -> [MappedPharmacy] {
        var seen = Set<String>()
        return elements.compactMap { item in
            guard let pharmacy = item.element.flatMap(pharmacy(from:)),
                seen.insert(pharmacy.id).inserted
            else { return nil }
            return pharmacy
        }
    }

    private static func pharmacy(from element: Element) -> MappedPharmacy? {
        guard ["node", "way", "relation"].contains(element.type),
            let latitude = element.lat ?? element.center?.lat,
            let longitude = element.lon ?? element.center?.lon,
            let tags = element.tags,
            tags["amenity"] == "pharmacy"
        else { return nil }

        let point = Point(lat: latitude, lon: longitude)
        guard point.isValid else { return nil }

        return MappedPharmacy(
            id: "\(element.type)/\(element.id)",
            name: tags["name"] ?? "",
            address: ["addr:street", "addr:housenumber", "addr:city"]
                .compactMap { tags[$0] }
                .joined(separator: " "),
            point: point,
            hours: String(
                (tags["opening_hours"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
        )
    }
}

/// Live search rules. No dependency on SwiftUI, CoreLocation or URLSession.
public enum PharmacySearch {
    public static let radii = [3_000, 10_000, 30_000]

    public static func query(center: Point, radius: Int) throws -> String {
        guard center.isValid, radii.contains(radius) else { throw SearchError.invalidLocation }
        return
            "[out:json][timeout:15];nwr[\"amenity\"=\"pharmacy\"](around:\(radius),\(center.lat),\(center.lon));out center;"
    }

    private struct Payload: Decodable {
        let elements: [OSMElement.Lenient]
        let remark: String?
    }

    /// Overpass reports a timeout or memory limit in `remark`; such a payload is incomplete.
    private static func decode(_ data: Data) throws -> Payload {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.remark == nil else { throw SearchError.invalidResponse }
        return payload
    }

    static func validatePayload(_ data: Data) throws {
        _ = try decode(data)
    }

    /// Nearest first; equal distances in a stable identifier order.
    static func rank(_ pharmacies: [MappedPharmacy], from origin: Point) -> [Pharmacy] {
        pharmacies.map { $0.ranked(from: origin) }.sorted {
            $0.distance == $1.distance ? $0.id < $1.id : $0.distance < $1.distance
        }
    }

    public static func normalize(_ data: Data, origin: Point) throws -> [Pharmacy] {
        guard origin.isValid else { throw SearchError.invalidLocation }
        return rank(OSMElement.pharmacies(in: try decode(data).elements), from: origin)
    }

    /// Queries a rounded centre at widening radii until the nearest result is proven.
    public static func search(
        origin: Point,
        fetch: @Sendable (String) async throws -> Data
    ) async throws -> SearchResult {
        guard origin.isValid else { throw SearchError.invalidLocation }
        let center = origin.approximate
        let roundingOffset = origin.distance(to: center)
        var pharmacies: [Pharmacy] = []

        for radius in radii {
            try Task.checkCancellation()
            let data = try await fetch(query(center: center, radius: radius))
            try Task.checkCancellation()
            pharmacies = try normalize(data, origin: origin)

            // Only a mapped result strictly inside the rounded area proves coverage.
            if let nearest = pharmacies.first, nearest.distance + roundingOffset < Double(radius) {
                return SearchResult(pharmacies: pharmacies, radius: radius, covered: true)
            }
        }
        return SearchResult(pharmacies: pharmacies, radius: radii.last ?? 30_000, covered: false)
    }
}
