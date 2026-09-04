#!/usr/bin/env python3
"""Generate private DKC2 snesrecomp units on Windows, Linux, or macOS."""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


EXPECTED_SIZE = 0x400000
MARKER_FILENAME = "dkc2_rom_profile.c"
SUPPORTED_ROM_PROFILES = (
    (
        "DKC2 USA v1.0",
        "35421a9af9dd011b40b91f792192af9f99c93201d8d394026bdfb42cbf2d8633",
    ),
    (
        "DKC2 USA Rev 1/v1.1",
        "b79c2bb86f6fc76e1fc61c62fc16d51c664c381e58bc2933be643bbc4d8b610c",
    ),
)
PROFILE_ENUM_BY_NAME = {
    "DKC2 USA v1.0": "DKC2_ROM_PROFILE_USA_V10",
    "DKC2 USA Rev 1/v1.1": "DKC2_ROM_PROFILE_USA_REV1",
}


def integer(value: str) -> int:
    return int(value, 0)


def validate_rom(path: Path) -> str:
    size = path.stat().st_size
    if size != EXPECTED_SIZE:
        raise ValueError(f"Unsupported ROM size {size}; expected {EXPECTED_SIZE} bytes.")
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    profile = next(
        (name for name, expected in SUPPORTED_ROM_PROFILES if digest == expected),
        None,
    )
    if profile is None:
        raise ValueError(f"Unsupported ROM SHA-256 {digest}.")
    return profile


def write_profile_marker(path: Path, profile: str) -> None:
    try:
        profile_enum = PROFILE_ENUM_BY_NAME[profile]
    except KeyError as error:
        raise ValueError(f"Unsupported DKC2 ROM profile {profile!r}.") from error
    path.write_text(
        '#include "verified_rom.h"\n\n'
        "Dkc2RomProfile Dkc2CompiledRomProfile(void) {\n"
        f"  return {profile_enum};\n"
        "}\n",
        encoding="utf-8",
        newline="\n",
    )


def publish_generated_output(staging: Path, output: Path) -> None:
    """Swap a complete generated tree into place, restoring the old tree on failure."""
    previous = output.with_name(f".{output.name}.previous")
    if previous.exists():
        if output.exists():
            shutil.rmtree(previous)
        else:
            os.replace(previous, output)
    moved_live = False
    try:
        if output.exists():
            os.replace(output, previous)
            moved_live = True
        os.replace(staging, output)
    except BaseException:
        if moved_live and not output.exists() and previous.exists():
            os.replace(previous, output)
        raise
    if previous.exists():
        shutil.rmtree(previous)


def run(command: list[str], description: str) -> None:
    result = subprocess.run(command, check=False)
    if result.returncode:
        raise RuntimeError(
            f"{description} failed with exit code {result.returncode}.")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rom", required=True, type=Path)
    parser.add_argument("--snesrecomp-root", type=Path)
    parser.add_argument(
        "--analysis-backend", choices=("native", "python", "auto"),
        default="native")
    parser.add_argument("--max-instructions", type=integer, default=4096)
    parser.add_argument("--max-nodes", type=integer, default=100000)
    parser.add_argument("--bank-shard-threshold-kib", type=integer,
                        default=1024)
    parser.add_argument("--bank-shard-pc-span", type=integer, default=0x10)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repository = Path(__file__).resolve().parent.parent
    snesrecomp_root = (args.snesrecomp_root or
                       repository / "snesrecomp").resolve()
    emitter = snesrecomp_root / "tools" / "v2_emit.py"
    native_builder = snesrecomp_root / "tools" / "build_native_analyzer.py"
    native_name = "snesrecomp-analyze.exe" if os.name == "nt" else "snesrecomp-analyze"
    native_analyzer = (snesrecomp_root / "recompiler-rs" / "target" /
                       "release" / native_name)
    header_sync = snesrecomp_root / "tools" / "v2_sync_funcs_h.py"
    config_directory = repository / "recomp"
    output_directory = repository / "generated" / "snesrecomp"

    if not emitter.is_file():
        raise FileNotFoundError(
            "snesrecomp is not initialized; run git submodule update --init --recursive")
    if not header_sync.is_file():
        raise FileNotFoundError(
            f"snesrecomp header synchronizer is missing: {header_sync}")
    if args.analysis_backend == "native":
        if not native_builder.is_file():
            raise FileNotFoundError(
                f"snesrecomp native analyzer builder is missing: {native_builder}")
        if shutil.which("cargo"):
            run([sys.executable, str(native_builder)],
                "snesrecomp native analyzer build")
        elif not native_analyzer.is_file():
            raise FileNotFoundError(
                f"Cargo is unavailable and no native analyzer exists at {native_analyzer}")
        else:
            print(f"Cargo is unavailable; using native analyzer: {native_analyzer}")

    rom = args.rom.expanduser().resolve(strict=True)
    profile = validate_rom(rom)
    print(f"Accepted ROM profile: {profile}")
    output_directory.parent.mkdir(parents=True, exist_ok=True)
    staging_directory = Path(tempfile.mkdtemp(
        prefix=f".{output_directory.name}.staging-",
        dir=str(output_directory.parent)))

    published = False
    try:
        if output_directory.exists():
            shutil.copytree(output_directory, staging_directory, dirs_exist_ok=True)
        run([
            sys.executable, str(header_sync), "--cfg-dir", str(config_directory),
            "--out", str(config_directory / "funcs.h")],
            "snesrecomp funcs.h synchronization")
        run([
            sys.executable, str(emitter), "--rom", str(rom),
            "--cfg-dir", str(config_directory), "--out-dir", str(staging_directory),
            "--no-host-root-scan", "--no-hle", "--cfg-roots",
            "--analysis-backend", args.analysis_backend,
            "--max-insns", str(args.max_instructions),
            "--max-nodes", str(args.max_nodes),
            "--bank-shard-threshold-kib", str(args.bank_shard_threshold_kib),
            "--bank-shard-pc-span", str(args.bank_shard_pc_span)],
            "snesrecomp generation")
        run([
            sys.executable,
            str(repository / "scripts" / "apply_dkc2_widescreen_overrides.py"),
            "--generated-dir", str(staging_directory)],
            "DKC2 widescreen override application")
        write_profile_marker(staging_directory / MARKER_FILENAME, profile)
        publish_generated_output(staging_directory, output_directory)
        published = True
    finally:
        if not published and staging_directory.exists():
            shutil.rmtree(staging_directory)
    print(f"Generated private sources in {output_directory}")
    print("The ROM and generated game code remain ignored by Git.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (FileNotFoundError, OSError, RuntimeError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
