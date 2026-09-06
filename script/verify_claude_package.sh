#!/usr/bin/env bash
set -euo pipefail
APP_BUNDLE="${1:-dist/Codex Reset Watcher.app}"
HELPER="$APP_BUNDLE/Contents/Helpers/ClaudeUsageBridge"
test -x "$HELPER"
ARCHS="$(/usr/bin/lipo -archs "$HELPER")"
for REQUIRED_ARCH in arm64 x86_64; do
  if [[ " $ARCHS " != *" $REQUIRED_ARCH "* ]]; then
    echo "Claude helper is missing $REQUIRED_ARCH" >&2
    exit 1
  fi
done
/usr/bin/codesign --verify --strict "$HELPER"
STRINGS_OUTPUT="$(mktemp)"
trap 'rm -f "$STRINGS_OUTPUT"' EXIT
strings -a "$HELPER" > "$STRINGS_OUTPUT"
SECRET_PATTERN='([[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,})|(eyJ[[:alnum:]_-]{10,}\.[[:alnum:]_-]{10,}\.[[:alnum:]_-]{10,})|(sk-ant-[[:alnum:]_-]{12,})|(Bearer[[:space:]]+[[:alnum:]_.-]{16,})|(/Users/[^[:space:]]+/\.claude/)|(\{"rate_limits"[[:space:]]*:)'
if grep -Eq "$SECRET_PATTERN" "$STRINGS_OUTPUT"; then
  echo "Claude helper contains a possible private value or raw payload; inspect locally without publishing matches." >&2
  exit 1
fi
python3 script/verify_claude_bridge.py "$HELPER"
