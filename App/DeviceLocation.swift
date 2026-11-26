import CoreLocation
import PharmacyCore

/// One-shot device position through Core Location, as `async` with cancellation.
///
/// Permission is requested only when a search asks for the position. The timeout starts after
/// permission is granted and the fix is requested, so time spent reading the system prompt never
/// counts against it.
@MainActor
final class DeviceLocation: NSObject, LocationProviding {
    private static let timeout: Duration = .seconds(15)

    private var manager: CLLocationManager?
    private var continuation: CheckedContinuation<Point, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var hasRequestedFix = false
    /// Identifies the request in flight, so a late cancellation of an earlier one cannot end it.
    private var requestID = 0

    func currentLocation() async throws -> Point {
        try Task.checkCancellation()
        finish(.failure(CancellationError()))
        requestID += 1
        let id = requestID
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let manager = CLLocationManager()
                manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
                manager.delegate = self
                self.manager = manager
                authorizationChanged(for: manager)
            }
        } onCancel: {
            Task { @MainActor in self.cancel(id) }
        }
    }

    private func cancel(_ id: Int) {
        guard id == requestID else { return }
        finish(.failure(CancellationError()))
    }

    private func authorizationChanged(for manager: CLLocationManager) {
        guard manager === self.manager else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            guard !hasRequestedFix else { return }
            hasRequestedFix = true
            manager.requestLocation()
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: Self.timeout)
                guard !Task.isCancelled else { return }
                self?.finish(.failure(LocationUnavailable()))
            }
        case .denied, .restricted:
            finish(.failure(LocationUnavailable()))
        @unknown default:
            finish(.failure(LocationUnavailable()))
        }
    }

    private func finish(_ result: Result<Point, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        manager?.delegate = nil
        manager = nil
        hasRequestedFix = false
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(with: result)
    }
}

extension DeviceLocation: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.authorizationChanged(for: manager) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
        let point = Point(lat: location.coordinate.latitude, lon: location.coordinate.longitude)
        Task { @MainActor in
            guard manager === self.manager else { return }
            self.finish(.success(point))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            guard manager === self.manager else { return }
            self.finish(.failure(LocationUnavailable()))
        }
    }
}
