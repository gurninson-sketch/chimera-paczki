"""Build deterministic manual-install and verified GitHub update assets."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "chimera_wtyczki/chimera_paczki"
FILES = tuple(sorted(f"{name}.lua" for name in (
    "init", "core", "routes", "new_routes", "npc", "travel", "offices",
    "scope", "road", "ferry", "journey", "transport_data", "inventory",
    "memory", "path", "postal", "checkpoint", "escape", "recovery", "eta",
    "karak_transport", "city", "city_data", "planner", "updater",
)))
REPOSITORY = "gurninson-sketch/chimera-paczki"


def encode(value: object) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


def sources() -> tuple[str, dict[str, str]]:
    version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("VERSION must contain major.minor.patch")
    actual = {path.name for path in RUNTIME.iterdir()}
    if actual != set(FILES):
        raise ValueError(f"Runtime file list differs: missing={set(FILES)-actual}; extra={actual-set(FILES)}")
    files = {name: (RUNTIME / name).read_text(encoding="utf-8") for name in FILES}
    for name in ("init.lua", "core.lua"):
        if not re.search(r'\bversion\s*=\s*"' + re.escape(version) + '"', files[name]):
            raise ValueError(f"VERSION differs from {name}")
    if any(len(body.encode("utf-8")) > 1024 * 1024 for body in files.values()):
        raise ValueError("A runtime file exceeds the updater's 1 MiB limit")
    return version, files


def build(repository: str = REPOSITORY, output: Path | None = None) -> Path:
    if not re.fullmatch(r"[A-Za-z0-9-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Expected GitHub OWNER/REPO")
    # The installed updater intentionally trusts one distribution repository.
    if repository != REPOSITORY:
        raise ValueError(f"The native updater is pinned to {REPOSITORY}")
    version, files = sources()
    output = output or ROOT / "dist"
    output.mkdir(parents=True, exist_ok=True)
    payload = encode({"schema": 1, "version": version, "files": files})
    if len(payload) > 2 * 1024 * 1024:
        raise ValueError("Runtime bundle exceeds the updater's 2 MiB limit")
    bundle_name = "chimera-paczki-runtime.json"
    (output / bundle_name).write_bytes(payload)
    descriptor = {
        "schema": 1,
        "version": version,
        "min_mudlet": "4.20.0",
        "bundle": {
            "url": f"https://github.com/{repository}/releases/download/v{version}/{bundle_name}",
            "bytes": len(payload),
            "sha256": hashlib.sha256(payload).hexdigest(),
        },
    }
    (output / "update.json").write_bytes(encode(descriptor))
    archive_files = {f"chimera_wtyczki/chimera_paczki/{name}": body.encode("utf-8") for name, body in files.items()}
    for name in ("README.md", "README_PL.txt", "NOTICE.md", "CHANGELOG.md", "PRZENOSZENIE_BAZY.txt"):
        path = ROOT / name
        if path.is_file():
            archive_files[name] = path.read_bytes()
    archive = output / "Chimera_Paczki.zip"
    with ZipFile(archive, "w", compression=ZIP_DEFLATED, compresslevel=9) as package:
        for name, body in sorted(archive_files.items()):
            info = ZipInfo(name, (2026, 1, 1, 0, 0, 0))
            info.compress_type = ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            package.writestr(info, body)
    with ZipFile(archive) as package:
        assert package.testzip() is None
        assert set(package.namelist()) == set(archive_files)
        for name, body in archive_files.items():
            assert package.read(name) == body
    assets = (archive, output / bundle_name, output / "update.json")
    (output / "SHA256SUMS").write_text("".join(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n" for path in assets), encoding="ascii")
    print(f"Built Chimera Paczki {version}: {len(files)} runtime files, {len(payload)} bundle bytes")
    return archive


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", default=REPOSITORY)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    build(args.repository, args.output)
