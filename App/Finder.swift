import PharmacyCore
import Foundation
import Combine
import CoreLocation

/// One main-actor owner for the search lifecycle.
/// Each request has an identity; replaced or cancelled work cannot publish.
@MainActor
final class Finder: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum Phase: String {
        case idle, locating, loading, found, empty, denied, error, cancelled
    }

    struct Snapshot {
        let phase: Phase
        let origin: String
        let result: SearchResult?
    }

    @Published private(set) var snapshot = Snapshot(phase: .idle, origin: "", result: nil)

    var status: String { snapshot.phase.rawValue }
    var result: SearchResult? { snapshot.result }
    var origin: String { snapshot.origin }
    var busy: Bool { snapshot.phase == .locating || snapshot.phase == .loading }

    private enum Action {
        case location
        case city(Point, String)
    }

    private let load: @Sendable (Point) async throws -> SearchResult
    private var locationManager: CLLocationManager?
    private var task: Task<Void, Never>?
    private var generation = 0
    private var lastAction: Action?
    private var requestedLocation = false

    init(load: @escaping @Sendable (Point) async throws -> SearchResult = { point in
        try await PharmacySearch.search(origin: point, fetch: { try await OverpassClient.shared.fetch(query: $0) })
    }) {
        self.load = load
        super.init()
    }

    private func publish(_ phase: Phase, origin: String = "", result: SearchResult? = nil) {
        snapshot = Snapshot(phase: phase, origin: origin, result: result)
    }

    /// Stop and detach the previous manager. Its queued callbacks are ignored.
    private func invalidate() {
        generation += 1
        task?.cancel()
        task = nil
        locationManager?.stopUpdatingLocation()
        locationManager?.delegate = nil
        locationManager = nil
        requestedLocation = false
    }

    func cancel() {
        invalidate()
        publish(.cancelled)
    }

    func retry() {
        switch lastAction {
        case .location: locate()
        case let .city(point, name): search(point, name: name)
        case nil: break
        }
    }

    func locate() {
        invalidate()
        lastAction = .location
        publish(.locating, origin: "device")
        let manager = CLLocationManager()
        locationManager = manager
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.delegate = self
        handleAuthorization(manager)
        guard locationManager === manager else { return }

        let id = generation
        task = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 15_000_000_000) }
            catch { return }
            guard let self, self.generation == id, self.locationManager === manager else { return }
            self.locationFailed()
        }
    }

    private func handleAuthorization(_ manager: CLLocationManager) {
        guard locationManager === manager else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            guard !requestedLocation else { return }
            requestedLocation = true
            manager.requestLocation()
        default:
            locationFailed()
        }
    }

    private func locationFailed() {
        invalidate()
        publish(.denied, origin: "device")
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in self?.handleAuthorization(manager) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
        let point = Point(lat: location.coordinate.latitude, lon: location.coordinate.longitude)
        Task { @MainActor [weak self] in
            guard let self, self.locationManager === manager else { return }
            self.search(point, name: "device")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.locationManager === manager else { return }
            self.locationFailed()
        }
    }

    func search(_ point: Point, name: String) {
        invalidate()
        lastAction = name == "device" ? .location : .city(point, name)
        publish(.loading, origin: name)
        let id = generation
        let loader = load
        task = Task { [weak self] in
            do {
                let result = try await loader(point)
                guard let self, !Task.isCancelled, self.generation == id else { return }
                self.task = nil
                self.publish(result.pharmacies.isEmpty ? .empty : .found, origin: name, result: result)
            } catch {
                guard let self, !Task.isCancelled, self.generation == id else { return }
                self.task = nil
                self.publish(.error, origin: name)
            }
        }
    }
}
