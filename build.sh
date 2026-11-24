#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$PWD"
python3 Scripts/check_licenses.py
BUILD="${WINDOW_NEST_BUILD_DIR:-$ROOT/../../work/build}"
APP="${WINDOW_NEST_APP_PATH:-$ROOT/窗匣.app}"
ARCHS="${WINDOW_NEST_ARCHS:-arm64 x86_64}"
DEPLOYMENT="${WINDOW_NEST_DEPLOYMENT_TARGET:-14.0}"
# Use the macOS 26 SDK when installed, even on a macOS 27 development host.
SDK="${WINDOW_NEST_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk}"
if [[ ! -d "$SDK" ]]; then SDK="$(xcrun --show-sdk-path)"; fi
SDK_VERSION="$(plutil -extract Version raw -o - "$SDK/SDKSettings.json")"
export WINDOW_NEST_ARCHS="$ARCHS" WINDOW_NEST_SDK="$SDK" WINDOW_NEST_DEPLOYMENT_TARGET="$DEPLOYMENT"
mkdir -p "$BUILD/module-cache" "$APP/Contents/MacOS" "$APP/Contents/Resources"
ENGINE_READY=true
ENGINE_SOURCE="$(python3 Scripts/engine_fingerprint.py)"
if [[ ! -f "$ROOT/Engine/source.sha256" ]] || [[ "$(cat "$ROOT/Engine/source.sha256")" != "$ENGINE_SOURCE" ]]; then ENGINE_READY=false; fi
for ARCH in $ARCHS; do
  if ! xcrun lipo "$ROOT/Engine/WindowNestCardinal" -verify_arch "$ARCH" 2>/dev/null; then ENGINE_READY=false; fi
done
if [[ "$ENGINE_READY" != true ]]; then bash "$ROOT/build-cardinal.sh"; fi
mkdir -p "$APP/Contents/Helpers"
rm -rf -- "$APP/Contents/Resources/Licenses"
mkdir -p "$APP/Contents/Resources/Licenses"
cp "$ROOT/Engine/WindowNestCardinal" "$APP/Contents/Helpers/WindowNestCardinal"
cp "$ROOT/Vendor/Cardinal/LICENSE" "$APP/Contents/Resources/Licenses/Cardinal-MIT.txt"
ditto "$ROOT/Resources/FileTypeIcons" "$APP/Contents/Resources/FileTypeIcons"
ditto "$ROOT/Resources/NewFileTemplates" "$APP/Contents/Resources/NewFileTemplates"
if [[ -d "$ROOT/Licenses" ]]; then ditto "$ROOT/Licenses" "$APP/Contents/Resources/Licenses"; fi
SIGN_IDENTITY="${WINDOW_NEST_SIGN_IDENTITY:--}"
SIGN_ARGS=(--force --options runtime --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != - ]]; then SIGN_ARGS+=(--timestamp); fi
# Default ad-hoc requirements bind the binary hash. Do not replace them with an
# identifier-only rule, which cannot authenticate a publisher.
codesign "${SIGN_ARGS[@]}" --identifier local.windownest.cardinal "$APP/Contents/Helpers/WindowNestCardinal"
SLICES=()
for ARCH in $ARCHS; do
  SLICE="$BUILD/WindowNest-$ARCH"
  xcrun swiftc -swift-version 5 -O -sdk "$SDK" -target "$ARCH-apple-macos$DEPLOYMENT" \
    -module-cache-path "$BUILD/module-cache" \
    Sources/*.swift Vendor/LRUCache/LRUCache.swift -o "$SLICE" \
    -Xlinker -platform_version -Xlinker macos -Xlinker "$DEPLOYMENT" -Xlinker "$SDK_VERSION" \
    -framework AppKit -framework SwiftUI -framework ApplicationServices -framework ScreenCaptureKit -framework Carbon
  SLICES+=("$SLICE")
done
xcrun lipo -create "${SLICES[@]}" -output "$APP/Contents/MacOS/WindowNest"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/install-update.sh "$APP/Contents/Resources/install-update.sh"
xcrun swift -module-cache-path "$BUILD/module-cache" Resources/MakeIcon.swift "$BUILD"
cp "$BUILD/WindowNest.icns" "$APP/Contents/Resources/AppIcon.icns"
codesign "${SIGN_ARGS[@]}" --identifier local.windownest.app "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built: %s\n' "$APP"
