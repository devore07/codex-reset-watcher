# Codex Reset Watcher

<img src="Assets/AppIcon.png" width="128" alt="Codex Reset Watcher icon">

Unofficial macOS utility for checking Codex rate-limit windows and banked reset credits, with optional Claude Pro/Max usage through Claude Desktop or terminal Claude Code.

It reads your existing local Codex Desktop login from `~/.codex/auth.json`, calls the same internal Codex Desktop endpoints used by the app, and shows:

- a desktop **Dashboard** with Codex usage and reset credits on the left and
  Claude usage on the right, with shared Refresh and appearance controls
- current weekly usage remaining
- usage bars that turn green, amber, or red based on remaining capacity
- weekly menu bar status with remaining capacity and reset weekday, for example
  `57% | Sunday`
- a natural-height menu dropdown with no forced full-screen viewport
- Light, Dark, and Auto appearance modes shared by the menu dropdown and main
  window
- active account label from the current local Codex login or usage response
- cached snapshots for previously seen Codex accounts, labeled separately from
  the active account
- blocked-limit states when Codex says a usage window is unavailable now
- honest loading, partial, signed-out, and endpoint-failure states instead of
  presenting missing data as zero or fresh live numbers
- banked reset credits and expiry dates
- explicit unavailable-expiry rows when Codex reports a reset count but omits a
  usable expiry record
- expiry urgency warnings as reset credits get closer to lapsing
- a reset-use nudge based on remaining 5h/weekly capacity, reset timing, reset-credit expiry, and reset credits in the bank

Codex Reset Watcher is read-only. It does not redeem resets, reset usage, modify your account, or send analytics.

## Requirements

- macOS 14 or newer
- Codex Desktop installed and signed in

No API key is required.

## Claude subscription usage

Choose **Claude Desktop** to check usage without a CLI or browser extension:

1. Sign into the Claude desktop app with your Pro/Max subscription.
2. In the watcher, select **Claude subscription**, choose **Claude Desktop**, and
   click **Connect Claude**.
3. Allow access to **Claude Safe Storage** if macOS requests it. Choose the
   system permission appropriate for you; the watcher never changes Keychain
   access rules itself. If access is denied or later unavailable, use
   **Reconnect Desktop** to try again.

This source reads only `sessionKey` and `lastActiveOrg` from Claude Desktop's
local cookie database, opened read-only, and uses macOS Keychain to decrypt
Chromium v10 cookies (supported database schemas 23 and 24). Schema 24's domain
hash is verified. It sends the session cookie over HTTPS only to
`https://claude.ai/api/organizations/<organization>/usage`. Redirects are refused.
This is an **unofficial internal endpoint**, not a supported Anthropic public API;
login, encryption, or endpoint changes may stop the connection from working.

Checks run every five minutes and on **Refresh**, including when you use only
Claude desktop or web. The desktop app must have an existing saved login; it
need not supply terminal activity. HTTP 429 pauses all usage checks, including
manual refresh, for 15 minutes. No messages are sent, no credits are redeemed,
and no account settings are changed. API billing and other model-specific allowances
are excluded. Only one currently selected Claude subscription is shown.

Session cookies, Keychain secrets, organization identifiers, and raw responses
stay in memory and are never logged or written to watcher storage. Desktop
reports also stay in memory; restart fetches them again. The only saved Desktop
setting is a private `desktop-enabled` marker in the watcher's Claude support
directory. The request uses a stateless session without shared cookies or cache.
Desktop account changes discard previous account values; unavailable login
states clear them. Network failures retain the original receipt timestamp.
**Disconnect Claude** stops polling without changing Claude's login. Disconnect
before switching sources; the terminal helper remains credential-free.

The implementation was validated on macOS with a real Desktop login on
2026-09-06: a single read-only request returned both usage windows. Comparison
against the visible Claude Usage screen remains a manual verification step.
Technical references: [Chromium cookie format](https://chromium.googlesource.com/chromium/src/net/+/master/extras/sqlite/sqlite_persistent_cookie_store.cc)
and an [existing independent Desktop usage implementation](https://github.com/skibidiskib/claude-web-usage).

### Fable weekly allowance

The Desktop source also reads Fable entries from the existing usage response's
`limits` array (`kind: weekly_scoped`, `scope.model.display_name`, `percent`, and
`resets_at`). It shows a separate **Fable weekly** meter in the dropdown and
Claude details. Percentages are already 0–100; remaining is 100 minus percent.
Each reported Fable bucket keeps its own reset time. Missing timing stays
unavailable, expired timing waits for an update, and conflicting duplicates
stay unknown. A missing Fable bucket shows **Not reported by Claude**, never
zero or 100%. Only allowlisted Fable names and derived usage/timing survive
decoding; arbitrary model metadata is discarded. No extra network requests or
Keychain prompts are added.

As checked on 2026-09-06, [Anthropic's plan documentation](https://support.claude.com/en/articles/15424964-claude-fable-models-on-your-plan)
says Pro uses paid usage credits for Fable, while Max and certain premium team
seats include a separate weekly allowance. The watcher displays what the server
reports and does not infer entitlement from a plan label. Paid credit balances
are not included. The terminal status-line feed still supplies only its two
documented overall windows and labels Fable **Not supplied by CLI feed**; select
Desktop for Fable checks. Using Desktop as the monitoring source does not stop
you using Claude Code CLI for your work.

### Alternative: terminal status-line feed

The terminal source shows five-hour and weekly remaining percentages,
reset times, and when a local report was received. The menu-bar title continues
to show Codex weekly capacity. Claude and Codex appear as separate groups in
the dropdown; select **Claude subscription** in the desktop sidebar for setup.

**Terminal Claude Code 2.1.251 or later is required. The Claude desktop Code tab
does not supply this status-line feed.** You can use the terminal alongside
desktop, signed into the same Pro/Max subscription. Desktop or web activity is
reflected only when terminal Claude Code reports the shared subscription limits.
This integration does not independently poll Anthropic, and does not infer
remaining allowance from token counts or session cost.

1. Open the desktop window and select **Claude subscription**.
2. Check the configuration directory (normally `~/.claude`) and Claude Code
   executable. The app detects standard CLI installations and compatible native
   engines already downloaded by Claude Desktop. **Choose…** supports other paths.
3. Click **Connect Claude**. This explicit action installs a helper in
   `~/Library/Application Support/Codex Reset Watcher/Claude` and updates only the
   selected `settings.json` status-line command. Existing commands keep their
   original input/output; other settings and status-line options are preserved.
4. Run that Claude Code executable in a terminal, sign in through Claude Code if
   needed, and use a session. Usage fields normally arrive after the first API
   response. The watcher never signs in, reads credentials, or sends a prompt.

If the app stays at **Waiting for Claude Code**, verify the terminal session uses
the selected configuration, the account is Pro/Max, and project-level settings
do not override `statusLine`. A bundled desktop engine is usable as a terminal
executable, but simply running the desktop Code tab does not activate this feed.
See the [official status-line documentation](https://code.claude.com/docs/en/statusline).

Reports are observations, not proof of a fresh server check. After five minutes,
values are labeled **Last reported**. A passed reset time becomes **Awaiting
updated usage**, never an assumed 100%. Missing windows stay unknown, and read
failures retain an older valid report only with its original receipt time and
an unavailable status. **Refresh** rereads the local report; it cannot request
a new Claude server reading. Only one Claude subscription is supported; no
account identity is inferred and no Claude account history is kept.

**Disconnect Claude** restores the previous command if the watcher still owns
the setting, preserving later edits to unrelated options. A replacement command
is never overwritten. The usage report is removed. An inert helper and minimal
command recovery metadata remain so already-running sessions can continue
forwarding to the previous command; the watcher does not read login information. To remove
these files entirely, first close terminal sessions and remove any project-level
references to the helper, then delete the dedicated Claude support directory.
After an app upgrade, disconnect and reconnect to install its updated helper.

Only percentages, reset times, a receipt timestamp, a startup-waiting flag, and a schema version are
stored in `usage.json`, with private permissions and serialized atomic writes.
Raw status-line input, transcripts, tokens, cookies, account IDs, and API keys
are not stored. The terminal source makes no Claude network requests. Existing status-line
commands continue to run under the user's original configuration.

## Install

1. Download the versioned zip asset from the latest GitHub release, for example
   `Codex.Reset.Watcher.v0.5.1.zip`.
2. Unzip it.
3. Drag `Codex Reset Watcher.app` into `/Applications`.
4. Open it.

If macOS warns that the app is from an unidentified developer, right-click the app and choose **Open**. Public distribution should use a Developer ID signed and notarized build.

## Build From Source

```bash
git clone https://github.com/devore07/codex-reset-watcher.git
cd codex-reset-watcher
./script/build_and_run.sh --package
open "dist/Codex Reset Watcher.app"
```

The script uses SwiftPM and writes SwiftPM scratch files under `/tmp/codex-reset-watcher-build` to avoid file-provider issues in synced folders.

### Verification

The portable helper and connection tests run in a tagged container:

```bash
docker build -t codex-reset-watcher:claude-tests .
docker run --rm codex-reset-watcher:claude-tests
```

The SwiftUI app requires the native macOS SDK. No additional host packages are
needed for these checks:

```bash
swift test --scratch-path /tmp/codex-reset-watcher-test --jobs 1
CONFIGURATION=release ./script/package.sh
bash script/verify_claude_package.sh
CONFIGURATION=release ./script/build_and_run.sh --verify
```

The packaged helper check uses synthetic input and isolated temporary settings.
It covers command forwarding, exit codes, permissions, concurrent invocations,
privacy, and disconnect behavior. Native tests also cover stale/partial reports,
directory observation, provider independence, and menu sizing in all appearances.
Real-account validation still requires a signed-in terminal Claude Code session
and a comparison with its usage display.

## Nudge Logic

The app uses rule-based advice from the data Codex returns for the current signed-in account. It does not use account-specific hardcoding.

- Low weekly room, resets banked, and weekly refresh far away: push the work and use a reset if Codex blocks meaningful work.
- Healthy weekly room but low 5-hour room: wait if the 5-hour refill is close, but treat it as a deadline call if the refill is still hours away.
- Healthy weekly room with weekly refresh close: keep the reset banked.
- Reset credit expiring today: show a use-it-or-lose-it warning before conservative hold advice.
- Codex says a limit is blocked now: show a blocked state before normal reset
  advice, even if the percentage fields still decode.
- A low 5-hour window with no banked reset says to wait for the refill rather
  than implying that a reset can be used.
- Cached snapshots show last-seen data and neutral copy; they never generate
  live spend/hold advice.

Reset-credit rows also change urgency as expiry gets close: available, this week, expires soon, ends today, or expired.

## Multi-Account Snapshots

The active Codex account is always the one currently signed into Codex Desktop.
Codex Reset Watcher does not switch accounts for you, and it does not show
multiple accounts as simultaneous live dashboards.

After a successful refresh, the app saves a minimized local snapshot for that
account. If you later sign into a different Codex account, the current account
updates live and previously seen accounts appear under **Cached snapshots** as
cached snapshots.

Cached snapshots are last-seen records, not live dashboards. They are labeled
`Cached snapshot` or `Stale snapshot`, and they refresh only when that account
becomes the active Codex Desktop login again.

Use `Forget stale` to remove a selected stale snapshot, or `Clear stale` to
remove stale snapshots without clearing every cached record.

The snapshot model is covered by unit tests for account-switch races,
same-label accounts with different account IDs, stale cleanup, invalid auth,
partial endpoint failures, corrupt snapshot files, and sensitive-field
redaction. Manual QA should still include signing into a second real Codex
Desktop account before claiming a specific cross-account login flow works in a
new environment.

Snapshots are stored locally at:

```text
~/Library/Application Support/Codex Reset Watcher/account-snapshots.json
```

The app stores derived fields such as display label, plan label, last checked
time, 5-hour/weekly percentages, reset times, reset count, and reset expiry
dates. It does not store Codex bearer tokens, refresh tokens, ID tokens, raw
auth JSON, raw endpoint responses, full account IDs, user IDs, cookies, API
keys, or reset credit IDs.

## Visual Assets

`Assets/AppIconSource.png` and `Assets/UsageHeader.png` are AI-generated artwork created for this project. They are included with the MIT-licensed source and are not OpenAI logos or product marks.

## Design System

Shared visual tokens live in `Sources/CodexResetWatcher/Support/CodexPalette.swift`
and `Sources/CodexResetWatcher/Support/CodexStyle.swift`, with semantic tones
in `Sources/CodexResetWatcher/Support/CodexTone.swift`. Use those colors,
spacing values, radii, typography styles, meters, and panel/row modifiers for
menu and desktop UI changes so the app stays visually consistent. See
[DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) before making visual changes.

The menu dropdown uses its natural content height: it must not be stretched to
the screen height or wrapped in a forced-height viewport. Its section order is
`Display settings`, `Current limits`, and `Banked Resets Expiration`, followed
by the nudge. Cached snapshots remain available in the full desktop app and are
not repeated in the menu dropdown.

The compact macOS menu bar title shows the live weekly remaining percentage and
reset weekday, for example `57% | Sunday`. There is no display-metric selector
while Codex is not returning the former 5-hour window. Missing reset timing uses
`week`, and missing weekly data uses `--% | week`; banked reset counts never
replace the weekly status.

The former Week/5h display design is intentionally preserved for a future
return of the 5-hour limit. See [MENU_BAR_DISPLAY_PLAN.md](MENU_BAR_DISPLAY_PLAN.md).

## What It Calls

```text
GET https://chatgpt.com/backend-api/wham/usage
GET https://chatgpt.com/backend-api/wham/rate-limit-reset-credits
```

Headers are built from the existing Codex Desktop auth file. The app loads one
auth context per refresh, sends the saved bearer token in the `Authorization`
header and, when available, the active account id in the `ChatGPT-Account-Id`
header to those endpoints. It does not redeem resets, mutate account state, or
store your token anywhere else.

The app rejects non-exact endpoint URLs before sending a request and rejects
redirects away from those URLs. The trusted URLs must be HTTPS `chatgpt.com`
endpoints on the known `/backend-api/wham/...` paths, with no query string,
fragment, userinfo, or custom port. Empty, HTML, and semantically unrecognized
successful responses are treated as errors instead of clearing valid state.

`/wham/usage` currently provides the weekly rate-limit window. The decoder
remains tolerant of older or variant window payloads. `/wham/rate-limit-reset-credits`
provides detailed reset-credit expiry dates. These endpoints are internal and
can change without notice.

## Privacy

See [PRIVACY.md](PRIVACY.md).

## Limitations

- This is unofficial and not affiliated with OpenAI.
- The endpoints are internal and may change without notice.
- Usage and reset-credit fields may differ by Codex plan, account type, region, or app version.
- The release app is ad-hoc signed unless a maintainer publishes a Developer ID notarized build.

## Maintainers

Current progress, decisions, and future-agent notes live in
[PROJECT_STATUS.md](PROJECT_STATUS.md), [AGENTS.md](AGENTS.md), and
[MULTI_ACCOUNT_PLAN.md](MULTI_ACCOUNT_PLAN.md).

Run tests:

```bash
swift test --scratch-path /tmp/codex-reset-watcher-test --jobs 1
```

Package a release zip:

```bash
./script/package.sh
```

Regenerate the icon:

```bash
python3 -m pip install pillow
./script/make_icon.py
```

## License

MIT. See [LICENSE](LICENSE).
