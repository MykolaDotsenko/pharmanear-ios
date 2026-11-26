import PharmacyCore
import SwiftUI

/// Search status, recovery actions and the ranked list.
struct ResultsSection: View {
    let snapshot: SearchSnapshot
    let canRetry: Bool
    let palette: NordicPalette
    let cancel: () -> Void
    let retry: () -> Void
    let showMap: (Pharmacy) -> Void

    @State private var showsAll = false
    @State private var showsDetails = false

    /// Five results answer the question; the rest are one tap away.
    private static let initialCount = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle().fill(palette.line).frame(height: 1).accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline) {
                Text("Nearby pharmacies")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if snapshot.phase.isBusy {
                    Button("Cancel", action: cancel)
                        .font(.subheadline)
                        .frame(minHeight: 44)
                }
            }
            status
            if [.failed, .denied, .empty].contains(snapshot.phase) {
                recovery
            }
            if let result = snapshot.result, !result.pharmacies.isEmpty {
                details(for: result)
                list(of: result)
            }
        }
        .onChange(of: snapshot.phase) { phase in
            if phase.isBusy { showsAll = false }
        }
    }

    @ViewBuilder
    private var status: some View {
        if snapshot.phase.isBusy {
            ProgressView(snapshot.statusText)
                .font(.subheadline)
                .foregroundStyle(palette.muted)
        } else {
            Text(snapshot.statusText)
                .font(.subheadline)
                .foregroundStyle(palette.muted)
                .accessibilityIdentifier("search-status")
        }
    }

    private var recovery: some View {
        VStack(alignment: .leading, spacing: 8) {
            if snapshot.phase == .failed, canRetry {
                Button("Try again", action: retry)
                    .buttonStyle(NordicButton(palette: palette, primary: false))
            }
            Link("Find a pharmacy on Apteekki.fi", destination: .pharmacyDirectory)
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
        }
    }

    private func details(for result: SearchResult) -> some View {
        DisclosureGroup(isExpanded: $showsDetails) {
            VStack(alignment: .leading, spacing: 6) {
                if let date = result.sourceDate {
                    Text("OSM catalog date: \(String(date.prefix(10)))")
                }
                if !result.covered {
                    Text("Search coverage is limited.")
                }
                if result.pharmacies.count > SearchResult.visibleLimit {
                    Text("Showing up to 20")
                }
                Text("Distances are straight-line estimates, not walking routes.")
                Text("MapKit loads this pharmacy location; Apple receives network metadata.")
            }
            .font(.footnote)
            .foregroundStyle(palette.muted)
        } label: {
            Text("About these results")
                .font(.subheadline)
                .foregroundStyle(palette.pine)
                .frame(minHeight: 44)
        }
    }

    @ViewBuilder
    private func list(of result: SearchResult) -> some View {
        let shown = result.visiblePharmacies.prefix(showsAll ? SearchResult.visibleLimit : Self.initialCount)
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, pharmacy in
                PharmacyRow(pharmacy: pharmacy, rank: index + 1, palette: palette) { showMap(pharmacy) }
            }
        }
        if result.pharmacies.count > Self.initialCount {
            Button {
                showsAll.toggle()
            } label: {
                if showsAll {
                    Text("Show fewer pharmacies")
                } else {
                    Text("Show more pharmacies")
                }
            }
            .buttonStyle(NordicButton(palette: palette, primary: false))
            .accessibilityIdentifier("show-more")
        }
    }
}
