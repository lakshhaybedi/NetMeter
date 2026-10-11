#!/bin/sh
# Builds, signs, packages and (optionally) notarizes NetMeter-<version>.dmg in dist/.
#   CODESIGN_IDENTITY  required: "Developer ID Application: Name (TEAMID)"
#   NOTARY_PROFILE     optional: keychain profile from `xcrun notarytool store-credentials`; without it the DMG is not notarized
#   BUNDLE_ID          optional reverse-DNS id (see build.sh)
set -e
cd "$(dirname "$0")"
: "${CODESIGN_IDENTITY:?set CODESIGN_IDENTITY to your Developer ID Application identity}"
./build.sh
VERSION=$(cat VERSION); DMG="dist/NetMeter-$VERSION.dmg"
rm -rf dist; mkdir -p dist/stage
cp -R NetMeter.app dist/stage/; ln -s /Applications dist/stage/Applications
hdiutil create -volname "NetMeter" -srcfolder dist/stage -ov -format UDZO "$DMG" >/dev/null
rm -rf dist/stage
[ "$CODESIGN_IDENTITY" = "-" ] || codesign --force --timestamp -s "$CODESIGN_IDENTITY" "$DMG"
if [ -n "$NOTARY_PROFILE" ]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature -v "$DMG"
else
  echo "Not notarized: set NOTARY_PROFILE to notarize (macOS will warn on first launch otherwise)."
fi
echo "ready: $DMG"
