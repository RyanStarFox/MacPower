#!/usr/bin/env python3
"""Checks that run before a pull request is worth building."""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = {
    "de",
    "en",
    "es",
    "fr",
    "it",
    "ja",
    "ko",
    "pt-BR",
    "ru",
    "zh-Hans",
    "zh-Hant",
}


def load_without_duplicate_keys(path: Path):
    def pairs(seq):
        seen = {}
        for key, value in seq:
            if key in seen:
                raise SystemExit(f"{path}: 重复的键 {key}")
            seen[key] = value
        return seen

    with path.open(encoding="utf-8") as handle:
        return json.load(handle, object_pairs_hook=pairs)


def main() -> None:
    catalog = ROOT / "MacPower" / "Localizable.xcstrings"
    notes = ROOT / "MacPower" / "ReleaseNotes.json"
    load_without_duplicate_keys(catalog)
    parsed = load_without_duplicate_keys(notes)
    missing = LANGUAGES - set(parsed)
    if missing:
        raise SystemExit(f"{notes}: 缺少语言 {', '.join(sorted(missing))}")
    print("catalog ok")


if __name__ == "__main__":
    sys.exit(main())
