import MapKit
import PharmacyCore
import SwiftUI

/// One ranked pharmacy, with source-aware details and explicit missing data.
struct PharmacyRow: View {
    let pharmacy: Pharmacy
    let rank: Int
    let palette: NordicPalette
    let possibleDuplicate: Bool
    let showMap: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct Review {
        let name: String
        let point: Point
        let address: String
        let hours: String
        let url: URL
    }

    // A dated source comparison, not a live opening-status feed.
    private var reviewed: Review? {
        let record: Review
        switch pharmacy.id {
        case "node/1369465698":
            record = Review(
                name: "Yliopiston apteekki", point: Point(lat: 60.169575, lon: 24.939536),
                address: "Mannerheimintie 5, Helsinki", hours: "08:00-24:00",
                url: URL(string: "https://www.yliopistonapteekki.fi/yhteystiedot/helsinki-keskusta")!)
        case "node/11771777459":
            record = Review(
                name: "Apteekki CityCenter", point: Point(lat: 60.170001, lon: 24.941615),
                address: "Kaivokatu 8, Helsinki", hours: "Mo-Fr 08:00-19:00; Sa 10:00-17:00; Su off",
                url: URL(string: "https://citycenter.fi/liikkeet/apteekki-citycenter/")!)
        default:
            return nil
        }
        return pharmacy.name == record.name && pharmacy.point.distance(to: record.point) <= 15 ? record : nil
    }

    private var displayAddress: String {
        pharmacy.address.isEmpty ? reviewed?.address ?? "" : pharmacy.address
    }

    private var isNearest: Bool { rank == 1 }

    private var name: String {
        pharmacy.name.isEmpty ? String(localized: "Pharmacy — name unavailable") : pharmacy.name
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
            if let reviewed {
                Link(destination: reviewed.url) {
                    if pharmacy.hours == reviewed.hours {
                        Text("Source checked: 26 November 2026")
                    } else {
                        Text("Pharmacy details")
                    }
                }
                .font(.footnote)
                .frame(minHeight: 44)
            } else if pharmacy.hours.isEmpty {
                Link("Check opening hours", destination: .pharmacyDirectory)
                    .font(.footnote)
                    .frame(minHeight: 44)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(distance)
                    .font((isNearest ? Font.title : Font.title2).weight(.medium))
                    .monospacedDigit()
                actionLayout { actions }
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
            if !displayAddress.isEmpty {
                Text(displayAddress)
                    .font(.subheadline)
                    .foregroundStyle(palette.muted)
            }
            if displayAddress.isEmpty && !pharmacy.name.isEmpty {
                Text("Address not listed")
                    .font(.footnote)
                    .foregroundStyle(palette.muted)
            }
            if pharmacy.name.isEmpty {
                Text(
                    possibleDuplicate
                        ? String(localized: "Possible duplicate map entry; identity not confirmed.")
                        : String(localized: "Incomplete map entry; confirm the pharmacy before travelling.")
                )
                    .font(.footnote)
                    .foregroundStyle(palette.muted)
            }
            if pharmacy.hours.isEmpty {
                Text("Opening hours unavailable")
                    .font(.footnote)
                    .foregroundStyle(palette.muted)
            } else {
                Text("Opening hours")
                    .font(.caption)
                    .foregroundStyle(palette.muted)
                Text(readableHours)
                    .font(.footnote)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }

    // Preserve the identity of each action when Dynamic Type changes, and give larger labels room to wrap.
    private var actionLayout: AnyLayout {
        if dynamicTypeSize >= .xxxLarge {
            AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
        } else {
            AnyLayout(HStackLayout(spacing: 16))
        }
    }

    @ViewBuilder
    private var actions: some View {
        Button(action: showMap) {
            Label("Map preview", systemImage: "map")
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 44)
        }
        .accessibilityLabel(Text("Map preview: \(name)"))
        .accessibilityIdentifier("map-preview-\(pharmacy.id)")
        .accessibilityHint(Text("MapKit loads this pharmacy location; Apple receives network metadata."))

        Button(action: openInMaps) {
            Label("Open in Maps", systemImage: "arrow.up.right")
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 44)
        }
        .accessibilityLabel(Text("Open in Maps: \(name)"))
        .accessibilityIdentifier("open-maps-\(pharmacy.id)")
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
