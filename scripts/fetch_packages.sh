#!/usr/bin/env bash
# Installs the bundled copy of yt-dlp (+ its pinned yt-dlp-ejs, + certifi) into ./app_packages.
# Only pure-Python wheels are allowed: host-built native modules would not load on iOS.
set -euo pipefail
cd "$(dirname "$0")/.."

rm -rf app_packages
mkdir app_packages

python3 -m pip install --quiet --no-deps --target app_packages yt-dlp certifi

# yt-dlp pins an exact yt-dlp-ejs version in its metadata; install that exact one.
ejs="$(grep -hoE 'Requires-Dist: yt-dlp-ejs *\(?== *[0-9][0-9.]*' app_packages/yt_dlp-*.dist-info/METADATA \
  | grep -oE '[0-9][0-9.]*$' | head -1 || true)"
if [ -n "$ejs" ]; then
  echo "yt-dlp pins yt-dlp-ejs==$ejs"
  python3 -m pip install --quiet --no-deps --target app_packages "yt-dlp-ejs==$ejs"
else
  echo "warning: no yt-dlp-ejs pin found, installing latest"
  python3 -m pip install --quiet --no-deps --target app_packages yt-dlp-ejs
fi

if find app_packages \( -name '*.so' -o -name '*.dylib' \) | grep -q .; then
  echo "error: native modules found in app_packages (not valid for iOS):" >&2
  find app_packages \( -name '*.so' -o -name '*.dylib' \) >&2
  exit 1
fi

# stale bytecode isn't needed; it gets regenerated on device
find app_packages -name '__pycache__' -type d -prune -exec rm -rf {} +
echo "OK: $(ls app_packages | tr '\n' ' ')"
