#!/bin/bash
# Builds meTools, packages it into a signed DMG, and (optionally) notarizes it.
#
# Usage:
#   scripts/make_dmg.sh                 # build + signed DMG
#   scripts/make_dmg.sh --notarize      # build + signed DMG + notarize + staple
#
# Notarization uses the keychain profile named below. Store it once with:
#   xcrun notarytool store-credentials meTools \
#     --apple-id "you@example.com" --team-id Y5K2497B6G \
#     --password "<app-specific password from appleid.apple.com>"
set -euo pipefail

cd "$(dirname "$0")/.."

SIGN_IDENTITY="Developer ID Application: Metin Aksu (Y5K2497B6G)"
NOTARY_PROFILE="meTools"
APP_NAME="meTools"
VERSION=$(sed -n 's/ *MARKETING_VERSION: "\(.*\)"/\1/p' project.yml | head -1)
DMG="dist/${APP_NAME}-${VERSION}.dmg"

echo "==> Building ${APP_NAME} ${VERSION}"
xcodegen generate >/dev/null
xcodebuild -project meTools.xcodeproj -scheme meTools \
  -configuration Release -derivedDataPath build \
  -destination 'generic/platform=macOS' \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  build -quiet

APP="build/Build/Products/Release/${APP_NAME}.app"

echo "==> Verifying signature"
codesign --verify --deep --strict "$APP"
if codesign -d --entitlements - "$APP/Contents/PlugIns/FinderExtension.appex" 2>/dev/null | grep -q get-task-allow; then
  echo "ERROR: get-task-allow entitlement present; not distributable." >&2
  exit 1
fi

echo "==> Creating DMG"
rm -rf dist/staging "$DMG"
mkdir -p dist/staging
cp -R "$APP" dist/staging/
ln -s /Applications dist/staging/Applications
hdiutil create -volname "$APP_NAME" -srcfolder dist/staging \
  -ov -format UDZO "$DMG" -quiet
rm -rf dist/staging

echo "==> Signing DMG"
codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"
codesign --verify "$DMG"

if [[ "${1:-}" == "--notarize" ]]; then
  echo "==> Notarizing (this can take a few minutes)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  echo "==> Stapling ticket"
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature -v "$DMG"
fi

# Remove the build copy so macOS never registers its Finder extension
# alongside the installed one (duplicate context-menu items).
rm -rf build

echo "==> Done: $DMG"
shasum -a 256 "$DMG"
