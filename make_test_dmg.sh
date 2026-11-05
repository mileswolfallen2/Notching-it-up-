#!/usr/bin/env bash
# make_test_dmg.sh
# Build a Release copy of Notching it up and package it as a DMG for final testing.
#
# Usage:
#   ./make_test_dmg.sh            Incremental Release build, then create the DMG.
#   ./make_test_dmg.sh --clean    Wipe the test build folder before building.
#
# Output:
#   Release/Notching-it-up-<version>-<build>-test.dmg
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

PROJECT="noching.xcodeproj"
SCHEME="boringNotch"
APP_NAME="Notching it up"
CONFIGURATION="Release"
BUILD_ROOT="$REPO_ROOT/build/TestDMG"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
RELEASE_DIR="$REPO_ROOT/Release"
LOG_FILE="$BUILD_ROOT/xcodebuild.log"

CLEAN=0
for arg in "$@"; do
    case "$arg" in
        --clean)
            CLEAN=1
            ;;
        -h|--help)
            sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown option: $arg" >&2
            echo "Usage: $0 [--clean]" >&2
            exit 1
            ;;
    esac
done

STAGING=""
cleanup() {
    if [[ -n "$STAGING" && -d "$STAGING" ]]; then
        rm -rf "$STAGING"
    fi
}
trap cleanup EXIT

mkdir -p "$BUILD_ROOT" "$RELEASE_DIR"

if [[ "$CLEAN" -eq 1 ]]; then
    echo "Cleaning test build folder…"
    rm -rf "$DERIVED_DATA"
fi

# ── Build ─────────────────────────────────────────────────────────────────────
echo "Building ${APP_NAME} (${CONFIGURATION})…"
echo "Build log: ${LOG_FILE}"

# Hardened runtime stays off for this local test image. The bundled
# MediaRemoteAdapter framework is ad-hoc signed, and macOS library validation
# rejects it when an ad-hoc app enables the hardened runtime. The release
# script handles signing separately.

if ! xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    ENABLE_HARDENED_RUNTIME=NO \
    build > "$LOG_FILE" 2>&1
then
    echo "" >&2
    echo "Build failed. Last 80 lines of ${LOG_FILE}:" >&2
    tail -n 80 "$LOG_FILE" >&2
    exit 1
fi

APP_PATH="$DERIVED_DATA/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
if [[ ! -d "$APP_PATH" ]]; then
    APP_PATH="$(find "$DERIVED_DATA/Build/Products" -maxdepth 3 -type d -name "${APP_NAME}.app" 2>/dev/null | head -n 1)"
fi
if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
    echo "Error: could not find the built app in ${DERIVED_DATA}/Build/Products." >&2
    exit 1
fi

PLIST="$APP_PATH/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST" 2>/dev/null || echo "unknown")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST" 2>/dev/null || echo "unknown")"

# ── Verify the app is signed ──────────────────────────────────────────────────
if ! codesign --verify --deep --strict "$APP_PATH" >/dev/null 2>&1; then
    echo "Error: ${APP_NAME}.app failed code-signature verification." >&2
    echo "Open the project in Xcode, check Signing & Capabilities, and try again." >&2
    exit 1
fi
echo "Code signature verified."

# ── Stage the app with an Applications shortcut ───────────────────────────────
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/notching-test-dmg.XXXXXX")"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# ── Create the DMG ────────────────────────────────────────────────────────────
OUTPUT_DMG="${RELEASE_DIR}/Notching-it-up-${VERSION}-${BUILD_NUMBER}-test.dmg"
rm -f "$OUTPUT_DMG"

echo "Creating DMG…"
hdiutil create \
    -volname "${APP_NAME} ${VERSION}" \
    -srcfolder "$STAGING" \
    -ov \
    -fs HFS+ \
    -format UDZO \
    "$OUTPUT_DMG" >/dev/null

hdiutil verify "$OUTPUT_DMG" >/dev/null
SIZE="$(du -h "$OUTPUT_DMG" | awk '{print $1}')"

echo ""
echo "Done."
echo "  App:     ${APP_PATH}"
echo "  Version: ${VERSION} (build ${BUILD_NUMBER})"
echo "  DMG:     ${OUTPUT_DMG}"
echo "  Size:    ${SIZE}"
echo ""
echo "Mount the DMG and drag ${APP_NAME} into Applications to test the final build."
