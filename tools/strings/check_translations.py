#!/usr/bin/env python3
"""Checks the hand translations in translations/<code>.json against the English source.

Usage:
  tools/strings/check_translations.py export <out.json>   # every key with its English and Chinese text
  tools/strings/check_translations.py check [codes...]    # validates translation files (all by default)

A translation file is a JSON object {key: text} for every key in the app's catalogs, with the same
format specifiers (%@, %lld, %1$.0f, %%) as the English text.
"""

import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).parent
ROOT = HERE.parents[1]
TRANSLATIONS = HERE / "translations"
SPECIFIER = re.compile(r"%(?:\d+\$)?[-#+ 0,(]*\d*(?:\.\d+)?(?:ll)?[@dfsu%]")


def source() -> dict[str, dict[str, str]]:
    """Every key in the two catalogs: {key: {"en": ..., "zh-Hans": ...}}."""
    out = {}
    for catalog in ("Localizable.xcstrings", "InfoPlist.xcstrings"):
        for key, entry in json.loads((ROOT / "Euphona" / catalog).read_text())["strings"].items():
            if entry.get("extractionState") != "manual":
                continue
            loc = entry["localizations"]
            out[key] = {code: text(loc[code]) for code in ("en", "zh-Hans") if code in loc}
    return out


def text(localization: dict) -> str:
    """A plain string, or the 'other' form of a plural or device variation."""
    if "stringUnit" in localization:
        return localization["stringUnit"]["value"]
    (variation,) = localization["variations"].values()
    return variation["other"]["stringUnit"]["value"]


def specifiers(text: str) -> list[str]:
    """The format specifiers, positions dropped: %1$lld and %lld are the same lone argument."""
    return sorted(re.sub(r"\d+\$", "", spec) for spec in SPECIFIER.findall(text))


def check(code: str, strings: dict) -> list[str]:
    path = TRANSLATIONS / f"{code}.json"
    try:
        table = json.loads(path.read_text())
    except Exception as error:
        return [f"{code}: unreadable ({error})"]
    problems = []
    for key in sorted(set(strings) - set(table)):
        problems.append(f"{code}: missing {key}")
    for key in sorted(set(table) - set(strings)):
        problems.append(f"{code}: unknown key {key}")
    for key, text in table.items():
        if key not in strings or not isinstance(text, str):
            continue
        if not text.strip():
            problems.append(f"{code}: empty {key}")
        if specifiers(text) != specifiers(strings[key]["en"]):
            problems.append(f"{code}: {key} has {specifiers(text)}, English has {specifiers(strings[key]['en'])}")
    return problems


def main() -> None:
    if len(sys.argv) >= 3 and sys.argv[1] == "export":
        Path(sys.argv[2]).write_text(json.dumps(source(), ensure_ascii=False, indent=1))
        return
    if len(sys.argv) >= 2 and sys.argv[1] == "check":
        strings = source()
        codes = sys.argv[2:] or sorted(p.stem for p in TRANSLATIONS.glob("*.json"))
        problems = [p for code in codes for p in check(code, strings)]
        for p in problems[:200]:
            print(p)
        print(f"{len(codes)} languages, {len(strings)} keys, {len(problems)} problems")
        sys.exit(1 if problems else 0)
    sys.exit(__doc__)


if __name__ == "__main__":
    main()
