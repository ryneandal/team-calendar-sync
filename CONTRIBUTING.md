# Contributing

Team Calendar supports macOS 14+ and iOS/iPadOS 17+ with shared Swift 6 code. Use Xcode 16 or later; there are no third-party Swift dependencies or required credentials.

## Local workflow

```sh
swift test
bash scripts/build-app.sh
codesign --verify --deep --strict "build/Team Calendar.app"
```

These commands do not open the app. Open `build/Team Calendar.app` yourself when you want to check the UI. `swift run TeamCalendar` also launches it. The bundle script accepts `debug` for faster iteration.

For iOS, open `TeamCalendar.xcodeproj` and use the `TeamCalendar-iOS` scheme. Its unit-test target reuses the core and app-state tests; `Mobile/UITests` checks selection/review/cancellation at standard and accessibility text sizes. Run with `xcodebuild test -project TeamCalendar.xcodeproj -scheme TeamCalendar-iOS -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' CODE_SIGNING_ALLOWED=NO`, replacing the destination with an installed simulator. Tests launch the app in the simulator but never open a calendar handler or approve a subscription.

CI tests iPhone and iPad on iOS 18.5 and retains Apple Silicon/Intel Mac builds with Xcode 16.4. Live providers are deliberately excluded from CI. See GitHub's [runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) for available environments.

The iOS Xcode project links the local `CalendarCore` package and compiles the shared app sources. Its application target is named `TeamCalendariOS` to avoid a UI-test host collision with the package's Mac executable; the product and module remain `TeamCalendar`. Add new app/test files to the appropriate Xcode target as well as their Swift package directory. The mobile icon is an opaque 1024-pixel asset, reproducible with `swift scripts/make-mobile-icon.swift Mobile/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.

## Code and design

- Keep feed models, parsing, networking, destination URLs, and persistence in `CalendarCore`. Keep SwiftUI and operating-system handoffs in `TeamCalendar`. See [architecture](docs/ARCHITECTURE.md) for the boundaries and state flow.
- Use Swift 6 concurrency checks. `AppStore` owns observable UI state on the main actor; `FeedClient` serializes shared request state in an actor.
- Prefer native controls, semantic colors, system typography, keyboard access, descriptive accessibility labels, and content that works in resizable windows and both appearances. Follow Apple's [macOS design guidance](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos).
- Keep approval explicit. Opening a destination or copying a link must never claim the subscription was verified. A user confirms it after completing setup in their calendar app.
- Test behavior at module boundaries: parser input/output, stubbed HTTP, persistence in temporary directories, and approval state. Avoid live accounts and changes to the developer's saved library in tests.
- Format Swift with `xcrun swift-format format --in-place --recursive Sources Tests scripts/make-icon.swift Package.swift` using the checked-in configuration. Formatting output may vary between Xcode versions; avoid unrelated reformatting in a focused change.

## Catalog updates

Read [calendar sources](docs/CALENDAR_SOURCES.md) before adding or refreshing feeds. Use a stable ID, public HTTPS feed URL or supported college team key, source page, provider attribution, and an honest coverage description. Do not commit private calendar URLs or access tokens. Clearly identify community, broader-than-title, and season-specific feeds.

```sh
python3 scripts/expand-catalog.py          # Soccer/NFL proposal summary
python3 scripts/expand-college.py          # College proposal summary
python3 scripts/verify-feeds.py            # Optional network check of direct URLs
```

The expansion scripts print proposed changes; `--emit-json` prints the proposed catalog for review. They never edit the catalog or subscribe users. Review realignment, promotion/relegation, season constants, and identity changes before updating `Sources/CalendarCore/Resources/catalog.json`. Update the corresponding roster expectations in the tests. A new season URL cannot migrate an existing subscription in an external service.

Do not bulk-resolve FBS links: the provider rate-limits creation requests. The live checker skips these entries. Provider availability can change, so a live failure needs investigation rather than a blind expectation change.

## Pull requests

Explain the user-visible problem, the resulting behavior, and the checks you ran. Include screenshots for visible changes when possible, with no personal calendar information. Check keyboard navigation, light/dark appearance, long team names, an empty result, a failed preview, and a pending subscription. Cancel before adding a real subscription unless you intend to keep it.

The [MIT license](LICENSE) covers this project's code. External feeds, schedules, names, and trademarks remain subject to their owners' terms.
