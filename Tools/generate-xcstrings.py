#!/usr/bin/env python3
"""Erzeugt den String-Katalog aus den Texten in Strings.swift.

Der Katalog `Resources/Localizable.xcstrings` ist die offizielle Lokalisierungs-
datei der App. Die bärndütschen Texte stehen in `Resources/Strings.swift` als
`defaultValue` direkt neben dem Schlüssel – dieses Skript liest sie dort aus und
schreibt sie in den Katalog.

Aufruf (aus dem Ordner Raepplispauter/):

    python3 Tools/generate-xcstrings.py

Interpolationen (`\\(name)`) werden zu `%@` bzw. `%lld` umgesetzt, wie es der
String-Katalog erwartet.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Raepplispauter" / "Resources" / "Strings.swift"
TARGET = ROOT / "Raepplispauter" / "Resources" / "Localizable.xcstrings"

# Kurzform:  t("schlüssel", "text")
SHORT_PATTERN = re.compile(
    r'\bt\(\s*"(?P<key>[^"]+)"\s*,\s*"(?P<value>(?:[^"\\]|\\.)*)"\s*\)',
    re.DOTALL,
)

# Langform:  String(localized: "schlüssel", defaultValue: "text")
FULL_PATTERN = re.compile(
    r'String\(\s*localized:\s*"(?P<key>[^"]+)"\s*,\s*defaultValue:\s*"(?P<value>(?:[^"\\]|\\.)*)"',
    re.DOTALL,
)

# Parameter, die im Quelltext als Int deklariert sind, brauchen %lld statt %@.
INT_PARAMETERS = {"count"}

# Interpolation im Swift-Literal: \(ausdruck)
INTERPOLATION = re.compile(r"\\\((?P<expr>[^()]*)\)")


def swift_literal_to_catalog_value(raw: str) -> str:
    """Wandelt ein Swift-Stringliteral in einen Katalogeintrag um."""

    def replace(match: re.Match) -> str:
        expression = match.group("expr").strip()
        return "%lld" if expression in INT_PARAMETERS else "%@"

    value = INTERPOLATION.sub(replace, raw)
    # Escapes des Swift-Literals auflösen.
    value = value.replace('\\"', '"').replace("\\\\", "\\").replace("\\n", "\n")
    return value


def main() -> int:
    if not SOURCE.exists():
        print(f"Strings.swift nicht gefunden: {SOURCE}", file=sys.stderr)
        return 1

    source = SOURCE.read_text(encoding="utf-8")
    strings: dict[str, dict] = {}

    matches = list(SHORT_PATTERN.finditer(source)) + list(FULL_PATTERN.finditer(source))
    for match in matches:
        key = match.group("key")
        value = swift_literal_to_catalog_value(match.group("value"))
        strings[key] = {
            "extractionState": "manual",
            "localizations": {
                "de": {
                    "stringUnit": {
                        "state": "translated",
                        "value": value,
                    }
                }
            },
        }

    catalog = {
        "sourceLanguage": "de",
        "strings": dict(sorted(strings.items())),
        "version": "1.0",
    }

    TARGET.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"{len(strings)} Texte nach {TARGET.relative_to(ROOT)} geschrieben.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
