#!/usr/bin/env python3
"""Checks the String Catalogs against the SwiftUI sources.

Fails when
- a literal shown by SwiftUI (Text, Button, Label, ...) or passed to String(localized:) has no catalog key,
- a catalog key is no longer used,
- a key lacks a translated English, Finnish or Swedish value, or a translation changes its format arguments.

Xcode compiles a missing key silently and shows the English text, so this runs in CI.

Limitation: Swift interpolations are matched by position, not type. `Text("\\(count) items")` needs the key
"%lld items" while a String interpolation needs "%@"; this script treats both as one placeholder, so check
the specifier when adding a key with a number in it.
"""

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LANGUAGES = ("en", "fi", "sv")

# A string literal directly passed to an API that takes a LocalizedStringKey or String.LocalizationValue.
LOCALIZED_LITERAL = re.compile(
    r"(?:\b(?:Text|Button|Label|Link|ProgressView|DisclosureGroup|Picker|navigationTitle)\(\s*"
    r"|\bString\(\s*localized:\s*)"
    r"\"((?:[^\"\\]|\\.)*)\""
)
FORMAT_SPECIFIER = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|lf|f|@)")


def without_interpolations(text):
    """Replaces each Swift interpolation, nested parentheses included, with a placeholder."""
    result, index = [], 0
    while index < len(text):
        if text.startswith("\\(", index):
            depth, index = 1, index + 2
            while index < len(text) and depth:
                depth += {"(": 1, ")": -1}.get(text[index], 0)
                index += 1
            result.append("%@")
        else:
            result.append(text[index])
            index += 1
    return "".join(result)


def placeholders(text):
    """Normalizes Swift interpolations and printf specifiers to one placeholder each."""
    return FORMAT_SPECIFIER.sub("%@", without_interpolations(text))


def values(localization):
    """Every value of one localization: a plain string unit or each plural variation."""
    if "stringUnit" in localization:
        yield localization["stringUnit"]
    for variants in localization.get("variations", {}).values():
        for variant in variants.values():
            yield variant["stringUnit"]


def check_catalog(path, errors):
    catalog = json.loads(path.read_text(encoding="utf-8"))
    if catalog.get("sourceLanguage") != "en":
        errors.append(f"{path.name}: source language must be en")
    for key, entry in catalog["strings"].items():
        # Marked as not translatable, or the app name Xcode copies from Info.plist when it syncs the catalog.
        if entry.get("shouldTranslate") is False or key.startswith("CFBundle"):
            continue
        expected = sorted(FORMAT_SPECIFIER.findall(key))
        for language in LANGUAGES:
            localization = entry.get("localizations", {}).get(language)
            units = list(values(localization)) if localization else []
            if not units:
                errors.append(f"{path.name}: “{key}” has no {language} value")
            for unit in units:
                if unit.get("state") != "translated" or not unit.get("value", "").strip():
                    errors.append(f"{path.name}: “{key}” is not translated to {language}")
                elif sorted(FORMAT_SPECIFIER.findall(unit["value"])) != expected:
                    errors.append(f"{path.name}: “{key}” changes its format arguments in {language}")
    return catalog["strings"]


def main():
    errors = []
    app = ROOT / "App"
    strings = check_catalog(app / "Localizable.xcstrings", errors)
    check_catalog(app / "InfoPlist.xcstrings", errors)

    keys = {placeholders(key): key for key in strings}
    used = set()
    for source in sorted(app.glob("*.swift")):
        for match in LOCALIZED_LITERAL.finditer(source.read_text(encoding="utf-8")):
            literal = placeholders(match.group(1))
            if literal in keys:
                used.add(keys[literal])
            else:
                errors.append(f"{source.name}: “{match.group(1)}” is not in Localizable.xcstrings")
    for key in sorted(set(strings) - used):
        errors.append(f"Localizable.xcstrings: “{key}” is not used by the app")

    for error in errors:
        print(f"error: {error}")
    print(f"{len(strings)} strings, {len(LANGUAGES)} languages, {len(errors)} problems")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
