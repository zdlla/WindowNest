#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
BUILD="${WINDOW_NEST_BUILD_DIR:-$PWD/../../work/build}"
mkdir -p "$BUILD/module-cache"
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$BUILD/module-cache" \
 Sources/PrivateStorage.swift Sources/AppLibrary.swift Sources/GlobalShortcut.swift Sources/AppearanceSettings.swift Sources/FolderInteraction.swift \
 Tests/FolderInteractionTests.swift -o "$BUILD/FolderInteractionTests" -framework AppKit -framework SwiftUI
"$BUILD/FolderInteractionTests"
