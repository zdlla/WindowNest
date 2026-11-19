#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
BUILD="${WINDOW_NEST_BUILD_DIR:-$PWD/../../work/build}"
mkdir -p "$BUILD/module-cache"
xcrun swiftc -module-cache-path "$BUILD/module-cache" Sources/PrivateStorage.swift Sources/GlobalShortcut.swift Sources/AppearanceSettings.swift Sources/WorkspaceLayout.swift Sources/WindowIdentity.swift Sources/AppLibrary.swift Sources/PageMotion.swift Sources/WorkspaceState.swift Sources/PageSwipe.swift Sources/FileSearchModels.swift Tests/main.swift -o "$BUILD/WindowNestTests"
"$BUILD/WindowNestTests" "$BUILD"
