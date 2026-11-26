import Foundation
import XCTest

@testable import PharmacyCore

@MainActor
final class SearchSessionTests: XCTestCase {
    private let found = SearchResult(
        pharmacies: [Pharmacy(id: "node/1", name: "A", address: "", point: City.turku.centre, distance: 10)],
        radius: 30_000, covered: true)
    private let nothing = SearchResult(pharmacies: [], radius: 30_000, covered: false)

    func testCitySearchShowsLoadingThenResults() async {
        let lookups = PendingLookups()
        let session = SearchSession(location: FixedLocation(.failure(LocationUnavailable())), lookup: lookups.lookup)

        session.search(from: .turku)
        XCTAssertEqual(session.snapshot.phase, .loading)
        XCTAssertEqual(session.snapshot.origin, .city(.turku))

        await lookups.waitForCalls(1)
        XCTAssertEqual(lookups.points, [City.turku.centre])
        lookups.resolve(0, with: .success(found))
        await settle()
        XCTAssertEqual(session.snapshot, SearchSnapshot(phase: .found, origin: .city(.turku), result: found))
    }

    func testEmptyResultIsDistinguishedFromFailure() async {
        let lookups = PendingLookups()
        let session = SearchSession(location: FixedLocation(.failure(LocationUnavailable())), lookup: lookups.lookup)

        session.search(from: .oulu)
        await lookups.waitForCalls(1)
        lookups.resolve(0, with: .success(nothing))
        await settle()
        XCTAssertEqual(session.snapshot.phase, .empty)

        session.search(from: .oulu)
        await lookups.waitForCalls(2)
        lookups.resolve(1, with: .failure(URLError(.timedOut)))
        await settle()
        XCTAssertEqual(session.snapshot.phase, .failed)
        XCTAssertNil(session.snapshot.result)
    }

    func testCancelledSearchNeverPublishesItsLateResult() async {
        let lookups = PendingLookups()
        let session = SearchSession(location: FixedLocation(.failure(LocationUnavailable())), lookup: lookups.lookup)

        session.search(from: .turku)
        await lookups.waitForCalls(1)
        session.cancel()
        lookups.resolve(0, with: .success(found))
        await settle()
        XCTAssertEqual(session.snapshot, SearchSnapshot(phase: .cancelled, origin: nil, result: nil))
    }

    func testNewerSearchSupersedesAnOlderOne() async {
        let lookups = PendingLookups()
        let session = SearchSession(location: FixedLocation(.failure(LocationUnavailable())), lookup: lookups.lookup)

        session.search(from: .turku)
        await lookups.waitForCalls(1)
        session.search(from: .helsinki)
        await lookups.waitForCalls(2)

        lookups.resolve(1, with: .success(nothing))
        lookups.resolve(0, with: .success(found))
        await settle()
        XCTAssertEqual(session.snapshot.phase, .empty)
        XCTAssertEqual(session.snapshot.origin, .city(.helsinki))
    }

    func testDeviceSearchLocatesThenSearchesTheExactPosition() async {
        let lookups = PendingLookups()
        let position = Point(lat: 60.4518, lon: 22.2666)
        let session = SearchSession(location: FixedLocation(.success(position)), lookup: lookups.lookup)

        session.locate()
        XCTAssertEqual(session.snapshot.phase, .locating)
        await lookups.waitForCalls(1)
        XCTAssertEqual(session.snapshot.phase, .loading)
        XCTAssertEqual(lookups.points, [position])
        lookups.resolve(0, with: .success(found))
        await settle()
        XCTAssertEqual(session.snapshot.phase, .found)
        XCTAssertEqual(session.snapshot.origin, .device)
    }

    func testUnavailableLocationIsReportedAsDeniedWithoutASearch() async {
        let lookups = PendingLookups()
        let session = SearchSession(location: FixedLocation(.failure(LocationUnavailable())), lookup: lookups.lookup)

        session.locate()
        await settle()
        XCTAssertEqual(session.snapshot.phase, .denied)
        XCTAssertEqual(lookups.points, [])
    }

    func testRetryRepeatsTheLastSearch() async {
        let lookups = PendingLookups()
        let session = SearchSession(location: FixedLocation(.failure(LocationUnavailable())), lookup: lookups.lookup)

        session.search(from: .vaasa)
        await lookups.waitForCalls(1)
        lookups.resolve(0, with: .failure(URLError(.notConnectedToInternet)))
        await settle()
        XCTAssertEqual(session.snapshot.phase, .failed)

        session.retry()
        await lookups.waitForCalls(2)
        XCTAssertEqual(lookups.points, [City.vaasa.centre, City.vaasa.centre])
        lookups.resolve(1, with: .success(found))
        await settle()
        XCTAssertEqual(session.snapshot.phase, .found)
    }

    func testBusyPhases() {
        XCTAssertTrue(SearchPhase.locating.isBusy)
        XCTAssertTrue(SearchPhase.loading.isBusy)
        for phase in [SearchPhase.idle, .found, .empty, .denied, .failed, .cancelled] {
            XCTAssertFalse(phase.isBusy)
        }
    }

    /// Lets queued main-actor work run.
    private func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }
}

@MainActor
private final class FixedLocation: LocationProviding {
    private let outcome: Result<Point, Error>

    init(_ outcome: Result<Point, Error>) {
        self.outcome = outcome
    }

    func currentLocation() async throws -> Point {
        try outcome.get()
    }
}

/// Lookups that wait until the test resolves them, in any order.
@MainActor
private final class PendingLookups {
    private(set) var points: [Point] = []
    private var continuations: [CheckedContinuation<SearchResult, Error>] = []

    nonisolated var lookup: @Sendable (Point) async throws -> SearchResult {
        { [self] point in try await self.wait(for: point) }
    }

    private func wait(for point: Point) async throws -> SearchResult {
        try await withCheckedThrowingContinuation { continuation in
            points.append(point)
            continuations.append(continuation)
        }
    }

    func resolve(_ index: Int, with result: Result<SearchResult, Error>) {
        continuations[index].resume(with: result)
    }

    func waitForCalls(_ count: Int) async {
        for _ in 0..<1_000 where points.count < count {
            await Task.yield()
        }
        XCTAssertGreaterThanOrEqual(points.count, count, "lookup was not called")
    }
}
