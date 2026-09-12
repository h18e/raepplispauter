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

# Funktionssignatur, z. B.:  public static func foo(_ number: Int, _ name: String) -> String
FUNC_SIGNATURE = re.compile(
    r"public static func \w+\((?P<params>[^)]*)\)\s*->\s*String"
)

# Ein einzelner Parameter:  _ number: Int   bzw.   name: String
PARAMETER = re.compile(r"(?:\w+\s+)?(?P<name>\w+)\s*:\s*(?P<type>\w+)")

# Interpolation im Swift-Literal: \(ausdruck)
INTERPOLATION = re.compile(r"\\\((?P<expr>[^()]*)\)")

# Format-Spezifikatoren je Swift-Typ. Stimmen sie nicht mit dem überein, was
# die App zur Laufzeit übergibt, liest Foundation den Wert als Zeiger und die
# App stürzt mit EXC_BAD_ACCESS ab – deshalb wird der Typ hier aus der
# Signatur gelesen und nicht am Parameternamen geraten.
FORMAT_BY_TYPE = {
    "Int": "%lld",
    "Int32": "%d",
    "Int64": "%lld",
    "Double": "%lf",
    "Float": "%f",
    "String": "%@",
}


def parameter_types(source: str, position: int) -> dict[str, str]:
    """Parametertypen der Funktion, in der die Fundstelle steht.

    Sucht rückwärts ab der Fundstelle nach der nächstgelegenen Signatur.
    """
    last = None
    for match in FUNC_SIGNATURE.finditer(source, 0, position):
        last = match
    if last is None:
        return {}
    return {
        param.group("name"): param.group("type")
        for param in PARAMETER.finditer(last.group("params"))
    }


def swift_literal_to_catalog_value(raw: str, types: dict[str, str], key: str) -> str:
    """Wandelt ein Swift-Stringliteral in einen Katalogeintrag um."""

    def replace(match: re.Match) -> str:
        expression = match.group("expr").strip()
        swift_type = types.get(expression)
        if swift_type is None:
            raise SystemExit(
                f"FEHLER bei «{key}»: Der Platzhalter \\({expression}) lässt sich keinem "
                f"Parameter zuordnen. Bekannte Parameter: {sorted(types) or 'keine'}.\n"
                f"Ohne bekannten Typ wäre der Format-Spezifikator geraten – das führt "
                f"zur Laufzeit zu einem Absturz."
            )
        if swift_type not in FORMAT_BY_TYPE:
            raise SystemExit(
                f"FEHLER bei «{key}»: Für den Typ «{swift_type}» ist kein "
                f"Format-Spezifikator hinterlegt. Bitte in FORMAT_BY_TYPE ergänzen."
            )
        return FORMAT_BY_TYPE[swift_type]

    # Enthält der Text Platzhalter, wird er zur Laufzeit als Format-String
    # verarbeitet. Dann muss ein gemeintes Prozentzeichen ("100 %") verdoppelt
    # werden, sonst deutet Foundation es als Spezifikator. Ohne Platzhalter
    # findet keine Formatierung statt – dort bliebe "%%" sichtbar stehen.
    if INTERPOLATION.search(raw):
        raw = raw.replace("%", "%%")

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
        types = parameter_types(source, match.start())
        value = swift_literal_to_catalog_value(match.group("value"), types, key)
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
