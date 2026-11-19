#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
BUILD="${WINDOW_NEST_BUILD_DIR:-$PWD/../../work/build}"
mkdir -p "$BUILD/module-cache"
SDK="${WINDOW_NEST_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk}"
xcrun swiftc -swift-version 5 -parse-as-library -sdk "$SDK" -module-cache-path "$BUILD/module-cache" \
 Sources/DesktopBoxLayout.swift Sources/DesktopDisplayLayout.swift Tests/DesktopDisplayLayoutTests.swift -framework AppKit -o "$BUILD/DesktopDisplayLayoutTests"
"$BUILD/DesktopDisplayLayoutTests"
xcrun swiftc -swift-version 5 -parse-as-library -sdk "$SDK" -module-cache-path "$BUILD/module-cache" \
 Sources/FileTypeIcons.swift Tests/FileTypeIconTests.swift -framework AppKit -o "$BUILD/FileTypeIconTests"
"$BUILD/FileTypeIconTests" "$PWD/Resources/FileTypeIcons"
xcrun swiftc -swift-version 5 -parse-as-library -sdk "$SDK" -module-cache-path "$BUILD/module-cache" \
 Sources/LoginItemController.swift Tests/LoginItemTests.swift -framework ServiceManagement -framework SwiftUI -framework AppKit -o "$BUILD/LoginItemTests"
"$BUILD/LoginItemTests"
xcrun swiftc -swift-version 5 -parse-as-library -sdk "$SDK" -module-cache-path "$BUILD/module-cache" \
 Sources/DesktopBoxLayout.swift Tests/DesktopBoxLayoutTests.swift -o "$BUILD/DesktopBoxLayoutTests"
"$BUILD/DesktopBoxLayoutTests"
xcrun swiftc -swift-version 5 -parse-as-library -sdk "$SDK" -module-cache-path "$BUILD/module-cache" \
 Sources/DesktopBoxClickFeedback.swift Tests/DesktopBoxClickFeedbackTests.swift -o "$BUILD/DesktopBoxClickFeedbackTests"
"$BUILD/DesktopBoxClickFeedbackTests"
sources=()
for source in Sources/*.swift; do [[ "$source" == Sources/main.swift ]] || sources+=("$source"); done
xcrun swiftc -swift-version 5 -parse-as-library -sdk "$SDK" -module-cache-path "$BUILD/module-cache" \
 Sources/DesktopBoxFileOperations.swift Tests/DesktopBoxFileOperationTests.swift -o "$BUILD/DesktopBoxFileOperationTests"
"$BUILD/DesktopBoxFileOperationTests"
xcrun swiftc -swift-version 5 -parse-as-library -sdk "$SDK" -module-cache-path "$BUILD/module-cache" \
 "${sources[@]}" Vendor/LRUCache/LRUCache.swift Tests/DesktopBoxTests.swift -o "$BUILD/DesktopBoxTests" \
 -framework AppKit -framework SwiftUI -framework ApplicationServices -framework ScreenCaptureKit -framework Carbon
"$BUILD/DesktopBoxTests"
