#!/usr/bin/env bash
# Pre-commit gate: secrets, doc links, swift-format, package unit tests.
# SwiftLint runs as its own step (see AGENTS.md). Safe to run from any cwd.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

scripts/check-no-secrets.sh
scripts/check-doc-links.sh
python3 scripts/check-core-imports.py
xcrun swift-format lint --strict --recursive --configuration .swift-format \
    SmartTubeIOS/Sources SmartTubeIOS/Tests SmartTubeApp/Sources SmartTubeApp/UITests "SmartTubeApp/Smart Tube"
(cd SmartTubeIOS && swift test --parallel)
echo "CI gate passed"
