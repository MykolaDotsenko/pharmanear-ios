import CoreLocation
import Foundation
import PharmacyCore
import SwiftUI

/// Foreground-only sensor session. The selected pharmacy and GPS fixes stay in memory.
@MainActor
final class RadarLocation: NSObject, ObservableObject {
    @Published private(set) var point: Point?
    @Published private(set) var accuracy: Double = 0
    @Published private(set) var heading: Double?
    @Published private(set) var usesCompass = false
    @Published private(set) var fresh = false
    @Published private(set) var denied = false
    private var manager: CLLocationManager?
    private var compass: Double?
    private var motion: Double?
    private var anchor: CLLocation?
    private var expiry: Task<Void, Never>?
    private var motionExpiry: Task<Void, Never>?

    func start() {
        guard manager == nil else { return }
        let manager = CLLocationManager()
        self.manager = manager
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 3
        manager.headingFilter = 3
        denied = false
        authorize(manager)
    }

    func stop(clear: Bool = false) {
        manager?.stopUpdatingLocation()
        manager?.stopUpdatingHeading()
        manager?.delegate = nil
        manager = nil
        expiry?.cancel()
        motionExpiry?.cancel()
        fresh = false
        heading = nil
        usesCompass = false
        compass = nil
        motion = nil
        anchor = nil
        if clear { point = nil }
    }

    private func authorize(_ manager: CLLocationManager) {
        guard self.manager === manager else { return }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
        case .denied, .restricted:
            denied = true
            stop(clear: true)
        @unknown default:
            denied = true
            stop(clear: true)
        }
    }

    private func update(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0, abs(location.timestamp.timeIntervalSinceNow) <= 15 else { return }
        let next = Point(lat: location.coordinate.latitude, lon: location.coordinate.longitude)
        guard next.isValid else { return }
        var direction: Double?
        if location.speed >= 0.5, location.course >= 0, location.horizontalAccuracy <= 30 {
            direction = location.course
        } else if let anchor, abs(location.timestamp.timeIntervalSince(anchor.timestamp)) <= 15,
            max(anchor.horizontalAccuracy, location.horizontalAccuracy) <= 30,
            location.distance(from: anchor) >= max(8, max(anchor.horizontalAccuracy, location.horizontalAccuracy))
        {
            direction = RadarGeometry.bearing(
                from: Point(lat: anchor.coordinate.latitude, lon: anchor.coordinate.longitude), to: next)
        }
        if direction != nil || anchor == nil || abs(location.timestamp.timeIntervalSince(anchor!.timestamp)) > 15 {
            anchor = location
        }
        if let direction {
            motion = RadarGeometry.smooth(motion, direction)
            motionExpiry?.cancel()
            motionExpiry = Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                self?.motion = nil
                self?.heading = self?.compass
            }
        }
        heading = compass ?? motion
        point = next
        accuracy = location.horizontalAccuracy
        fresh = true
        expiry?.cancel()
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            self?.fresh = false
        }
    }
}

extension RadarLocation: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.authorize(manager) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            guard self.manager === manager else { return }
            self.update(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0, newHeading.trueHeading >= 0 else { return }
        Task { @MainActor in
            guard self.manager === manager else { return }
            self.compass = RadarGeometry.smooth(self.compass, newHeading.trueHeading)
            self.usesCompass = true
            self.heading = self.compass
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.manager === manager else { return }
            self.fresh = false
            if (error as? CLError)?.code == .denied {
                self.denied = true
                self.stop(clear: true)
            }
        }
    }
}
