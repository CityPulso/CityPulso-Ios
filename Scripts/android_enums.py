#!/usr/bin/env python3
"""Generate Swift enums from the CityPulso-Android Kotlin enums.

Android is the source of truth for closed value sets, the same as for copy (android_strings.py) and images
(android_assets.py). Every top-level `enum class` in an Android enums package becomes one Swift enum:

  enum class X(val wire: String, …)       → enum X: String, WireEnum  (rawValue = wire, fallback = DEFAULT or
                                             the first case, the same rule the hand-written core enums used)
  enum class X(@StringRes val labelRes…)  → enum X: CaseIterable      + `labelKey` (the strings-catalog key)
  every other constructor parameter       → a computed property with the same name and value
  KDoc on the enum and on each entry      → kept

Companion members other than DEFAULT / fromWire and functions in the enum body are not generated; their Swift
counterparts live in hand-written extensions next to the code that needs them.

  pulsolink-core/…/base/enums/*.kt   → PulsoLinkCore/Sources/PulsoLinkCore/Base/Enums/Generated (public)
  pulsoloop/…/pulsoloop/enums/*.kt   → PulsoLoop/Enums/Generated
  pulsonear/…/pulsonear/enums/*.kt   → PulsoNear/Enums/Generated

Usage:
  python3 Scripts/android_enums.py           # write
  python3 Scripts/android_enums.py --check   # fail when a generated file differs from Android
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

IOS_ROOT = Path(__file__).resolve().parent.parent
ANDROID_ROOT = IOS_ROOT.parent / "CityPulso-Android"


@dataclass(frozen=True)
class Module:
    source: Path
    output: Path
    access: str
    imports: tuple[str, ...]
    # Type of string-resource properties: apps hand them straight to Text; core has no SwiftUI.
    string_type: str


MODULES = [
    Module(
        ANDROID_ROOT / "pulsolink-core/src/main/java/com/citypulso/pulsolink/base/enums",
        IOS_ROOT / "PulsoLinkCore/Sources/PulsoLinkCore/Base/Enums/Generated",
        "public ",
        (),
        "String",
    ),
    Module(
        ANDROID_ROOT / "pulsoloop/src/main/java/com/citypulso/pulsoloop/enums",
        IOS_ROOT / "PulsoLoop/Enums/Generated",
        "",
        ("PulsoLinkCore", "SwiftUI"),
        "LocalizedStringKey",
    ),
    Module(
        ANDROID_ROOT / "pulsonear/src/main/java/com/citypulso/pulsonear/enums",
        IOS_ROOT / "PulsoNear/Enums/Generated",
        "",
        ("PulsoLinkCore", "SwiftUI"),
        "LocalizedStringKey",
    ),
]

SWIFT_KEYWORDS = {
    "associatedtype", "class", "default", "deinit", "enum", "extension", "fileprivate", "func", "import", "init",
    "inout", "internal", "let", "open", "operator", "private", "protocol", "public", "repeat", "rethrows", "return",
    "static", "struct", "subscript", "super", "switch", "throws", "true", "false", "try", "typealias", "var",
    "where", "while", "in", "is", "as", "case", "if", "else", "for", "do", "break", "continue", "self", "Self",
    "Type", "nil", "any", "some",
}

TYPES = {"String": "String", "Int": "Int", "Long": "Int64", "Float": "Float", "Double": "Double", "Boolean": "Bool"}
RESOURCE_PARAMS = {"labelRes": "labelKey", "hintRes": "hintKey", "titleRes": "titleKey", "bodyRes": "bodyKey", "iconRes": "iconAsset"}


def camel(name: str) -> str:
    """UPPER_SNAKE / lowerCamel → lowerCamel, Swift-safe."""
    if "_" in name or name.isupper():
        parts = name.lower().split("_")
        name = parts[0] + "".join(p.capitalize() for p in parts[1:])
    else:
        name = name[0].lower() + name[1:]
    if name[0].isdigit():
        name = "_" + name
    return f"`{name}`" if name in SWIFT_KEYWORDS else name


def split_top(text: str, separator: str = ",") -> list[str]:
    """Split on [separator] outside brackets, strings and comments."""
    parts, depth, current, i = [], 0, [], 0
    while i < len(text):
        c = text[i]
        if c == '"':
            end = i + 1
            while text[end] != '"':
                end += 2 if text[end] == "\\" else 1
            current.append(text[i : end + 1])
            i = end + 1
            continue
        if text.startswith("/*", i):
            end = text.index("*/", i) + 2
            current.append(text[i:end])
            i = end
            continue
        if text.startswith("//", i):
            end = text.find("\n", i)
            end = len(text) if end < 0 else end
            current.append(text[i:end])
            i = end
            continue
        if c in "([{<":
            depth += 1
        elif c in ")]}>":
            depth -= 1
        if c == separator and depth == 0:
            parts.append("".join(current))
            current = []
        else:
            current.append(c)
        i += 1
    if "".join(current).strip():
        parts.append("".join(current))
    return parts


def matching(text: str, start: int, open_c: str, close_c: str) -> int:
    """Index of the bracket closing the one at [start], skipping strings and comments."""
    depth, i = 0, start
    while i < len(text):
        c = text[i]
        if c == '"':
            i += 1
            while text[i] != '"':
                i += 2 if text[i] == "\\" else 1
        elif text.startswith("/*", i):
            i = text.index("*/", i) + 1
        elif text.startswith("//", i):
            i = text.find("\n", i)
        elif c == open_c:
            depth += 1
        elif c == close_c:
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise ValueError("unbalanced brackets")


def kdoc(text: str) -> str | None:
    """The last /** … */ block in [text] as Swift doc lines, or None."""
    blocks = re.findall(r"/\*\*(.*?)\*/", text, re.S)
    if not blocks:
        return None
    lines = [re.sub(r"^\s*\*\s?", "", line).rstrip() for line in blocks[-1].strip().splitlines()]
    lines = [line for line in lines if line.strip()]
    return "\n".join(lines) if lines else None


def doc_lines(doc: str | None, indent: str) -> list[str]:
    if not doc:
        return []
    lines = doc.splitlines()
    if len(lines) == 1:
        return [f"{indent}/** {lines[0]} */"]
    return [f"{indent}/**", *[f"{indent} * {line}" for line in lines], f"{indent} */"]


@dataclass
class Param:
    name: str
    kotlin_type: str
    default: str | None = None

    @property
    def swift_name(self) -> str:
        return RESOURCE_PARAMS.get(self.name, self.name)

    @property
    def is_resource(self) -> bool:
        return self.name in RESOURCE_PARAMS or self.name.endswith("Res")


@dataclass
class Entry:
    name: str
    args: list[str]
    doc: str | None
    serial_name: str | None = None


@dataclass
class KotlinEnum:
    name: str
    doc: str | None
    params: list[Param]
    entries: list[Entry]
    default: str | None
    skipped: list[str] = field(default_factory=list)
    serializable: bool = False


def swift_type(kotlin: str) -> str:
    kotlin = kotlin.strip()
    if kotlin.endswith("?"):
        return swift_type(kotlin[:-1]) + "?"
    list_match = re.fullmatch(r"List<(.+)>", kotlin)
    if list_match:
        return f"[{swift_type(list_match[1])}]"
    return TYPES.get(kotlin, kotlin)


def swift_value(kotlin: str) -> str:
    value = kotlin.strip()
    value = re.sub(r"/\*.*?\*/|//[^\n]*", "", value, flags=re.S).strip()
    if value in ("null", "true", "false"):
        return {"null": "nil"}.get(value, value)
    resource = re.fullmatch(r"R\.\w+\.(\w+)", value)
    if resource:
        return f'"{resource[1]}"'
    if value.startswith('"'):
        return value
    list_match = re.fullmatch(r"(?:listOf|setOf)\((.*)\)", value, re.S)
    if list_match:
        return "[" + ", ".join(swift_value(v) for v in split_top(list_match[1])) + "]"
    if value == "emptyList()":
        return "[]"
    member = re.fullmatch(r"[A-Z]\w*\.([A-Z][A-Z0-9_]*)", value)
    if member:
        return "." + camel(member[1])
    number = re.fullmatch(r"(-?(?:0x[0-9A-Fa-f_]+|[0-9_.]+))[LuUfF]*", value)
    if number:
        return number[1]
    raise ValueError(f"unsupported value: {value}")


def parse_params(text: str) -> list[Param]:
    params = []
    for raw in split_top(text):
        raw = re.sub(r"/\*.*?\*/|//[^\n]*", "", raw, flags=re.S)
        raw = re.sub(r"@\w+(\([^)]*\))?", "", raw).strip()
        if not raw:
            continue
        match = re.fullmatch(r"(?:val|var)\s+(\w+)\s*:\s*(.+?)(\s*=.*)?", raw, re.S)
        if not match:
            raise ValueError(f"unsupported parameter: {raw}")
        default = match[3].strip()[1:].strip() if match[3] else None
        params.append(Param(match[1], match[2].strip(), default))
    return params


def parse_file(path: Path) -> list[KotlinEnum]:
    text = path.read_text()
    enums = []
    for match in re.finditer(r"^enum class (\w+)\s*(\()?", text, re.M):
        name = match[1]
        prefix = text[: match.start()]
        # KDoc directly above (annotations such as @Serializable may sit in between).
        tail = re.search(r"(/\*\*(?:(?!\*/).)*\*/)\s*(?:@\w+(?:\([^)]*\))?\s*)*$", prefix, re.S)
        doc = kdoc(tail[1]) if tail else None
        cursor = match.end()
        params: list[Param] = []
        if match[2]:
            close = matching(text, match.end() - 1, "(", ")")
            params = parse_params(text[match.end() : close])
            cursor = close + 1
        body_start = text.index("{", cursor)
        body_end = matching(text, body_start, "{", "}")
        body = text[body_start + 1 : body_end]
        entries_text = body
        semicolon = top_level_semicolon(body)
        rest = ""
        if semicolon is not None:
            entries_text, rest = body[:semicolon], body[semicolon + 1 :]
        entries = []
        for raw in split_top(entries_text):
            entry_doc = kdoc(raw)
            serial = re.search(r'@SerialName\("([^"]+)"\)', raw)
            cleaned = re.sub(r"/\*.*?\*/|//[^\n]*", "", raw, flags=re.S)
            cleaned = re.sub(r"@\w+(\([^)]*\))?", "", cleaned).strip()
            if not cleaned:
                continue
            entry = re.fullmatch(r"(\w+)\s*(?:\((.*)\))?\s*(\{.*\})?", cleaned, re.S)
            if not entry:
                raise ValueError(f"{path.name}: {name}: unsupported entry {cleaned!r}")
            args = [a.strip() for a in split_top(entry[2])] if entry[2] and entry[2].strip() else []
            entries.append(Entry(entry[1], ordered_args(args, params, f"{path.name}: {name}.{entry[1]}"), entry_doc, serial[1] if serial else None))
        default = re.search(r"val DEFAULT(?:\s*:\s*\w+)?\s*=\s*(\w+)", rest)
        members = re.findall(r"^\s*(?:(?:private|internal|override|inline|const)\s+)*(?:val|fun)\s+(?:<[^>]*>\s*)?(?:[\w.]+\.)?(\w+)", rest, re.M)
        skipped = [m for m in members if m not in ("DEFAULT", "fromWire")]
        serializable = bool(re.search(r"@Serializable\s*(?:@\w+(?:\([^)]*\))?\s*)*$", prefix))
        enums.append(KotlinEnum(name, doc, params, entries, default[1] if default else None, skipped, serializable))
    return enums


def ordered_args(args: list[str], params: list[Param], where: str) -> list[str]:
    """Positional or `name = value` arguments → values in parameter order."""
    named = {}
    positional = []
    for arg in args:
        cleaned = re.sub(r"/\*.*?\*/|//[^\n]*", "", arg, flags=re.S).strip()
        match = re.fullmatch(r"(\w+)\s*=(?!=)\s*(.+)", cleaned, re.S)
        if match and any(p.name == match[1] for p in params):
            named[match[1]] = match[2]
        else:
            positional.append(arg)
    out = []
    for index, param in enumerate(params):
        if param.name in named:
            out.append(named[param.name])
        elif index < len(positional):
            out.append(positional[index])
        elif param.default is not None:
            out.append(param.default)
        else:
            raise ValueError(f"{where}: missing argument {param.name}")
    return out


def top_level_semicolon(body: str) -> int | None:
    depth, i = 0, 0
    while i < len(body):
        c = body[i]
        if c == '"':
            i += 1
            while body[i] != '"':
                i += 2 if body[i] == "\\" else 1
        elif body.startswith("/*", i):
            i = body.index("*/", i) + 1
        elif body.startswith("//", i):
            i = body.find("\n", i)
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == ";" and depth == 0:
            return i
        i += 1
    return None


def render(enum: KotlinEnum, access: str, string_type: str) -> list[str]:
    wire = next((p for p in enum.params if p.name == "wire" and p.kotlin_type == "String"), None)
    wire_index = enum.params.index(wire) if wire else None
    # Without a `wire` property, a @Serializable enum goes on the wire by @SerialName, else by its constant name.
    by_serial = wire is None and enum.serializable
    lines = doc_lines(enum.doc, "")
    conformance = "String, WireEnum" if wire or by_serial else "CaseIterable, Codable, Sendable, Hashable"
    lines.append(f"{access}enum {enum.name}: {conformance} {{")
    for entry in enum.entries:
        lines += doc_lines(entry.doc, "    ")
        case = camel(entry.name)
        if wire is not None or by_serial:
            raw = swift_value(entry.args[wire_index]) if wire is not None else f'"{entry.serial_name or entry.name}"'
            plain = case.strip("`")
            lines.append(f"    case {case}" if raw == f'"{plain}"' else f"    case {case} = {raw}")
        else:
            lines.append(f"    case {case}")
    if wire is not None or by_serial:
        fallback = camel(enum.default) if enum.default else camel(enum.entries[0].name)
        lines += ["", f"    {access}static let fallback: {enum.name} = .{fallback}"]
    for index, param in enumerate(enum.params):
        if param is wire:
            continue
        kind = swift_type(param.kotlin_type)
        if param.is_resource:
            kind = "String" if param.name == "iconRes" or "drawable" in "".join(enum_args(enum, index)) else string_type
        name = param.swift_name if param.is_resource else param.name
        if param.is_resource and param.name not in RESOURCE_PARAMS:
            name = param.name[: -len("Res")] + "Key"
        lines += ["", f"    {access}var {camel(name)}: {kind} {{", "        switch self {"]
        for entry in enum.entries:
            lines.append(f"        case .{camel(entry.name)}: {swift_value(entry.args[index])}")
        lines += ["        }", "    }"]
        if param.name == "labelRes" and kind == "LocalizedStringKey":
            # Android reads the same @StringRes with getString() too (text the user keeps, e.g. equipment names).
            lines += ["", f"    {access}var labelResource: String.LocalizationValue {{", "        switch self {"]
            for entry in enum.entries:
                lines.append(f"        case .{camel(entry.name)}: {swift_value(entry.args[index])}")
            lines += ["        }", "    }"]
    lines.append("}")
    return lines


notes: list[str] = []


def enum_args(enum: KotlinEnum, index: int) -> list[str]:
    return [entry.args[index] for entry in enum.entries]


def render_lists(text: str, enums: list[KotlinEnum], access: str) -> list[str]:
    """Top-level `const val` literals and `val NAME = listOf(Enum.A, Enum.B)` over an enum of this file → Swift constants."""
    names = {enum.name for enum in enums}
    lines: list[str] = []
    number = r"-?[0-9][0-9_.]*[LfF]?"
    for match in re.finditer(rf"^const val (\w+)\s*=\s*(\"[^\"]*\"|{number}(?:\s*\*\s*{number})*)\s*$", text, re.M):
        before = text[: match.start()]
        tail = before[max(before.rfind("}"), before.rfind("\n\n")) + 1 :]
        doc = kdoc(tail) if "/**" in tail else None
        value = " * ".join(swift_value(factor) for factor in match.group(2).split("*"))
        lines += doc_lines(doc, "") + [f"{access}let {camel(match.group(1))} = {value}", ""]
    for match in re.finditer(rf"^val (\w+)\s*=\s*listOf\(((?:\s*{number}\s*,?)+)\)\s*$", text, re.M):
        before = text[: match.start()]
        doc = kdoc(before[before.rfind("}") + 1 :]) if "/**" in before[before.rfind("}") + 1 :] else None
        items = [swift_value(item) for item in match.group(2).split(",") if item.strip()]
        kind = "Double" if any("." in item for item in items) else "Int"
        lines += doc_lines(doc, "") + [f"{access}let {camel(match.group(1))}: [{kind}] = [{', '.join(items)}]", ""]
    for match in re.finditer(r"^val (\w+)\s*=\s*listOf\(([^)]*)\)", text, re.M):
        items = [item.strip() for item in match.group(2).split(",") if item.strip()]
        types = {item.split(".")[0] for item in items}
        if len(types) != 1 or not types <= names or not all(item.count(".") == 1 for item in items):
            continue
        before = text[: match.start()]
        doc = kdoc(before[before.rfind("}") + 1 :]) if "/**" in before[before.rfind("}") + 1 :] else None
        cases = ", ".join(f".{camel(item.split('.')[1])}" for item in items)
        lines += doc_lines(doc, "") + [f"{access}let {camel(match.group(1))}: [{types.pop()}] = [{cases}]", ""]
    return lines


def generate(module: Module) -> dict[Path, str]:
    files = {}
    for path in sorted(module.source.glob("*.kt")):
        enums = parse_file(path)
        if not enums:
            continue
        relative = path.relative_to(ANDROID_ROOT)
        lines = [f"// Generated by Scripts/android_enums.py from {relative} — do not edit.", ""]
        lines += [f"import {name}" for name in module.imports]
        if module.imports:
            lines.append("")
        for enum in enums:
            lines += render(enum, module.access, module.string_type) + [""]
            for member in enum.skipped:
                notes.append(f"{relative.name}: {enum.name}.{member}")
        lines += render_lists(path.read_text(), enums, module.access)
        files[module.output / f"{path.stem}.swift"] = "\n".join(lines).rstrip() + "\n"
    return files


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail when a generated file differs from Android")
    args = parser.parse_args()

    stale: list[Path] = []
    for module in MODULES:
        expected = generate(module)
        existing = set(module.output.glob("*.swift")) if module.output.exists() else set()
        for path in sorted(existing - expected.keys()):
            stale.append(path)
            if not args.check:
                path.unlink()
        for path, content in expected.items():
            if path.exists() and path.read_text() == content:
                continue
            stale.append(path)
            if not args.check:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content)
        if not args.check:
            print(f"{module.output.relative_to(IOS_ROOT)}: {len(expected)} files")
    if not args.check and notes:
        print("\nnot generated (hand-write a Swift extension where the app needs it):")
        for note in notes:
            print(f"  {note}")

    if args.check and stale:
        for path in stale:
            print(f"stale: {path.relative_to(IOS_ROOT)}", file=sys.stderr)
        print("run: python3 Scripts/android_enums.py", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
