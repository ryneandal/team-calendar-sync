# Validation notes

## Automated checks

Run `swift test` for deterministic offline tests. The suite covers roster counts and membership, feed disclosures, destination routing, URL policy, parser and recurrence behavior, stubbed network resolution, rate limits, saved library compatibility, and approval state.

`bash scripts/build-app.sh` builds the release bundle, embeds resources, generates the icon, and ad-hoc signs the result. `codesign --verify --deep --strict "build/Team Calendar.app"` checks the bundle. These commands do not launch it. CI performs both tests and bundle checks on Apple Silicon and Intel macOS runners.

## iPhone and iPad

The `TeamCalendar-iOS` scheme compiles an iOS 17+ application, the shared core/app-state tests, and a UI-test host. CI runs those tests on isolated iPhone 16 and iPad Pro 11-inch simulators using iOS 18.5. UI tests check selection, the default-calendar choice, review, and cancellation at standard and accessibility text sizes. They stop before approval, so no external feed or calendar account is touched.

Local validation of the port includes all 68 shared tests, an unsigned physical-device build, and a simulator build-for-testing. This Mac has no installed iOS runtime; simulator execution is performed in CI. Actual subscription completion, third-party calendar handlers, VoiceOver, and physical-device layouts still require device testing. Installing on hardware requires selecting a signing team in Xcode; App Store distribution is not configured.

## Provider checks: October 21, 2026

All 488 direct feed URLs returned valid iCalendar payloads. All 128 FCS feeds also passed the production Swift parser with upcoming games and no skipped events.

The other 138 college options resolve on demand and are excluded from bulk checks to respect the provider's rate limit. Alabama, Texas A&M, and North Dakota State resolved successfully and each showed five upcoming games. Every FBS team's live payload has not been checked. Availability and publisher accuracy may change.

## Manual UI coverage

Earlier native UI checks covered search, multiple selection, approval, skipped/pending states, invalid custom URLs, duplicate sources, esports and show previews, and Apple Calendar's subscription dialog. Dimension 20's broader coverage was visible in its detail view and approval sheet. The Apple test was canceled before subscribing.

The subsequent review fixes and Favorites/status/resume additions were validated with offline state tests and compilation. They have not had a fresh interactive UI pass; the app was kept out of the foreground during that work. Final Google and Exchange subscriptions have not been tested against personal accounts.

Before distributing a release, manually check the updated flows with keyboard navigation, VoiceOver, both appearances, and the minimum supported macOS version. Developer ID signing, notarization, sandboxed distribution, and automatic updates are not configured by the local bundle script.
