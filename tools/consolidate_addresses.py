"""Validate and deterministically consolidate confirmed courier address exports.

Input files contain game NPC/address records only, never raw profile databases.
Running this command twice produces identical bytes. Delivery counts are maxima,
not sums, because an imported record may already appear in several profiles.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import re
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
MAX_NUMBER = 9007199254740990
MAX_BYTES = 4 * 1024 * 1024
FIELDS = {"recipient", "npcId", "name", "short", "title", "roomHashes", "count", "last", "postal"}
IDENTITY = ("npcId", "name", "short", "title")
ACCENTS = str.maketrans("ąćęłńóśźżĄĆĘŁŃÓŚŹŻ", "acelnoszzacelnoszz")


def text(value: Any, label: str) -> str:
    if not isinstance(value, str) or re.search(r"[\x00-\x1f\x7f]", value):
        raise ValueError(f"{label}: expected plain text")
    value = " ".join(value.replace("\u00a0", " ").split())
    if not value or len(value) > 1024:
        raise ValueError(f"{label}: empty or oversized text")
    return value


def normalized(value: str) -> str:
    return text(value, "recipient").translate(ACCENTS).lower().rstrip(" .")


def finite(value: Any, label: str, minimum: int = 0, integer: bool = False) -> int | float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError(f"{label}: expected finite number")
    if not minimum <= value <= MAX_NUMBER or (integer and value != math.floor(value)):
        raise ValueError(f"{label}: invalid number range")
    return int(value) if value == math.floor(value) else value


def validate_snapshot(snapshot: Any) -> dict:
    if not isinstance(snapshot, dict) or set(snapshot) != {"format", "version", "memory"}:
        raise ValueError("export contains unknown or missing fields")
    if snapshot["format"] != "chimera_paczki_baza" or type(snapshot["version"]) is not int or snapshot["version"] != 1:
        raise ValueError("unsupported courier export format/version")
    memory = snapshot["memory"]
    if not isinstance(memory, dict) or set(memory) != {"schema", "records"} or type(memory["schema"]) is not int or memory["schema"] != 1:
        raise ValueError("unsupported memory schema")
    raw_records = memory["records"]
    if not isinstance(raw_records, dict) or len(raw_records) > 10000:
        raise ValueError("expected at most 10000 address records")
    records = {}
    for key, record in sorted(raw_records.items()):
        if not isinstance(key, str) or not isinstance(record, dict) or set(record) - FIELDS:
            raise ValueError("record contains unknown fields")
        required = {"recipient", "roomHashes", "count", "last"}
        if not required <= set(record):
            raise ValueError("record is incomplete")
        recipient = text(record["recipient"], "recipient")
        if normalized(recipient) != key:
            raise ValueError("recipient key does not match full recipient name")
        if "postal" in record and not isinstance(record["postal"], bool):
            raise ValueError("postal must be a boolean")
        rooms = record["roomHashes"]
        if not isinstance(rooms, list) or not 1 <= len(rooms) <= 2048:
            raise ValueError("record requires a nonempty bounded location list")
        clean_rooms = []
        for room in rooms:
            if not isinstance(room, str) or not re.fullmatch(r"[0-9a-fA-F]{16}", room):
                raise ValueError("location must be a stable 16-digit game room hash")
            room = room.lower()
            if room not in clean_rooms:
                clean_rooms.append(room)
        clean = dict(recipient=recipient, roomHashes=clean_rooms,
                     count=finite(record["count"], "count", 1, True),
                     last=finite(record["last"], "last"), postal=record.get("postal", False))
        if any(field in record for field in IDENTITY):
            if clean["postal"] or not {"npcId", "name"} <= set(record):
                raise ValueError("invalid or incomplete NPC identity")
            for field in IDENTITY:
                if field in record:
                    clean[field] = text(record[field], field)
        records[key] = clean
    return {"format": "chimera_paczki_baza", "version": 1, "memory": {"schema": 1, "records": records}}


def no_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def load_snapshot(path: Path) -> dict:
    body = path.read_bytes()
    if len(body) > MAX_BYTES:
        raise ValueError("export exceeds 4 MiB")
    return validate_snapshot(json.loads(body.decode("utf-8"), object_pairs_hook=no_duplicate_keys))


def canonical(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)


def consolidate(snapshots: list[dict]) -> tuple[dict, dict]:
    groups: dict[str, list[dict]] = {}
    for snapshot in snapshots:
        for key, record in validate_snapshot(snapshot)["memory"]["records"].items():
            groups.setdefault(key, []).append(record)
    records, conflicts = {}, []
    for key in sorted(groups):
        # Timestamp is delivery evidence, not proof of the NPC's current presence.
        # Exact ties are broken by record content, never input/profile order.
        variants = sorted({canonical(record): record for record in groups[key]}.values(),
                          key=lambda record: (-record["last"], canonical(record)))
        kinds = {record["postal"] for record in variants}
        if len(kinds) != 1:
            raise ValueError(f"conflicting NPC/postal classification: {key}")
        rooms = []
        for record in variants:
            for room in record["roomHashes"]:
                if room not in rooms:
                    rooms.append(room)
        identities = {canonical({field: record[field] for field in IDENTITY if field in record}):
                      {field: record[field] for field in IDENTITY if field in record}
                      for record in variants if "npcId" in record}
        merged = dict(recipient=variants[0]["recipient"], roomHashes=rooms,
                      count=max(record["count"] for record in variants),
                      last=max(record["last"] for record in variants), postal=variants[0]["postal"])
        if len(identities) == 1:
            merged.update(next(iter(identities.values())))
        elif len(identities) > 1:
            # Keep the confirmed recipient/locations, but do not select an
            # arbitrary conflicting NPC identity for automatic delivery.
            conflicts.append({"recipient": merged["recipient"], "type": "npc_identity",
                              "resolution": "identity_omitted_pending_review",
                              "alternatives": [identities[value] for value in sorted(identities)]})
        records[key] = merged
    snapshot = validate_snapshot({"format": "chimera_paczki_baza", "version": 1,
                                  "memory": {"schema": 1, "records": records}})
    report = {"format": "chimera_paczki_address_report", "version": 1,
              "recipients": len(records), "locations": sum(len(record["roomHashes"]) for record in records.values()),
              "multiple_location_recipients": sum(len(record["roomHashes"]) > 1 for record in records.values()),
              "identity_conflicts": conflicts, "delivery_count_rule": "maximum_not_sum"}
    return snapshot, report


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    body = json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False) + "\n"
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(body, encoding="utf-8")
    temporary.replace(path)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sources", type=Path, default=ROOT / "data/address_sources")
    parser.add_argument("--output", type=Path, default=ROOT / "data/addresses.json")
    parser.add_argument("--report", type=Path, default=ROOT / "data/address_report.json")
    args = parser.parse_args()
    paths = sorted(args.sources.glob("*.json"))
    if not paths:
        parser.error("no courier source exports found")
    loaded = [(path, load_snapshot(path)) for path in paths]
    snapshot, report = consolidate([data for _, data in loaded])
    report["sources"] = [{"file": path.name, "recipients": len(data["memory"]["records"])} for path, data in loaded]
    write_json(args.output, snapshot)
    write_json(args.report, report)
    print(f"Consolidated {len(paths)} sources: {report['recipients']} recipients, {report['locations']} locations, "
          f"{len(report['identity_conflicts'])} identity conflicts")


if __name__ == "__main__":
    main()
