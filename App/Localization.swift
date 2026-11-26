import Foundation
import PharmacyCore

// Display text for domain values. Every string is a key in Localizable.xcstrings, so each case is
// checked by the compiler for exhaustiveness and by scripts/check-strings.py for a translation.

extension City {
    /// The official name in the app's language: Åbo and Helsingfors in Swedish.
    var localizedName: String {
        switch self {
        case .turku: String(localized: "Turku")
        case .helsinki: String(localized: "Helsinki")
        case .tampere: String(localized: "Tampere")
        case .oulu: String(localized: "Oulu")
        case .vaasa: String(localized: "Vaasa")
        }
    }
}

extension SearchSnapshot {
    /// One line under the results heading, also announced to VoiceOver when a search ends.
    var statusText: String {
        switch phase {
        case .idle:
            return String(localized: "Choose your location to start.")
        case .locating:
            return String(localized: "Getting your location…")
        case .loading:
            return String(localized: "Searching for pharmacies…")
        case .found:
            let count = result?.pharmacies.count ?? 0
            return "\(String(localized: "\(count) mapped pharmacies")) · \(originName)"
        case .empty:
            return String(localized: "No mapped pharmacies found within the searched area.")
        case .denied:
            return String(localized: "Location is unavailable or denied. Choose a city centre instead.")
        case .failed:
            return String(localized: "Search is temporarily unavailable. Try again.")
        case .cancelled:
            return String(localized: "Search cancelled.")
        }
    }

    private var originName: String {
        switch origin {
        case .city(let city)?: city.localizedName
        case .device?, nil: String(localized: "your location")
        }
    }
}
