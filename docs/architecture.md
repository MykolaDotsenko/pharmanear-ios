# Architecture

Target: iOS 16+. Apple recommends ObservableObject/StateObject for this deployment target; Observation is available on iOS 17+.

- App/PharmaNearApp.swift: entry point.
- App/ContentView.swift: SwiftUI composition and local presentation state.
- App/Finder.swift: main-actor observable model, location permission, retry and task lifetime. One typed snapshot is published atomically. Fresh CLLocationManager per explicit request prevents stale delegate events from previous requests.
- App/NordicDesign.swift: palette, button style, decorative winter artwork.
- App/PharmacyMapSheet.swift: opt-in native map.
- App/Translations.swift: localized UI strings.
- Sources/PharmacyCore/Core.swift: platform-independent geometry, ranking, normalization and transport. Swift Package tests exercise domain logic without Xcode.

There is no global store, service locator, DI container or artificial repository hierarchy. Search loader is injected at initialization for future model tests. Coordinates are not persisted.

Official references: [SwiftUI model data](https://developer.apple.com/documentation/swiftui/monitoring-model-data-changes-in-your-app), [StateObject](https://developer.apple.com/documentation/swiftui/stateobject), [Core Location authorization](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services), [single location request](https://developer.apple.com/documentation/corelocation/cllocationmanager/requestlocation()).

Verification: swift test + Xcode simulator build; simulator screenshot workflow is separate evidence. Manual VoiceOver and live provider remain gates.

## Local Swift package and transport
The app target links the local PharmacyCore package instead of compiling its source files directly. Domain and transport remain in one small package, with named search helpers in Core.swift and an injected asynchronous transport in OverpassClient.swift. An ephemeral reusable URLSession avoids rebuilding the session per query. HTTP 403/429 are not retried; selected transient failures can use one alternate provider. See [Apple local packages](https://developer.apple.com/documentation/xcode/organizing-your-code-with-local-packages), [URLSession](https://developer.apple.com/documentation/foundation/urlsession), and [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).

The two public endpoints are best effort. Network-independent data needs a verified licensed extract; no mock data is bundled.
