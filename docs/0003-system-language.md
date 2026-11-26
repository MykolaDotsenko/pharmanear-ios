# ADR 0003: follow the system language

Status: accepted.

## Context

The first version had an in-app EN/FI/SV picker backed by Swift dictionaries. Only the app's own text switched:
the permission prompt, system controls and VoiceOver's speech language stayed in the device language, number
and distance formatting needed a manually injected locale, and a missing translation silently fell back to its
key.

## Decision

Use String Catalogs and the language iOS resolves for the app. Since iOS 13 people can pick a language per app in
Settings, and Apple recommends sending people there rather than building an in-app picker
([WWDC19: Creating Great Localized Experiences with Xcode 11](https://developer.apple.com/videos/play/wwdc2019/403/)).
iOS shows that per-app setting only when more than one language is set on the device, so the toolbar's globe
button appears only then, and opens the app's page in Settings.

## Consequences

- Text, formatting, plural rules, VoiceOver and the permission prompt always agree on one language.
- Changing the language relaunches the app, as iOS does for every app.
- On a device with a single language the app uses that language (English if it is not Finnish or Swedish),
  with no in-app control. Testers choose _App Language_ in the Xcode scheme instead.
- The web app keeps its own picker: a browser has no per-site language setting.
