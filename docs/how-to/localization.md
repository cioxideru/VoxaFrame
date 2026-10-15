> Status: current — catalog and script inspected 2026-10-15; translation quality not reviewed.

# Localisation

## Catalog state (2026-10-15)

### Languages
| Code | Language | Coverage |
|------|----------|----------|
| `ar` | Arabic | 275/345 |
| `de` | German | 275/345 |
| `en` | English (source) | — |
| `es` | Spanish | 275/345 |
| `fr` | French | 275/345 |
| `hi` | Hindi | 275/345 |
| `id` | Indonesian | 275/345 |
| `it` | Italian | 275/345 |
| `ja` | Japanese | 275/345 |
| `ko` | Korean | 275/345 |
| `pt-BR` | Portuguese (Brazil) | 275/345 |
| `ru` | Russian | 275/345 |
| `sr` | Serbian | 275/345 |
| `hr` | Croatian | 275/345 |
| `tr` | Turkish | 275/345 |
| `zh-Hans` | Chinese (Simplified) | 275/345 |

**Total keys: 345.** Coverage counts existing locale entries, not reviewed translation quality. The 3 intentionally untranslated keys are the empty key, `%lld`, and `%lld s` — these are format-specifier-only strings that need no translation.

The strings file lives at:
```
SmartTubeIOS/Sources/SmartTubeIOS/Localizable.xcstrings
```

---

## Adding or Fixing Translations

The automation script lives alongside the strings file:
```
SmartTubeIOS/Sources/SmartTubeIOS/translate_strings.py
```

It uses Google Translate (via `deep-translator`, no API key required) and correctly protects `%@`, `%lld`, `%d`, `%.2g` format specifiers from being translated or transliterated.

### One-time setup

```bash
python3 -m venv /tmp/loctranslate_venv
/tmp/loctranslate_venv/bin/pip install deep-translator
```

The venv lives in `/tmp/` so it is wiped on reboot. Re-run the two commands above whenever needed.

---

### Dry run — preview what would be translated without writing anything

```bash
cd SmartTubeIOS/Sources/SmartTubeIOS
/tmp/loctranslate_venv/bin/python3 translate_strings.py --dry-run
```

---

### Fill missing translations — any new keys added by a developer

Run with no flags. The script is **additive only** — it skips any key/language pair that already has a translation.

```bash
cd SmartTubeIOS/Sources/SmartTubeIOS
/tmp/loctranslate_venv/bin/python3 translate_strings.py
```

---

### Re-translate an entire language — e.g. after discovering bad output

Overwrites every entry for that language, even ones that already exist.

```bash
/tmp/loctranslate_venv/bin/python3 translate_strings.py --fix-lang sr
/tmp/loctranslate_venv/bin/python3 translate_strings.py --fix-lang hr
```

---

### Adding a new language

1. Open `translate_strings.py` and add an entry to the `LANG_MAP` dict:
   ```python
   LANG_MAP = {
       ...
       "nl": "nl",   # Dutch — xcstrings code : GoogleTranslator code
   }
   ```
   Use the [xcstrings language code](https://developer.apple.com/documentation/xcode/choosing-localization-regions-and-scripts) as the key and the [Google Translate language code](https://py-googletrans.readthedocs.io/en/latest/#googletrans-languages) as the value. Usually they match; notable exceptions are `pt-BR → pt` and `zh-Hans → zh-CN`.

2. Add the language through the Xcode project's localization settings. Do not hand-edit
   `project.pbxproj`; Xcode owns project changes (see [ADR-0003](../adr/0003-no-project-generation.md)).

3. Run the script:
   ```bash
   cd SmartTubeIOS/Sources/SmartTubeIOS
   /tmp/loctranslate_venv/bin/python3 translate_strings.py
   ```

4. Commit both `Localizable.xcstrings` and `project.pbxproj`.

---

### Adding new localised strings (developer workflow)

When a developer adds a new string in Swift, they use `String(localized:)` with a key that is the English text itself:

```swift
Text(String(localized: "My New Feature"))
```

Xcode will extract it into `Localizable.xcstrings` with an empty `localizations` dict. After merging, run the script once to fill all languages automatically:

```bash
/tmp/loctranslate_venv/bin/python3 translate_strings.py
```

---

## Checking coverage

```bash
cd SmartTubeIOS/Sources/SmartTubeIOS
python3 - <<'EOF'
import json
with open('Localizable.xcstrings') as f:
    data = json.load(f)
strings = data['strings']
total = len(strings)
langs = sorted({l for v in strings.values() for l in v.get('localizations', {})})
print(f'Total keys: {total}\n')
for lang in langs:
    count = sum(1 for v in strings.values() if lang in v.get('localizations', {}))
    print(f'{lang:10} {count:4}/{total}  ({count/total*100:.0f}%)')
EOF
```

---

## Known limitations

- **Machine translation quality** — Google Translate is used for all strings. Translations are generally good for UI labels and short phrases, but long or idiomatic strings may need native review before a public release.
- **Cyrillic/non-Latin script caution** — Format specifiers (`%@`, `%lld`, etc.) are protected by `⟪0⟫` / `⟪1⟫` symbol brackets before translation and restored afterwards. This avoids the transliteration bug where Cyrillic engines turned `FMTSPEC0END` into `ФМТСПЕЦ0ЕНД`.
- **Plural forms** — The xcstrings file currently has no plural entries (all entries are `stringUnit`). If a string needs plural handling (e.g. "1 video / 2 videos"), add it manually in Xcode using the plural editor, and preserve that locale entry. The script skips existing locales by default, but `--fix-lang` replaces them with `stringUnit` values regardless of `extractionState`; do not force-retranslate plural entries.
- **English coverage** — English source text is usually the key rather than a `localizations.en` entry; a low explicit-entry count is expected.
