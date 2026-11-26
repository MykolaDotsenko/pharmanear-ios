# Architecture

Target: iOS 16 and later. SwiftUI for the interface, a local Swift package for everything that does not need
UIKit, Core Location or MapKit.

## Boundaries

```
App (SwiftUI, Core Location, MapKit)          PharmacyCore (Foundation only)
  ContentView ──► SearchSession ◄──────────────  SearchSession, SearchPhase, LocationProviding
  DeviceLocation ─ implements LocationProviding   PharmacyCatalog ──► OverpassClient
  SearchHeader, ResultsSection, PharmacyRow       Core: Point, City, Pharmacy, ranking, coverage
```

- **`PharmacyCore`** has no SwiftUI, UIKit, Core Location or MapKit imports, so all of its behaviour is tested
  with `swift test`, also on Linux. The app links it as a
  [local package](https://developer.apple.com/documentation/xcode/organizing-your-code-with-local-packages).
- **`SearchSession`** owns one search at a time on the main actor and publishes one `SearchSnapshot` (phase,
  origin, result). Starting, retrying or cancelling cancels the previous task, and a generation number stops a
  superseded search from publishing even if its work finishes. It conforms to `ObservableObject` where Combine
  exists, so `ContentView` holds it as a
  [`StateObject`](https://developer.apple.com/documentation/swiftui/stateobject) without a wrapper.
- **`LocationProviding`** is the only thing the session knows about location: one `async` position, or
  `LocationUnavailable`. Tests use a fake; the app uses `DeviceLocation`.
- **`DeviceLocation`** wraps `CLLocationManager` in a checked continuation with task cancellation. It
  [requests When In Use authorization](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services)
  only on demand, reacts to
  [`locationManagerDidChangeAuthorization`](<https://developer.apple.com/documentation/corelocation/cllocationmanagerdelegate/locationmanagerdidchangeauthorization(_:)>),
  and asks for a single fix with
  [`requestLocation()`](<https://developer.apple.com/documentation/corelocation/cllocationmanager/requestlocation()>).
  Its timeout starts only after permission is granted. Each request has an identifier so a late cancellation of
  an earlier request cannot end a newer one.
- **`PharmacyCatalog`** is an actor: it decodes the bundled snapshot once, caches a refreshed snapshot, and
  serializes refresh decisions without locks. Download, live search and the clock are injected for tests.
- **Views** receive values and closures, not the session: `SearchHeader` needs only whether the app is idle and
  two actions; `ResultsSection` renders a snapshot. There is no global store, service locator or persistence of
  coordinates.

## Localization

Copy lives in [String Catalogs](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog):
`Localizable.xcstrings` for the interface, with plural variations for the result count, and
`InfoPlist.xcstrings` for the location permission prompt. Keys are the English source strings, as Xcode
extracts them from `Text`, `Button`, `Label` and `String(localized:)`. `scripts/check-strings.py` fails CI when
a literal has no key, a key is unused, or a translation is missing or changes its format arguments.

The app follows the system language. Since iOS 13 people can choose a language per app in Settings, so the
globe button opens [the app's settings](https://developer.apple.com/documentation/uikit/uiapplication/opensettingsurlstring)
instead of offering a second, in-app choice; see [ADR 0003](0003-system-language.md).

## Accessibility

Controls are at least 44 points; the city controls stack at accessibility text sizes; motion is removed with
Reduce Motion; each result's details are one VoiceOver element; and a finished search is announced while
VoiceOver users keep their reading position. Text colours keep at least 5.2:1 contrast in every palette. See
the [Human Interface Guidelines on accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility).

## Code style

[Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) for naming and
[swift-format](https://github.com/swiftlang/swift-format) for layout, with the configuration in
`.swift-format`; CI runs it in strict lint mode.
