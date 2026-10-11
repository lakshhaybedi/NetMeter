#!/bin/sh
# Builds a universal (arm64 + x86_64) NetMeter.app, signed with the hardened runtime.
#   CODESIGN_IDENTITY  "Developer ID Application: Name (TEAMID)"; default "-" = ad-hoc (runs on this Mac only)
#   BUNDLE_ID          reverse-DNS id; default io.github.lakshhaybedi.NetMeter. Use your own if you fork.
#   COPYRIGHT          shown in the About panel
set -e
cd "$(dirname "$0")"
VERSION=$(cat VERSION)
BUILD=${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}
BUNDLE_ID=${BUNDLE_ID:-io.github.lakshhaybedi.NetMeter}
COPYRIGHT=${COPYRIGHT:-"Copyright © $(date +%Y) Lakshhay Bedi. All rights reserved."}
IDENT=${CODESIGN_IDENTITY:--}

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/NetMeter"

APP=NetMeter.app; C=$APP/Contents
rm -rf "$APP"; mkdir -p "$C/MacOS" "$C/Resources"
cp "$BIN" "$C/MacOS/NetMeter"; strip -x "$C/MacOS/NetMeter"
cp AppIcon.icns "$C/Resources/"
cat > "$C/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleExecutable</key><string>NetMeter</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>NetMeter</string>
<key>CFBundleDisplayName</key><string>NetMeter</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHumanReadableCopyright</key><string>$COPYRIGHT</string>
<key>NSLocationUsageDescription</key><string>NetMeter reads the name of the Wi-Fi network you are on, so usage and limits can be tracked per network. The name never leaves your Mac.</string>
<key>NSLocationWhenInUseUsageDescription</key><string>NetMeter reads the name of the Wi-Fi network you are on, so usage and limits can be tracked per network. The name never leaves your Mac.</string>
</dict></plist>
P

if [ "$IDENT" = "-" ]; then
  codesign --force --options runtime --entitlements NetMeter.entitlements -s - "$APP"
else
  codesign --force --options runtime --timestamp --entitlements NetMeter.entitlements -s "$IDENT" "$APP"
fi
codesign --verify --strict "$APP"
echo "built $APP  v$VERSION ($BUILD)  $BUNDLE_ID  signed: $([ "$IDENT" = "-" ] && echo ad-hoc || echo "$IDENT")  archs: $(lipo -archs "$C/MacOS/NetMeter")"
