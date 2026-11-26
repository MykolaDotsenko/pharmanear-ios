import XCTest

@testable import PharmacyCore

final class RadarGeometryTests: XCTestCase {
    func testBearingAndWrap() {
        let origin = Point(lat: 0, lon: 0)
        XCTAssertEqual(RadarGeometry.bearing(from: origin, to: Point(lat: 1, lon: 0)), 0)
        XCTAssertEqual(RadarGeometry.bearing(from: origin, to: Point(lat: 0, lon: 1)), 90)
        XCTAssertNil(RadarGeometry.bearing(from: origin, to: origin))
        XCTAssertEqual(RadarGeometry.smooth(359, 1, factor: 0.5), 0)
    }

    func testProjectionAndHysteresis() {
        let point = RadarGeometry.project(bearing: 90, heading: 90, distance: 200, range: 100)
        XCTAssertEqual(point.lat, 0.09, accuracy: 0.000001)
        XCTAssertEqual(point.lon, 0.5, accuracy: 0.000001)
        XCTAssertEqual(RadarGeometry.range(distance: 70), 100)
        XCTAssertEqual(RadarGeometry.range(distance: 70, current: 200), 200)
        XCTAssertEqual(RadarGeometry.range(distance: 60, current: 200), 100)
    }

    func testArrivalRequiresAccuracy() {
        XCTAssertFalse(RadarGeometry.isNear(distance: 20, accuracy: 80))
        XCTAssertFalse(RadarGeometry.isNear(distance: 20, accuracy: -1))
        XCTAssertTrue(RadarGeometry.isNear(distance: 35, accuracy: 35, wasNear: true))
    }
}
