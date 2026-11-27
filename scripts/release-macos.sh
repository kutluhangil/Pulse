#!/usr/bin/env bash
# Build Pulse.app (Release, ad-hoc signed) and package it as a DMG in dist/.
#
#   ./scripts/release-macos.sh            build + DMG
#   ./scripts/release-macos.sh --install  also replace /Applications/Pulse.app and relaunch it
#
# There is no Developer ID yet, so the app is ad-hoc signed. First launch on
# another Mac: right-click Pulse.app > Open (or xattr -dr com.apple.quarantine).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
VERSION="$(sed -n 's/^    MARKETING_VERSION: //p' app/project.yml)"
BUILD_DIR="$ROOT/app/build"
APP="$BUILD_DIR/Release/Pulse.app"
DMG="$ROOT/dist/Pulse-$VERSION.dmg"

echo "==> Testing PulseKit"
(cd app/Packages/PulseKit && swift test --quiet)

echo "==> Building Pulse $VERSION (Release)"
(cd app && xcodegen generate --quiet)
xcodebuild -project app/Pulse.xcodeproj -scheme Pulse -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" CONFIGURATION_BUILD_DIR="$BUILD_DIR/Release" \
  -quiet build
codesign --verify --deep --strict "$APP"
echo "    signed: $(codesign -dv "$APP" 2>&1 | grep -E '^Signature' || true)"

echo "==> Packaging $DMG"
mkdir -p dist
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "Pulse $VERSION" -srcfolder "$STAGE" -format UDZO "$DMG"
shasum -a 256 "$DMG" | tee "$DMG.sha256"

if [[ "${1:-}" == "--install" ]]; then
  echo "==> Installing to /Applications"
  pkill -x Pulse 2>/dev/null || true
  sleep 1
  rm -rf /Applications/Pulse.app
  cp -R "$APP" /Applications/
  open /Applications/Pulse.app
fi
echo "Done."
