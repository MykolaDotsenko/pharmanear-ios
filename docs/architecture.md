# Architecture

Target: iOS 16 and later. SwiftUI for the interface, a local Swift package for everything that does not need
UIKit, Core Location or MapKit.

## Boundaries

```
App (SwiftUI, Core Location, MapKit)          PharmacyCore (Foundation; Combine where available)
  ContentView ──► SearchSession ◄──────────────  SearchSession, SearchPhase, LocationProviding
  DeviceLocation ─ implements LocationProviding   PharmacyCatalog ──► OverpassClient
  SearchHeader, ResultsSection, PharmacyRow       Core: Point, City, Pharmacy, ranking, coverage
  PharmacyRadarView ──► RadarLocation ─────────►  RadarTracker, RadarGuidance, RadarAnnouncer, RadarGeometry
                                                  CheckedSources
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
- **`CheckedSources`** holds manually checked pages for a few pharmacies. A check applies only while the
  mapped name, position and hours still match it, and vouches for the hours for ninety days; after that the row
  keeps only the link. Mapped hours are otherwise labelled unverified.
- **The radar** opens from a _Radar_ button on each row, pointing to that pharmacy, with the other results as
  context and a menu to switch. It keeps its rules in `PharmacyCore`, tested on Linux, and only the sensors in
  the app.
  `RadarTracker` decides which fixes count (none older than 15 s, none invalid), when a fix is stale (read at
  the moment, so no timers), and what turns the chart: the compass while it is better than ±30°, used as
  delivered so it never lags after a turn; otherwise the direction of travel; otherwise north-up.
  `RadarGuidance` names a direction only for a live fix outside the GPS uncertainty, with hysteresis at each
  eighth of a turn; keeps "near" on a stale fix, since someone at the door gets none; and says when the results
  are far away. `RadarAnnouncer` lets VoiceOver hear a new target, note or clear change in distance, and a new
  direction at most every eight seconds. `RadarLocation` feeds it from `CLLocationManager` with every fix and
  a heading filter of 1°, sets `headingOrientation` from the interface orientation, treats only a denial as
  final and a heading failure as a fall-back to north-up, and reports approximate location. The radar stops
  only in the background, since the permission prompt makes the app inactive; it keeps the screen on while a
  fix is live and restores the idle timer afterwards. With Reduce Motion the chart stays north-up.
- **Row actions** sit in a small wrapping layout: on one line when they fit and on more when the width or text
  size needs it, so each action keeps its identity and VoiceOver focus when Dynamic Type changes.
- **Views** receive values and closures, not the session: `SearchHeader` needs only whether the app is idle and
  two actions; `ResultsSection` renders a snapshot. There is no global store, service locator or persistence of
  coordinates.

## Localization

Copy lives in [String Catalogs](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog):
`Localizable.xcstrings` for the interface, with plural variations for the result count, and
`InfoPlist.xcstrings` for the location permission prompt. Keys are the English source strings, as Xcode
extracts them from `Text`, `Button`, `Label` and `String(localized:)`. `scripts/check-strings.py` fails CI when
a literal has no key, a key is unused, or a translation is missing or changes its format arguments.

The app follows the system language. Since iOS 13 people can choose a language per app in Settings once more
than one language is set on the device; then the globe button opens
[the app's settings](https://developer.apple.com/documentation/uikit/uiapplication/opensettingsurlstring)
instead of offering a second, in-app choice. See [ADR 0003](0003-system-language.md).

The checker matches interpolations by position, not type: a number needs a `%lld` key and a string a `%@` key,
so the specifier of a new key with a number in it needs a look by eye.

## Accessibility

Controls are at least 44 points; the city controls stack at accessibility text sizes; motion is removed with
Reduce Motion; each result's details are one VoiceOver element; and a finished search is announced while
VoiceOver users keep their reading position. Text colours keep at least 5.2:1 contrast in every palette. See
the [Human Interface Guidelines on accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility).

## Code style

[Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) for naming and
[swift-format](https://github.com/swiftlang/swift-format) for layout, with the configuration in
`.swift-format`; CI runs it in strict lint mode.
