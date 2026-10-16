#!/usr/bin/env python3
"""Reject new platform dependencies in Core; existing exceptions stay file-scoped."""

import re
from pathlib import Path

BASE_MODULES = {
    "Foundation", "FoundationNetworking", "FoundationXML", "Observation",
    "os", "OSLog", "CryptoKit",
}
# Existing adapters are migrated separately. These exceptions permit no new callers.
LEGACY_IMPORTS = {
    "InnerTubeAPI.swift": {"Network"},
    "VideoPreloadCache.swift": {"Network"},
    "BotGuardClient.swift": {"JavaScriptCore"},
    "DownloadActivityAttributes.swift": {"ActivityKit"},
    "HomeWidgetSnapshot.swift": {"ImageIO", "UniformTypeIdentifiers"},
}
IMPORT = re.compile(
    r"(?m)^[ \t]*(?:(?:@\w+(?:\([^\n)]*\))?|public|internal|package|private|fileprivate)\s+)*"
    r"import\s+(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?([A-Za-z_]\w*)"
)


def violations(source: str, relative_path: str) -> list[str]:
    allowed = BASE_MODULES | LEGACY_IMPORTS.get(relative_path, set())
    return [match[1] for match in IMPORT.finditer(source) if match[1] not in allowed]


def self_check() -> None:
    assert violations("import Foundation\nimport Observation\nimport CryptoKit", "Model.swift") == []
    assert violations("import Network", "InnerTubeAPI.swift") == []
    assert violations("import Network", "NewAdapter.swift") == ["Network"]
    assert violations("import SwiftUI", "InnerTubeAPI.swift") == ["SwiftUI"]
    assert violations("#if os(iOS)\n@preconcurrency import AVFoundation\n#endif", "Model.swift") == ["AVFoundation"]
    assert violations("@_exported\nimport SwiftUI", "Model.swift") == ["SwiftUI"]
    assert violations("public import struct UIKit.UIColor", "Model.swift") == ["UIKit"]
    assert violations("// import SwiftUI\nlet importKey = 1", "Model.swift") == []


def main() -> None:
    self_check()
    root = Path(__file__).resolve().parents[1] / "SmartTubeIOS/Sources/SmartTubeIOSCore"
    failures = []
    for path in sorted(root.rglob("*.swift")):
        relative = path.relative_to(root).as_posix()
        failures.extend(f"{relative}: unexpected Core import {module}" for module in violations(path.read_text(), relative))
    if failures:
        raise SystemExit("\n".join(failures))
    print("Core import boundary passed (including guard self-check)")


if __name__ == "__main__":
    main()
