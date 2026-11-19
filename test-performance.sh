#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
BUILD="${WINDOW_NEST_BUILD_DIR:-$PWD/../../work/build}"
mkdir -p "$BUILD/module-cache"
xcrun swiftc -swift-version 5 -O -parse-as-library -module-cache-path "$BUILD/module-cache" \
 Sources/PrivateStorage.swift Sources/GlobalShortcut.swift Sources/AppearanceSettings.swift Sources/TopOverviewPolicy.swift Sources/InteractionMotion.swift Sources/WindowFilterTransition.swift Sources/WindowPreviewPolicy.swift Sources/WorkspaceActivityPolicy.swift Sources/WindowRecord.swift Sources/WindowControls.swift Sources/WindowIconCache.swift \
 Vendor/LRUCache/LRUCache.swift Tests/PerformanceTests.swift \
 -o "$BUILD/WindowNestPerformanceTests" -framework SwiftUI
"$BUILD/WindowNestPerformanceTests"
