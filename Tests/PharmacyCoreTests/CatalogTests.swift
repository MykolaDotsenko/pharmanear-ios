import Foundation
import XCTest
@testable import PharmacyCore

final class CatalogTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-11-26T00:00:00Z")!

    func testBundledCatalogFindsRealPharmaciesInAllCities() throws {
        let data = try PharmacyCatalog.bundledData()
        for (name, point) in PharmacySearch.cities {
            let result = try PharmacyCatalog.search(data, origin: point, now: now)
            XCTAssertFalse(result.pharmacies.isEmpty, name)
            XCTAssertEqual(result.sourceDate, "2026-11-24T21:21:23Z")
            XCTAssertFalse(result.covered)
        }
    }

    func testTurkuNearestMappedPharmacy() throws {
        let result = try PharmacyCatalog.search(PharmacyCatalog.bundledData(), origin: PharmacySearch.cities[0].1, now: now)
        XCTAssertEqual(result.pharmacies.first?.name, "Yliopiston Apteekki")
        XCTAssertEqual(result.pharmacies.count, 44)
    }

    func testExpiredCatalogRejected() throws {
        XCTAssertThrowsError(try PharmacyCatalog.search(PharmacyCatalog.bundledData(), origin: PharmacySearch.cities[0].1, now: now.addingTimeInterval(31 * 86_400)))
    }
}
