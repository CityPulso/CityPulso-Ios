#!/usr/bin/env python3
"""Generate Swift Codable DTOs from the CityPulso-Android `@Serializable data class` files.

Android is the source of truth for wire shapes, the same as for copy, images and enums. Every `@Serializable data class`
in an app's `*/dto/*.kt` becomes one Swift struct with the semantics of Android's `WireJson`:

  missing or null field         → the Kotlin default (`coerceInputValues`); a field without a default must be present
  `@JsonNames("a", "b")`        → extra keys tried when decoding
  encoding                      → nil is left out (`explicitNulls = false`), so is a value equal to its default
                                  (`encodeDefaults = false`)
  `const val X = …`             → a `let` constant
  KDoc                          → kept

Keys are the Kotlin property names; `WireCoding`'s snake_case strategies map them to and from the wire.
Not generated (listed after a run, hand-write them next to the code that needs them): generic classes, sealed hierarchies,
interfaces, custom serializers, and members declared in a class body.

  pulsoloop/src/main/**/dto/*.kt → PulsoLoop/Data/Generated/*.swift
  pulsonear/src/main/**/dto/*.kt → PulsoNear/Data/Generated/*.swift

Usage:
  python3 Scripts/android_dtos.py           # write
  python3 Scripts/android_dtos.py --check   # fail when a generated file differs from Android
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from android_enums import ANDROID_ROOT, IOS_ROOT, camel, doc_lines, kdoc, matching, split_top  # noqa: E402


@dataclass(frozen=True)
class Module:
    source: Path
    output: Path
    access: str = ""
    # Sub-trees of [source] to read; empty reads everything.
    include: tuple[str, ...] = ()
    imports: tuple[str, ...] = ("Foundation", "PulsoLinkCore")
    # A few request / response classes live next to their Retrofit interface.
    patterns: tuple[str, ...] = ("dto/*.kt", "api/*.kt")


CORE_BASE = ANDROID_ROOT / "pulsolink-core/src/main/java/com/citypulso/pulsolink/base"

MODULES = [
    # auth / social / asset DTOs in core are hand-written (custom preference decoding); the rest is generated.
    Module(
        CORE_BASE,
        IOS_ROOT / "PulsoLinkCore/Sources/PulsoLinkCore/Base/Data/Generated",
        "public ",
        ("data/communication", "data/location", "data/payments", "data/resource", "data/social", "realtime"),
        ("Foundation",),
    ),
    Module(
        ANDROID_ROOT / "pulsolink-core/src/main/java/com/citypulso/pulsolink/core/common",
        IOS_ROOT / "PulsoLinkCore/Sources/PulsoLinkCore/Core/Common/Generated",
        "public ",
        (),
        ("Foundation",),
        ("Geometry.kt",),
    ),
    # Persisted filter shapes live in features/search.
    Module(
        ANDROID_ROOT / "pulsoloop/src/main/java/com/citypulso/pulsoloop",
        IOS_ROOT / "PulsoLoop/Data/Generated",
        patterns=("dto/*.kt", "api/*.kt", "features/search/NearbyFilters.kt"),
    ),
    Module(
        ANDROID_ROOT / "pulsonear/src/main/java/com/citypulso/pulsonear",
        IOS_ROOT / "PulsoNear/Data/Generated",
        patterns=("dto/*.kt", "api/*.kt", "features/search/NearbyFilters.kt"),
    ),
]

SWIFT_KEYWORDS = {
    "associatedtype", "class", "default", "deinit", "enum", "extension", "fileprivate", "func", "import", "init",
    "inout", "internal", "let", "open", "operator", "private", "protocol", "public", "repeat", "rethrows", "return",
    "static", "struct", "subscript", "super", "switch", "throws", "var", "where", "while", "in", "is", "as", "case",
    "if", "else", "for", "do", "break", "continue", "self", "Self", "Type", "nil", "true", "false", "any", "some",
}

SCALARS = {
    "String": "String", "Int": "Int", "Long": "Int", "Short": "Int", "Double": "Double", "Float": "Float",
    "Boolean": "Bool", "JsonElement": "WireJSON", "JsonObject": "[String: WireJSON]",
}

COMMENTS = re.compile(r"/\*.*?\*/|//[^\n]*", re.S)
ANNOTATION = re.compile(r"@[\w.]+(?:\((?:[^()]|\([^()]*\))*\))?")


def ident(name: str) -> str:
    return f"`{name}`" if name in SWIFT_KEYWORDS else name


def swift_type(kotlin: str) -> str:
    kotlin = re.sub(r"\s+", "", kotlin)
    if kotlin.endswith("?"):
        return swift_type(kotlin[:-1]) + "?"
    generic = re.fullmatch(r"(\w+)<(.+)>", kotlin)
    if generic:
        name, args = generic[1], [swift_type(a) for a in split_top(generic[2])]
        if name in ("List", "MutableList", "Collection"):
            return f"[{args[0]}]"
        if name == "Set":
            return f"Set<{args[0]}>"
        if name == "Map":
            return f"[{args[0]}: {args[1]}]"
        return f"{name}<{', '.join(args)}>"
    return SCALARS.get(kotlin, kotlin)


def swift_default(kotlin: str, swift: str) -> str:
    value = COMMENTS.sub("", kotlin).strip()
    if value == "null":
        return "nil"
    if value in ("true", "false") or value.startswith('"'):
        return value
    if value in ("emptyList()", "emptySet()", "listOf()", "setOf()"):
        return "[]"
    if value in ("emptyMap()", "mapOf()", "JsonObject(emptyMap())"):
        return "[:]"
    listed = re.fullmatch(r"(?:listOf|setOf)\((.*)\)", value, re.S)
    if listed:
        element = re.fullmatch(r"\[(.*)\]\??|Set<(.*)>\??", swift)
        inner = (element[1] or element[2]) if element else swift
        return "[" + ", ".join(swift_default(v, inner) for v in split_top(listed[1])) + "]"
    wire = re.fullmatch(r"([A-Z]\w*)\.([A-Z][A-Z0-9_]*)\.wire", value)
    if wire:
        case = "fallback" if wire[2] == "DEFAULT" else camel(wire[2]).strip("`")
        return f"{wire[1]}.{case}.rawValue"
    member = re.fullmatch(r"[A-Z]\w*\.([A-Z][A-Z0-9_]*)", value)
    if member:
        return ".fallback" if member[1] == "DEFAULT" else "." + camel(member[1]).strip("`")
    if re.fullmatch(r"[A-Z][A-Z0-9_]+", value):
        return camel(value).strip("`")  # a `const val`
    construct = re.fullmatch(r"([A-Z]\w*)\(\)", value)
    if construct:
        return f"{construct[1]}()"
    number = re.fullmatch(r"(-?[0-9][0-9_]*(?:\.[0-9_]+)?)[LfF]?", value)
    if number:
        return number[1] + (".0" if swift.rstrip("?") in ("Double", "Float") and "." not in number[1] else "")
    raise ValueError(f"unsupported default: {value}")


@dataclass
class Prop:
    name: str
    kotlin_type: str
    default: str | None
    alternates: list[str]
    doc: str | None

    @property
    def swift_type(self) -> str:
        return swift_type(self.kotlin_type)

    @property
    def optional(self) -> bool:
        return self.swift_type.endswith("?")

    @property
    def swift_default(self) -> str | None:
        if self.default is None:
            return "nil" if self.optional else None
        return swift_default(self.default, self.swift_type)


@dataclass
class DataClass:
    name: str
    doc: str | None
    props: list[Prop]
    source: str
    skipped: list[str] = field(default_factory=list)

    @property
    def defaults(self) -> int:
        return sum(p.default is not None for p in self.props)

    def signature(self) -> list[tuple[str, str, str | None]]:
        return [(p.name, p.swift_type, p.swift_default) for p in self.props]


@dataclass
class Sealed:
    """`@JsonClassDiscriminator(key) sealed interface` → Swift enum with one case per `@SerialName` subtype."""
    name: str
    doc: str | None
    discriminator: str
    shared: list[Prop]
    cases: list[tuple[str, str]] = field(default_factory=list)  # (serial name, subtype)


def wire_camel(name: str) -> str:
    """A JSON key as Swift's convertFromSnakeCase sees it."""
    if "_" not in name.strip("_"):
        return name
    head, *rest = [part for part in name.split("_") if part]
    return head + "".join(part[:1].upper() + part[1:] for part in rest)


def parse_props(text: str, where: str) -> list[Prop]:
    props = []
    for raw in split_top(text):
        doc = kdoc(raw)
        alternates: list[str] = []
        for annotation in ANNOTATION.findall(raw):
            if annotation.startswith("@JsonNames"):
                alternates += re.findall(r'"([^"]+)"', annotation)
            elif annotation.startswith("@SerialName"):
                alternates.insert(0, re.findall(r'"([^"]+)"', annotation)[0])
            elif annotation.startswith("@Serializable("):
                raise ValueError(f"{where}: custom serializer on {raw.strip()}")
        cleaned = ANNOTATION.sub("", COMMENTS.sub("", raw)).strip()
        if not cleaned:
            continue
        match = re.fullmatch(r"(?:override\s+)?(?:val|var)\s+(\w+)\s*:\s*(.+?)(?:\s*=\s*(.+))?", cleaned, re.S)
        if not match:
            raise ValueError(f"{where}: unsupported property {cleaned!r}")
        props.append(Prop(match[1], match[2].strip(), match[3].strip() if match[3] else None, alternates, doc))
    return props


def parse_file(path: Path) -> tuple[list[DataClass], list[tuple[str, str, str | None]], list[str], list[Sealed]]:
    text = path.read_text()
    sealed: dict[str, Sealed] = {}
    for match in re.finditer(r'@JsonClassDiscriminator\("(\w+)"\)\s*sealed interface (\w+)\s*\{', text):
        prefix = text[: match.start()]
        tail = re.search(r"(/\*\*(?:(?!\*/).)*\*/)\s*(?:@[\w.]+(?:\([^)]*\))?\s*)*$", prefix, re.S)
        start = match.end() - 1
        shared = parse_props(text[start + 1 : matching(text, start, "{", "}")].replace("\n", ","), f"{path.name}: {match[2]}")
        sealed[match[2]] = Sealed(match[2], kdoc(tail[1]) if tail else None, match[1], shared)
    classes: list[DataClass] = []
    constants: list[tuple[str, str, str | None]] = []
    skipped: list[str] = []
    for match in re.finditer(r"^((?:@[\w.]+(?:\([^)]*\))?\s*)*)data class (\w+)(<[^>]*>)?\s*\(", text, re.M):
        annotations, name = match[1], match[2]
        where = f"{path.name}: {name}"
        if "@Serializable" not in annotations:
            skipped.append(f"{name} (not @Serializable)")
            continue
        serial = re.search(r'@SerialName\("([^"]+)"\)', annotations)
        if match[3]:
            skipped.append(f"{name} (generic)")
            continue
        prefix = text[: match.start()]
        tail = re.search(r"(/\*\*(?:(?!\*/).)*\*/)\s*$", prefix, re.S)
        close = matching(text, match.end() - 1, "(", ")")
        data = DataClass(name, kdoc(tail[1]) if tail else None, parse_props(text[match.end():close], where), path.name)
        after = text[close + 1 :]
        parent = re.match(r"\s*:\s*(\w+)", after)
        if serial and parent and parent[1] in sealed:
            sealed[parent[1]].cases.append((serial[1], name))
        elif serial:
            skipped.append(f"{name} (@SerialName subtype of an unknown parent)")
            continue
        body = re.match(r"\s*(?::\s*[\w<>, ]+)?\s*\{", after)
        if body:
            start = close + 1 + body.end() - 1
            members = re.findall(r"^\s*(?:override\s+)?(?:val|fun)\s+(?:[\w.]+\.)?(\w+)", text[start : matching(text, start, "{", "}")], re.M)
            data.skipped = members
        classes.append(data)
    for match in re.finditer(r"^((?:/\*\*(?:(?!\*/).)*\*/\s*)?)const val (\w+)(?:\s*:\s*\w+)?\s*=\s*([^\n]+)", text, re.M | re.S):
        constants.append((match[2], match[3].strip(), kdoc(match[1]) if match[1] else None))
    for match in re.finditer(r"^(?:sealed\s+)?(interface|sealed class|class|object) (\w+)", text, re.M):
        if match[2] not in sealed:
            skipped.append(f"{match[2]} ({match[1]})")
    return classes, constants, skipped, list(sealed.values())


def render_class(data: DataClass, access: str) -> list[str]:
    lines = doc_lines(data.doc, "")
    lines.append(f"{access}struct {data.name}: Codable, Sendable, Hashable {{")
    for prop in data.props:
        lines += doc_lines(prop.doc, "    ")
        lines.append(f"    {access}var {ident(prop.name)}: {prop.swift_type}")

    params = []
    for prop in data.props:
        default = prop.swift_default
        params.append(f"{ident(prop.name)}: {prop.swift_type}" + (f" = {default}" if default is not None else ""))
    joined = ", ".join(params)
    lines += ["", f"    {access}init({joined}) {{"]
    lines += [f"        self.{ident(p.name)} = {ident(p.name)}" for p in data.props]
    lines.append("    }")

    lines += ["", f"    {access}init(from decoder: any Decoder) throws {{"]
    if data.props:
        lines.append("        let container = try decoder.container(keyedBy: WireKey.self)")
    for prop in data.props:
        names = [prop.name] + [wire_camel(a) for a in prop.alternates]
        keys = ", ".join(f'"{n}"' for n in dict.fromkeys(names))
        base = prop.swift_type.rstrip("?")
        default = prop.swift_default
        if prop.default is None and not prop.optional:
            lines.append(f"        {ident(prop.name)} = try container.wireRequired({base}.self, {keys})")
        elif default == "nil":
            lines.append(f"        {ident(prop.name)} = try container.wire({base}.self, {keys})")
        else:
            lines.append(f"        {ident(prop.name)} = try container.wire({base}.self, {keys}) ?? {default}")
    lines.append("    }")

    lines += ["", f"    {access}func encode(to encoder: any Encoder) throws {{"]
    if data.props:
        lines.append("        var container = encoder.container(keyedBy: WireKey.self)")
    for prop in data.props:
        default = prop.swift_default
        if prop.optional:
            lines.append(f'        try container.wireOptional({ident(prop.name)}, "{prop.name}")')
        elif default is None:
            lines.append(f'        try container.wire({ident(prop.name)}, "{prop.name}")')
        else:
            lines.append(f'        try container.wire({ident(prop.name)}, "{prop.name}", default: {default})')
    lines += ["    }", "}"]
    return lines


def render_sealed(sealed: Sealed, access: str) -> list[str]:
    lines = doc_lines(sealed.doc, "")
    lines.append(f"{access}enum {sealed.name}: Codable, Sendable, Hashable {{")
    cases = [(serial, sub, sub[0].lower() + sub[1:]) for serial, sub in sealed.cases]
    lines += [f"    case {ident(case)}({sub})" for _, sub, case in cases]
    for prop in sealed.shared:
        lines += ["", f"    {access}var {ident(prop.name)}: {prop.swift_type} {{", "        switch self {"]
        lines += [f"        case let .{ident(case)}(value): value.{ident(prop.name)}" for _, _, case in cases]
        lines += ["        }", "    }"]
    lines += ["", f"    {access}init(from decoder: any Decoder) throws {{",
              "        let container = try decoder.container(keyedBy: WireKey.self)",
              f'        switch try container.wireRequired(String.self, "{sealed.discriminator}") {{']
    lines += [f'        case "{serial}": self = .{ident(case)}(try {sub}(from: decoder))' for serial, sub, case in cases]
    lines += ["        case let other:",
              f'            throw DecodingError.dataCorruptedError(forKey: WireKey("{sealed.discriminator}"), in: container, debugDescription: "unknown {sealed.name} \\(other)")',
              "        }", "    }", "", f"    {access}func encode(to encoder: any Encoder) throws {{",
              "        var container = encoder.container(keyedBy: WireKey.self)", "        switch self {"]
    for serial, _, case in cases:
        lines += [f"        case let .{ident(case)}(value):",
                  f'            try container.encode("{serial}", forKey: WireKey("{sealed.discriminator}"))',
                  "            try value.encode(to: encoder)"]
    lines += ["        }", "    }", "}"]
    return lines


def render_constant(name: str, value: str, doc: str | None, access: str) -> list[str]:
    swift = re.sub(r"(?<=\d)[LfF]$", "", COMMENTS.sub("", value).strip())
    return doc_lines(doc, "") + [f"{access}let {camel(name).strip('`')} = {swift}"]


notes: list[str] = []


def generate(module: Module) -> dict[Path, str]:
    files: dict[Path, str] = {}
    seen: dict[str, DataClass] = {}
    parsed = []
    paths = sorted({p for pattern in module.patterns for p in module.source.rglob(pattern)})
    if module.include:
        paths = [p for p in paths if any(str(p.relative_to(module.source)).startswith(i) for i in module.include)]
    for path in paths:
        classes, constants, skipped, sealed = parse_file(path)
        notes.extend(f"{path.name}: {s}" for s in skipped)
        for data in classes:
            notes.extend(f"{path.name}: {data.name}.{m} (class body)" for m in data.skipped)
            other = seen.get(data.name)
            if other is None or data.defaults > other.defaults:
                if other is not None and other.signature() != data.signature():
                    notes.append(f"{data.name}: differs in {other.source} and {path.name}, using {path.name}")
                seen[data.name] = data
            elif other.signature() != data.signature():
                notes.append(f"{data.name}: differs in {other.source} and {path.name}, using {other.source}")
        parsed.append((path, classes, constants, sealed))

    for path, classes, constants, sealed in parsed:
        relative = path.relative_to(ANDROID_ROOT)
        body: list[str] = []
        for name, value, doc in constants:
            body += render_constant(name, value, doc, module.access) + [""]
        for hierarchy in sealed:
            body += render_sealed(hierarchy, module.access) + [""]
        for data in classes:
            if seen.get(data.name) is data:
                body += render_class(data, module.access) + [""]
        if not body:
            continue
        lines = [f"// Generated by Scripts/android_dtos.py from {relative} — do not edit.", "",
                 *[f"import {name}" for name in module.imports], "", *body]
        stem = path.stem.replace("Dtos", "DTOs") if "Dtos" in path.stem else f"{path.stem}DTOs"
        files[module.output / f"{stem}.swift"] = "\n".join(lines).rstrip() + "\n"
    return files


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail when a generated file differs from Android")
    args = parser.parse_args()

    stale: list[Path] = []
    for module in MODULES:
        expected = generate(module)
        # The same folder holds android_apis.py's *API.swift files.
        existing = {p for p in module.output.glob("*.swift") if not p.name.endswith("API.swift")} if module.output.exists() else set()
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
        print("\nnot generated (hand-write a Swift counterpart where the app needs it):")
        for note in notes:
            print(f"  {note}")

    if args.check and stale:
        for path in stale:
            print(f"stale: {path.relative_to(IOS_ROOT)}", file=sys.stderr)
        print("run: python3 Scripts/android_dtos.py", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
