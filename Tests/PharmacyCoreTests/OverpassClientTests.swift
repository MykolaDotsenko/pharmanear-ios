import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import PharmacyCore

private actor StubTransport {
    var statuses: [Int]
    private(set) var hosts: [String] = []

    init(statuses: [Int]) {
        self.statuses = statuses
    }

    func send(_ request: URLRequest) throws -> (Data, URLResponse) {
        guard let url = request.url, let host = url.host,
              !statuses.isEmpty else { throw URLError(.badURL) }
        hosts.append(host)
        let status = statuses.removeFirst()
        let response = HTTPURLResponse(url: url, statusCode: status,
                                      httpVersion: "HTTP/1.1", headerFields: nil)!
        return (Data(#"{"elements":[]}"#.utf8), response)
    }
}

final class OverpassClientTests: XCTestCase {
    func testTemporaryFailureUsesIndependentProviderOnce() async throws {
        let stub = StubTransport(statuses: [503, 200])
        let client = OverpassClient { try await stub.send($0) }
        _ = try await client.fetch(query: "test")
        let hosts = await stub.hosts
        XCTAssertEqual(hosts, ["overpass-api.de", "overpass.private.coffee"])
    }

    func testRateLimitDoesNotTriggerFallback() async {
        let stub = StubTransport(statuses: [429])
        let client = OverpassClient { try await stub.send($0) }
        do {
            _ = try await client.fetch(query: "test")
            XCTFail("Expected HTTP failure")
        } catch {}
        let hosts = await stub.hosts
        XCTAssertEqual(hosts, ["overpass-api.de"])
    }

    func testValidEmptyResponseDoesNotTriggerFallback() async throws {
        let stub = StubTransport(statuses: [200])
        let client = OverpassClient { try await stub.send($0) }
        _ = try await client.fetch(query: "test")
        let hosts = await stub.hosts
        XCTAssertEqual(hosts.count, 1)
    }

    func testMalformedElementDoesNotDiscardValidPharmacy() throws {
        let payload = Data(#"{"elements":[null,{"type":"node","id":1,"lat":60.45,"lon":22.27,"tags":{"amenity":"pharmacy"}}]}"#.utf8)
        let rows = try PharmacySearch.normalize(payload, origin: Point(lat: 60.45, lon: 22.27))
        XCTAssertEqual(rows.map(\.id), ["node/1"])
    }
}
