#!/usr/bin/env bash
# Builds an ad-hoc signed SealPad.ipa. AltStore / SideStore / Sideloadly re-sign it on install.
set -euo pipefail
cd "$(dirname "$0")/.."

rm -rf build Payload SealPad.ipa

set -o pipefail
xcodebuild \
  -project SealPad.xcodeproj \
  -scheme SealPad \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  DEVELOPMENT_TEAM="" \
  ENABLE_USER_SCRIPT_SANDBOXING=NO \
  build | tee build.log | (command -v xcbeautify >/dev/null && xcbeautify || cat)

app="build/Build/Products/Release-iphoneos/SealPad.app"
[ -d "$app" ] || { echo "error: $app not found" >&2; exit 1; }

mkdir Payload
cp -R "$app" Payload/
zip -qry SealPad.ipa Payload
rm -rf Payload
echo "Built SealPad.ipa ($(du -h SealPad.ipa | cut -f1))"
