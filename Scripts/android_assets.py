#!/usr/bin/env python3
"""Generate the iOS asset catalogs from CityPulso-Android drawables and the shared logos.

Android is the source of truth for in-app images, the same as for copy (see android_strings.py):

  res/drawable-nodpi/<name>.png|webp      → Assets.xcassets/<name>.imageset
  <name>_light + <name>_dark              → one imageset <name> with a dark-appearance variant
  res/drawable-zh-nodpi/<name>.*          → zh-Hans / zh-Hant localized variant of that imageset
  .icons/inputs/logos/<app>/*.png         → AppIcon.appiconset (1024 px, Any + Dark), the logo centered on
                                             the Android adaptive-icon background colors

WebP without transparency becomes JPEG (asset catalogs take PNG / JPEG); PNG is copied byte for byte.

Usage:
  python3 Scripts/android_assets.py           # write
  python3 Scripts/android_assets.py --check   # fail when a catalog differs from Android
"""

from __future__ import annotations

import argparse
import io
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

from PIL import Image

IOS_ROOT = Path(__file__).resolve().parent.parent
CITYPULSO_ROOT = IOS_ROOT.parent
ANDROID_ROOT = CITYPULSO_ROOT / "CityPulso-Android"
LOGOS = CITYPULSO_ROOT / ".icons/inputs/logos"

ICON_SIZE = 1024
# The mark fills this share of the icon, like the Android adaptive-icon safe zone.
ICON_MARK_SCALE = 0.72
# Android res/values/ic_launcher_{light,dark}_background.xml (same for Loop and Near).
ICON_LIGHT_BACKGROUND = (0xFD, 0xF8, 0xF0)
ICON_DARK_BACKGROUND = (0x05, 0x06, 0x07)
JPEG_QUALITY = 88


@dataclass(frozen=True)
class AppAssets:
    android_module: str | None
    ios_dir: str
    icon_light: str
    icon_dark: str
    # CityPulso has a single dark-ink logo, so its dark-appearance icon keeps the light background.
    icon_dark_background: tuple[int, int, int] = ICON_DARK_BACKGROUND


APPS = [
    AppAssets("pulsoloop", "PulsoLoop", "pulsoloop/youloopy.png", "pulsoloop/youloopy_dark.png"),
    AppAssets("pulsonear", "PulsoNear", "pulsonear/Youneary.png", "pulsonear/youneary_dark.png"),
    # Placeholder app (Android `pulsolink` is "Hello Android" too): only the icon.
    AppAssets(None, "PulsoLink", "citypulso/logo.png", "citypulso/logo.png", ICON_LIGHT_BACKGROUND),
]

LOCALIZED_DIRS = {"drawable-zh-nodpi": ["zh-Hans", "zh-Hant"]}
THEMED = re.compile(r"^(?P<base>.+)_(?P<theme>light|dark)$")
INFO = {"author": "xcode", "version": 1}


def dumps(value: dict) -> bytes:
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()


def encode(source: Path) -> tuple[str, bytes]:
    """Returns (extension, bytes) for a drawable."""
    if source.suffix == ".png":
        return ".png", source.read_bytes()
    image = Image.open(source)
    buffer = io.BytesIO()
    if image.mode in ("RGBA", "LA") and image.getextrema()[-1][0] < 255:
        image.save(buffer, "PNG", optimize=True)
        return ".png", buffer.getvalue()
    image.convert("RGB").save(buffer, "JPEG", quality=JPEG_QUALITY, optimize=True)
    return ".jpg", buffer.getvalue()


def drawables(res: Path, directory: str) -> dict[str, Path]:
    folder = res / directory
    if not folder.is_dir():
        return {}
    return {p.stem: p for p in sorted(folder.iterdir()) if p.suffix in (".png", ".webp")}


def imagesets(module: str) -> dict[Path, bytes]:
    """Relative path inside Assets.xcassets → file bytes."""
    res = ANDROID_ROOT / module / "src/main/res"
    base = drawables(res, "drawable-nodpi")
    localized = {d: drawables(res, d) for d in LOCALIZED_DIRS}

    groups: dict[str, dict[str, str]] = {}
    for stem in base:
        match = THEMED.match(stem)
        name, theme = (match["base"], match["theme"]) if match else (stem, "any")
        groups.setdefault(name, {})[theme] = stem

    files: dict[Path, bytes] = {}
    for name, themes in sorted(groups.items()):
        folder = Path(f"{name}.imageset")
        entries = []

        def add(stem: str, source: Path, theme: str, locale: str | None) -> None:
            extension, data = encode(source)
            filename = f"{stem}{'_' + locale if locale else ''}{extension}"
            files[folder / filename] = data
            entry: dict = {"filename": filename, "idiom": "universal"}
            if theme == "dark":
                entry["appearances"] = [{"appearance": "luminosity", "value": "dark"}]
            if locale:
                entry["locale"] = locale
            entries.append(entry)

        for theme in ("any", "light", "dark"):
            stem = themes.get(theme)
            if stem is None:
                continue
            add(stem, base[stem], theme, None)
            for directory, locales in LOCALIZED_DIRS.items():
                if stem in localized[directory]:
                    for locale in locales:
                        add(stem, localized[directory][stem], theme, locale)

        contents: dict = {"images": entries, "info": INFO}
        if any("locale" in e for e in entries):
            contents["properties"] = {"localizable": True}
        files[folder / "Contents.json"] = dumps(contents)
    return files


def icon(logo: Path, background: tuple[int, int, int]) -> bytes:
    mark = Image.open(logo).convert("RGBA")
    box = mark.getchannel("A").getbbox() or (0, 0, *mark.size)
    mark = mark.crop(box)
    target = int(ICON_SIZE * ICON_MARK_SCALE)
    ratio = target / max(mark.size)
    mark = mark.resize((round(mark.width * ratio), round(mark.height * ratio)), Image.LANCZOS)
    canvas = Image.new("RGBA", (ICON_SIZE, ICON_SIZE), (*background, 255))
    canvas.alpha_composite(mark, ((ICON_SIZE - mark.width) // 2, (ICON_SIZE - mark.height) // 2))
    buffer = io.BytesIO()
    canvas.convert("RGB").save(buffer, "PNG", optimize=True)
    return buffer.getvalue()


def app_icon(app: AppAssets) -> dict[Path, bytes]:
    """AppIcon (light + dark appearance), the AppIcon-Dark alternate (dark everywhere, the "dark" launcher icon
    pack), and both as plain images for the app-icon settings page."""
    light = icon(LOGOS / app.icon_light, ICON_LIGHT_BACKGROUND)
    dark = icon(LOGOS / app.icon_dark, app.icon_dark_background)
    single = lambda filename: {"images": [{"filename": filename, "idiom": "universal", "platform": "ios", "size": "1024x1024"}], "info": INFO}
    preview = lambda filename: {"images": [{"filename": filename, "idiom": "universal"}], "info": INFO}
    files = {
        Path("AppIcon-Dark.appiconset/icon_dark.png"): dark,
        Path("AppIcon-Dark.appiconset/Contents.json"): dumps(single("icon_dark.png")),
        Path("app_icon_preview.imageset/icon.png"): light,
        Path("app_icon_preview.imageset/Contents.json"): dumps(preview("icon.png")),
        Path("app_icon_preview_dark.imageset/icon_dark.png"): dark,
        Path("app_icon_preview_dark.imageset/Contents.json"): dumps(preview("icon_dark.png")),
    }
    folder = Path("AppIcon.appiconset")
    contents = {
        "images": [
            {"filename": "icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
            {
                "appearances": [{"appearance": "luminosity", "value": "dark"}],
                "filename": "icon_dark.png",
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024",
            },
        ],
        "info": INFO,
    }
    return files | {
        folder / "icon.png": light,
        folder / "icon_dark.png": dark,
        folder / "Contents.json": dumps(contents),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail when a catalog differs from Android")
    args = parser.parse_args()

    stale: list[Path] = []
    for app in APPS:
        catalog = IOS_ROOT / app.ios_dir / "Resources/Assets.xcassets"
        expected = {Path("Contents.json"): dumps({"info": INFO})}
        expected |= app_icon(app) if app.android_module else {
            path: data for path, data in app_icon(app).items() if path.parts[0] == "AppIcon.appiconset"
        }
        if app.android_module:
            expected |= imagesets(app.android_module)

        existing = {p.relative_to(catalog) for p in catalog.rglob("*") if p.is_file()} if catalog.exists() else set()
        for path in sorted(existing - expected.keys()):
            stale.append(catalog / path)
            if not args.check:
                (catalog / path).unlink()
        for path, data in sorted(expected.items()):
            target = catalog / path
            if target.exists() and target.read_bytes() == data:
                continue
            stale.append(target)
            if not args.check:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
        if not args.check:
            for folder in sorted((p for p in catalog.rglob("*") if p.is_dir()), reverse=True):
                if not any(folder.iterdir()):
                    folder.rmdir()
            print(f"{app.ios_dir}: {sum(1 for p in expected if p.name == 'Contents.json') - 1} sets")

    if args.check and stale:
        for path in stale:
            print(f"stale: {path.relative_to(IOS_ROOT)}", file=sys.stderr)
        print("run: python3 Scripts/android_assets.py", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
