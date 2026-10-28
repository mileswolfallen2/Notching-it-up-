#!/usr/bin/env zsh
# release.sh — Build, sign appcast, update appcast.xml, tag, and push a new release
# Usage: ./scripts/release.sh
# Run from the repo root.

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { print -P "%F{cyan}ℹ %f$*"; }
success() { print -P "%F{green}✔ %f$*"; }
warn()    { print -P "%F{yellow}⚠ %f$*"; }
die()     { print -P "%F{red}✖ %f$*" >&2; exit 1; }

# ── Repo root ─────────────────────────────────────────────────────────────────
REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$REPO_ROOT"

APPCAST_PATH="updater/appcast.xml"
FEED_URL="https://raw.githubusercontent.com/mileswolfallen2/Notching-it-up-/main/updater/appcast.xml"
DOWNLOAD_BASE="https://github.com/mileswolfallen2/Notching-it-up-/releases/download"
PROJECT_NAME="boringNotch"
SCHEME="boringNotch"
APP_NAME="Notching it up"

# ── Find generate_appcast ─────────────────────────────────────────────────────
GENERATE_APPCAST=""
for candidate in \
    "/Users/miles/Library/Developer/Xcode/DerivedData/boringNotch-drwtzmthavqbtvchsdxydlanefqe/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast" \
    "/Users/miles/Library/Developer/Xcode/DerivedData/noching-faonocqigecsnadodxmfuwkyhrcl/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast" \
    "$(find ~/Library/Developer/Xcode/DerivedData -name 'generate_appcast' -path '*/artifacts/sparkle/*' 2>/dev/null | head -1)"
do
    if [[ -x "$candidate" ]]; then
        GENERATE_APPCAST="$candidate"
        break
    fi
done
[[ -n "$GENERATE_APPCAST" ]] || die "Could not find generate_appcast. Build the project in Xcode first so the Sparkle package is resolved."
info "Using generate_appcast: $GENERATE_APPCAST"

# ── Ask for version ───────────────────────────────────────────────────────────
echo ""
print -P "%F{cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%f"
print -P "%F{cyan}  Notching it up — Release Script%f"
print -P "%F{cyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%f"
echo ""

print -nP "%F{yellow}Enter the version number (e.g. b0.3.0 or 1.0.0): %f"
read VERSION
[[ -n "$VERSION" ]] || die "Version cannot be empty."
# Strip leading v if provided
VERSION="${VERSION#v}"
TAG="v${VERSION}"

# ── Ask for private key path ──────────────────────────────────────────────────
DEFAULT_KEY_PATH="$HOME/Desktop/sparkle_private_key.txt"
print -nP "%F{yellow}Path to Sparkle private key [${DEFAULT_KEY_PATH}]: %f"
read KEY_PATH
KEY_PATH="${KEY_PATH:-$DEFAULT_KEY_PATH}"
[[ -f "$KEY_PATH" ]] || die "Private key file not found at: $KEY_PATH"
success "Private key found."

# ── Check for uncommitted changes ─────────────────────────────────────────────
if ! git diff --quiet || ! git diff --cached --quiet; then
    warn "You have uncommitted changes:"
    git status --short
    print -nP "%F{yellow}Continue anyway? (y/N): %f"
    read CONFIRM
    [[ "${CONFIRM:l}" == "y" ]] || die "Aborted. Commit your changes first."
fi

# ── Archive in Xcode ─────────────────────────────────────────────────────────
echo ""
info "Archiving ${APP_NAME}…  (this takes a minute)"

ARCHIVE_PATH="$TMPDIR/${PROJECT_NAME}.xcarchive"
xcodebuild archive \
    -project "${PROJECT_NAME}.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    | xcpretty 2>/dev/null || true

[[ -d "$ARCHIVE_PATH" ]] || die "Archive failed — check Xcode build settings."
success "Archive created."

# ── Export .app ───────────────────────────────────────────────────────────────
info "Exporting app…"
EXPORT_DIR="$TMPDIR/${PROJECT_NAME}_export"
rm -rf "$EXPORT_DIR"

# Write a minimal export options plist
EXPORT_OPTIONS="$TMPDIR/ExportOptions.plist"
cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    | xcpretty 2>/dev/null || true

APP_PATH=$(find "$EXPORT_DIR" -name "*.app" -maxdepth 2 | head -1)
[[ -n "$APP_PATH" ]] || die "Export failed — .app not found in $EXPORT_DIR"
success "App exported: $(basename "$APP_PATH")"

# ── Create DMG ────────────────────────────────────────────────────────────────
info "Creating DMG…"
RELEASE_DIR="$REPO_ROOT/Release"
mkdir -p "$RELEASE_DIR"
DMG_PATH="${RELEASE_DIR}/${PROJECT_NAME}.dmg"
rm -f "$DMG_PATH"

hdiutil create \
    -volname "${APP_NAME} ${VERSION}" \
    -srcfolder "$APP_PATH" \
    -ov -format UDZO \
    "$DMG_PATH" \
    | grep -v "^$" || true

[[ -f "$DMG_PATH" ]] || die "DMG creation failed."
success "DMG created: $DMG_PATH"

# ── Generate signed appcast entry ─────────────────────────────────────────────
info "Generating signed appcast entry…"
NEW_APPCAST="$TMPDIR/new_appcast.xml"

"$GENERATE_APPCAST" \
    --ed-key-file "$KEY_PATH" \
    --link "https://github.com/mileswolfallen2/Notching-it-up-/releases" \
    --download-url-prefix "${DOWNLOAD_BASE}/${TAG}/" \
    -o "$NEW_APPCAST" \
    "$RELEASE_DIR/"

[[ -f "$NEW_APPCAST" ]] || die "generate_appcast produced no output."
success "Appcast entry generated."

# ── Merge new entry into existing appcast ─────────────────────────────────────
info "Merging into $APPCAST_PATH…"

python3 - <<PYEOF
import xml.etree.ElementTree as ET
import sys

ET.register_namespace('sparkle', 'http://www.andymatuschak.org/xml-namespaces/sparkle')
ET.register_namespace('dc', 'http://purl.org/dc/elements/1.1/')

existing = ET.parse('${APPCAST_PATH}')
new_cast = ET.parse('${NEW_APPCAST}')

existing_channel = existing.find('channel')
new_items = new_cast.findall('.//item')

if not new_items:
    print("No items found in generated appcast", file=sys.stderr)
    sys.exit(1)

# Prepend new items (newest first)
for i, item in enumerate(new_items):
    existing_channel.insert(i, item)

existing.write('${APPCAST_PATH}', xml_declaration=True, encoding='utf-8')
print(f"Merged {len(new_items)} item(s) into appcast.")
PYEOF

success "Appcast updated."

# ── Show the new appcast item for review ──────────────────────────────────────
echo ""
info "New appcast entry:"
python3 -c "
import xml.etree.ElementTree as ET
tree = ET.parse('${APPCAST_PATH}')
items = tree.findall('.//item')
if items:
    print(ET.tostring(items[0], encoding='unicode'))
"
echo ""

# ── Confirm before committing ─────────────────────────────────────────────────
print -nP "%F{yellow}Commit appcast, tag ${TAG}, and push? (y/N): %f"
read PUSH_CONFIRM
[[ "${PUSH_CONFIRM:l}" == "y" ]] || { warn "Stopped before push. Appcast is updated locally — review it and push manually."; exit 0; }

# ── Commit and tag ────────────────────────────────────────────────────────────
git add "$APPCAST_PATH"
git commit -m "Update appcast for ${TAG}"
git tag "$TAG"
git push origin main
git push origin "$TAG"

success "Done! Tag ${TAG} pushed."
echo ""
info "Next steps:"
echo "  1. Go to https://github.com/mileswolfallen2/Notching-it-up-/releases"
echo "  2. Create a release from tag ${TAG}"
echo "  3. Upload: ${DMG_PATH}"
echo "  4. Once published, Sparkle will serve the update automatically."
echo ""
