#!/usr/bin/env bash
# Everything needed before xcodebuild: Python runtime, bundled packages, Xcode project.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/fetch_python.sh
./scripts/fetch_packages.sh

if ! command -v xcodegen >/dev/null; then
  echo "Installing XcodeGen…"
  brew install xcodegen
fi
xcodegen generate
echo "Done. Open SealPad.xcodeproj, or run ./scripts/build_ipa.sh"
