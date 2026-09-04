import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest import mock


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "generate_snesrecomp.py"
SPEC = importlib.util.spec_from_file_location("generate_snesrecomp", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)

EXPECTED_PROFILES = (
    (
        "DKC2 USA v1.0",
        "35421a9af9dd011b40b91f792192af9f99c93201d8d394026bdfb42cbf2d8633",
    ),
    (
        "DKC2 USA Rev 1/v1.1",
        "b79c2bb86f6fc76e1fc61c62fc16d51c664c381e58bc2933be643bbc4d8b610c",
    ),
)


class GenerateSnesrecompTests(unittest.TestCase):
    def test_integer_accepts_decimal_and_hex(self):
        self.assertEqual(MODULE.integer("4096"), 4096)
        self.assertEqual(MODULE.integer("0x10"), 16)

    def test_rom_size_is_checked_before_private_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            rom = Path(directory) / "synthetic.smc"
            rom.write_bytes(b"not a game")
            with self.assertRaisesRegex(ValueError, "Unsupported ROM size"):
                MODULE.validate_rom(rom)

    def test_known_rom_profiles_are_accepted(self):
        self.assertEqual(MODULE.SUPPORTED_ROM_PROFILES, EXPECTED_PROFILES)
        self.assertEqual(
            MODULE.PROFILE_ENUM_BY_NAME["DKC2 USA v1.0"],
            "DKC2_ROM_PROFILE_USA_V10",
        )
        self.assertEqual(
            MODULE.PROFILE_ENUM_BY_NAME["DKC2 USA Rev 1/v1.1"],
            "DKC2_ROM_PROFILE_USA_REV1",
        )
        with tempfile.TemporaryDirectory() as directory:
            rom = Path(directory) / "synthetic.sfc"
            with rom.open("wb") as stream:
                stream.truncate(MODULE.EXPECTED_SIZE)

            for profile, digest in EXPECTED_PROFILES:
                with self.subTest(profile=profile):
                    with mock.patch.object(MODULE.hashlib, "sha256") as sha256:
                        sha256.return_value.hexdigest.return_value = digest
                        self.assertEqual(MODULE.validate_rom(rom), profile)

            with mock.patch.object(MODULE.hashlib, "sha256") as sha256:
                sha256.return_value.hexdigest.return_value = "0" * 64
                with self.assertRaisesRegex(ValueError, "Unsupported ROM SHA-256"):
                    MODULE.validate_rom(rom)

    def test_marker_names_the_selected_profile(self):
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / MODULE.MARKER_FILENAME
            MODULE.write_profile_marker(marker, "DKC2 USA v1.0")
            self.assertIn(
                "return DKC2_ROM_PROFILE_USA_V10;", marker.read_text())
            MODULE.write_profile_marker(marker, "DKC2 USA Rev 1/v1.1")
            self.assertIn(
                "return DKC2_ROM_PROFILE_USA_REV1;", marker.read_text())

    def test_publication_swaps_the_complete_tree(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root / "generated"
            output.mkdir()
            (output / "old.c").write_text("old", encoding="utf-8")
            staging = root / "staging"
            staging.mkdir()
            (staging / "new.c").write_text("new", encoding="utf-8")

            MODULE.publish_generated_output(staging, output)

            self.assertEqual((output / "new.c").read_text(), "new")
            self.assertFalse((output / "old.c").exists())
            self.assertFalse(staging.exists())

    def test_publication_restores_old_tree_after_swap_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root / "generated"
            output.mkdir()
            (output / "old.c").write_text("old", encoding="utf-8")
            staging = root / "staging"
            staging.mkdir()
            (staging / "new.c").write_text("new", encoding="utf-8")
            real_replace = MODULE.os.replace
            calls = 0

            def fail_new_tree(source, destination):
                nonlocal calls
                calls += 1
                if calls == 2:
                    raise OSError("injected publication failure")
                return real_replace(source, destination)

            with mock.patch.object(
                    MODULE.os, "replace", side_effect=fail_new_tree):
                with self.assertRaisesRegex(
                        OSError, "injected publication failure"):
                    MODULE.publish_generated_output(staging, output)

            self.assertEqual((output / "old.c").read_text(), "old")
            self.assertFalse((output / "new.c").exists())
            shutil.rmtree(staging)


if __name__ == "__main__":
    unittest.main()
