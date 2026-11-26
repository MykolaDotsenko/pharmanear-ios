import PharmacyCore
import SwiftUI
import UIKit

/// The single screen: search controls, results and attribution.
struct ContentView: View {
    @StateObject private var search = SearchSession.makeForApp()
    @State private var mappedPharmacy: Pharmacy?
    @State private var radar: RadarRequest?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    private static let resultsID = "results"

    private var palette: NordicPalette { NordicPalette(dark: colorScheme == .dark) }
    private var phase: SearchPhase { search.snapshot.phase }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: phase == .found ? 14 : 24) {
                        SearchHeader(
                            isIdle: phase == .idle, palette: palette,
                            locate: { search.locate() }, searchFromCity: { search.search(from: $0) })
                        if phase == .idle {
                            ContourArt(palette: palette)
                        }
                        ResultsSection(
                            snapshot: search.snapshot, palette: palette,
                            cancel: { search.cancel() }, retry: { search.retry() },
                            showMap: { mappedPharmacy = $0 },
                            showRadar: { pharmacies in
                                if let target = pharmacies.first {
                                    radar = RadarRequest(pharmacies: pharmacies, target: target)
                                }
                            }
                        )
                        .id(Self.resultsID)
                        footer
                    }
                    .frame(maxWidth: 620)
                    .padding(.horizontal, 20)
                    .padding(.vertical, phase == .found ? 14 : 24)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: phase) { phase in
                    announce(phase)
                    // VoiceOver users keep their place; everyone else sees the results move into view.
                    guard phase == .found, !UIAccessibility.isVoiceOverRunning else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                        proxy.scrollTo(Self.resultsID, anchor: .top)
                    }
                }
            }
            .background(palette.paper.ignoresSafeArea())
            .foregroundStyle(palette.ink)
            .tint(palette.pine)
            .toolbarBackground(palette.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationTitle(Text(verbatim: "PharmaNear"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if offersLanguageChoice { languageButton }
                }
            }
        }
        .sheet(item: $mappedPharmacy) { PharmacyMapSheet(pharmacy: $0) }
        .sheet(item: $radar) { PharmacyRadarView(pharmacies: $0.pharmacies, target: $0.target) }
    }

    /// The app follows the system language. iOS offers a language per app in Settings once more than one
    /// language is set on the device, so the button appears only then and opens that page.
    private var offersLanguageChoice: Bool { Locale.preferredLanguages.count > 1 }

    private var languageButton: some View {
        Button {
            if let settings = URL(string: UIApplication.openSettingsURLString) { openURL(settings) }
        } label: {
            Label("Language", systemImage: "globe")
                .labelStyle(.iconOnly)
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityHint(Text("Opens Settings, where you can choose the app's language."))
        .accessibilityIdentifier("language")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(palette.line).frame(height: 1).accessibilityHidden(true)
            Text("Distances are not walking routes. Check opening hours before travelling. Map data can be incomplete.")
                .font(.footnote)
                .foregroundStyle(palette.muted)
            Link("Check Finnish pharmacy details at Apteekki.fi", destination: .pharmacyDirectory)
                .font(.subheadline)
                .frame(minHeight: 44)
            Link(destination: .openStreetMapCopyright) {
                Text(verbatim: "© OpenStreetMap contributors")
            }
            .font(.footnote)
            .frame(minHeight: 44)
        }
    }

    private func announce(_ phase: SearchPhase) {
        guard !phase.isBusy, phase != .idle else { return }
        UIAccessibility.post(notification: .announcement, argument: search.snapshot.statusText)
    }
}

extension URL {
    /// The Association of Finnish Pharmacies' directory, the authoritative source for opening hours.
    static let pharmacyDirectory = URL(string: "https://www.apteekki.fi/apteekkihaku")!
    static let openStreetMapCopyright = URL(string: "https://www.openstreetmap.org/copyright")!
}

/// One opening of the radar: the results to show and the pharmacy to point to.
private struct RadarRequest: Identifiable {
    let id = UUID()
    let pharmacies: [Pharmacy]
    let target: Pharmacy
}
