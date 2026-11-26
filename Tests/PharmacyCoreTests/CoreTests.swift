import Foundation
import XCTest
@testable import PharmacyCore
final class CoreTests: XCTestCase {
    let origin = Point(lat:60.4518,lon:22.2666)
    func testDistance() { XCTAssertEqual(origin.distance(to:origin),0); XCTAssertEqual(Point(lat:0,lon:0).distance(to:.init(lat:1,lon:0)),111195,accuracy:1) }
    func testAntimeridian() { XCTAssertLessThan(Point(lat:0,lon:179.9).distance(to:.init(lat:0,lon:-179.9)),23000) }
    func testPrivacy() throws { XCTAssertEqual(origin.approximate,.init(lat:60.45,lon:22.27)); XCTAssertTrue(try PharmacySearch.query(center:origin.approximate,radius:3000).contains("3000,60.45,22.27")); XCTAssertThrowsError(try PharmacySearch.query(center:origin,radius:1)) }
    func testNormalize() throws {
        let data = Data(#"{"elements":[{"type":"node","id":1,"lat":60.48,"lon":22.3,"tags":{"amenity":"pharmacy"}},{"type":"way","id":2,"center":{"lat":60.452,"lon":22.267},"tags":{"amenity":"pharmacy","name":"Closest"}},{"type":"way","id":2,"center":{"lat":60.452,"lon":22.267},"tags":{"amenity":"pharmacy"}},{"type":"node","id":3,"lat":91,"lon":0,"tags":{"amenity":"pharmacy"}}]}"#.utf8)
        XCTAssertEqual(try PharmacySearch.normalize(data,origin:origin).map(\.id),["way/2","node/1"])
    }
    func testPartialResponse() { XCTAssertThrowsError(try PharmacySearch.normalize(Data(#"{"elements":[],"remark":"timeout"}"#.utf8),origin:origin)) }
    func testBoundedEmptySearch() async throws { let result = try await PharmacySearch.search(origin:origin){_ in Data(#"{"elements":[]}"#.utf8)}; XCTAssertEqual(result.radius,30000); XCTAssertFalse(result.covered) }
    func testNearestSearch() async throws { let result = try await PharmacySearch.search(origin:origin){_ in Data(#"{"elements":[{"type":"node","id":1,"lat":60.452,"lon":22.267,"tags":{"amenity":"pharmacy"}}]}"#.utf8)}; XCTAssertEqual(result.radius,3000); XCTAssertTrue(result.covered); XCTAssertEqual(result.pharmacies.count,1) }
    func testInvalidLocation() async { do { _ = try await PharmacySearch.search(origin:.init(lat:100,lon:0)){_ in XCTFail("Unexpected fetch");return Data()}; XCTFail("Expected error") } catch {} }
}


extension CoreTests {
    func testVisibleResultsAreBoundedWithoutChangingTotal() {
        let rows=(0..<25).map { index in
            Pharmacy(id:"node/\(index)",name:"Pharmacy \(index)",address:"",point:origin,distance:Double(index))
        }
        let result=SearchResult(pharmacies:rows,radius:3000,covered:true)
        XCTAssertEqual(result.pharmacies.count,25)
        XCTAssertEqual(result.visiblePharmacies.count,20)
        XCTAssertEqual(result.visiblePharmacies.first?.id,"node/0")
        XCTAssertEqual(result.visiblePharmacies.last?.id,"node/19")
    }
    func testNonPharmaciesAreNotPresented() throws {
        let data=Data(#"{"elements":[{"type":"node","id":1,"lat":60.45,"lon":22.27,"tags":{"amenity":"cafe"}}]}"#.utf8)
        XCTAssertTrue(try PharmacySearch.normalize(data,origin:origin).isEmpty)
    }
    func testTieBreakIsStable() throws {
        let data=Data(#"{"elements":[{"type":"node","id":2,"lat":60.45,"lon":22.27,"tags":{"amenity":"pharmacy"}},{"type":"node","id":1,"lat":60.45,"lon":22.27,"tags":{"amenity":"pharmacy"}}]}"#.utf8)
        XCTAssertEqual(try PharmacySearch.normalize(data,origin:origin).map(\.id),["node/1","node/2"])
    }
    func testCancelledProviderDoesNotProduceResults() async {
        do {
            _ = try await PharmacySearch.search(origin:origin) { _ in throw CancellationError() }
            XCTFail("Cancellation must propagate")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    func testSearchExpandsWhenOnlyMappedPointIsOutsideGuaranteedCoverage() async throws {
        let result=try await PharmacySearch.search(origin:origin) { _ in
            Data(#"{"elements":[{"type":"node","id":1,"lat":60.48,"lon":22.27,"tags":{"amenity":"pharmacy"}}]}"#.utf8)
        }
        XCTAssertEqual(result.radius,10000)
        XCTAssertTrue(result.covered)
    }
}

extension CoreTests {
    func testMappedScheduleIsTrimmedAndMissingRemainsUnknown() throws {
        let data=Data(#"{"elements":[{"type":"node","id":1,"lat":60.45,"lon":22.27,"tags":{"amenity":"pharmacy","opening_hours":" Mo-Fr 09:00-18:00 "}},{"type":"node","id":2,"lat":60.46,"lon":22.27,"tags":{"amenity":"pharmacy"}}]}"#.utf8)
        let rows=try PharmacySearch.normalize(data,origin:origin)
        XCTAssertEqual(rows.first(where:{$0.id=="node/1"})?.hours,"Mo-Fr 09:00-18:00")
        XCTAssertEqual(rows.first(where:{$0.id=="node/2"})?.hours,"")
    }
    func testMappedScheduleLengthBound() throws {
        let data=try JSONSerialization.data(withJSONObject:["elements":[["type":"node","id":1,"lat":60.45,"lon":22.27,"tags":["amenity":"pharmacy","opening_hours":String(repeating:"x",count:400)]]]])
        XCTAssertEqual(try PharmacySearch.normalize(data,origin:origin).first?.hours.count,240)
    }
}
