import PharmacyCore
import SwiftUI

/// Heading, the location button, the privacy disclosure and the city fallback.
struct SearchHeader: View {
    let isIdle: Bool
    let palette: NordicPalette
    let locate: () -> Void
    let searchFromCity: (City) -> Void

    @State private var city = City.turku
    @State private var showsPrivacy = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Pharmacy finder")
                .textCase(.uppercase)
                .font(.caption.weight(.semibold))
                .tracking(1.7)
                .foregroundStyle(palette.festiveInk)
            Text("Find a pharmacy near you.")
                .font(.system(isIdle ? .largeTitle : .title2, design: .serif, weight: .regular))
                .accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal: false, vertical: true)
            if isIdle {
                Text("Find the closest mapped pharmacies by straight-line distance. No account needed.")
                    .font(.body)
                    .foregroundStyle(palette.muted)
            }
            locationButton
            privacy
            citySelection
        }
    }

    private var locationButton: some View {
        Button(action: locate) {
            HStack(spacing: 10) {
                Image(systemName: "location").accessibilityHidden(true)
                Text("Use my location").multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right").font(.subheadline).accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(NordicButton(palette: palette, primary: true))
        .accessibilityIdentifier("use-location")
    }

    private var privacy: some View {
        DisclosureGroup(isExpanded: $showsPrivacy) {
            Text(
                "Catalog search stays on your device. If live search is needed, only rounded coordinates go to the Overpass providers (FOSSGIS or Private.coffee)."
            )
            .font(.footnote)
            .foregroundStyle(palette.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Location privacy")
                .font(.subheadline)
                .foregroundStyle(palette.pine)
                .frame(minHeight: 44, alignment: .leading)
        }
    }

    /// Side by side at regular text sizes; stacked at accessibility sizes so neither control truncates.
    private var citySelection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("City centre").font(.subheadline.weight(.semibold))
            if typeSize.isAccessibilitySize {
                cityPicker
                searchButton
            } else {
                HStack(spacing: 12) {
                    cityPicker
                    Spacer(minLength: 4)
                    searchButton
                }
            }
        }
    }

    private var cityPicker: some View {
        Picker("City centre", selection: $city) {
            ForEach(City.allCases) { Text($0.localizedName).tag($0) }
        }
        .pickerStyle(.menu)
        .frame(minHeight: 48, alignment: .leading)
        .accessibilityIdentifier("city-picker")
    }

    private var searchButton: some View {
        Button("Search") { searchFromCity(city) }
            .buttonStyle(NordicButton(palette: palette, primary: false))
            .accessibilityIdentifier("city-search")
    }
}
