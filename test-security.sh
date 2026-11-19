#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
BUILD="${WINDOW_NEST_BUILD_DIR:-$PWD/../../work/build}"
mkdir -p "$BUILD/module-cache"
xcrun swiftc -parse-as-library -module-cache-path "$BUILD/module-cache" Sources/PrivateStorage.swift Tests/PrivateStorageTests.swift -o "$BUILD/PrivateStorageTests"
"$BUILD/PrivateStorageTests" "$BUILD"
