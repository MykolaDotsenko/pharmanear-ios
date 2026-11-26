import MapKit
import PharmacyCore
import SwiftUI

/// An opt-in native map of one pharmacy. MapKit is created only when the sheet opens, and the user's
/// own position is never shown or requested here.
struct PharmacyMapSheet: View {
    let pharmacy: Pharmacy

    @Environment(\.dismiss) private var dismiss
    @State private var region: MKCoordinateRegion

    init(pharmacy: Pharmacy) {
        self.pharmacy = pharmacy
        _region = State(
            initialValue: MKCoordinateRegion(
                center: pharmacy.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.018, longitudeDelta: 0.025)))
    }

    private var name: String {
        pharmacy.name.isEmpty ? String(localized: "Unnamed pharmacy") : pharmacy.name
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(name).font(.headline)
                Text("MapKit loads this pharmacy location; Apple receives network metadata.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Map(coordinateRegion: $region, showsUserLocation: false, annotationItems: [pharmacy]) { pharmacy in
                    MapMarker(coordinate: pharmacy.coordinate, tint: .green)
                }
                .accessibilityLabel(Text("Map of \(name)"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if !pharmacy.address.isEmpty {
                    Text(pharmacy.address).font(.subheadline)
                }
            }
            .padding()
            .navigationTitle("Pharmacy map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close map") { dismiss() }
                }
            }
        }
    }
}

extension Pharmacy {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon)
    }
}
