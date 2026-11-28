#!/usr/bin/env bash
# Builds an unsigned SealPad.ipa. AltStore / SideStore / Sideloadly sign it on install.
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
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  DEVELOPMENT_TEAM="" \
  ENABLE_USER_SCRIPT_SANDBOXING=NO \
  build | tee build.log | (command -v xcbeautify >/dev/null && xcbeautify || cat)

app="build/Build/Products/Release-iphoneos/SealPad.app"
[ -d "$app" ] || { echo "error: $app not found" >&2; exit 1; }

# Guard: the app is useless without the Python stdlib inside the bundle.
stdlib="$(ls -d "$app"/python/lib/python3.* 2>/dev/null | head -1 || true)"
if [ -z "$stdlib" ] || [ ! -f "$stdlib/os.py" ]; then
  echo "error: Python stdlib missing from the app bundle (python/lib/python3.x)." >&2
  echo "       The 'Process Python libraries' step in project.yml must run install_python." >&2
  exit 1
fi
echo "Python stdlib found at ${stdlib#$app/}"

mkdir Payload
cp -R "$app" Payload/
zip -qry SealPad.ipa Payload
rm -rf Payload
echo "Built SealPad.ipa ($(du -h SealPad.ipa | cut -f1))"
