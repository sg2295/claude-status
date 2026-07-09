# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project scope

ClaudeStatus is a macOS menu bar app (SwiftUI `MenuBarExtra`, no Dock icon) that tracks
https://status.claude.com. The icon reacts only to the "claude.ai" and "Claude Code"
components. The icon is the Claude Code mascot (Clawd) drawn as a code-defined pixel
grid in StatusIconRenderer, in labelColor (white on a dark menu bar), with a status
dot badge at bottom right (green = operational, orange = degraded, red = major outage,
gray = unreachable). Clicking it opens a panel that re-renders the site's uptime section:
one card per service with status label, 90 colored day-bars, uptime percentage, and
hover tooltips.

## Commands

```
make run                              # build, assemble+sign bundle, launch
make check                            # parser selftest against the live site
make check FIXTURE=fixtures/homepage.html   # selftest against a local fixture
make fixtures                         # download homepage.html + summary.json into fixtures/
make install                          # copy bundle to ~/Applications and launch
```

There is no XCTest: the machine has Command Line Tools only (no Xcode, no `xcodebuild`,
no asset catalogs). The regression test is the binary's `--selftest [file.html]` mode
(SelfTest.swift), wired to `make check`. Run it after any change to the parsing layer,
and run `make fixtures` first so a fixture-based run works offline.

Build is plain `swift build -c release`; the `.app` bundle (LSUIElement, ad-hoc codesign)
is assembled by the Makefile `app` target from `Resources/Info.plist`.

## Architecture: two data sources, on purpose

1. `GET /api/v2/summary.json` (official Statuspage API) - polled every 90s by
   StatusStore for the icon state and the per-component status labels.
2. `GET /` (homepage HTML) - fetched on panel open (5 min TTL) and parsed by
   HomepageUptimeParser for the 90-day bars. The HTML embeds three things:
   `uptimeValues` (the exact displayed percentages), per-day SVG `<rect>` fills
   (the exact bar colors), and `uptimeData` (dates, outage seconds, incident names
   for tooltips).

Do NOT switch the bars to `/uptime/{id}.json`: it only returns the current calendar
quarter, not the trailing 90 days, and ignores date-range params. The homepage is the
only public source of the 90-day window. If `uptimeValues` ever disappears, the
fallback formula is `uptime = 1 - (m + 0.3*p) / (elapsed_days * 86400)` from
uptimeData's day-level outage seconds (documented in the parser).

Degradation is layered by design: summary.json alone renders name + status cards;
bars and tooltips are optional layers that soft-fail independently. Parser failures
must never propagate past StatusStore - a Statuspage template change should produce
status-only cards plus a footer hint, not a crash. `make check` is the canary when
the site's markup changes.

Data flow: StatusAPIClient (fetch) -> HomepageUptimeParser (extract) ->
StatusStore (@MainActor @Observable; polling, TTL cache, iconState) ->
StatusIconRenderer (NSImage per IconState) + Views/ (panel).

## Conventions and constraints

- ASCII only in every file, no em-dashes (user requirement). Check before committing:
  `LC_ALL=C grep -rnP '[^\x00-\x7F]' Sources Resources Makefile Package.swift` must
  return nothing. For this reason fetched fixtures are gitignored, never committed.
- Swift 6 language mode with strict concurrency; the design that keeps it clean is
  value-type models (Sendable structs), one `@MainActor` store, and a `Sendable`
  stateless client. Keep new code in that shape.
- Tracked components are matched by name ("claude.ai", "Claude Code") OR id
  (`rwppv331jlwc`, `yyzkbfz2thpt`) so either a rename or an id change alone does not
  break tracking.

## Gotchas

- The MenuBarExtra `.window` panel sizes to its content's ideal height. `ScrollView`
  (and other views without intrinsic height) collapse to zero there - the card list
  is a plain VStack for that reason. Test any panel layout change by actually opening
  the panel.
- `open` does not pass environment variables. Testing hooks must be run against the
  bundle binary directly:
  `CLAUDE_STATUS_FORCE_STATE=degraded build/ClaudeStatus.app/Contents/MacOS/ClaudeStatus`
  (values: operational|degraded|major|unknown), and `CLAUDE_STATUS_BASE_URL=http://...`
  to point both fetches at a mock server.
- `--selftest` must run before AppKit starts (Main.swift dispatches it ahead of
  `ClaudeStatusApp.main()`); keep it that way or the selftest spawns a menu bar icon.
- The panel's `.task` runs on every open (window-style MenuBarExtra recreates its
  content view each time); the uptime TTL check lives there, not in a timer.
