import Foundation

/// One GPS fix as the radar uses it. `speed` and `course` are negative when unknown, as in Core Location.
public struct RadarFix: Equatable, Sendable {
    public let point: Point
    public let accuracy: Double
    public let time: Date
    public let speed: Double
    public let course: Double

    public init(point: Point, accuracy: Double, time: Date, speed: Double = -1, course: Double = -1) {
        self.point = point
        self.accuracy = accuracy
        self.time = time
        self.speed = speed
        self.course = course
    }
}

/// How the chart is turned.
public enum RadarMode: Equatable, Sendable {
    case compass
    case travel
    case northUp
}

/// What the radar may show at one moment.
public struct RadarReading: Equatable, Sendable {
    public let point: Point?
    public let accuracy: Double
    /// Degrees clockwise from north that the top of the screen faces, when known.
    public let heading: Double?
    public let mode: RadarMode
    /// The last fix is recent enough to give a direction.
    public let isLive: Bool
}

/// The radar's sensor rules without Core Location, so they are tested on their own: which fixes count, when a
/// fix goes stale, and whether the compass, the direction of travel or nothing turns the chart.
public struct RadarTracker: Sendable {
    /// A fix older than this is stale, and a direction of travel older than this is dropped.
    public static let staleAfter: TimeInterval = 15
    /// A compass less certain than this many degrees would point the wrong way, so it is not used.
    public static let compassLimit: Double = 30

    public private(set) var fix: RadarFix?
    private var anchor: RadarFix?
    private var travel: Double?
    private var travelTime: Date?
    private var compass: Double?

    public init() {}

    /// Records a fix and returns whether it counted. Invalid fixes and fixes older than `staleAfter` (Core
    /// Location can deliver a cached one first) are ignored.
    @discardableResult
    public mutating func record(_ next: RadarFix, now: Date) -> Bool {
        guard next.point.isValid, next.accuracy.isFinite, next.accuracy >= 0,
            abs(now.timeIntervalSince(next.time)) <= Self.staleAfter
        else { return false }
        let recentAnchor = anchor.flatMap { abs(next.time.timeIntervalSince($0.time)) <= Self.staleAfter ? $0 : nil }
        var direction: Double?
        if next.speed >= 0.5, next.course >= 0, next.accuracy <= 30 {
            // The device's own course is trusted only when moving with a good fix.
            direction = RadarGeometry.degrees(next.course)
        } else if let recentAnchor {
            // Otherwise two fixes further apart than their uncertainty give the direction of travel.
            let uncertainty = max(recentAnchor.accuracy, next.accuracy)
            if uncertainty <= 30, recentAnchor.point.distance(to: next.point) >= max(8, uncertainty) {
                direction = RadarGeometry.bearing(from: recentAnchor.point, to: next.point)
            }
        }
        if direction != nil || recentAnchor == nil { anchor = next }
        if let direction {
            travel = RadarGeometry.smooth(travel, direction, factor: 0.32)
            travelTime = next.time
        }
        fix = next
        return true
    }

    /// Records a compass reading. The heading is used as it is: Core Location already filters it, and smoothing
    /// that only advances when a reading arrives would leave the chart behind after the phone stops turning.
    public mutating func record(heading: Double, accuracy: Double) {
        guard heading.isFinite, heading >= 0, accuracy.isFinite, accuracy >= 0, accuracy <= Self.compassLimit else {
            compass = nil
            return
        }
        compass = RadarGeometry.degrees(heading)
    }

    /// The compass failed, for example near a magnet; positions keep working.
    public mutating func compassFailed() {
        compass = nil
    }

    public func reading(at now: Date) -> RadarReading {
        let isLive = fix.map { now.timeIntervalSince($0.time) <= Self.staleAfter } ?? false
        let recentTravel = travelTime.map { now.timeIntervalSince($0) <= Self.staleAfter } == true ? travel : nil
        let heading = compass ?? recentTravel
        let mode: RadarMode = compass != nil ? .compass : recentTravel != nil ? .travel : .northUp
        return RadarReading(
            point: fix?.point, accuracy: fix?.accuracy ?? 0, heading: heading, mode: mode, isLive: isLive)
    }
}

/// What the radar says about one target at one moment.
public struct RadarGuidance: Equatable, Sendable {
    public enum Note: Equatable, Sendable {
        case none
        case near
        case uncertain
        case farResults
        case outsideRange
    }

    /// When even the nearest result is this far away, the results were searched for somewhere else.
    public static let farAway: Double = 5000

    public let distance: Double
    public let range: Double
    public let isNear: Bool
    /// The eighth of a turn to name (0 is ahead, or north when `isRelative` is false), or nil for no direction.
    public let sector: Int?
    public let isRelative: Bool
    public let note: Note

    /// Evaluates the reading for `target`. `previous` gives the range, "near" and direction hysteresis.
    public static func evaluate(
        _ reading: RadarReading, target: Point, nearestDistance: Double, previous: RadarGuidance?
    ) -> RadarGuidance? {
        guard let point = reading.point else { return nil }
        let distance = point.distance(to: target)
        let range = RadarGeometry.range(distance: distance, current: previous?.range)
        // The last fix still counts for "near" when it is merely stale: someone at the door gets no new fixes.
        let isNear = RadarGeometry.isNear(
            distance: distance, accuracy: reading.accuracy, wasNear: previous?.isNear ?? false)
        // Inside the GPS uncertainty a direction would be noise.
        let isUncertain = !isNear && distance <= reading.accuracy
        let isRelative = reading.heading != nil
        var sector: Int?
        if reading.isLive, !isNear, !isUncertain, let bearing = RadarGeometry.bearing(from: point, to: target) {
            let angle = bearing - (reading.heading ?? 0)
            let keep = previous?.isRelative == isRelative ? previous?.sector : nil
            sector = RadarGeometry.sector(angle, previous: keep)
        }
        let note: Note =
            isNear
            ? .near
            : isUncertain
                ? .uncertain : nearestDistance > farAway ? .farResults : distance > range ? .outsideRange : .none
        return RadarGuidance(
            distance: distance, range: range, isNear: isNear, sector: sector, isRelative: isRelative, note: note)
    }
}

/// Decides when VoiceOver hears the radar: on a new target or note, a clear change in distance, or a new
/// direction at most every `interval` seconds, never on every fix.
public struct RadarAnnouncer: Sendable {
    public static let interval: TimeInterval = 8

    private struct Spoken: Sendable {
        let target: String
        let note: RadarGuidance.Note
        let distance: Double
        let sector: Int?
        let time: Date
    }

    private var spoken: Spoken?

    public init() {}

    public mutating func shouldAnnounce(target: String, guidance: RadarGuidance, now: Date) -> Bool {
        if let spoken {
            let movedClearly = abs(guidance.distance - spoken.distance) >= max(10, spoken.distance / 4)
            let turned = guidance.sector != spoken.sector && now.timeIntervalSince(spoken.time) >= Self.interval
            guard spoken.target != target || spoken.note != guidance.note || movedClearly || turned else {
                return false
            }
        }
        spoken = Spoken(
            target: target, note: guidance.note, distance: guidance.distance, sector: guidance.sector, time: now)
        return true
    }
}
