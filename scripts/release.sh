#!/bin/bash
# Builds the app, sends it to Apple for notarization, staples the ticket and zips it:
#   build/Meme-Lab-<version>.zip
# Needs the Developer ID Application identity and a notarytool keychain profile, named by NOTARY_PROFILE
# (default "onair"; create one with `xcrun notarytool store-credentials`).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
VERSION="$(cat VERSION)"
APP="$ROOT/build/Tim's Astonishing Meme Laboratory.app"
ZIP="$ROOT/build/Meme-Lab-$VERSION.zip"
./scripts/build-app.sh
codesign -dv "$APP" 2>&1 | grep -q "Authority=Developer ID Application" || { echo "The app is not signed with a Developer ID; it cannot be notarized."; exit 1; }
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "${NOTARY_PROFILE:-onair}" --wait
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
spctl -a -vv -t exec "$APP"
shasum -a 256 "$ZIP"
echo "built $ZIP"
