#!/usr/bin/env bash
# Downloads the official python.org iOS XCframework into ./Python.xcframework
# PY_MINOR picks the minor version (default 3.13); the newest patch release is used.
set -euo pipefail
cd "$(dirname "$0")/.."

PY_MINOR="${PY_MINOR:-3.13}"

if [ -d Python.xcframework ]; then
  echo "Python.xcframework already present, skipping download"
  exit 0
fi

echo "Looking up the latest Python ${PY_MINOR} iOS XCframework…"
page="$(curl -fsSL https://www.python.org/downloads/ios/)"
path="$(printf '%s' "$page" \
  | grep -oE "/ftp/python/${PY_MINOR}\.[0-9]+/python-${PY_MINOR}\.[0-9]+-iOS-XCframework\.tar\.gz" \
  | sort -uV | tail -1 || true)"

if [ -z "$path" ]; then
  echo "error: no iOS XCframework link for Python ${PY_MINOR} found on python.org/downloads/ios/" >&2
  exit 1
fi

url="https://www.python.org${path}"
echo "Downloading $url"
tmp="$(mktemp -d)"
curl -fsSL "$url" -o "$tmp/py.tar.gz"
tar -xzf "$tmp/py.tar.gz" -C "$tmp"

found="$(find "$tmp" -maxdepth 3 -name Python.xcframework -type d | head -1)"
if [ -z "$found" ]; then
  echo "error: Python.xcframework not found inside the archive" >&2
  exit 1
fi
cp -R "$found" ./Python.xcframework
rm -rf "$tmp"
echo "OK: Python.xcframework ready"
