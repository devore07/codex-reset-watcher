# Menu Bar Display Plan

## Current Weekly Provider Rotation

Codex currently returns the weekly usage window but not the former 5-hour
window. Until that changes:

- The menu bar alternates Codex and connected Claude every 10 seconds, starting
  with Codex. It stays on Codex when Claude is disconnected.
- Use the OpenAI knot for Codex and the Claude starburst for Claude, plus the
  service name: `Codex 57% | Sunday`, `Claude 80% | Monday`.
- Claude uses only its overall weekly window. Old/failed observations append `*`
  to the percentage; the tooltip explains that marker and gives exact reset and
  receipt times. Passed resets show `Claude --% | updating`.
- Rotation is presentation only; it never triggers network refreshes.
- If the reset weekday is unavailable, use `57% | week`.
- If weekly usage is unavailable, use `--% | week`.
- Banked reset counts never replace the usage title.
- The dropdown has no Week/5h selector; Display settings contains Appearance.
- The weekly limit row is the highlighted menu-bar source.

Keep the decoder tolerant of 5-hour payloads. Keep 5-hour snapshot fields and
nudge logic intact so older snapshots remain readable and the feature can
return without a data migration.

## Restore When 5h Returns

Restore the selector only after the live endpoint reliably returns a recognized
5-hour window again. The prior design contract was:

- Add a persisted `Menu bar` segmented control with `Week` and `5h` options.
- `Week` title: remaining percentage plus weekly reset weekday, such as
  `57% | Sunday`.
- `5h` title: remaining percentage plus 5-hour reset time, such as
  `80% | 9:50 PM`.
- Highlight the usage row selected for the menu bar title.
- Keep reset counts, account labels, and status sentences out of the title.
- If the selected window is temporarily missing, do not substitute reset-credit
  data. Show an honest placeholder for that metric.

Before release, test both endpoint orders, a missing selected window, missing
reset timing, blocked windows, app relaunch persistence, and the real macOS menu
bar rendering. Update `README.md`, `AGENTS.md`, `DESIGN_SYSTEM.md`,
`PROJECT_STATUS.md`, and `CHANGELOG.md` when the selector returns.
