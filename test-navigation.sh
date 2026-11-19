#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
BUILD="${WINDOW_NEST_BUILD_DIR:-$PWD/../../work/build}"
mkdir -p "$BUILD/module-cache"
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$BUILD/module-cache" \
  Sources/PrivateStorage.swift Sources/PageMotion.swift Sources/WorkspaceState.swift Sources/WorkspacePager.swift Sources/WorkspaceColors.swift Sources/WorkspaceNavigation.swift \
  Tests/NavigationTests.swift -o "$BUILD/NavigationTests" -framework AppKit
"$BUILD/NavigationTests"
