import Foundation
import XCTest

@testable import PharmacyCore

final class CoreTests: XCTestCase {
    private let origin = City.turku.centre

    private func payload(_ json: String) -> Data { Data(json.utf8) }

    func testDistanceMatchesKnownValues() {
        XCTAssertEqual(origin.distance(to: origin), 0)
        XCTAssertEqual(Point(lat: 0, lon: 0).distance(to: Point(lat: 1, lon: 0)), 111_195, accuracy: 1)
    }

    func testDistanceCrossesTheAntimeridian() {
        XCTAssertLessThan(Point(lat: 0, lon: 179.9).distance(to: Point(lat: 0, lon: -179.9)), 23_000)
    }

    func testQueriesUseOnlyRoundedCoordinatesAndAllowedRadii() throws {
        XCTAssertEqual(origin.approximate, Point(lat: 60.45, lon: 22.27))
        let query = try PharmacySearch.query(center: origin.approximate, radius: 3_000)
        XCTAssertTrue(query.contains("3000,60.45,22.27"))
        XCTAssertThrowsError(try PharmacySearch.query(center: origin, radius: 1))
    }

    func testNormalizeDeduplicatesFiltersInvalidPointsAndSorts() throws {
        let data = payload(
            #"""
            {"elements":[
              {"type":"node","id":1,"lat":60.48,"lon":22.3,"tags":{"amenity":"pharmacy"}},
              {"type":"way","id":2,"center":{"lat":60.452,"lon":22.267},"tags":{"amenity":"pharmacy","name":"Closest"}},
              {"type":"way","id":2,"center":{"lat":60.452,"lon":22.267},"tags":{"amenity":"pharmacy"}},
              {"type":"node","id":3,"lat":91,"lon":0,"tags":{"amenity":"pharmacy"}}
            ]}
            """#)
        XCTAssertEqual(try PharmacySearch.normalize(data, origin: origin).map(\.id), ["way/2", "node/1"])
    }

    func testPartialProviderResponseIsRejected() {
        XCTAssertThrowsError(
            try PharmacySearch.normalize(payload(#"{"elements":[],"remark":"timeout"}"#), origin: origin))
    }

    func testEmptySearchStopsAtTheLargestRadius() async throws {
        let result = try await PharmacySearch.search(origin: origin) { _ in Data(#"{"elements":[]}"#.utf8) }
        XCTAssertEqual(result.radius, 30_000)
        XCTAssertFalse(result.covered)
    }

    func testSearchStopsWhenTheNearestResultIsProven() async throws {
        let result = try await PharmacySearch.search(origin: origin) { _ in
            Data(#"{"elements":[{"type":"node","id":1,"lat":60.452,"lon":22.267,"tags":{"amenity":"pharmacy"}}]}"#.utf8)
        }
        XCTAssertEqual(result.radius, 3_000)
        XCTAssertTrue(result.covered)
        XCTAssertEqual(result.pharmacies.count, 1)
    }

    func testSearchExpandsWhenTheOnlyResultIsOutsideProvenCoverage() async throws {
        let result = try await PharmacySearch.search(origin: origin) { _ in
            Data(#"{"elements":[{"type":"node","id":1,"lat":60.48,"lon":22.27,"tags":{"amenity":"pharmacy"}}]}"#.utf8)
        }
        XCTAssertEqual(result.radius, 10_000)
        XCTAssertTrue(result.covered)
    }

    func testInvalidLocationNeverReachesTheProvider() async {
        do {
            _ = try await PharmacySearch.search(origin: Point(lat: 100, lon: 0)) { _ in
                XCTFail("Unexpected fetch")
                return Data()
            }
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? SearchError, .invalidLocation)
        }
    }

    func testCancellationPropagates() async {
        do {
            _ = try await PharmacySearch.search(origin: origin) { _ in throw CancellationError() }
            XCTFail("Cancellation must propagate")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testVisibleResultsAreBoundedWithoutChangingTheTotal() {
        let rows = (0..<25).map { index in
            Pharmacy(
                id: "node/\(index)", name: "Pharmacy \(index)", address: "", point: origin, distance: Double(index))
        }
        let result = SearchResult(pharmacies: rows, radius: 3_000, covered: true)
        XCTAssertEqual(result.pharmacies.count, 25)
        XCTAssertEqual(result.visiblePharmacies.map(\.id).first, "node/0")
        XCTAssertEqual(result.visiblePharmacies.map(\.id).last, "node/19")
    }

    func testNonPharmaciesAreNotPresented() throws {
        let data = payload(#"{"elements":[{"type":"node","id":1,"lat":60.45,"lon":22.27,"tags":{"amenity":"cafe"}}]}"#)
        XCTAssertTrue(try PharmacySearch.normalize(data, origin: origin).isEmpty)
    }

    func testEqualDistancesUseAStableIdentifierOrder() throws {
        let data = payload(
            #"""
            {"elements":[
              {"type":"node","id":2,"lat":60.45,"lon":22.27,"tags":{"amenity":"pharmacy"}},
              {"type":"node","id":1,"lat":60.45,"lon":22.27,"tags":{"amenity":"pharmacy"}}
            ]}
            """#)
        XCTAssertEqual(try PharmacySearch.normalize(data, origin: origin).map(\.id), ["node/1", "node/2"])
    }

    func testMappedHoursAreTrimmedAndMissingHoursStayUnknown() throws {
        let data = payload(
            #"""
            {"elements":[
              {"type":"node","id":1,"lat":60.45,"lon":22.27,"tags":{"amenity":"pharmacy","opening_hours":" Mo-Fr 09:00-18:00 "}},
              {"type":"node","id":2,"lat":60.46,"lon":22.27,"tags":{"amenity":"pharmacy"}}
            ]}
            """#)
        let rows = try PharmacySearch.normalize(data, origin: origin)
        XCTAssertEqual(rows.first { $0.id == "node/1" }?.hours, "Mo-Fr 09:00-18:00")
        XCTAssertEqual(rows.first { $0.id == "node/2" }?.hours, "")
    }

    func testMappedHoursAreBoundedInLength() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "elements": [
                [
                    "type": "node", "id": 1, "lat": 60.45, "lon": 22.27,
                    "tags": ["amenity": "pharmacy", "opening_hours": String(repeating: "x", count: 400)],
                ]
            ]
        ])
        XCTAssertEqual(try PharmacySearch.normalize(data, origin: origin).first?.hours.count, 240)
    }

    func testEveryCityCentreIsInFinland() {
        for city in City.allCases {
            XCTAssertTrue(PharmacyCatalog.isInFinland(city.centre), city.rawValue)
        }
    }
}
