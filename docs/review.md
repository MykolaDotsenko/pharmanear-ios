# Verification record

What is verified, how, and what still needs a person.

## Automated on every push (iOS CI, macOS 15, Xcode 16)

| Check                          | What it proves                                                                                   |
| ------------------------------ | ------------------------------------------------------------------------------------------------ |
| `scripts/check-strings.py`     | Every interface literal has a catalog key; every key is used and translated to fi and sv         |
| `swift-format lint --strict`   | Package, tests, app and UI tests follow the checked-in style                                     |
| 41 `PharmacyCore` tests        | Geometry, ranking, coverage, OSM decoding, catalog freshness, refresh caching and back-off, live fallback, transport fallback, and the search lifecycle: cancellation, superseded searches, denial, retry |
| 7 XCUITest flows               | On an iPhone simulator, offline with the bundled catalog at a fixed date: Turku search ranks Yliopiston Apteekki first, result details show the catalog date and scope, show more and fewer, the map sheet opens and closes, Finnish and Swedish copy with plural forms and city names, and Apple's accessibility audit of the start and result screens (iOS 17 and later) |

Screenshots from the UI tests are uploaded as `ios-ui-test-screenshots` on every run. Manual workflow runs also
capture the start screen in light, dark, Finnish and Swedish as `ios-ui-evidence`.

## Needs a person

- [ ] VoiceOver on a device: reading order, the announcement after a search, the map sheet, the language
      button's hint.
- [ ] Largest accessibility text size (AX5): nothing truncated or overlapping.
- [ ] Location permission flow: allow once, allow while using, deny, and changing it later in Settings.
- [ ] Per-app language in Settings for Finnish and Swedish; native speakers review the copy.
- [ ] A known location compared with an independent map.
- [ ] Offline launch with the bundled catalog.

Automated checks do not establish accessibility conformance on their own.
