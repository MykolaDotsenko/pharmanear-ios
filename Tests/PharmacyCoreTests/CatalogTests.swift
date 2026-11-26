import Foundation
import XCTest

@testable import PharmacyCore

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

final class CatalogTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-26T00:00:00Z")!
    private let day: TimeInterval = 86_400
    private let turku = City.turku.centre

    // MARK: Bundled data

    func testBundledCatalogFindsRealPharmaciesNearEveryCity() throws {
        let snapshot = try Snapshot(data: PharmacyCatalog.bundledData())
        XCTAssertTrue(snapshot.isUsable(at: now))
        for city in City.allCases {
            let result = snapshot.search(from: city.centre)
            XCTAssertFalse(result.pharmacies.isEmpty, city.rawValue)
            XCTAssertTrue(result.covered, city.rawValue)
            XCTAssertEqual(result.sourceDate, "2026-11-24T21:21:23Z")
        }
    }

    func testTurkuNearestMappedPharmacy() throws {
        let result = try Snapshot(data: PharmacyCatalog.bundledData()).search(from: turku)
        XCTAssertEqual(result.pharmacies.first?.name, "Yliopiston Apteekki")
        XCTAssertEqual(result.pharmacies.count, 44)
        XCTAssertTrue(result.pharmacies.allSatisfy { $0.distance <= 30_000 })
    }

    func testSnapshotsOlderThanThirtyDaysAreNotUsable() throws {
        let snapshot = try Snapshot(data: PharmacyCatalog.bundledData())
        XCTAssertFalse(snapshot.isUsable(at: now.addingTimeInterval(31 * day)))
        XCTAssertFalse(snapshot.isUsable(at: snapshot.sourceDate.addingTimeInterval(-2 * day)))
    }

    func testInvalidMetadataIsRejected() {
        XCTAssertThrowsError(try Snapshot(data: catalog(date: "2026-11-25T00:00:00Z", license: "unknown")))
        XCTAssertThrowsError(try Snapshot(data: catalog(date: "not a date")))
        XCTAssertThrowsError(try Snapshot(data: catalog(date: "2026-11-25T00:00:00Z", pharmacies: 0)))
    }

    // MARK: Lookup policy

    func testFreshCatalogAnswersWithoutNetwork() async throws {
        let network = Recorder()
        let catalog = makeCatalog(bundled: catalog(date: "2026-11-25T00:00:00Z"), network: network)
        let result = try await catalog.lookup(origin: turku)
        XCTAssertEqual(result.sourceDate, "2026-11-25T00:00:00Z")
        let calls = await network.calls
        XCTAssertEqual(calls, [])
    }

    func testStaleCatalogIsRefreshedOnceAndTheNewerSnapshotIsKept() async throws {
        let network = Recorder(download: catalog(date: "2026-11-25T00:00:00Z"))
        let catalog = makeCatalog(bundled: catalog(date: "2026-11-10T00:00:00Z"), network: network)
        let first = try await catalog.lookup(origin: turku)
        let second = try await catalog.lookup(origin: City.helsinki.centre)
        XCTAssertEqual(first.sourceDate, "2026-11-25T00:00:00Z")
        XCTAssertEqual(second.sourceDate, "2026-11-25T00:00:00Z")
        let calls = await network.calls
        XCTAssertEqual(calls, ["download \(PharmacyCatalog.refreshURL.absoluteString)"])
    }

    func testRefreshRequestCarriesNoCoordinates() {
        let url = PharmacyCatalog.refreshURL
        XCTAssertNil(url.query)
        XCTAssertFalse(url.absoluteString.contains("60."))
    }

    func testFailedRefreshKeepsTheValidCatalogAndWaitsBeforeRetrying() async throws {
        let network = Recorder(download: nil)
        let catalog = makeCatalog(bundled: catalog(date: "2026-11-10T00:00:00Z"), network: network)
        let first = try await catalog.lookup(origin: turku)
        let second = try await catalog.lookup(origin: turku)
        XCTAssertEqual(first.sourceDate, "2026-11-10T00:00:00Z")
        XCTAssertEqual(second.sourceDate, "2026-11-10T00:00:00Z")
        let calls = await network.calls
        XCTAssertEqual(calls.count, 1, "A failed refresh must not delay every search")
    }

    func testOlderPublishedSnapshotIsIgnored() async throws {
        let network = Recorder(download: catalog(date: "2026-11-01T00:00:00Z"))
        let catalog = makeCatalog(bundled: catalog(date: "2026-11-10T00:00:00Z"), network: network)
        let result = try await catalog.lookup(origin: turku)
        XCTAssertEqual(result.sourceDate, "2026-11-10T00:00:00Z")
    }

    func testExpiredCatalogWithoutRefreshFallsBackToLiveSearch() async throws {
        let network = Recorder(download: nil)
        let catalog = makeCatalog(bundled: catalog(date: "2026-10-01T00:00:00Z"), network: network)
        let result = try await catalog.lookup(origin: turku)
        XCTAssertNil(result.sourceDate)
        let calls = await network.calls
        XCTAssertEqual(calls.last, "live 60.4518,22.2666")
    }

    func testAreasWithoutCataloguedPharmaciesUseLiveSearch() async throws {
        let network = Recorder()
        let catalog = makeCatalog(bundled: catalog(date: "2026-11-25T00:00:00Z"), network: network)
        _ = try await catalog.lookup(origin: Point(lat: 68.9, lon: 27.0))
        let calls = await network.calls
        XCTAssertEqual(calls, ["live 68.9,27.0"])
    }

    func testLocationsOutsideFinlandNeverLoadTheCatalog() async throws {
        let network = Recorder()
        let catalog = PharmacyCatalog(
            loadBundled: { throw SearchError.invalidResponse },
            download: { try await network.download($0) },
            live: { await network.live($0) },
            now: { [now] in now })
        _ = try await catalog.lookup(origin: Point(lat: 59.33, lon: 18.07))
        let calls = await network.calls
        XCTAssertEqual(calls, ["live 59.33,18.07"])
    }

    // MARK: Helpers

    private func makeCatalog(bundled: Data, network: Recorder) -> PharmacyCatalog {
        PharmacyCatalog(
            loadBundled: { bundled },
            download: { try await network.download($0) },
            live: { await network.live($0) },
            now: { [now] in now })
    }

    /// A small catalog with pharmacies near Turku and Helsinki.
    private func catalog(date: String, license: String = "ODbL-1.0", pharmacies: Int = 2) -> Data {
        let elements: [[String: Any]] = [
            ["type": "node", "id": 1, "lat": 60.452, "lon": 22.267, "tags": ["amenity": "pharmacy", "name": "A"]],
            ["type": "node", "id": 2, "lat": 60.170, "lon": 24.940, "tags": ["amenity": "pharmacy", "name": "B"]],
        ]
        let file: [String: Any] = [
            "schema": 1, "region": "FI", "license": license, "sourceDate": date,
            "elements": Array(elements.prefix(pharmacies)),
        ]
        return try! JSONSerialization.data(withJSONObject: file)
    }
}

/// Records network use and answers with canned data.
private actor Recorder {
    private(set) var calls: [String] = []
    private let downloadData: Data?

    init(download: Data? = nil) {
        downloadData = download
    }

    func download(_ url: URL) throws -> (Data, URLResponse) {
        calls.append("download \(url.absoluteString)")
        guard let downloadData else { throw URLError(.notConnectedToInternet) }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (downloadData, response)
    }

    func live(_ origin: Point) -> SearchResult {
        calls.append("live \(origin.lat),\(origin.lon)")
        return SearchResult(pharmacies: [], radius: 30_000, covered: false)
    }
}
