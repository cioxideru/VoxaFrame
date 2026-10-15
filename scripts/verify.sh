#!/usr/bin/env bash
# Full verification. VERIFY_SCOPE: fast = ci.sh + SwiftLint; build = + iOS/tvOS simulator
# builds (what PR CI runs); full (default) = + the hermetic Smoke UI plan.
# Optional: VERIFY_DESTINATION (iOS simulator destination), SMARTTUBE_DERIVED_DATA.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

scope="${VERIFY_SCOPE:-full}"
destination="${VERIFY_DESTINATION:-platform=iOS Simulator,name=iPhone 17}"
derived=(${SMARTTUBE_DERIVED_DATA:+-derivedDataPath "$SMARTTUBE_DERIVED_DATA"})

scripts/ci.sh
swiftlint lint --strict --quiet --baseline .swiftlint.baseline --config .swiftlint.yml
[ "$scope" = fast ] && exit 0

xcodebuild build -workspace SmartTube.xcworkspace -scheme SmartTube -destination "$destination" \
    "${derived[@]}" CODE_SIGNING_ALLOWED=NO -quiet
xcodebuild build -workspace SmartTube.xcworkspace -scheme "Smart Tube" -destination "generic/platform=tvOS Simulator" \
    "${derived[@]}" CODE_SIGNING_ALLOWED=NO -quiet
[ "$scope" = build ] && exit 0

# 3 workers: the 16 GB build Mac stalls with more simulator clones (docs/how-to/run-tests.md).
xcodebuild test -workspace SmartTube.xcworkspace -scheme SmartTube -testPlan Smoke -destination "$destination" \
    "${derived[@]}" -parallel-testing-enabled YES -maximum-parallel-testing-workers 3 CODE_SIGNING_ALLOWED=NO
