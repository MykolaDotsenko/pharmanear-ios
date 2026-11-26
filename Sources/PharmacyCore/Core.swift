import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct Point: Equatable, Sendable, Codable {
    public let lat: Double
    public let lon: Double
    public init(lat: Double, lon: Double) { self.lat = lat; self.lon = lon }
    public var valid: Bool { lat.isFinite && lon.isFinite && abs(lat) <= 90 && abs(lon) <= 180 }
    public var approximate: Point { .init(lat: (lat * 100).rounded() / 100, lon: (lon * 100).rounded() / 100) }
    public func distance(to other: Point) -> Double {
        let rad = Double.pi / 180
        let a = sin((other.lat-lat)*rad/2) * sin((other.lat-lat)*rad/2) + cos(lat*rad)*cos(other.lat*rad)*sin((other.lon-lon)*rad/2)*sin((other.lon-lon)*rad/2)
        return 6_371_008.8 * 2 * asin(sqrt(max(0, min(1, a))))
    }
}
public struct Pharmacy: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let address: String
    public let point: Point
    public let distance: Double
}
public struct SearchResult: Sendable {
    public let pharmacies: [Pharmacy]
    public let radius: Int
    public let covered: Bool
}
public enum SearchError: Error { case invalidLocation, invalidResponse }
public enum PharmacySearch {
    public static let radii = [3000, 10000, 30000]
    public static let cities: [(String, Point)] = [("Turku", .init(lat:60.4518,lon:22.2666)), ("Helsinki", .init(lat:60.1699,lon:24.9384)), ("Tampere", .init(lat:61.4978,lon:23.7610)), ("Oulu", .init(lat:65.0121,lon:25.4651)), ("Vaasa", .init(lat:63.0951,lon:21.6165))]
    public static func query(center: Point, radius: Int) throws -> String {
        guard center.valid, radii.contains(radius) else { throw SearchError.invalidLocation }
        return "[out:json][timeout:15];nwr[\"amenity\"=\"pharmacy\"](around:\(radius),\(center.lat),\(center.lon));out center;"
    }
    private struct Payload: Decodable { let elements: [Element]; let remark: String? }
    private struct Element: Decodable { let type: String; let id: Int64; let lat: Double?; let lon: Double?; let center: Point?; let tags: [String:String]? }
    public static func normalize(_ data: Data, origin: Point) throws -> [Pharmacy] {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.remark == nil else { throw SearchError.invalidResponse }
        var seen = Set<String>()
        return payload.elements.compactMap { e -> Pharmacy? in
            guard ["node","way","relation"].contains(e.type), let lat = e.lat ?? e.center?.lat, let lon = e.lon ?? e.center?.lon, let tags = e.tags, tags["amenity"] == "pharmacy" else { return nil }
            let point = Point(lat:lat,lon:lon), id = "\(e.type)/\(e.id)"
            guard point.valid, seen.insert(id).inserted else { return nil }
            return .init(id:id,name:tags["name"] ?? "",address:["addr:street","addr:housenumber","addr:city"].compactMap{tags[$0]}.joined(separator:" "),point:point,distance:origin.distance(to:point))
        }.sorted { $0.distance == $1.distance ? $0.id < $1.id : $0.distance < $1.distance }
    }
    public static func search(origin: Point, fetch: @Sendable (String) async throws -> Data) async throws -> SearchResult {
        guard origin.valid else { throw SearchError.invalidLocation }
        let center = origin.approximate, offset = origin.distance(to:center)
        var pharmacies = [Pharmacy]()
        for radius in radii {
            try Task.checkCancellation()
            let data = try await fetch(query(center:center,radius:radius))
            try Task.checkCancellation()
            pharmacies = try normalize(data,origin:origin)
            if let nearest = pharmacies.first, nearest.distance + offset < Double(radius) { return .init(pharmacies:pharmacies,radius:radius,covered:true) }
        }
        return .init(pharmacies:pharmacies,radius:radii.last!,covered:false)
    }
    public static func fetch(query: String) async throws -> Data {
        var request = URLRequest(url: URL(string:"https://overpass-api.de/api/interpreter")!,timeoutInterval:20)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded",forHTTPHeaderField:"Content-Type")
        let allowed = CharacterSet(charactersIn:"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        request.httpBody = Data(("data=" + (query.addingPercentEncoding(withAllowedCharacters:allowed) ?? "")).utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil; configuration.timeoutIntervalForResource = 25
        let session = URLSession(configuration:configuration)
        defer { session.finishTasksAndInvalidate() }
        let (data,response) = try await session.data(for:request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw SearchError.invalidResponse }
        return data
    }
}
