import Foundation
import PharmacyCore

extension SearchSession {
    /// The session the app runs with.
    ///
    /// Debug builds launched with `PHARMANEAR_CATALOG_DATE` (an ISO 8601 date) search only the bundled catalog as
    /// of that date and never use the network, so UI tests see the same real results on any day.
    static func makeForApp() -> SearchSession {
        #if DEBUG
            if let value = ProcessInfo.processInfo.environment["PHARMANEAR_CATALOG_DATE"],
                let date = ISO8601DateFormatter().date(from: value)
            {
                let catalog = PharmacyCatalog.offline(at: date)
                return SearchSession(location: DeviceLocation()) { try await catalog.lookup(origin: $0) }
            }
        #endif
        return SearchSession(location: DeviceLocation())
    }
}
