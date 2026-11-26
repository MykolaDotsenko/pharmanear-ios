import Foundation

/// Geographic orientation only; no pedestrian route is inferred from a bearing.
public enum RadarGeometry {
    public static let ranges: [Double] = [50, 100, 200, 400, 800, 1200, 2000, 5000, 10000, 30000]

    public static func degrees(_ value: Double) -> Double {
        (value.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }

    public static func bearing(from: Point, to: Point) -> Double? {
        guard from.isValid, to.isValid, from.distance(to: to) >= 0.01 else { return nil }
        let a = from.lat * .pi / 180
        let b = to.lat * .pi / 180
        let delta = (to.lon - from.lon) * .pi / 180
        let y = sin(delta) * cos(b)
        let x = cos(a) * sin(b) - sin(a) * cos(b) * cos(delta)
        return degrees(atan2(y, x) * 180 / .pi)
    }

    public static func smooth(_ previous: Double?, _ next: Double, factor: Double = 0.24) -> Double {
        guard let previous else { return degrees(next) }
        return degrees(previous + (degrees(next - previous + 180) - 180) * factor)
    }

    public static func range(distance: Double, current: Double? = nil) -> Double {
        guard distance.isFinite, distance >= 0 else { return current ?? 200 }
        let fit = ranges.first { $0 >= distance * 1.25 } ?? 30000
        guard let current, ranges.contains(current), fit < current else { return fit }
        return ranges.first { $0 >= fit && $0 < current && distance <= $0 * 2 / 3 } ?? current
    }

    /// Coordinates are fractions of the view, with the user's position at (0.5, 0.5).
    public static func project(bearing: Double, heading: Double?, distance: Double, range: Double) -> Point {
        let angle = (bearing - (heading ?? 0)) * .pi / 180
        let radius = min(1, max(0, distance / range)) * 0.41
        return Point(lat: 0.5 - radius * cos(angle), lon: 0.5 + radius * sin(angle))
    }

    public static func isNear(distance: Double, accuracy: Double, wasNear: Bool = false) -> Bool {
        let limit = wasNear ? 40.0 : 30.0
        return distance.isFinite && accuracy.isFinite && distance >= 0 && accuracy >= 0
            && distance <= limit && accuracy <= limit
    }
}
