import XCTest

@testable import PharmacyCore

final class RadarTrackerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let here = Point(lat: 60.4518, lon: 22.2666)

    private func fix(_ point: Point, accuracy: Double = 8, at seconds: TimeInterval = 0) -> RadarFix {
        RadarFix(point: point, accuracy: accuracy, time: start.addingTimeInterval(seconds))
    }

    func testCompassFollowsATurnWithoutLagging() {
        var tracker = RadarTracker()
        tracker.record(fix(here), now: start)
        for heading in stride(from: 0.0, through: 90, by: 3) { tracker.record(heading: heading, accuracy: 10) }
        // The phone stops turning: no more readings arrive, and the chart must already face 90°.
        let reading = tracker.reading(at: start)
        XCTAssertEqual(reading.mode, .compass)
        XCTAssertEqual(reading.heading, 90)
    }

    func testAnInaccurateOrFailedCompassIsNotUsed() {
        var tracker = RadarTracker()
        tracker.record(fix(here), now: start)
        tracker.record(heading: 40, accuracy: 10)
        tracker.record(heading: 120, accuracy: 60)
        XCTAssertEqual(tracker.reading(at: start).mode, .northUp)
        XCTAssertNil(tracker.reading(at: start).heading)
        tracker.record(heading: 40, accuracy: -1)
        XCTAssertNil(tracker.reading(at: start).heading)
        tracker.record(heading: 40, accuracy: 10)
        tracker.compassFailed()
        XCTAssertNil(tracker.reading(at: start).heading)
    }

    func testAFixGoesStaleButStaysOnScreen() {
        var tracker = RadarTracker()
        tracker.record(fix(here), now: start)
        XCTAssertTrue(tracker.reading(at: start.addingTimeInterval(15)).isLive)
        let later = tracker.reading(at: start.addingTimeInterval(16))
        XCTAssertFalse(later.isLive)
        XCTAssertEqual(later.point, here)
    }

    func testCachedAndInvalidFixesAreIgnored() {
        var tracker = RadarTracker()
        XCTAssertFalse(tracker.record(fix(here, at: -30), now: start))
        XCTAssertFalse(tracker.record(fix(here, accuracy: -1), now: start))
        XCTAssertFalse(tracker.record(fix(Point(lat: 91, lon: 0)), now: start))
        XCTAssertNil(tracker.reading(at: start).point)
    }

    func testWalkingGivesADirectionOfTravelThatExpires() {
        var tracker = RadarTracker()
        tracker.record(fix(here), now: start)
        // About 22 m due north, further than either fix's uncertainty.
        let north = Point(lat: here.lat + 0.0002, lon: here.lon)
        tracker.record(fix(north, at: 5), now: start.addingTimeInterval(5))
        let walking = tracker.reading(at: start.addingTimeInterval(5))
        XCTAssertEqual(walking.mode, .travel)
        XCTAssertEqual(walking.heading ?? -1, 0, accuracy: 0.5)
        XCTAssertEqual(tracker.reading(at: start.addingTimeInterval(21)).mode, .northUp)
    }

    func testJitterIsNotADirection() {
        var tracker = RadarTracker()
        tracker.record(fix(here, accuracy: 20), now: start)
        tracker.record(fix(Point(lat: here.lat + 0.00005, lon: here.lon), accuracy: 20, at: 2), now: start)
        XCTAssertEqual(tracker.reading(at: start).mode, .northUp)
    }

    func testSectorsKeepTheirLabelNearAnEdge() {
        XCTAssertEqual(RadarGeometry.sector(0), 0)
        XCTAssertEqual(RadarGeometry.sector(90), 2)
        XCTAssertEqual(RadarGeometry.sector(-10), 0)
        XCTAssertEqual(RadarGeometry.sector(350), 0)
        XCTAssertEqual(RadarGeometry.sector(25), 1)
        // 25° would be "slightly right", but "ahead" holds until 30.5°.
        XCTAssertEqual(RadarGeometry.sector(25, previous: 0), 0)
        XCTAssertEqual(RadarGeometry.sector(31, previous: 0), 1)
        XCTAssertEqual(RadarGeometry.sector(335, previous: 0), 0)
        XCTAssertEqual(RadarGeometry.sector(330, previous: 0), 0)
        XCTAssertEqual(RadarGeometry.sector(329, previous: 0), 7)
    }

    func testGuidanceNamesADirectionOnlyOutsideTheUncertainty() {
        let target = Point(lat: here.lat + 0.001, lon: here.lon)  // about 111 m north
        let clear = RadarReading(point: here, accuracy: 8, heading: 90, mode: .compass, isLive: true)
        let guidance = RadarGuidance.evaluate(clear, target: target, nearestDistance: 111, previous: nil)
        XCTAssertEqual(guidance?.sector, 6)  // facing east, north is to the left
        XCTAssertEqual(guidance?.isRelative, true)
        XCTAssertEqual(guidance?.note, RadarGuidance.Note.none)

        let blurred = RadarReading(point: here, accuracy: 150, heading: 90, mode: .compass, isLive: true)
        let uncertain = RadarGuidance.evaluate(blurred, target: target, nearestDistance: 111, previous: nil)
        XCTAssertNil(uncertain?.sector)
        XCTAssertEqual(uncertain?.note, .uncertain)

        let stale = RadarReading(point: here, accuracy: 8, heading: nil, mode: .northUp, isLive: false)
        XCTAssertNil(RadarGuidance.evaluate(stale, target: target, nearestDistance: 111, previous: nil)?.sector)
        XCTAssertNil(
            RadarGuidance.evaluate(
                RadarReading(point: nil, accuracy: 0, heading: nil, mode: .northUp, isLive: false),
                target: target, nearestDistance: 0, previous: nil))
    }

    func testNearSurvivesAStaleFixAndFarResultsAreNamed() {
        let door = Point(lat: here.lat + 0.0001, lon: here.lon)  // about 11 m
        let stale = RadarReading(point: here, accuracy: 10, heading: nil, mode: .northUp, isLive: false)
        XCTAssertEqual(RadarGuidance.evaluate(stale, target: door, nearestDistance: 11, previous: nil)?.note, .near)

        let live = RadarReading(point: here, accuracy: 10, heading: nil, mode: .northUp, isLive: true)
        let elsewhere = Point(lat: here.lat + 0.1, lon: here.lon)  // about 11 km
        let far = RadarGuidance.evaluate(live, target: elsewhere, nearestDistance: 11_000, previous: nil)
        XCTAssertEqual(far?.note, .farResults)
        XCTAssertEqual(far?.sector, 0)
        XCTAssertEqual(far?.isRelative, false)
    }

    func testAnnouncementsAreThrottled() {
        var announcer = RadarAnnouncer()
        let first = RadarGuidance(distance: 200, range: 400, isNear: false, sector: 0, isRelative: true, note: .none)
        XCTAssertTrue(announcer.shouldAnnounce(target: "a", guidance: first, now: start))
        XCTAssertFalse(announcer.shouldAnnounce(target: "a", guidance: first, now: start.addingTimeInterval(1)))
        let turned = RadarGuidance(distance: 198, range: 400, isNear: false, sector: 1, isRelative: true, note: .none)
        XCTAssertFalse(announcer.shouldAnnounce(target: "a", guidance: turned, now: start.addingTimeInterval(3)))
        XCTAssertTrue(announcer.shouldAnnounce(target: "a", guidance: turned, now: start.addingTimeInterval(9)))
        let closer = RadarGuidance(distance: 140, range: 200, isNear: false, sector: 1, isRelative: true, note: .none)
        XCTAssertTrue(announcer.shouldAnnounce(target: "a", guidance: closer, now: start.addingTimeInterval(10)))
        XCTAssertTrue(announcer.shouldAnnounce(target: "b", guidance: closer, now: start.addingTimeInterval(10.5)))
    }
}

final class CheckedSourcesTests: XCTestCase {
    private let cityCenter = Pharmacy(
        id: "node/11771777459", name: "Apteekki CityCenter", address: "",
        point: Point(lat: 60.170001, lon: 24.941615), distance: 0,
        hours: "Mo-Fr 08:00-19:00; Sa 10:00-17:00; Su off")
    private let soon = Date(timeIntervalSince1970: 1_796_947_200)  // 2026-12-10
    private let later = Date(timeIntervalSince1970: 1_804_204_800)  // 2027-03-04

    func testAMatchingRecentCheckVouchesForTheHours() {
        let source = CheckedSources.source(for: cityCenter, now: soon)
        XCTAssertEqual(source?.address, "Kaivokatu 8, Helsinki")
        XCTAssertNotNil(source?.checked)
    }

    func testChangedDataOrAnOldCheckNoLongerVouches() {
        let changed = Pharmacy(
            id: cityCenter.id, name: cityCenter.name, address: "", point: cityCenter.point, distance: 0, hours: "24/7")
        XCTAssertNil(CheckedSources.source(for: changed, now: soon)?.checked)
        XCTAssertNotNil(CheckedSources.source(for: changed, now: soon)?.url)
        XCTAssertNil(CheckedSources.source(for: cityCenter, now: later)?.checked)
        let moved = Pharmacy(
            id: cityCenter.id, name: cityCenter.name, address: "", point: Point(lat: 60.18, lon: 24.94), distance: 0)
        XCTAssertNil(CheckedSources.source(for: moved, now: soon))
        let renamed = Pharmacy(
            id: cityCenter.id, name: "Other pharmacy", address: "", point: cityCenter.point, distance: 0)
        XCTAssertNil(CheckedSources.source(for: renamed, now: soon))
    }
}
