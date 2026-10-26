#!/usr/bin/env python3
"""Build the public urban metadata fallback from an exact upstream checkout."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import subprocess

EXPECTED_COMMIT = "4f7cb4922310adc65c929e63f837dfd542d94a0e"


def quote(value: str) -> str:
    # These generated strings contain no JSON-only escape sequences.
    return json.dumps(value, ensure_ascii=False)


def packed(values: list[str]) -> str:
    return "[[" + "\n".join(" ".join(values[i:i + 8]) for i in range(0, len(values), 8)) + "]]"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("checkout", type=Path)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / "chimera_wtyczki/chimera_paczki/city_data.lua")
    args = parser.parse_args()
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=args.checkout, text=True).strip()
    if commit != EXPECTED_COMMIT:
        raise SystemExit(f"Unexpected upstream commit: {commit}")

    entries = []
    total = 0
    for path in sorted((args.checkout / "data/world").glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        rooms = data.get("rooms", {})
        if not any(row.get("terrain") == "miasto" for row in rooms.values()):
            continue
        groups: list[list[str]] = [[], [], []]
        for room_hash, row in sorted(rooms.items()):
            if len(room_hash) != 16 or any(character not in "0123456789abcdef" for character in room_hash):
                raise SystemExit(f"Invalid room hash in {path}: {room_hash}")
            if row.get("terrain") == "miasto":
                groups[1 if row.get("indoors") is True else 0].append(room_hash)
            elif row.get("terrain") is None and row.get("indoors") is True:
                groups[2].append(room_hash)
        total += sum(map(len, groups))
        entries.append((data["area_id"], data["area"], groups))
    if len(entries) != 21 or total != 2127:
        raise SystemExit(f"Unexpected registry size: {len(entries)} areas, {total} rooms")
    lines = [
        "-- Generated public metadata; no NPC, character, account or profile data.",
        "-- Source: https://gitlab.com/bfbps-group/chimera-mud-skrypty", 
        "-- Tag: 5.0.1; commit: " + EXPECTED_COMMIT,
        "-- Selection: area has an urban room; terrain=miasto OR absent terrain + indoors=true.",
        "-- Rebuild: python3 tools/generate_city_data.py ../chimera-501", 
        "local areas = {",
    ]
    for area_id, name, groups in sorted(entries):
        lines.append("    {" + quote(area_id) + "," + quote(name) + ",")
        for group in groups:
            lines.append("        " + packed(group) + ",")
        lines.append("    },")
    lines += [
        "}",
        "local index = {}",
        "for _, area in ipairs(areas) do",
        "    for kind=3,5 do",
        "        for hash in area[kind]:gmatch(\"%x+\") do",
        "            assert(index[hash]==nil, \"duplicate public city hash\")",
        "            index[hash]={area=area,kind=kind}",
        "        end",
        "    end",
        "end",
        "local api={version=\"1.5.9\"}",
        "function api.room(hash)",
        "    if type(hash)~=\"string\" then return nil end",
        "    local row=index[hash]",
        "    if not row then return nil end",
        "    return {id=hash,area_id=row.area[1],area=row.area[2],",
        "        terrain=row.kind<5 and \"miasto\" or nil,indoors=row.kind~=3}",
        "end",
        "function api.info()",
        "    return {version=\"1.5.9\",tag=\"5.0.1\",commit=\"" + EXPECTED_COMMIT + "\",areas=21,rooms=2127,",
        "        source=\"https://gitlab.com/bfbps-group/chimera-mud-skrypty\"}",
        "end",
        "return api",
        "",
    ]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(lines), encoding="utf-8")
    print(f"{args.output}: {len(entries)} areas, {total} rooms")


if __name__ == "__main__":
    main()
