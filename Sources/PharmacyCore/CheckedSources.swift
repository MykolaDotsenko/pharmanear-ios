import Foundation

/// A pharmacy's own page, checked by hand against the mapped data.
public struct CheckedSource: Equatable, Sendable {
    /// The address from the source, used when the map has none.
    public let address: String
    public let url: URL
    /// The day the mapped hours were found to match the source, while that check still vouches for them.
    public let checked: Date?
}

/// Manually reviewed evidence, not a live opening-status feed. A check applies only while the mapped name,
/// position and hours still match it, and it stops vouching for the hours after `validity`, because schedules
/// change; the link to the source remains.
public enum CheckedSources {
    public static let validity: TimeInterval = 90 * 86_400

    private struct Entry {
        let name: String
        let point: Point
        let address: String
        let hours: String
        let url: String
        let checked: DateComponents
    }

    private static let entries: [String: Entry] = [
        "node/1369465698": Entry(
            name: "Yliopiston apteekki", point: Point(lat: 60.169575, lon: 24.939536),
            address: "Mannerheimintie 5, Helsinki", hours: "08:00-24:00",
            url: "https://www.yliopistonapteekki.fi/yhteystiedot/helsinki-keskusta",
            checked: DateComponents(year: 2026, month: 11, day: 26)),
        "node/11771777459": Entry(
            name: "Apteekki CityCenter", point: Point(lat: 60.170001, lon: 24.941615),
            address: "Kaivokatu 8, Helsinki", hours: "Mo-Fr 08:00-19:00; Sa 10:00-17:00; Su off",
            url: "https://citycenter.fi/liikkeet/apteekki-citycenter/",
            checked: DateComponents(year: 2026, month: 11, day: 26)),
    ]

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        return calendar
    }()

    public static func source(for pharmacy: Pharmacy, now: Date = Date()) -> CheckedSource? {
        guard let entry = entries[pharmacy.id], pharmacy.name == entry.name,
            pharmacy.point.distance(to: entry.point) <= 15, let url = URL(string: entry.url),
            let day = utc.date(from: entry.checked)
        else { return nil }
        let age = now.timeIntervalSince(day)
        let current = age >= 0 && age <= validity
        return CheckedSource(
            address: entry.address, url: url, checked: pharmacy.hours == entry.hours && current ? day : nil)
    }
}
