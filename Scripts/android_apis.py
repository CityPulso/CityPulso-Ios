#!/usr/bin/env python3
"""Generate Swift API clients from the CityPulso-Android Retrofit interfaces.

Android is the source of truth for endpoints, the same as for copy, images, enums and DTOs. Every Retrofit `interface`
in an `api/*.kt` file becomes one Swift struct over `APIClient`, one method per endpoint:

  @GET/@POST/@PUT/@PATCH/@DELETE("path/{id}")  → client.request / client.send with the same method and path
  @Path("id") id: String                       → `id: String`, interpolated into the path
  @Query("k") k: Int? = null                   → `k: Int? = nil`, nil left out of the URL
  @Header("Idempotency-Key") key: String       → `idempotencyKey: String`, sent as that header
  @Body body: T = T()                          → `_ body: T = T()`
  : DataResponse<T>                            → returns `DataResponse<T>`; no return type → `send`

Which client (public or Bearer) an API gets is decided where it is registered, like Android's DI qualifiers.
Not generated (listed after a run): endpoints that stream a raw `ResponseBody`.

  pulsoloop/**/api/*.kt               → PulsoLoop/Data/Generated/*API.swift
  pulsonear/**/api/*.kt               → PulsoNear/Data/Generated/*API.swift
  pulsolink-core communication / location / payments / resource / realtime api
                                      → PulsoLinkCore/Sources/PulsoLinkCore/Base/Data/Generated (public)

Usage:
  python3 Scripts/android_apis.py           # write
  python3 Scripts/android_apis.py --check   # fail when a generated file differs from Android
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from android_dtos import COMMENTS, ident, swift_default, swift_type  # noqa: E402
from android_enums import ANDROID_ROOT, IOS_ROOT, doc_lines, kdoc, matching, split_top  # noqa: E402


@dataclass(frozen=True)
class Module:
    source: Path
    output: Path
    access: str = ""
    include: tuple[str, ...] = ()
    imports: tuple[str, ...] = ("Foundation", "PulsoLinkCore")


CORE = ANDROID_ROOT / "pulsolink-core/src/main/java/com/citypulso/pulsolink/base"

MODULES = [
    # auth / social / asset APIs in core are hand-written; the rest is generated.
    Module(
        CORE,
        IOS_ROOT / "PulsoLinkCore/Sources/PulsoLinkCore/Base/Data/Generated",
        "public ",
        ("data/communication", "data/location", "data/payments", "data/resource", "realtime"),
        ("Foundation",),
    ),
    Module(ANDROID_ROOT / "pulsoloop/src/main/java/com/citypulso/pulsoloop", IOS_ROOT / "PulsoLoop/Data/Generated"),
    Module(ANDROID_ROOT / "pulsonear/src/main/java/com/citypulso/pulsonear", IOS_ROOT / "PulsoNear/Data/Generated"),
]

TYPE_RENAMES = {"EmptyJsonBody": "EmptyBody"}
METHODS = {"GET": ".get", "POST": ".post", "PUT": ".put", "PATCH": ".patch", "DELETE": ".delete"}

notes: list[str] = []


def api_name(kotlin: str) -> str:
    return re.sub(r"Api$", "API", kotlin)


def mapped(kotlin_type: str) -> str:
    swift = swift_type(kotlin_type)
    for old, new in TYPE_RENAMES.items():
        swift = re.sub(rf"\b{old}\b", new, swift)
    return swift


def query_value(name: str, swift: str) -> str:
    base = swift.rstrip("?")
    convert = "$0" if base == "String" else ("$0.rawValue" if base not in ("Int", "Double", "Float", "Bool") else "String($0)")
    if swift.endswith("?"):
        return name if base == "String" else f"{name}.map {{ {convert} }}"
    return name if base == "String" else convert.replace("$0", name)


def resolve_path(expression: str, constants: dict[str, str]) -> str:
    """`"$ENTRY/courts"` / `ENTRY` → the literal path, with the file's `const val` strings filled in."""
    expression = expression.strip()
    if expression in constants:
        return constants[expression]
    if not expression.startswith('"'):
        raise ValueError(f"unsupported path {expression}")
    return re.sub(r"\$\{?([A-Z_][A-Z0-9_]*)\}?", lambda m: constants[m[1]], expression[1:-1])


def render_method(block: str, where: str, access: str, constants: dict[str, str]) -> list[str] | None:
    doc = kdoc(block)
    if "@Streaming" in block:
        notes.append(f"{where} (streams a raw body)")
        return None
    verb = re.search(r"@(GET|POST|PUT|PATCH|DELETE)\(([^)]*)\)", block)
    signature = re.search(r"suspend fun (\w+)\s*\(", block)
    if not verb or not signature:
        raise ValueError(f"{where}: unsupported endpoint {block.strip()[:120]}")
    start = signature.end() - 1
    close = matching(block, start, "(", ")")
    returns = re.match(r"\s*:\s*([\w<>?, ]+)", block[close + 1 :])
    result = mapped(returns[1].strip()) if returns else None
    if result in ("DataResponse<Unit>", "DataResponse<Unit?>", "Unit"):
        result = None
    if result == "ResponseBody":
        notes.append(f"{where}.{signature[1]} (returns a raw body)")
        return None

    params: list[str] = []
    path_args: dict[str, str] = {}
    query: list[str] = []
    headers: list[str] = []
    body = None
    for raw in split_top(block[start + 1 : close]):
        raw = COMMENTS.sub("", raw).strip()
        if not raw:
            continue
        match = re.fullmatch(r'@(Path|Query|Body|Header)(?:\("([^"]*)"\))?\s+(\w+)\s*:\s*(.+?)(?:\s*=\s*(.+))?', raw, re.S)
        if not match:
            raise ValueError(f"{where}.{signature[1]}: unsupported parameter {raw!r}")
        kind, wire, name, kotlin_type, default = match.groups()
        swift = mapped(kotlin_type.strip())
        default_swift = None
        if default is not None:
            default_swift = swift_default(default.strip(), swift)
            for old, new in TYPE_RENAMES.items():
                default_swift = re.sub(rf"\b{old}\b", new, default_swift)
        elif swift.endswith("?"):
            default_swift = "nil"
        suffix = f" = {default_swift}" if default_swift is not None else ""
        if kind == "Body":
            params.append(f"_ {ident(name)}: {swift}{suffix}")
            body = ident(name)
        else:
            params.append(f"{ident(name)}: {swift}{suffix}")
            if kind == "Path":
                path_args[wire or name] = ident(name)
            elif kind == "Query":
                query.append(f'"{wire or name}": {query_value(ident(name), swift)}')
            else:
                headers.append(f'"{wire}": {ident(name)}')

    path = re.sub(r"\{(\w+)\}", lambda m: f"\\({path_args[m[1]]})", resolve_path(verb[2], constants))
    args = [METHODS[verb[1]], f'"{path}"']
    if query:
        args.append(f"query: [{', '.join(query)}]")
    if headers:
        args.append(f"headers: [{', '.join(headers)}]")
    if body:
        args.append(f"body: {body}")
    call = "request" if result else "send"
    lines = doc_lines(doc, "    ")
    returns_swift = f" -> {result}" if result else ""
    lines.append(f"    {access}func {signature[1]}({', '.join(params)}) async throws{returns_swift} {{")
    lines.append(f"        try await client.{call}({', '.join(args)})")
    lines.append("    }")
    return lines


def render_interface(name: str, doc: str | None, body: str, where: str, access: str, constants: dict[str, str]) -> list[str]:
    lines = doc_lines(doc, "")
    lines += [
        f"{access}struct {api_name(name)}: Sendable {{",
        "    private let client: APIClient",
        "",
        f"    {access}init(client: APIClient) {{",
        "        self.client = client",
        "    }",
    ]
    # Each endpoint runs from the end of the previous one to the end of its own parameter list and return type.
    cursor = 0
    for match in re.finditer(r"suspend fun \w+\s*\(", body):
        if match.start() < cursor:
            continue
        close = matching(body, match.end() - 1, "(", ")")
        returns = re.match(r"\s*:\s*[\w<>?, ]+", body[close + 1 :])
        end = close + 1 + (returns.end() if returns else 0)
        method = render_method(body[cursor:end], f"{where}: {name}", access, constants)
        cursor = end
        if method:
            lines += [""] + method
    lines.append("}")
    return lines


def generate(module: Module) -> dict[Path, str]:
    files: dict[Path, str] = {}
    paths = sorted(module.source.rglob("api/*.kt"))
    if module.include:
        paths = [p for p in paths if any(str(p.relative_to(module.source)).startswith(i) for i in module.include)]
    for path in paths:
        text = path.read_text()
        constants = dict(re.findall(r'^(?:private\s+)?const val (\w+)\s*=\s*"([^"]*)"', text, re.M))
        body: list[str] = []
        for match in re.finditer(r"^interface (\w+)\s*\{", text, re.M):
            prefix = text[: match.start()]
            tail = re.search(r"(/\*\*(?:(?!\*/).)*\*/)\s*$", prefix, re.S)
            start = match.end() - 1
            inner = text[start + 1 : matching(text, start, "{", "}")]
            body += render_interface(match[1], kdoc(tail[1]) if tail else None, inner, path.name, module.access, constants) + [""]
        if not body:
            continue
        relative = path.relative_to(ANDROID_ROOT)
        lines = [f"// Generated by Scripts/android_apis.py from {relative} — do not edit.", "",
                 *[f"import {name}" for name in module.imports], "", *body]
        files[module.output / f"{api_name(path.stem)}.swift"] = "\n".join(lines).rstrip() + "\n"
    return files


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail when a generated file differs from Android")
    args = parser.parse_args()

    stale: list[Path] = []
    for module in MODULES:
        expected = generate(module)
        existing = set(module.output.glob("*API.swift")) if module.output.exists() else set()
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
            print(f"{module.output.relative_to(IOS_ROOT)}: {len(expected)} API files")
    if not args.check and notes:
        print("\nnot generated (hand-write where the app needs it):")
        for note in notes:
            print(f"  {note}")

    if args.check and stale:
        for path in stale:
            print(f"stale: {path.relative_to(IOS_ROOT)}", file=sys.stderr)
        print("run: python3 Scripts/android_apis.py", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
