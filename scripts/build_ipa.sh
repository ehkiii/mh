#!/usr/bin/env bash
# Builds an unsigned SealPad.ipa. AltStore / SideStore / Sideloadly sign it on install.
set -euo pipefail
cd "$(dirname "$0")/.."

rm -rf build Payload SealPad.ipa

set +e
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
  build 2>&1 | tee build.log | (command -v xcbeautify >/dev/null && xcbeautify || cat)
status=${PIPESTATUS[0]}
set -e

if [ "$status" -ne 0 ]; then
  # xcbeautify hides build-script output, so print the raw log where the failure happened.
  echo "::group::RAW xcodebuild log (last 250 lines)"
  tail -n 250 build.log
  echo "::endgroup::"
  echo "::group::Output of the 'Process Python libraries' script"
  grep -n -A80 "Process Python libraries" build.log | head -n 200 || true
  echo "::endgroup::"
  exit "$status"
fi

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
