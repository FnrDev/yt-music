#!/usr/bin/env bash
# Builds "YT Music.app" into macos/build/.
#   scripts/build.sh            # Release
#   scripts/build.sh Debug      # Debug (web inspector enabled)
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIGURATION="${1:-Release}"

command -v xcodegen >/dev/null || { echo "xcodegen not found: brew install xcodegen" >&2; exit 1; }

if [[ ! -f YTMusic/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json ]]; then
  swift scripts/make-icon.swift
fi

xcodegen generate --quiet

FORMATTER=(cat)
command -v xcbeautify >/dev/null && FORMATTER=(xcbeautify --quiet)

xcodebuild \
  -project YTMusic.xcodeproj \
  -scheme YTMusic \
  -configuration "$CONFIGURATION" \
  -derivedDataPath build/DerivedData \
  -destination 'platform=macOS' \
  build | "${FORMATTER[@]}"

APP="build/DerivedData/Build/Products/$CONFIGURATION/YT Music.app"
[[ -d "$APP" ]] || { echo "Build failed" >&2; exit 1; }

rm -rf "build/YT Music.app"
cp -R "$APP" "build/YT Music.app"
echo "Built: $(pwd)/build/YT Music.app"
