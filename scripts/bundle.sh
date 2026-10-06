#!/bin/sh
# Build SplitPreventer.app and a release zip.
# VERSION: bundle version (default 0.0.0). SIGN_IDENTITY: codesign identity (default: ad-hoc).
set -eu
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.0.0}"

swift build -c release
APP=build/SplitPreventer.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/SplitPreventer "$APP/Contents/MacOS/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>io.github.mudream4869.SplitPreventer</string>
    <key>CFBundleName</key><string>SplitPreventer</string>
    <key>CFBundleExecutable</key><string>SplitPreventer</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"

ZIP="build/SplitPreventer-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "built $APP, $ZIP"
