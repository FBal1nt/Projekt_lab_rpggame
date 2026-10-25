#!/usr/bin/env python3
"""Lightweight, dependency-free checks for the RPG project's data resources.

Run from any working directory:
    python tools/validate_project.py

This does not replace opening the project in Godot; it catches common content
integration mistakes before the team opens the editor.
"""

from __future__ import annotations

import re
import sys
from collections import defaultdict
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
TEXT_EXTENSIONS = {".gd", ".tscn", ".tres", ".godot", ".svg", ".md"}
RESOURCE_REFERENCE = re.compile(r"res://[A-Za-z0-9_./-]+")
STRING_ID = re.compile(r'^\s*id\s*=\s*&?"([^"]+)"', re.MULTILINE)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def parse_packed_string_array(text: str, property_name: str) -> list[str]:
    match = re.search(
        rf'^\s*{re.escape(property_name)}\s*=\s*PackedStringArray\((.*?)\)\s*$',
        text,
        re.MULTILINE,
    )
    if not match:
        return []
    return re.findall(r'"([^"]*)"', match.group(1))


def parse_packed_int_array(text: str, property_name: str) -> list[int]:
    match = re.search(
        rf'^\s*{re.escape(property_name)}\s*=\s*PackedInt32Array\((.*?)\)\s*$',
        text,
        re.MULTILINE,
    )
    if not match:
        return []
    return [int(value) for value in re.findall(r"-?\d+", match.group(1))]


def resource_id(path: Path) -> str | None:
    match = STRING_ID.search(read_text(path))
    return match.group(1) if match else None


def check_resource_paths(errors: list[str]) -> int:
    checked = 0
    for path in PROJECT_ROOT.rglob("*"):
        if not path.is_file() or path.suffix not in TEXT_EXTENSIONS:
            continue
        for match in RESOURCE_REFERENCE.finditer(read_text(path)):
            checked += 1
            relative_target = match.group(0).removeprefix("res://")
            if not (PROJECT_ROOT / relative_target).exists():
                errors.append(f"Missing res:// reference in {path.relative_to(PROJECT_ROOT)}: {match.group(0)}")
    return checked


def check_unique_ids(relative_directory: str, errors: list[str]) -> tuple[int, set[str]]:
    directory = PROJECT_ROOT / relative_directory
    seen: dict[str, Path] = {}
    ids: set[str] = set()
    for path in sorted(directory.rglob("*.tres")):
        identifier = resource_id(path)
        if not identifier:
            errors.append(f"Missing ID in {path.relative_to(PROJECT_ROOT)}")
            continue
        if identifier in seen:
            errors.append(
                f"Duplicate ID '{identifier}' in {path.relative_to(PROJECT_ROOT)} "
                f"and {seen[identifier].relative_to(PROJECT_ROOT)}"
            )
            continue
        seen[identifier] = path
        ids.add(identifier)
    return len(ids), ids


def main() -> int:
    errors: list[str] = []
    path_count = check_resource_paths(errors)

    summary = {}
    known_ids = {}
    for directory, label in [
        ("Data/Items", "items"),
        ("Data/CharacterClasses", "character classes"),
        ("Data/SmithingRecipes", "smithing recipes"),
        ("Data/Enchantments", "enchantments"),
        ("Data/Dungeons", "dungeons"),
    ]:
        count, ids = check_unique_ids(directory, errors)
        summary[label] = count
        known_ids[directory] = ids

    item_ids = known_ids["Data/Items"]
    for directory in (PROJECT_ROOT / "Data/SmithingRecipes", PROJECT_ROOT / "Data/Enchantments"):
        for path in sorted(directory.rglob("*.tres")):
            text = read_text(path)
            ingredient_ids = parse_packed_string_array(text, "ingredient_item_ids")
            ingredient_amounts = parse_packed_int_array(text, "ingredient_amounts")
            if len(ingredient_ids) != len(ingredient_amounts):
                errors.append(
                    f"Ingredient ID/count mismatch in {path.relative_to(PROJECT_ROOT)} "
                    f"({len(ingredient_ids)} IDs, {len(ingredient_amounts)} quantities)"
                )
            for item_id in ingredient_ids:
                if item_id and item_id not in item_ids:
                    errors.append(
                        f"Unknown ingredient '{item_id}' in {path.relative_to(PROJECT_ROOT)}"
                    )
            if directory.name == "SmithingRecipes":
                output_match = re.search(r'^\s*result_item_id\s*=\s*&?"([^"]*)"', text, re.MULTILINE)
                if output_match and output_match.group(1) and output_match.group(1) not in item_ids:
                    errors.append(
                        f"Unknown recipe output '{output_match.group(1)}' in {path.relative_to(PROJECT_ROOT)}"
                    )

    dungeon_ids = known_ids["Data/Dungeons"]
    for path in sorted((PROJECT_ROOT / "Data/DungeonDifficulties").rglob("*.tres")):
        text = read_text(path)
        dungeon_match = re.search(r'^\s*dungeon_id\s*=\s*&?"([^"]+)"', text, re.MULTILINE)
        if not dungeon_match or dungeon_match.group(1) not in dungeon_ids:
            errors.append(f"Unknown/missing dungeon_id in {path.relative_to(PROJECT_ROOT)}")
        enemy_ids = parse_packed_string_array(text, "enemy_type_ids")
        enemy_names = parse_packed_string_array(text, "enemy_type_names")
        if enemy_names and len(enemy_names) != len(enemy_ids):
            errors.append(
                f"Enemy ID/name count mismatch in {path.relative_to(PROJECT_ROOT)} "
                f"({len(enemy_ids)} IDs, {len(enemy_names)} names)"
            )

    scripts = list((PROJECT_ROOT / "Scripts").rglob("*.gd"))
    duplicate_functions = []
    for path in scripts:
        names = re.findall(r"^(?:static\s+)?func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(", read_text(path), re.MULTILINE)
        seen_names: set[str] = set()
        for name in names:
            if name in seen_names:
                duplicate_functions.append((path.relative_to(PROJECT_ROOT), name))
            seen_names.add(name)
    for path, name in duplicate_functions:
        errors.append(f"Duplicate function '{name}' in {path}")

    print(f"Project: {PROJECT_ROOT.name}")
    print(f"res:// references checked: {path_count}")
    print(f"GDScript files scanned: {len(scripts)}")
    for label, count in summary.items():
        print(f"{label}: {count}")
    if errors:
        print(f"\nFAILED: {len(errors)} issue(s)")
        for error in errors:
            print(f"- {error}")
        return 1
    print("\nPASS: no issues found by the lightweight static validator.")
    print("Note: this tool does not parse GDScript or replace a Godot editor/runtime test.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
