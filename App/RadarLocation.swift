import CoreLocation
import Foundation
import PharmacyCore
import SwiftUI
import UIKit

/// Foreground-only sensor session around `RadarTracker`. Fixes and headings stay in memory.
@MainActor
final class RadarLocation: NSObject, ObservableObject {
    @Published private(set) var tracker = RadarTracker()
    @Published private(set) var denied = false
    /// Approximate location gives kilometre-wide fixes, which cannot point the way.
    @Published private(set) var reducedAccuracy = false
    private var manager: CLLocationManager?

    func start() {
        guard manager == nil, !denied else { return }
        let manager = CLLocationManager()
        self.manager = manager
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // Every fix, standing still included, so a fix at the pharmacy's door stays live.
        manager.distanceFilter = kCLDistanceFilterNone
        manager.headingFilter = 1
        updateOrientation()
        authorize(manager)
    }

    func stop(clear: Bool = false) {
        manager?.stopUpdatingLocation()
        manager?.stopUpdatingHeading()
        manager?.delegate = nil
        manager = nil
        if clear { tracker = RadarTracker() }
    }

    /// Headings are measured against the top of the screen as the interface is turned. UIKit names landscape by
    /// the interface and Core Location by the device, so the two landscape cases are mirrored.
    func updateOrientation() {
        guard let manager else { return }
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        switch scene?.interfaceOrientation {
        case .landscapeLeft: manager.headingOrientation = .landscapeRight
        case .landscapeRight: manager.headingOrientation = .landscapeLeft
        case .portraitUpsideDown: manager.headingOrientation = .portraitUpsideDown
        default: manager.headingOrientation = .portrait
        }
    }

    private func authorize(_ manager: CLLocationManager) {
        guard self.manager === manager else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            reducedAccuracy = manager.accuracyAuthorization == .reducedAccuracy
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
        default:
            denied = true
            stop(clear: true)
        }
    }

    /// Callbacks from a manager this session has already replaced are dropped.
    private func isCurrent(_ source: ObjectIdentifier) -> Bool {
        manager.map { ObjectIdentifier($0) == source } ?? false
    }
}

extension RadarLocation: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let source = ObjectIdentifier(manager)
        Task { @MainActor in
            guard self.isCurrent(source), let current = self.manager else { return }
            self.authorize(current)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let fix = RadarFix(
            point: Point(lat: location.coordinate.latitude, lon: location.coordinate.longitude),
            accuracy: location.horizontalAccuracy, time: location.timestamp, speed: location.speed,
            course: location.course)
        let source = ObjectIdentifier(manager)
        Task { @MainActor in
            guard self.isCurrent(source) else { return }
            self.tracker.record(fix, now: Date())
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // True north needs a position; until the first fix the magnetic heading stands in.
        let heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        let accuracy = newHeading.headingAccuracy
        let source = ObjectIdentifier(manager)
        Task { @MainActor in
            guard self.isCurrent(source) else { return }
            self.tracker.record(heading: heading, accuracy: accuracy)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let code = (error as? CLError)?.code
        let source = ObjectIdentifier(manager)
        Task { @MainActor in
            guard self.isCurrent(source) else { return }
            switch code {
            case .denied?:
                self.denied = true
                self.stop(clear: true)
            case .headingFailure?:
                // Magnetic interference: positions keep working, the chart falls back to north-up.
                self.tracker.compassFailed()
            default:
                // Temporary, such as no fix yet: keep waiting.
                break
            }
        }
    }

    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        true
    }
}
