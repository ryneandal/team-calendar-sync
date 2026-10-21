# Team Calendar

[![macOS CI](https://github.com/ryneandal/team-calendar-sync/actions/workflows/ci.yml/badge.svg)](https://github.com/ryneandal/team-calendar-sync/actions/workflows/ci.yml)

A native macOS app for following sports, esports, actual-play shows, and spectator events in Apple Calendar, Google Calendar, or Outlook/Exchange.

Browse 626 calendars, preview upcoming events, save favorites, and approve subscriptions in your chosen calendar app. Built with SwiftUI and Swift 6, with no third-party Swift dependencies.

## What it does

- **Discover:** search teams, shows, cities, and leagues; filter by league or college conference.
- **Organize:** keep Favorites separate from your selection, and select or deselect only visible results.
- **Preview:** see upcoming events in local time, source attribution, coverage limits, and when the preview was checked.
- **Approve:** review the selected calendars and destination, then complete each subscription with a validated link.
- **Resume:** track pending and user-confirmed subscriptions, including separate destinations for the same calendar.
- **Bring your own feed:** add a public HTTPS or webcal calendar and keep its history when restoring a removed source.

The catalog includes all NFL, NCAA Division I FBS/FCS, MLB, NPB, and KBO teams; clubs across 12 major soccer leagues; seven golf tours; selected NBA teams; motorsport; esports; Critical Role; Dropout/Dimension 20; UFC; tennis; and space launches.

Coverage is explicit: college football excludes Division II, Division III, and NAIA. MLB and NPB feeds are season-specific, golf covers tournament dates, and the Dimension 20 option includes other Dropout shows. See the full [catalog and source notes](docs/CALENDAR_SOURCES.md).

## Build and run

Requires macOS 14 or later and Xcode 16 or later with Swift 6. No API keys or calendar account credentials are needed.

```sh
git clone https://github.com/ryneandal/team-calendar-sync.git
cd team-calendar-sync
swift test
bash scripts/build-app.sh
```

Open `build/Team Calendar.app` in Finder when ready. Build and test commands do not launch the app. For development, open `Package.swift` in Xcode or use `swift run TeamCalendar`.

The script creates an app for the current Mac's architecture and ad-hoc signs it. Developer ID signing and notarization are not configured; this is a source-built app, not a notarized release download.

## Subscribe

1. Select calendars with **+**, or use **Select Visible** after filtering.
2. Choose **Review** (`⌘Return`), inspect sources and coverage, and choose a destination.
3. Choose **Approve & Continue**, then open the calendar app or copy the validated feed link.
4. Finish setup there, return, and choose **I've Added This Calendar**. Pending records can be resumed from **My subscriptions**.

| Destination | Handoff |
| --- | --- |
| Apple Calendar / iCloud | Opens the native subscription dialog. Choose **iCloud** or **On My Mac** as the location. |
| Google Calendar | Opens Google's add-calendar URL, with a copyable feed URL as a fallback. |
| Microsoft 365 / Outlook.com | Copies the URL and opens the selected web calendar. Use **Add calendar → Subscribe from web**. |
| Other Exchange servers | Opens the supplied HTTPS Outlook Web Access address. The organization must allow internet subscriptions. |

The destination service controls refresh timing. Team Calendar can be closed after subscribing. Confirmation is recorded by the user; the app cannot inspect or remove subscriptions in external services.

Add a custom feed with `⇧⌘N`, refresh a preview with `⌘R`, and open Settings with `⌘,`.

Provider instructions: [Apple Calendar](https://support.apple.com/guide/calendar/icl1022/mac), [Google Calendar](https://support.google.com/calendar/answer/37100?hl=en), [Outlook](https://support.microsoft.com/en-us/office/import-or-subscribe-to-a-calendar-in-outlook-com-or-outlook-on-the-web-cff1429c-5af6-41ec-a5b4-74f2c278e98c).

## Design and architecture

SwiftUI supplies the resizable split view, sidebar, toolbar search, native sheets, Settings, system typography, and light/dark appearance. Selection, favorites, and external subscription status are separate concepts. Keyboard shortcuts and descriptive accessibility labels accompany the visible controls.

The code separates Foundation models, parsing, networking, and persistence in `CalendarCore` from observable app state, SwiftUI views, and an AppKit handoff adapter in `TeamCalendar`. Async validation follows an immutable review queue, and only explicit user confirmation completes a subscription.

Read the [architecture](docs/ARCHITECTURE.md) for module boundaries, approval state, identity, concurrency, and preview limits. The UI follows Apple's [macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos), [sidebar](https://developer.apple.com/design/human-interface-guidelines/sidebars), and [toolbar](https://developer.apple.com/design/human-interface-guidelines/toolbars) guidance.

## Privacy and verification

No EventKit access, passwords, OAuth tokens, or analytics are used. The library lives at `~/Library/Application Support/TeamCalendar/library.json`. Preview requests connect directly to feed providers; FBS links are resolved on demand using public team identifiers and then saved locally.

Offline tests cover catalog expectations, parsing, recurrence, routing, provider behavior, persistence, and approval state. CI runs tests and builds/signature-checks the app on Apple Silicon and Intel. Optional live verification is available through `python3 scripts/verify-feeds.py`.

See [validation notes](docs/VALIDATION.md) for the dated provider checks, manual UI coverage, and untested external-account flows.

## Contributing and license

[Contributing](CONTRIBUTING.md) covers setup, code conventions, native UI expectations, tests, and catalog maintenance.

Released under the [MIT license](LICENSE). External feeds and schedules remain subject to their publishers' terms. Team Calendar is not affiliated with any team, league, show, or feed provider.
