# PharmaNear — iOS

A small, independent pharmacy finder built as a Treat Health engineering application exercise. Not affiliated with Treat Health and not medical advice.

## What it does
- On explicit request, obtains a device position; alternatively search from one of five Finnish city centres.
- Queries OpenStreetMap pharmacies via Overpass, expanding the search from 3 km to 10 km to 30 km if needed.
- Calculates great-circle distances on the device and presents the closest returned mapped pharmacies first (up to 20 displayed).
- Opens a selected pharmacy in a map application/site; supports English, Finnish and Swedish.
- Handles permission denial, loading, cancellation, empty results, and provider failures without displaying stale search results.

## Privacy and limitations
No account, analytics, location history or persistent application storage. The search sends a coordinate rounded to two decimal places (not anonymous; the external provider also receives normal network metadata, including IP address). The device-provided position is retained in memory during the search and used for distance calculation. Location precision depends on the OS/browser; distances are straight-line estimates, not travel distance. Map links only open on request and are external services with their own privacy policies. OpenStreetMap may be incomplete, and building centres may differ from entrances. The nearest result means nearest returned mapped location within the bounded search, not a guarantee of the nearest real-world pharmacy. No opening-hours claims are made. Public Overpass is best-effort, not an SLA-backed production service. Production rollout would require a reviewed EU-hosted provider or self-hosted dataset, rate limiting, monitoring and licensing review. See [ADR](docs/0001-search-and-privacy.md).

Data © [OpenStreetMap contributors](https://www.openstreetmap.org/copyright), ODbL. No OSM data is bundled.

## Run locally
Requires macOS with Xcode 16+ and an iOS 16+ simulator/device.

1. Open `PharmaNear.xcodeproj` in Xcode.
2. Select the PharmaNear scheme and an iPhone simulator.
3. Run (Cmd+R). Select a simulated location or search a city centre.

```sh
swift test
xcodebuild -project PharmaNear.xcodeproj -scheme PharmaNear -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

For a physical iPhone, select your own signing team in Xcode. No external Swift dependencies or API keys are required.

## Structure
- `App/PharmaNearApp.swift`: SwiftUI, observable search state, CoreLocation and MapKit.
- `Sources/PharmacyCore/Core.swift`: pure Swift search logic and HTTP client, built into the app and separately tested as a Swift package.
- `Tests/PharmacyCoreTests/CoreTests.swift`: XCTest coverage.
- `.github/workflows/ci.yml`: Swift tests and simulator build on macOS.

## Verification
The original core implementation reported eight passing tests. Five new XCTest scenarios cover result limits, pharmacy filtering, deterministic ranking, cancellation and search expansion. The refreshed revision must pass CI before submission. The Apple SDK is unavailable in the isolated environment, so the SwiftUI target is not yet compiled or tested on a simulator. The macOS CI build is required before submission; run the manual checklist too.

## Engineering process
AI-assisted implementation was used. See [review checklist and limitations](docs/review.md). This is an initial candidate deliverable, not a claim of production certification.

## Design
The native UI follows Finnish functionalism with paper/pine tones, a scalable system serif heading, decorative Canvas contour art (not a geographic map), native navigation, numbered result rows, adaptive city controls for accessibility text sizes, dark mode and reduced-motion-aware button and result transitions. No additional dependencies or remote visual assets.

## Manual UI verification
On an iPhone simulator test location permission denial, city search, cancellation, locale changes, dark mode, largest Dynamic Type and VoiceOver. The SwiftUI target requires macOS/Xcode; no claim of simulator or accessibility certification is made.

## Map, schedules and icon
The native MapKit sheet opens only on explicit selection. Opening hours are community-sourced OSM strings, explicitly unverified; use the Apteekki.fi link or pharmacy website for confirmation. The asset catalog contains a custom 1024px RGB app icon. The existing CI builds for an iOS simulator; manual UI validation remains required.

## Architecture
See [architecture notes](docs/architecture.md) for file responsibilities, state ownership, cancellation and official Apple references. The minimum deployment target remains iOS 16.
