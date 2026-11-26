import MapKit
import PharmacyCore
import SwiftUI

/// One ranked pharmacy. The nearest is emphasised; hours are always labelled as unverified.
struct PharmacyRow: View {
    let pharmacy: Pharmacy
    let rank: Int
    let palette: NordicPalette
    let showMap: () -> Void

    private var isNearest: Bool { rank == 1 }

    private var name: String {
        pharmacy.name.isEmpty ? String(localized: "Unnamed pharmacy") : pharmacy.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Text(rank, format: .number.precision(.integerLength(2)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(palette.muted)
                    .accessibilityHidden(true)
                details
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(distance)
                    .font((isNearest ? Font.title : Font.title2).weight(.medium))
                    .monospacedDigit()
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { actions }
                    VStack(alignment: .leading, spacing: 0) { actions }
                }
            }
        }
        .padding(14)
        .background(isNearest ? palette.wash : Color.clear)
        .overlay(alignment: .leading) {
            if isNearest {
                Rectangle().fill(palette.pine).frame(width: 3).accessibilityHidden(true)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.line).frame(height: 1).accessibilityHidden(true)
        }
    }

    /// Read by VoiceOver as one element: label, name, address and hours.
    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            if isNearest {
                Text("Closest mapped result")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.pine)
            }
            Text(name)
                .font(isNearest ? .title3.weight(.semibold) : .headline)
                .fixedSize(horizontal: false, vertical: true)
            if !pharmacy.address.isEmpty {
                Text(pharmacy.address)
                    .font(.subheadline)
                    .foregroundStyle(palette.muted)
            }
            if pharmacy.hours.isEmpty {
                Text("Hours not listed")
                    .font(.footnote)
                    .foregroundStyle(palette.muted)
            } else {
                Text("Mapped hours (unverified)")
                    .font(.caption)
                    .foregroundStyle(palette.muted)
                Text(readableHours)
                    .font(.footnote)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var actions: some View {
        Button(action: showMap) {
            Label("Map preview", systemImage: "map")
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
        }
        .accessibilityLabel(Text("Map preview: \(name)"))
        .accessibilityHint(Text("MapKit loads this pharmacy location; Apple receives network metadata."))

        Button(action: openInMaps) {
            Label("Open in Maps", systemImage: "arrow.up.right")
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
        }
        .accessibilityLabel(Text("Open in Maps: \(name)"))
    }

    /// OSM separates rules with semicolons; a middle dot reads better and keeps each rule intact.
    private var readableHours: String {
        pharmacy.hours
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " · ")
    }

    private var distance: String {
        let meters = pharmacy.distance
        let isShort = meters < 1_000
        let measurement =
            isShort
            ? Measurement(value: meters, unit: UnitLength.meters)
            : Measurement(value: meters / 1_000, unit: UnitLength.kilometers)
        return measurement.formatted(
            .measurement(
                width: .abbreviated, usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(0...(isShort ? 0 : 1)))))
    }

    private func openInMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: pharmacy.coordinate))
        item.name = name
        item.openInMaps(launchOptions: nil)
    }
}
