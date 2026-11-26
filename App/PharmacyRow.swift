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

    /// A hand-checked source, which vouches for the hours only while they match and the check is recent.
    private var source: CheckedSource? { CheckedSources.source(for: pharmacy) }

    private var displayAddress: String {
        pharmacy.address.isEmpty ? source?.address ?? "" : pharmacy.address
    }

    /// The check date in UTC, the day it was made wherever the reader is.
    private func day(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .long, time: .omitted)
        style.timeZone = TimeZone(identifier: "UTC") ?? .current
        return date.formatted(style)
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
            // Each row repeats these links, so their accessible names carry the pharmacy's name.
            if let source, let checked = source.checked {
                Link(destination: source.url) { Text("Source checked: \(day(checked))") }
                    .font(.footnote)
                    .frame(minHeight: 44)
                    .accessibilityLabel(Text("Source checked \(day(checked)): \(name)"))
            } else if let source {
                Link(destination: source.url) { Text("Pharmacy details") }
                    .font(.footnote)
                    .frame(minHeight: 44)
                    .accessibilityLabel(Text("Pharmacy details: \(name)"))
            } else if pharmacy.hours.isEmpty {
                Link(destination: .pharmacyDirectory) { Text("Check opening hours") }
                    .font(.footnote)
                    .frame(minHeight: 44)
                    .accessibilityLabel(Text("Check opening hours: \(name)"))
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
            // Every line may wrap instead of truncating, so Dynamic Type sizes stay fully supported.
            if !displayAddress.isEmpty {
                Text(displayAddress)
                    .font(.subheadline)
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if displayAddress.isEmpty && !pharmacy.name.isEmpty {
                Text("Address not listed")
                    .font(.footnote)
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if pharmacy.name.isEmpty {
                Text(
                    possibleDuplicate
                        ? String(localized: "Possible duplicate map entry; identity not confirmed.")
                        : String(localized: "Incomplete map entry; confirm the pharmacy before travelling.")
                )
                .font(.footnote)
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            }
            if pharmacy.hours.isEmpty {
                Text("Opening hours unavailable")
                    .font(.footnote)
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // Mapped hours are unverified; only hours matching a recent check drop the qualifier.
                Group {
                    if source?.checked != nil {
                        Text("Opening hours")
                    } else {
                        Text("Mapped hours (unverified)")
                    }
                }
                .font(.caption)
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                Text(readableHours)
                    .font(.footnote)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
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
