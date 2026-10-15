#!/usr/bin/env bash
# Compiles the iOS and tvOS apps together with their UI-test targets (no test run).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
xcodebuild build-for-testing -workspace SmartTube.xcworkspace -scheme SmartTube \
    -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO -quiet
xcodebuild build-for-testing -workspace SmartTube.xcworkspace -scheme "Smart Tube" \
    -destination "generic/platform=tvOS Simulator" CODE_SIGNING_ALLOWED=NO -quiet
