#!/bin/bash
# Builds "build/Tim's Astonishing Meme Laboratory.app" for Apple silicon and Intel. Signs it with the Developer ID
# Application identity when one is installed (hardened runtime, ready to notarize), otherwise ad hoc.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
NAME="Tim's Astonishing Meme Laboratory"
VERSION="$(cat VERSION)"
grep -q "version = \"$VERSION\"" Sources/MemeCore/Support.swift || { echo "VERSION ($VERSION) and About.version in Support.swift differ"; exit 1; }
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/MemeLab"
APP="$ROOT/build/$NAME.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MemeLab"

SET="$ROOT/build/AppIcon.iconset"; rm -rf "$SET"; mkdir -p "$SET"
"$BIN" --icon "$ROOT/build/icon-1024.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$ROOT/build/icon-1024.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$ROOT/build/icon-1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.timgailey.MemeLab</string>
  <key>CFBundleName</key><string>Meme Lab</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleExecutable</key><string>MemeLab</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Tim Gailey. MIT License.</string>
</dict></plist>
PLIST

ID="${SIGN_ID:-$(security find-identity -v -p codesigning | awk '/Developer ID Application/ {print $2; exit}')}"
if [ -n "$ID" ]; then
  codesign --force --options runtime --timestamp --sign "$ID" "$APP"
else
  codesign --force --sign - "$APP"
fi
echo "built $APP"
