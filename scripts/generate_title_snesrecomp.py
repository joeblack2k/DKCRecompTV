#!/usr/bin/env python3
"""Generate private snesrecomp units for a supported DKC title."""

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
TITLES = {
    "dkc3": {
        "header": b"DONKEY KONG COUNTRY 3",
        "config": "titles/dkc3/recomp",
        "output": "generated/dkc3/snesrecomp",
    },
}


def run(command: list[str], description: str) -> None:
    result = subprocess.run(command, check=False)
    if result.returncode:
        raise RuntimeError(
            f"{description} failed with exit code {result.returncode}."
        )


def validate_rom(path: Path, expected_header: bytes) -> bytes:
    payload = path.read_bytes()
    if len(payload) != EXPECTED_SIZE:
        raise ValueError(
            f"Unsupported ROM size {len(payload)}; expected {EXPECTED_SIZE} bytes."
        )
    internal_name = payload[0xFFC0 : 0xFFD5].rstrip(b" \0")
    if internal_name != expected_header:
        raise ValueError(
            f"ROM title {internal_name!r} does not match {expected_header!r}."
        )
    return payload


def write_profile_marker(path: Path, payload: bytes) -> None:
    digest = hashlib.sha256(payload).digest()
    values = ", ".join(f"0x{value:02x}" for value in digest)
    path.write_text(
        "#include <stddef.h>\n"
        "#include <stdint.h>\n\n"
        f"const size_t dkc_compiled_rom_size = {len(payload)}u;\n"
        f"const uint8_t dkc_compiled_rom_sha256[32] = {{{values}}};\n",
        encoding="utf-8",
        newline="\n",
    )


def publish(staging: Path, output: Path) -> None:
    previous = output.with_name(f".{output.name}.previous")
    if previous.exists():
        shutil.rmtree(previous)
    if output.exists():
        os.replace(output, previous)
    try:
        os.replace(staging, output)
    except BaseException:
        if previous.exists() and not output.exists():
            os.replace(previous, output)
        raise
    if previous.exists():
        shutil.rmtree(previous)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--title", choices=sorted(TITLES), required=True)
    parser.add_argument("--rom", required=True, type=Path)
    parser.add_argument("--snesrecomp-root", type=Path)
    parser.add_argument(
        "--analysis-backend",
        choices=("native", "python", "auto"),
        default="native",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repository = Path(__file__).resolve().parent.parent
    title = TITLES[args.title]
    snesrecomp_root = (
        args.snesrecomp_root or repository / "snesrecomp"
    ).resolve()
    emitter = snesrecomp_root / "tools" / "v2_emit.py"
    header_sync = snesrecomp_root / "tools" / "v2_sync_funcs_h.py"
    native_builder = snesrecomp_root / "tools" / "build_native_analyzer.py"
    config = repository / str(title["config"])
    output = repository / str(title["output"])

    for required in (emitter, header_sync):
        if not required.is_file():
            raise FileNotFoundError(
                "snesrecomp is not initialized; run "
                "git submodule update --init --recursive"
            )
    if args.analysis_backend == "native":
        if not native_builder.is_file():
            raise FileNotFoundError(
                f"snesrecomp native analyzer builder is missing: {native_builder}"
            )
        run(
            [sys.executable, str(native_builder)],
            "snesrecomp native analyzer build",
        )

    rom = args.rom.expanduser().resolve(strict=True)
    payload = validate_rom(rom, title["header"])
    output.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(
        tempfile.mkdtemp(prefix=f".{output.name}.staging-", dir=output.parent)
    )
    published = False
    try:
        run(
            [
                sys.executable,
                str(header_sync),
                "--cfg-dir",
                str(config),
                "--out",
                str(config / "funcs.h"),
            ],
            "snesrecomp funcs.h synchronization",
        )
        run(
            [
                sys.executable,
                str(emitter),
                "--rom",
                str(rom),
                "--cfg-dir",
                str(config),
                "--out-dir",
                str(staging),
                "--no-host-root-scan",
                "--no-hle",
                "--cfg-roots",
                "--analysis-backend",
                args.analysis_backend,
            ],
            "snesrecomp generation",
        )
        write_profile_marker(staging / "dkc_compiled_rom.c", payload)
        publish(staging, output)
        published = True
    finally:
        if not published and staging.exists():
            shutil.rmtree(staging)

    print(f"Generated private {args.title} sources in {output}")
    print(f"Compiled ROM SHA-256: {hashlib.sha256(payload).hexdigest()}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (FileNotFoundError, OSError, RuntimeError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
