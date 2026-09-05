#!/usr/bin/env python3
from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path
import hashlib
import stat
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "scripts" / "generate_title_snesrecomp.py"
BUILDER = ROOT / "scripts" / "tvos" / "build-title-app.sh"
GENERIC_GAME = ROOT / "runner" / "dkc_generic_game.c"
DKC3_CORE = ROOT / "tvos" / "core" / "dkc3_game_core.c"


def load_generator():
    spec = spec_from_file_location("generate_title_snesrecomp", GENERATOR)
    module = module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


class TitleTvOSPortTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.generator = load_generator()
        cls.builder = BUILDER.read_text(encoding="utf-8")
        cls.game = GENERIC_GAME.read_text(encoding="utf-8")
        cls.core = DKC3_CORE.read_text(encoding="utf-8")

    def test_dkc3_rom_validation_is_revision_agnostic(self):
        payload = bytearray(self.generator.EXPECTED_SIZE)
        title = self.generator.TITLES["dkc3"]["header"]
        payload[0xFFC0 : 0xFFC0 + len(title)] = title
        with tempfile.NamedTemporaryFile() as rom:
            rom.write(payload)
            rom.flush()
            self.assertEqual(
                self.generator.validate_rom(Path(rom.name), title),
                payload,
            )

    def test_profile_marker_binds_generated_code_to_input(self):
        payload = b"title-specific test payload"
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / "marker.c"
            self.generator.write_profile_marker(marker, payload)
            text = marker.read_text(encoding="utf-8")
        digest = hashlib.sha256(payload).digest()
        for value in digest:
            self.assertIn(f"0x{value:02x}", text)
        self.assertIn(f"dkc_compiled_rom_size = {len(payload)}u", text)

    def test_title_builder_is_executable_shell_and_reuses_host(self):
        self.assertTrue(BUILDER.stat().st_mode & stat.S_IXUSR)
        result = subprocess.run(
            ["sh", "-n", str(BUILDER)],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        self.assertEqual(result.returncode, 0, result.stdout)
        for required in (
            "generate_title_snesrecomp.py",
            "DKC3_BUILD_TVOS_CORE",
            "dkc3_tvos_core",
            "dkc3_game_core",
            "tv.nijssen.DKC3RecompTV",
            "build-app.sh",
            "--core-archive",
        ):
            self.assertIn(required, self.builder)

    def test_dkc3_core_uses_shared_abi_and_cartridge_vectors(self):
        for required in (
            "ReadVector(0x00ffea)",
            "ReadVector(0x00ffee)",
            "ReadVector(0x00fffc)",
            "DkcGenericGameInfo",
        ):
            self.assertIn(required, self.game)
        for required in (
            "DKC_GAME_CORE_ABI_VERSION",
            '.id = "dkc3"',
            ".framebuffer_width = kFramebufferWidth",
            ".framebuffer_height = kFramebufferHeight",
            "dkc3_game_core",
        ):
            self.assertIn(required, self.core)


if __name__ == "__main__":
    unittest.main()
