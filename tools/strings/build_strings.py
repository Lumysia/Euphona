#!/usr/bin/env python3
"""Builds the app's String Catalogs from Euphona's own strings.

Usage: tools/strings/build_strings.py

strings.json holds every string in English and Simplified Chinese: {key: {language: text}}, in Apple
format; Xcode generates Swift symbols from the keys (`nav_settings` -> `.navSettings`). Other
languages are translated in translations/<code>.json ({key: text}, checked by check_translations.py).
plurals.json adds plural variations, mac.json Mac wording ("Click" for "Tap"), and
infoplist_strings.json the permission prompts (into InfoPlist.xcstrings). Only keys the code uses are
written. The app's languages are the project's supported localizations.
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).parent
CATALOG = ROOT / "Euphona" / "Localizable.xcstrings"
INFOPLIST_CATALOG = ROOT / "Euphona" / "InfoPlist.xcstrings"
PROJECT = ROOT / "Euphona.xcodeproj" / "project.xcproj"
SOURCE_LANGUAGE = "en"
STRINGS = HERE / "strings.json"
INFOPLIST_STRINGS = HERE / "infoplist_strings.json"
TRANSLATIONS = HERE / "translations"
# Strings with a count, as plural variations: {key: {language: {category: text}}}.
PLURALS = HERE / "plurals.json"
# Strings worded differently on Mac, as device variations: {key: {language: text}}.
MAC = HERE / "mac.json"

# Only strings the app's code uses are written.
SOURCES = [ROOT / "Euphona", ROOT / "Packages" / "EuphonaKit" / "Sources" / "Swift"]
# Keys built at runtime, as `localized(key: "prefix_\(...)")`: every key with that prefix is used.
DYNAMIC_KEY = re.compile(r'localized\(key: "([a-z0-9_]+)\\\(')


def languages() -> list[str]:
    """The project's development language and supported localizations, Base excluded."""
    text = PROJECT.read_text()
    development = re.search(r'"development":\s*"([^"]+)"', text).group(1)
    block = re.search(r'"supported":\s*\[(.*?)\]', text, re.S).group(1)
    return [development] + [code for code in re.findall(r'"([^"]+)"', block) if code not in ("Base", development)]


def symbol(key: str) -> str:
    """The Swift symbol Xcode generates for a key: `nav_dashboard` -> `navDashboard`."""
    head, *rest = key.split("_")
    return head + "".join(part[:1].upper() + part[1:] for part in rest)


def used_keys(keys) -> set[str]:
    code = "\n".join(path.read_text() for folder in SOURCES for path in folder.rglob("*.swift"))
    identifiers = set(re.findall(r"[A-Za-z_][A-Za-z0-9_]*", code))
    literals = set(re.findall(r'"([a-z0-9_]+)"', code))
    prefixes = tuple(DYNAMIC_KEY.findall(code))
    return {key for key in keys if symbol(key) in identifiers or key in literals or key.startswith(prefixes)}


def unit(text: str) -> dict:
    return {"stringUnit": {"state": "translated", "value": text}}


def write_catalog(path: Path, entries: dict) -> None:
    """Writes entries in Xcode's own format, so building in Xcode leaves the file unchanged. This script
    owns the "manual" entries; strings Xcode extracts from code (chart labels, the bundle name) are kept."""
    if path.exists():
        for key, entry in json.loads(path.read_text())["strings"].items():
            if entry.get("extractionState") != "manual" and key not in entries:
                entries[key] = entry
    catalog = {"sourceLanguage": SOURCE_LANGUAGE, "strings": entries, "version": "1.0"}
    path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True, separators=(",", " : ")) + "\n")


def main() -> None:
    codes = languages()
    strings = json.loads(STRINGS.read_text())
    translations = {path.stem: json.loads(path.read_text()) for path in sorted(TRANSLATIONS.glob("*.json"))}
    for code in translations:
        if code not in codes:
            sys.exit(f"translations/{code}.json is not a project language")

    used = used_keys(strings)
    entries = {}
    for key in sorted(used):
        texts = strings[key] | {code: table[key] for code, table in translations.items() if key in table}
        entries[key] = {"extractionState": "manual", "localizations": {code: unit(text) for code, text in texts.items()}}

    # Counted strings become plural variations; a language without them keeps its single string.
    for key, by_language in json.loads(PLURALS.read_text()).items():
        if key not in strings:
            sys.exit(f"plural {key} matches no string")
        if key not in entries:
            continue
        for code, forms in by_language.items():
            if "other" not in forms:
                sys.exit(f"plural {key} ({code}) needs an 'other' form")
            entries[key]["localizations"][code] = {"variations": {"plural": {category: unit(text) for category, text in forms.items()}}}

    # Mac wording becomes a device variation; every other device keeps the plain string.
    for key, by_language in json.loads(MAC.read_text()).items():
        if key not in strings:
            sys.exit(f"mac {key} matches no string")
        for code, text in by_language.items():
            plain = entries.get(key, {}).get("localizations", {}).get(code, {}).get("stringUnit")
            if plain is None:
                continue
            entries[key]["localizations"][code] = {"variations": {"device": {"mac": unit(text), "other": {"stringUnit": plain}}}}

    write_catalog(CATALOG, entries)
    missing = {code: len(used) - sum(key in strings and code in entries[key]["localizations"] for key in used) for code in codes}
    print(f"{len(entries)} keys, {len(codes)} languages -> {CATALOG.relative_to(ROOT)}")

    plist = {}
    for key, texts in json.loads(INFOPLIST_STRINGS.read_text()).items():
        texts = texts | {code: table[key] for code, table in translations.items() if key in table}
        if set(texts) != set(codes):
            sys.exit(f"{key} needs exactly the {len(codes)} app languages")
        plist[key] = {"extractionState": "manual", "localizations": {code: unit(text) for code, text in texts.items()}}
    write_catalog(INFOPLIST_CATALOG, plist)
    untranslated = {code: count for code, count in missing.items() if count}
    if untranslated:
        print("untranslated keys per language:", untranslated)


if __name__ == "__main__":
    main()
