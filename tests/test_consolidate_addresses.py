"""Behavioral checks for portable, deterministic address consolidation."""
from __future__ import annotations

from copy import deepcopy
import importlib.util
import itertools
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("consolidate_addresses", ROOT / "tools/consolidate_addresses.py")
M = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(M)
A, B, C = ("a" * 16, "b" * 16, "c" * 16)


def export(*records):
    return {"format": "chimera_paczki_baza", "version": 1,
            "memory": {"schema": 1, "records": {M.normalized(r["recipient"]): r for r in records}}}


def npc(name="Torquato di Assemani", rooms=None, count=1, last=100, identity=False):
    record = {"recipient": name, "roomHashes": rooms or [A], "count": count, "last": last, "postal": False}
    if identity:
        record.update(npcId="npc123", name="Torquato", short="wysoki mezczyzna", title="Torquato di Assemani")
    return record


class ConsolidationTests(unittest.TestCase):
    def test_input_order_and_duplicate_snapshots_do_not_change_result(self):
        snapshots = [export(npc(rooms=[A], last=100, count=2)),
                     export(npc(rooms=[B, A], last=200, count=4, identity=True)),
                     export(npc(name="Boreg Khrazaksson", rooms=[C], last=200))]
        expected = M.consolidate(snapshots)
        for order in itertools.permutations(snapshots):
            self.assertEqual(expected, M.consolidate(list(order)))
            self.assertEqual(expected, M.consolidate(list(order) * 3))
        record = expected[0]["memory"]["records"]["torquato di assemani"]
        self.assertEqual([B, A], record["roomHashes"])
        self.assertEqual(4, record["count"])
        self.assertEqual(200, record["last"])
        self.assertEqual("npc123", record["npcId"])

    def test_equal_timestamp_location_ties_are_deterministic(self):
        first, second = export(npc(rooms=[B])), export(npc(rooms=[A]))
        self.assertEqual(M.consolidate([first, second]), M.consolidate([second, first]))
        self.assertEqual([A, B], M.consolidate([first, second])[0]["memory"]["records"]["torquato di assemani"]["roomHashes"])

    def test_counts_are_maxima_and_originals_are_not_mutated(self):
        snapshots = [export(npc(count=8)), export(npc(count=8))]
        originals = deepcopy(snapshots)
        master, _ = M.consolidate(snapshots)
        self.assertEqual(8, master["memory"]["records"]["torquato di assemani"]["count"])
        self.assertEqual(originals, snapshots)
        self.assertEqual(master, M.validate_snapshot(master))

    def test_identity_conflict_preserves_locations_and_reports_both_candidates(self):
        first, second = npc(identity=True), npc(identity=True, rooms=[B], last=200)
        second["npcId"] = "different_npc"
        master, report = M.consolidate([export(first), export(second)])
        record = master["memory"]["records"]["torquato di assemani"]
        self.assertEqual([B, A], record["roomHashes"])
        self.assertNotIn("npcId", record)
        self.assertEqual(2, len(report["identity_conflicts"][0]["alternatives"]))
        self.assertEqual(master, M.validate_snapshot(master))

    def test_postal_identity_conflict_is_not_silently_published(self):
        first, second = npc(), npc()
        second["postal"] = True
        with self.assertRaisesRegex(ValueError, "classification"):
            M.consolidate([export(first), export(second)])

    def test_unknown_sensitive_fields_and_invalid_data_are_rejected(self):
        bad_cases = []
        for key, value in (("account", "private"), ("password", "private"), ("map", 12)):
            case = export(npc())
            case["memory"]["records"]["torquato di assemani"][key] = value
            bad_cases.append(case)
        for key, value in (("count", True), ("count", 0), ("last", float("nan")),
                           ("roomHashes", ["123"]), ("roomHashes", []), ("postal", "false"),
                           ("recipient", "Torquato\nprivate"), ("npcId", "alone")):
            case = export(npc())
            case["memory"]["records"]["torquato di assemani"][key] = value
            bad_cases.append(case)
        case = export(npc()); case["profile"] = "private"; bad_cases.append(case)
        for case in bad_cases:
            with self.subTest(case=case), self.assertRaises(ValueError):
                M.validate_snapshot(case)

    def test_duplicate_json_keys_are_rejected_before_validation(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "snapshot.json"
            path.write_text('{"format":"one","format":"two"}')
            with self.assertRaisesRegex(ValueError, "duplicate JSON key"):
                M.load_snapshot(path)

    def test_current_exports_consolidate_without_personal_fields(self):
        paths = sorted((ROOT / "data/address_sources").glob("*.json"))
        self.assertGreaterEqual(len(paths), 1)
        snapshots = [M.load_snapshot(path) for path in paths]
        master, report = M.consolidate(snapshots)
        all_records = [data["memory"]["records"] for data in snapshots]
        keys = set().union(*(set(records) for records in all_records))
        locations = sum(len(set(room for records in all_records for room in records.get(key, {}).get("roomHashes", []))) for key in keys)
        self.assertEqual(len(keys), report["recipients"])
        self.assertEqual(locations, report["locations"])
        M.load_snapshot(ROOT / "data/addresses.json")  # Published catalogue may lag a new source commit until Actions completes.
        for record in master["memory"]["records"].values():
            self.assertFalse(set(record) - M.FIELDS)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "master.json"
            M.write_json(path, master); original = path.read_bytes()
            M.write_json(path, master)
            self.assertEqual(original, path.read_bytes())
            self.assertEqual(master, M.load_snapshot(path))


if __name__ == "__main__":
    unittest.main()
