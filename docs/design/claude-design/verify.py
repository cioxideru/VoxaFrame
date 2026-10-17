#!/usr/bin/env python3
"""Verify the self-contained design handoff with Python's standard library."""

import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def flatten(value, prefix=""):
    result = {}
    for name, child in value.items():
        if name.startswith("$") or not isinstance(child, dict):
            continue
        path = prefix + name
        if "$value" in child:
            result[path] = child
        else:
            result.update(flatten(child, path + "."))
    return result


def luminance(rgb):
    linear = [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in rgb]
    return sum(x * weight for x, weight in zip(linear, (0.2126, 0.7152, 0.0722)))


def ratio(a, b):
    first, second = sorted((luminance(a), luminance(b)))
    return (second + 0.05) / (first + 0.05)


def main():
    required = ["README.md", "CLAUDE_IMPORT.md", "IMPORT_PROMPT.txt", "preview.html",
                "VoxaFrame-Design-System.pdf", "components.json", "platforms.json",
                "figma-reference.json", "provenance.json", "assets/voxaframe-icon.png",
                "tokens/voxaframe.css", "tokens/light.tokens.json", "tokens/dark.tokens.json"]
    assert all((ROOT / p).is_file() for p in required), "Missing deliverable"
    for p in ROOT.rglob("*.json"):
        json.loads(p.read_text())
    contrasts = {}
    names = []
    for appearance in ("light", "dark"):
        tokens = flatten(json.loads((ROOT / f"tokens/{appearance}.tokens.json").read_text()))
        names.append(set(tokens))
        assert all("$type" in t and "$description" in t for t in tokens.values())
        for name, t in tokens.items():
            v = t["$value"]
            if t["$type"] == "color":
                assert v["colorSpace"] == "srgb" and len(v["components"]) == 3
                assert all(0 <= x <= 1 for x in v["components"]) and 0 <= v["alpha"] <= 1
                expected = [int(v["hex"][i:i+2], 16) / 255 for i in (1, 3, 5)]
                assert all(abs(x-y) < 1e-9 for x, y in zip(expected, v["components"]))
            elif t["$type"] == "dimension":
                assert v["unit"] == "px" and v["value"] >= 0
            elif t["$type"] == "duration":
                assert v["unit"] == "ms" and v["value"] >= 0
            elif t["$type"] == "typography":
                assert v["fontSize"]["value"] > 0 and v["lineHeight"] >= 1
        contrasts[appearance] = {}
        pairs = [(fg, bg, 4.5) for fg in ("text", "secondary", "action", "success", "warning", "danger")
                 for bg in ("background", "surface", "elevated")]
        pairs += [("onAction", "action", 4.5), ("focus", "surface", 3), ("focus", "background", 3)]
        for fg, bg, minimum in pairs:
            result = ratio(tokens["color."+fg]["$value"]["components"], tokens["color."+bg]["$value"]["components"])
            assert result >= minimum, (appearance, fg, bg, result)
            contrasts[appearance][f"{fg}/{bg}"] = round(result, 2)
        # The lightest arbitrary video frame is the worst case for a black scrim.
        scrim = tokens["color.scrim"]["$value"]
        composite = [x * scrim["alpha"] + (1-scrim["alpha"]) for x in scrim["components"]]
        media = ratio(tokens["color.onMedia"]["$value"]["components"], composite)
        assert media >= 4.5
        contrasts[appearance]["onMedia/scrim-over-white"] = round(media, 2)
    assert names[0] == names[1]
    components = json.loads((ROOT / "components.json").read_text())["components"]
    assert len({c["id"] for c in components}) == len(components) == 23
    for c in components:
        assert c["states"] and c["variants"] and c["behavior"] and c["accessibility"]
        assert all(t in names[0] for t in c["tokens"]), c["id"]
    platforms = json.loads((ROOT / "platforms.json").read_text())["platforms"]
    assert {p["id"] for p in platforms} == {"iphone", "ipad", "mac", "tv"}
    for doc in ROOT.glob("*.md"):
        for target in re.findall(r"\]\(([^)]+)\)", doc.read_text()):
            if not re.match(r"https?://|mailto:|#", target):
                assert (doc.parent / target.split("#")[0]).exists(), (doc.name, target)
    html = (ROOT / "preview.html").read_text()
    assert not re.search(r'(?:src|href)=[\"\']https?://', html)
    assert "fetch(" not in html and "XMLHttpRequest" not in html
    provenance = json.loads((ROOT / "provenance.json").read_text())
    assert hashlib.sha256((ROOT / "assets/voxaframe-icon.png").read_bytes()).hexdigest() == provenance["brand"]["sha256"]
    pdf = (ROOT / "VoxaFrame-Design-System.pdf").read_bytes()
    assert pdf.startswith(b"%PDF") and b"%%EOF" in pdf[-2048:]
    for screen in ("components-light", "components-dark", "iphone", "iphone-dark", "ipad", "mac", "tv", "player"):
        assert (ROOT / f"previews/{screen}.png").read_bytes().startswith(b"\x89PNG\r\n\x1a\n")
    if (ROOT / "manifest.json").exists():
        for name, digest in json.loads((ROOT / "manifest.json").read_text())["sha256"].items():
            assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == digest, name
    result = {"status":"pass", "tokensPerAppearance":len(names[0]), "components":len(components),
              "platforms":len(platforms), "contrastRatios":contrasts,
              "scope":"Token subset syntax/value checks, measured static contrast, JSON, local links, assets. Not an official DTCG schema certification or native accessibility audit."}
    if "--write" in sys.argv:
        existing = json.loads((ROOT / "checks.json").read_text()) if (ROOT / "checks.json").exists() else {}
        existing["package"] = result
        (ROOT / "checks.json").write_text(json.dumps(existing, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
