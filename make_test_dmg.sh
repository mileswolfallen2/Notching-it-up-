#!/usr/bin/env bash
# make_test_dmg.sh
# Creates Release/test.dmg from the built app using only built-in macOS tools.
# No dmgbuild or other Python dependencies required.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="$REPO_DIR/Release/Notching it up.app"
OUTPUT_DMG="$REPO_DIR/Release/test.dmg"
VOLUME_NAME="Notching it up"

# ── Sanity checks ──────────────────────────────────────────────────────────────
if [ ! -d "$APP_PATH" ]; then
  echo "Error: App not found at: $APP_PATH" >&2
  echo "Build the project first (Product → Archive, or xcodebuild)." >&2
  exit 1
fi

# ── Remove any existing test.dmg ──────────────────────────────────────────────
[ -f "$OUTPUT_DMG" ] && rm "$OUTPUT_DMG"

# ── Build a staging folder ────────────────────────────────────────────────────
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "$APP_PATH" "$STAGING/"
# Add an /Applications symlink so users can drag-to-install
ln -s /Applications "$STAGING/Applications"

# ── Calculate a size with 20 MB headroom ─────────────────────────────────────
APP_SIZE_KB=$(du -sk "$APP_PATH" | awk '{print $1}')
DMG_SIZE_KB=$(( APP_SIZE_KB + 20480 ))

# ── Create the DMG ────────────────────────────────────────────────────────────
echo "Creating test.dmg (${DMG_SIZE_KB} KB)…"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING" \
  -ov \
  -fs HFS+ \
  -format UDZO \
  "$OUTPUT_DMG"

echo "Done → $OUTPUT_DMG"
