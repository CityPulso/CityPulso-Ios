#!/usr/bin/env python3
"""Android string resources → Xcode String Catalogs (one-way, Android is the source of truth).

Copy is written once for all clients (WEB i18n / API / Android). The iOS apps reuse the
Android keys, so this script regenerates every `.xcstrings` from CityPulso-Android:

    python3 scripts/android_strings.py           # write catalogs
    python3 scripts/android_strings.py --check   # fail if a catalog is stale (CI)

Mapping:
- `values` (zh) → zh-Hans (source language), `values-b+zh+Hant` → zh-Hant, `values-en` → en, `values-fr` → fr
- `%1$s` → `%1$@`, `%1$d` → `%1$lld` (Swift Int is 64-bit), Android escapes (\\' \\" \\n \\@ \\?) unescaped
- `<plurals>` → catalog plural variations; `app_name` → InfoPlist catalog `CFBundleDisplayName`
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

IOS_ROOT = Path(__file__).resolve().parent.parent
ANDROID_ROOT = IOS_ROOT.parent / "CityPulso-Android"

SOURCE_LANGUAGE = "zh-Hans"
LANGUAGE_DIRS = {
    "values": "zh-Hans",
    "values-b+zh+Hant": "zh-Hant",
    "values-en": "en",
    "values-fr": "fr",
}

# Android module → iOS output directory (relative to CityPulso-Ios).
TARGETS = {
    "pulsolink-ui": "PulsoLinkUI/Sources/PulsoLinkUI/Resources",
    "pulsoloop": "PulsoLoop/Resources",
    "pulsonear": "PulsoNear/Resources",
}

FORMAT = re.compile(r"%(\d+\$)?([sd])")
ESCAPES = {"\\'": "'", '\\"': '"', "\\n": "\n", "\\t": "\t", "\\@": "@", "\\?": "?"}


def convert_text(raw: str, plural: bool = False) -> str:
    """Android escapes and %s/%d → iOS %@/%lld.

    In a plural item the first placeholder is the count (Android writes it as %1$s and passes an Int);
    Xcode only selects a plural form from a numeric argument, so it always becomes %lld there.
    """
    text = raw
    if len(text) >= 2 and text[0] == text[-1] == '"':
        text = text[1:-1]
    for escaped, plain in ESCAPES.items():
        text = text.replace(escaped, plain)
    seen = 0

    def replace(match: re.Match) -> str:
        nonlocal seen
        seen += 1
        numeric = match.group(2) == "d" or (plural and seen == 1)
        return f"%{match.group(1) or ''}{'lld' if numeric else '@'}"

    return FORMAT.sub(replace, text)


def element_text(element: ET.Element, plural: bool = False) -> str:
    # Inline markup (<b>, <xliff:g>) keeps only its text.
    return convert_text("".join(element.itertext()), plural)


def read_module(module: str) -> tuple[dict[str, dict], dict[str, str]]:
    """Returns (strings[key][lang] = value | {plural: {...}}, app_name[lang])."""
    strings: dict[str, dict] = {}
    app_names: dict[str, str] = {}
    res = ANDROID_ROOT / module / "src/main/res"
    for directory, language in LANGUAGE_DIRS.items():
        for file in sorted((res / directory).glob("strings*.xml")):
            for element in ET.parse(file).getroot():
                name = element.get("name")
                if not name or element.get("translatable") == "false" and language != SOURCE_LANGUAGE:
                    continue
                if element.tag == "string":
                    value = element_text(element)
                    if name == "app_name":
                        app_names[language] = value
                        continue
                    strings.setdefault(name, {})[language] = value
                elif element.tag == "plurals":
                    forms = {item.get("quantity"): element_text(item, plural=True) for item in element.findall("item")}
                    strings.setdefault(name, {})[language] = {"plural": forms}
    return strings, app_names


def unit(value: str) -> dict:
    return {"stringUnit": {"state": "translated", "value": value}}


def localization(value: str | dict) -> dict:
    if isinstance(value, str):
        return unit(value)
    return {"variations": {"plural": {form: unit(text) for form, text in value["plural"].items()}}}


def catalog(entries: dict[str, dict[str, str | dict]]) -> str:
    body = {
        "sourceLanguage": SOURCE_LANGUAGE,
        "strings": {
            key: {
                "extractionState": "manual",
                "localizations": {lang: localization(v) for lang, v in sorted(langs.items())},
            }
            for key, langs in sorted(entries.items())
        },
        "version": "1.0",
    }
    return json.dumps(body, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


# Info.plist 权限说明 ← Android 设置里同一项权限的说明（iOS 系统弹窗里显示）。
INFO_PLIST_STRINGS = {
    "NSLocationWhenInUseUsageDescription": "settings_permission_location_body",
    "NSCameraUsageDescription": "settings_permission_camera_body",
    "NSPhotoLibraryUsageDescription": "settings_permission_photos_body",
    "NSMicrophoneUsageDescription": "settings_permission_microphone_body",
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail when a catalog differs from Android")
    args = parser.parse_args()

    stale: list[Path] = []
    for module, out_dir in TARGETS.items():
        strings, app_names = read_module(module)
        outputs = {}
        if strings:
            outputs[IOS_ROOT / out_dir / "Localizable.xcstrings"] = catalog(strings)
        if app_names:
            info = {"CFBundleDisplayName": app_names}
            info |= {key: strings[source] for key, source in INFO_PLIST_STRINGS.items() if source in strings}
            outputs[IOS_ROOT / out_dir / "InfoPlist.xcstrings"] = catalog(info)
        for path, content in outputs.items():
            current = path.read_text(encoding="utf-8") if path.exists() else None
            if current == content:
                continue
            if args.check:
                stale.append(path)
                continue
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
            print(f"wrote {path.relative_to(IOS_ROOT)} ({len(json.loads(content)['strings'])} keys)")

    if stale:
        print("stale catalogs (run scripts/android_strings.py):", *map(str, stale), sep="\n  ", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
