#!/bin/bash
# Downloads the pinned Sparkle release (the updater framework Arc ships) into
# vendor/sparkle: Sparkle.framework for the app, bin/ (generate_keys,
# sign_update) for releases. Safe to re-run; skips what is already there.
set -euo pipefail
cd "$(dirname "$0")/.."

SPARKLE_VERSION="2.10.0"
SPARKLE_SHA256="c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"

if [ "$(cat vendor/sparkle/VERSION 2>/dev/null)" != "$SPARKLE_VERSION" ]; then
  echo "Downloading Sparkle ${SPARKLE_VERSION}..."
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  # GitHub's DNS can fail briefly on a runner; ordinary --retry does not cover every DNS error.
  # Bound both individual transfers and retries, and keep checksum verification mandatory below.
  curl -fL --progress-bar --retry 2 --retry-all-errors --retry-delay 5 \
    --connect-timeout 15 --max-time 180 --retry-max-time 300 -o "$TMP/Sparkle.tar.xz" \
    "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
  echo "${SPARKLE_SHA256}  $TMP/Sparkle.tar.xz" | shasum -a 256 -c - >/dev/null
  mkdir "$TMP/x"
  tar -xJf "$TMP/Sparkle.tar.xz" -C "$TMP/x"
  rm -rf vendor/sparkle
  mkdir -p vendor/sparkle
  mv "$TMP/x/Sparkle.framework" "$TMP/x/bin" "$TMP/x/LICENSE" vendor/sparkle/
  echo "$SPARKLE_VERSION" > vendor/sparkle/VERSION
fi
echo "Sparkle ready: vendor/sparkle"
