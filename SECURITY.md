# Security Policy

## Supported Versions

This is a small unofficial utility. Only the latest commit on `main` is supported.

## Reporting A Vulnerability

Please open a private GitHub security advisory if available, or contact the repository owner.

Do not paste Codex auth tokens, `~/.codex/auth.json`, screenshots containing secrets, or bearer tokens into public issues.

## Public Repository Checks

Run `./script/check_secrets.sh` before pushing. It scans all reachable Git history
with official Gitleaks v8.30.1, pinned by container digest, using Docker. The
scanner has no network access during the scan, mounts the repository read-only,
and fully redacts findings. No test directories or credential rules are excluded.
CI also runs this scan with complete history on pull requests, main pushes, and
release tags; builds and release uploads depend on a successful scan.

Install the local push guard once per clone, after checking that the destination
does not contain a custom hook you need to preserve:

```bash
cp .githooks/pre-push "$(git rev-parse --git-path hooks/pre-push)"
```

The hook blocks a push when a finding occurs or the scanner cannot run. Docker
must be available. Git hooks can be bypassed, so keep CI and review in place too.
The existing release checks separately inspect app/helper strings and ensure the
Claude helper persists only derived reports, never raw input or credentials.

On 2026-09-07, a read-only audit of the public fork found no credentials in
41 commits across its advertised refs or six published release archives through
v0.7.2. Supplementary checks covered session-cookie/token patterns, account IDs,
email-like strings, sensitive filenames, and public PR/release metadata. Matches
were synthetic fixtures, upstream author/path metadata, and public image-signing
certificate contacts. This is a bounded audit result, not a guarantee that a
scanner can recognize every possible secret. Do not commit real usage screenshots,
auth/cookie files, diagnostic output, or private account reports.

## Runtime Handling

Codex Reset Watcher:

- reads the local Codex Desktop auth file at `~/.codex/auth.json`
- may read account name or email claims from the local Codex ID token only to
  label the active account in the UI
- sends the saved Codex bearer token only to:
  - `https://chatgpt.com/backend-api/wham/usage`
  - `https://chatgpt.com/backend-api/wham/rate-limit-reset-credits`
- rejects non-exact endpoint URLs before a request is sent, including URLs with
  another host, another path, userinfo, query string, fragment, or custom port
- rejects redirects when the final response URL is not one of those exact
  trusted endpoints
- rejects empty auth tokens before a request is sent
- rejects semantically empty or unrecognized successful JSON responses instead
  of treating them as valid zero-data responses
- sends the active account id in the `ChatGPT-Account-Id` header to those same endpoints when Codex auth exposes it
- does not redeem resets
- does not write to the auth file
- does not store tokens elsewhere
- stores only minimized derived multi-account snapshots under Application
  Support
- stores account snapshot keys as salted hashes, not full account IDs
- does not store bearer tokens, refresh tokens, ID tokens, raw auth JSON, raw
  endpoint JSON, full account IDs, user IDs, cookies, API keys, or reset credit
  IDs in snapshots
- does not include analytics or telemetry
- uses a dedicated stateless URL session without shared cookies, URL cache, or
  credential persistence for refresh calls

Each refresh loads one auth context and uses it for both usage and reset-credit
requests so the app does not mix account identities if Codex Desktop changes
login mid-refresh.

The endpoint is internal and may change without notice.
