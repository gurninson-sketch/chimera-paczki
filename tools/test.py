"""Run offline courier simulations against two pinned Chimera releases.

No character login or connection to the game server is used. By default the
official upstream test harnesses are cloned into a disposable workspace.
--upstream-root accepts an existing folder containing the two exact checkouts.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
from zipfile import ZipFile

from build import ROOT, FILES, REPOSITORY, build

UPSTREAM_URL = "https://gitlab.com/bfbps-group/chimera-mud-skrypty.git"
UPSTREAMS = {
    "chimera-main": ("5.0.0-beta.13", "4376ef2f9eeef8d95e7ba8070a22d0428100ed19"),
    "chimera-501": ("5.0.1", "4f7cb4922310adc65c929e63f837dfd542d94a0e"),
}
PURE = (
    "extended", "npc", "travel", "offices", "road", "ferry", "scope",
    "journey", "inventory", "memory", "path", "postal", "checkpoint", "city_budget",
    "escape", "recovery", "eta", "eta_core", "karak_transport",
    "karak_journey", "city", "city_core", "city_data", "identity_upgrade",
    "planner", "planning_path", "ship_resume",
)
NATIVE = (
    "native", "native_map", "gate_ferry_native", "rest_native",
    "inventory_native", "speed_native", "learning_native", "path_native",
    "offers_native", "auto_backpack_native", "resume_native",
    "periodic_npc_native", "gmcp_resume_native", "portable_memory_native",
    "combat_native", "eta_native", "karak_native", "city_native",
    "torquato_native", "boreg_native", "michael_native", "planning_native",
    "fryderik_native", "nikolaus_native", "ship_resume_native",
    "ship_reconnect_native", "unload_native",
)


def upstream(destination: Path, name: str, existing_root: Path | None) -> None:
    tag, expected = UPSTREAMS[name]
    if existing_root:
        source = existing_root / name
        actual = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source, text=True).strip()
        if actual != expected:
            raise ValueError(f"{name}: expected upstream {expected}, got {actual}")
        # Use real sibling directories, not symlinked cwd: Lua fixtures rely
        # on ../chimera-native, and the OS resolves cwd symlinks physically.
        destination.mkdir()
        for directory in ("src", "tests", "data"):
            shutil.copytree(source / directory, destination / directory)
    else:
        subprocess.run(["git", "clone", "--depth", "1", "--branch", tag, UPSTREAM_URL, str(destination)], check=True)
        actual = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=destination, text=True).strip()
        if actual != expected:
            raise ValueError(f"{name}: tag {tag} no longer points to pinned {expected}")


def check_assets() -> None:
    with tempfile.TemporaryDirectory(prefix="paczki-assets-") as name:
        output = Path(name)
        archive = build(output=output)
        first = {path.name: path.read_bytes() for path in output.iterdir()}
        descriptor = json.loads(first["update.json"])
        payload = first["chimera-paczki-runtime.json"]
        bundle = json.loads(payload)
        assert descriptor["schema"] == bundle["schema"] == 1
        assert descriptor["version"] == bundle["version"] == (ROOT / "VERSION").read_text().strip()
        assert descriptor["bundle"]["bytes"] == len(payload)
        assert descriptor["bundle"]["sha256"] == hashlib.sha256(payload).hexdigest()
        assert descriptor["bundle"]["url"] == f"https://github.com/{REPOSITORY}/releases/download/v{bundle['version']}/chimera-paczki-runtime.json"
        assert set(bundle["files"]) == set(FILES)
        with ZipFile(archive) as package:
            assert package.testzip() is None
            assert {path for path in package.namelist() if path.endswith(".lua")} == {
                f"chimera_wtyczki/chimera_paczki/{name}" for name in FILES
            }
            for name in FILES:
                body = (ROOT / "chimera_wtyczki/chimera_paczki" / name).read_text(encoding="utf-8")
                assert body == bundle["files"][name]
                assert package.read(f"chimera_wtyczki/chimera_paczki/{name}") == body.encode("utf-8")
        build(output=output)
        assert first == {path.name: path.read_bytes() for path in output.iterdir()}, "Non-reproducible release build"
    print("ASSETS: source parity, exact file list, SHA-256, fixed release URL and reproducibility passed", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--upstream-root", type=Path, help="Existing parent directory of chimera-main and chimera-501")
    parser.add_argument("--suite", choices=("all", "pure", "native", "native501"), default="all")
    parser.add_argument("--lua", help="Lua executable; defaults to texlua, lua5.3 or lua")
    parser.add_argument("--jobs", type=int, default=3)
    args = parser.parse_args()
    lua = args.lua or next((path for name in ("texlua", "lua5.3", "lua") if (path := shutil.which(name))), None)
    if not lua:
        parser.error("Install texlua (texlive-luatex), or Lua 5.3+ and LuaFileSystem")
    if args.jobs < 1 or args.jobs > 16:
        parser.error("--jobs must be between 1 and 16")
    subprocess.run(["python3", "-m", "unittest", "discover", "-s", "tests", "-p", "test_consolidate_addresses.py"], cwd=ROOT, check=True)
    check_assets()
    reports = ROOT / "test-results"
    reports.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="chimera-paczki-tests-") as directory:
        workspace = Path(directory)
        project = workspace / "chimera-native"
        project.mkdir()
        for name in ("chimera_wtyczki", "tests", "data"):
            shutil.copytree(ROOT / name, project / name)
        shutil.copytree(ROOT / "tests/fixtures/legacy", workspace / "chimera-kurier")
        shutil.copytree(ROOT / "tests/fixtures/reconnect", workspace / "chimera-reconnect")
        for name in UPSTREAMS:
            upstream(workspace / name, name, args.upstream_root.resolve() if args.upstream_root else None)

        compiler = workspace / "syntax.lua"
        compiler.write_text('for i=1,#arg do assert(loadfile(arg[i])) end\nprint("All runtime files compile")\n', encoding="utf-8")
        subprocess.run([lua, str(compiler), *(str(project / "chimera_wtyczki/chimera_paczki" / name) for name in FILES)], check=True)

        # New updater simulations are included automatically without allowing
        # arbitrary non-test Lua files to become executable CI entries.
        extra = sorted({path.stem.removeprefix("test_") for pattern in ("test_update*.lua", "test_updater*.lua") for path in (project / "tests").glob(pattern)})
        extra_pure = [name for name in extra if "_native" not in name]
        extra_native = [name for name in extra if "_native" in name]
        cases: list[tuple[str, Path, str]] = []
        if args.suite in ("all", "pure"):
            cases.append(("CORE", workspace / "chimera-kurier", "tests/test_native_core.lua"))
            cases.extend((name.upper(), project, f"tests/test_{name}.lua") for name in (*PURE, *extra_pure))
        for suite, source in (("native", "chimera-main"), ("native501", "chimera-501")):
            if args.suite not in ("all", suite):
                continue
            suffix = "_501" if suite == "native501" else ""
            cases.extend((name.upper() + suffix, workspace / source, f"../chimera-native/tests/test_{name}.lua") for name in (*NATIVE, *extra_native))

        def run(case: tuple[str, Path, str]) -> int:
            name, cwd, source = case
            try:
                result = subprocess.run([lua, source], cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=300)
                output, code = result.stdout, result.returncode
            except subprocess.TimeoutExpired as error:
                output, code = f"Suite timed out after 300 seconds: {error}", 1
            (reports / f"{name}.txt").write_text(output, encoding="utf-8")
            summary = output.strip().splitlines()[-1] if output.strip() else "No output"
            print(f"{name}: {'PASS' if code == 0 else 'FAIL'}; {summary}", flush=True)
            if code:
                print(output, flush=True)
            return code

        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            results = list(pool.map(run, cases))
        failed = sum(code != 0 for code in results)
        print(f"Finished {len(cases)} suites: {len(cases)-failed} passed, {failed} failed", flush=True)
        raise SystemExit(bool(failed))


if __name__ == "__main__":
    main()
