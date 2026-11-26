# PharmaNear — iOS

A small, independent pharmacy finder for Finland in SwiftUI, built as a Treat Health engineering exercise. Not
affiliated with Treat Health and not medical advice. The web version is
[pharmanear-web](https://github.com/MykolaDotsenko/pharmanear-web).

## What it does

- Finds the closest mapped pharmacies to the device position, asking for location permission only when you tap
  _Use my location_, or to one of five Finnish city centres.
- Searches a dated national OpenStreetMap catalog **on the device**; no coordinates leave the phone.
- Falls back to live Overpass queries only when the catalog cannot serve the area, sending a coordinate rounded
  to two decimals and widening from 3 to 10 to 30 km.
- Ranks by straight-line distance and shows up to 20 results (5 at first), with an in-app MapKit preview or
  _Open in Maps_ on request.
- Shows community-mapped opening hours as _Opening hours (OpenStreetMap)_, with a notice that they can be out
  of date; a few pharmacies whose hours were checked against their own page show that date for ninety days.
  Rows without hours link to Apteekki.fi.
- A _Radar_ button on every result opens a radar for that pharmacy alone, in a straight line from live GPS and
  the compass: the distance and the way to turn first, then the dial. It asks for location when opened if
  _Use my location_ has not, gives no direction while the pharmacy is within the GPS uncertainty, keeps "near"
  at the door, works in landscape, and stops in the background. Nothing it reads is stored or sent.
- English, Finnish and Swedish from String Catalogs, following the system or per-app language; Dynamic Type up
  to the accessibility sizes, VoiceOver, dark mode, Reduce Motion, and a quiet seasonal palette from
  25 November to 6 January.
- Handles denied permission, slow or failed providers, cancellation and empty areas without ever showing a
  stale result.

## Data and privacy

The catalog is the same validated Geofabrik extract the web app publishes weekly, bundled in the
`PharmacyCore` package. When the bundled copy is more than a week old the app downloads the newest published
copy from a fixed URL (no coordinates, no identifiers), keeps it in memory, and never uses data older than
30 days. See [ADR 0002](docs/0002-local-catalog.md).

No account, analytics, persistent storage or location history. MapKit and the live fallback are third-party
services that receive normal network metadata. OpenStreetMap can be incomplete and is not the official
register; a building centre is not an entrance. See [ADR 0001](docs/0001-search-and-privacy.md).

Data © [OpenStreetMap contributors](https://www.openstreetmap.org/copyright), available under the
[Open Database License 1.0](https://opendatacommons.org/licenses/odbl/1-0/).

## Run locally

Xcode 16 or later; the app runs on iOS 16 and later. There are no third-party dependencies or API keys.

1. Open `PharmaNear.xcodeproj` and run the _PharmaNear_ scheme on an iPhone simulator.
2. Use _Features › Location_ in the simulator to set a position, or search from a city centre.
3. To see Finnish or Swedish, set _App Language_ in the scheme's Run options. On a device or simulator with more
   than one language under _Settings › General › Language & Region_, the globe button opens the app's own
   _Language_ setting.

```sh
swift test                                   # PharmacyCore tests (macOS or Linux)
python3 scripts/check-strings.py             # String Catalogs against the sources
xcrun swift-format lint --strict --recursive Package.swift Sources Tests App UITests
xcodebuild test -project PharmaNear.xcodeproj -scheme PharmaNear \
  -destination 'platform=iOS Simulator,name=iPhone 16'   # builds the app and runs the UI tests
```

The UI tests launch the app with `PHARMANEAR_CATALOG_DATE`, which makes a Debug build read the bundled catalog
as of that date with no network, so they see the same pharmacies on any day.

For a physical iPhone, select your own signing team in Xcode.

## Project layout

| Path                                        | Responsibility                                                       |
| ------------------------------------------- | -------------------------------------------------------------------- |
| `Sources/PharmacyCore/Core.swift`           | Geometry, OSM decoding, ranking, coverage, cities                    |
| `Sources/PharmacyCore/PharmacyCatalog.swift`| On-device catalog, freshness, refresh and live fallback (an actor)   |
| `Sources/PharmacyCore/OverpassClient.swift` | Overpass transport with one independent fallback                     |
| `Sources/PharmacyCore/SearchSession.swift`  | Search lifecycle and the `LocationProviding` boundary                |
| `App/DeviceLocation.swift`                  | Core Location as a cancellable `async` request                       |
| `App/ContentView.swift` and views           | `SearchHeader`, `ResultsSection`, `PharmacyRow`, `PharmacyMapSheet`  |
| `App/Localizable.xcstrings`                 | All copy in English, Finnish and Swedish                             |
| `App/InfoPlist.xcstrings`                   | The location permission prompt in all three languages                |
| `App/NordicDesign.swift`                    | Palette, button style and decorative artwork                         |
| `UITests/PharmaNearUITests.swift`           | XCUITest flows and Apple's accessibility audit                       |

[docs/architecture.md](docs/architecture.md) explains the boundaries and the Apple guidance behind them.

## Verification

Every push runs the String Catalog check, swift-format in strict mode, the `PharmacyCore` tests (search rules,
catalog policy, transport, and the search lifecycle including cancellation and superseded searches) and the
XCUITest flows on an iPhone simulator (city search, result details, show more, the map sheet, the radar from a
row, Finnish and Swedish, the largest text size, and Apple's accessibility audit). Screenshots from the UI tests are uploaded with every
run, the largest text size among them; a manual run also captures the start screen in light, dark, Finnish and
Swedish, and with _log_screenshots_ prints a small contact sheet of them to the log, for reviewers who cannot
download artifacts. [docs/review.md](docs/review.md) records what is verified and what still needs a person.

## Engineering process

Implementation was AI-assisted; the author reviews every change. The checks above, not the tooling, are what
the claims in this document rest on.
