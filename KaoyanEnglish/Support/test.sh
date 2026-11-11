#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Build tmp
KAOYAN_TEST_ROOT="$PWD/tmp" CLANG_MODULE_CACHE_PATH="$PWD/Build/ModuleCache" \
    swift test --package-path . --scratch-path Build/SwiftPM --cache-path Build/PackageCache --disable-sandbox
xcodebuild -project KaoyanEnglish.xcodeproj -scheme KaoyanEnglish -configuration Debug \
    -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath Build/DerivedData CODE_SIGNING_ALLOWED=NO build-for-testing
