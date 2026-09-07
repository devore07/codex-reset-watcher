#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Gitleaks v8.30.1, pinned to the official multi-platform image digest.
SCANNER_IMAGE="ghcr.io/gitleaks/gitleaks@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f"

if ! command -v docker >/dev/null 2>&1; then
  echo "Secret check requires Docker. Start Docker and retry; the push has not been checked." >&2
  exit 1
fi

# Scan every locally reachable commit, including the outgoing branch. No raw
# findings or secret values are written to the repository or printed to logs.
docker run --rm --network none \
  -v "$ROOT_DIR:/repo:ro" \
  "$SCANNER_IMAGE" git /repo --log-opts="--all" --redact=100 --no-banner
