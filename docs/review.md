# Verification record

What is verified, how, and what still needs a person.

## Automated on every push (iOS CI, macOS 15, Xcode 16)

| Check                          | What it proves                                                                                   |
| ------------------------------ | ------------------------------------------------------------------------------------------------ |
| `scripts/check-strings.py`     | Every interface literal has a catalog key; every key is used and translated to fi and sv         |
| `swift-format lint --strict`   | Package, tests and app follow the checked-in style                                               |
| 40 `PharmacyCore` tests        | Geometry, ranking, coverage, OSM decoding, catalog freshness, refresh caching and back-off, live fallback, transport fallback, and the search lifecycle: cancellation, superseded searches, denial, retry |
| Simulator build                | The app target compiles and links the package                                                    |

Manual workflow runs also install the app on a simulator and capture light, dark, Finnish and Swedish
screenshots as the `ios-ui-evidence` artifact.

## Needs a person

- [ ] VoiceOver on a device: reading order, the announcement after a search, the map sheet, the language
      button's hint.
- [ ] Largest accessibility text size (AX5): nothing truncated or overlapping.
- [ ] Location permission flow: allow once, allow while using, deny, and changing it later in Settings.
- [ ] Per-app language in Settings for Finnish and Swedish; native speakers review the copy.
- [ ] A known location compared with an independent map.
- [ ] Offline launch with the bundled catalog.

Automated checks do not establish accessibility conformance on their own.
