#!/usr/bin/env bash
# Ratchet metrics (docs/adr/0001-maintainability-baseline.md).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
pkg=SmartTubeIOS
echo "largest files:"; find $pkg/Sources -name '*.swift' -exec wc -l {} + | sort -rn | head -11
echo "AGENTS.md bytes/lines:"; wc -c -l AGENTS.md
echo "a11y literals:"; grep -rho 'accessibilityIdentifier("' --include='*.swift' $pkg/Sources SmartTubeApp/Sources | wc -l
echo "sleep( in UITests:"; grep -rhoE '\bsleep\(' SmartTubeApp/UITests | wc -l
echo "XCTSkip:"; grep -rho 'XCTSkip' SmartTubeApp/UITests | wc -l
echo ".shared reads in Views:"; grep -rho '\.shared\b' --include='*.swift' $pkg/Sources/SmartTubeIOS/Views | wc -l
echo "mirror tests:"; grep -rli 'mirror' $pkg/Tests | wc -l
