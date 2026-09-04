#!/usr/bin/env python3
from pathlib import Path
import plistlib
import stat
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
APPLE_CMAKE = ROOT / "tvos" / "apple" / "CMakeLists.txt"
BUILD = ROOT / "scripts" / "tvos" / "build-app.sh"
AUDIT = ROOT / "scripts" / "tvos" / "audit-app.sh"
STAGE = ROOT / "scripts" / "tvos" / "stage-game.sh"
INFO = ROOT / "tvos" / "apple" / "Info.plist"
PRIVACY = ROOT / "tvos" / "apple" / "PrivacyInfo.xcprivacy"
DEVELOPER_DIR = "/Applications/Xcode-27-beta-5.app/Contents/Developer"


class TvOSBuildToolingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cmake = APPLE_CMAKE.read_text(encoding="utf-8")
        cls.build = BUILD.read_text(encoding="utf-8")
        cls.audit = AUDIT.read_text(encoding="utf-8")
        cls.stage = STAGE.read_text(encoding="utf-8")

    def test_tooling_files_are_executable_and_shell_clean(self):
        for script in (BUILD, AUDIT, STAGE):
            self.assertTrue(script.stat().st_mode & stat.S_IXUSR, script)
            result = subprocess.run(
                ["sh", "-n", str(script)],
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
            )
            self.assertEqual(result.returncode, 0, result.stdout)

    def test_isolated_app_project_imports_only_the_core_archive(self):
        for required in (
            "project(DKCRecompTV LANGUAGES OBJCXX)",
            "CMAKE_SYSTEM_NAME=tvOS",
            "DKC2_TVOS_CORE_ARCHIVE",
            'set(DKC2_TVOS_CORE_FUNCTION "dkc2_game_core" CACHE STRING',
            "add_library(dkc2_tvos_core STATIC IMPORTED GLOBAL)",
            "IMPORTED_LOCATION",
            "DKCTVApp.mm",
            "DKC_CORE_FUNCTION=${DKC2_TVOS_CORE_FUNCTION}",
            "dkc2_platform_constants.mm",
            "-Wl,-force_load,",
            "DKCTVShaders.metal",
            "air64-apple-tvos17.0",
            "default.metallib",
            "PrivacyInfo.xcprivacy",
            "MACOSX_BUNDLE_INFO_PLIST",
            "PRODUCT_BUNDLE_IDENTIFIER",
            "tv.nijssen.DKC2RecompTV",
            "PRODUCT_NAME",
            "DKC2 Recomp TV",
            "DKC2_EXECUTABLE_NAME",
            "OUTPUT_NAME",
            "MARKETING_VERSION",
            "CURRENT_PROJECT_VERSION",
            "17.0",
            "-fobjc-arc",
            "-ffile-prefix-map=",
            "-fdebug-prefix-map=",
        ):
            self.assertIn(required, self.cmake)
        for framework in (
            "UIKit",
            "Metal",
            "MetalKit",
            "QuartzCore",
            "AVFAudio",
            "GameController",
            "Foundation",
        ):
            self.assertIn(f'"-framework {framework}"', self.cmake)
        self.assertNotIn("add_subdirectory(", self.cmake)
        self.assertNotIn("DKC2_SNESRECOMP_GEN_DIR", self.cmake)
        self.assertNotIn("generated/snesrecomp", self.cmake)

    def test_build_runs_preflight_generator_ninja_core_and_app(self):
        for required in (
            f'EXPECTED_DEVELOPER_DIR="{DEVELOPER_DIR}"',
            "preflight.sh",
            "generate_snesrecomp.py",
            "--core-archive",
            "--core-function",
            "--bundle-id",
            "--product-name",
            "--executable-name",
            'xcrun --sdk "$sdk" --find clang',
            'xcrun --sdk "$sdk" --find clang++',
            "-G Ninja",
            "CMAKE_SYSTEM_NAME=tvOS",
            "CMAKE_OSX_SYSROOT",
            "CMAKE_OSX_ARCHITECTURES=arm64",
            "CMAKE_OSX_DEPLOYMENT_TARGET=17.0",
            "CMAKE_BUILD_TYPE=Release",
            "DKC2_BUILD_TVOS_CORE=ON",
            "dkc2_tvos_core",
            "DKC2_TVOS_CORE_ARCHIVE",
            "DKC2_TVOS_CORE_FUNCTION",
            "DKC2_BUNDLE_ID",
            "DKC2_PRODUCT_NAME",
            "DKC2_EXECUTABLE_NAME",
            'app_path="$app_build/$executable_name.app"',
            "APP_PATH:",
        ):
            self.assertIn(required, self.build)
        self.assertNotIn("xcode-select", self.build)

    def test_audit_checks_binary_plist_resources_symbols_frameworks_and_boundary(self):
        for required in (
            "lipo",
            "vtool",
            "minos",
            "TVOS",
            "TVOSSIMULATOR",
            "arm64",
            "Info.plist",
            "PrivacyInfo.xcprivacy",
            "default.metallib",
            "CFBundleIdentifier",
            "CFBundleExecutable",
            "CFBundleShortVersionString",
            "CFBundleVersion",
            "CFBundleSupportedPlatforms",
            "EXPECTED_CORE_SYMBOL",
            "DKC2_TVOS_AUDIT_SYMBOL",
            "DKCGameViewController",
            "otool",
            "generated",
            "*.sfc",
            "*.smc",
            "personal absolute source path",
        ):
            self.assertIn(required, self.audit)
        for framework in (
            "UIKit",
            "Metal",
            "MetalKit",
            "QuartzCore",
            "AVFAudio",
            "GameController",
            "Foundation",
        ):
            self.assertIn(f"/${{framework}}", self.audit)
        self.assertNotIn("codesign --verify", self.audit)

    def test_stage_uses_non_destructive_app_data_copy_and_readback(self):
        for required in (
            "preflight.sh",
            "Game.sfc",
            "appDataContainer",
            "DEFAULT_CORE_ID=\"dkc2\"",
            "DEFAULT_DATA_ROOT=\"Library/Caches/DKCRecompTV\"",
            "core_id=",
            "data_root=",
            "data_destination=\"$data_root/$core_id/Game.sfc\"",
            "remove-existing-content false",
            "device copy to",
            "device copy from",
            "shasum",
            "stat",
            "cmp -s",
            "trap 'rm -rf",
        ):
            self.assertIn(required, self.stage)
        for forbidden in (
            "device install",
            "simctl install",
            "device launch",
            "simctl launch",
        ):
            self.assertNotIn(forbidden, self.stage)

    def test_stage_rejects_unsafe_core_ids_before_external_tools(self):
        with tempfile.NamedTemporaryFile() as rom:
            for core_id in (
                "",
                ".",
                "..",
                "../dkc3",
                "dkc3/alt",
                r"dkc3\alt",
                "dkc 3",
                "dkc3;rm",
            ):
                result = subprocess.run(
                    [
                        "sh",
                        str(STAGE),
                        rom.name,
                        "device",
                        "tv.nijssen.DKC2RecompTV",
                        core_id,
                    ],
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    env={"PATH": ""},
                    executable="/bin/sh",
                )
                self.assertEqual(result.returncode, 64, result.stdout)
                self.assertIn("core ID", result.stdout)

    def test_stage_keeps_dkc2_preflight_title_specific(self):
        self.assertIn(
            'if [ "$core_id" = "$DEFAULT_CORE_ID" ]; then',
            self.stage,
        )
        self.assertIn('"$preflight" "$rom_path"', self.stage)
        self.assertIn(
            '[ -f "$rom_path" ] || die 3 "ROM file not found: $rom_path"',
            self.stage,
        )

    def test_existing_bundle_metadata_remains_placeholder_driven(self):
        with INFO.open("rb") as stream:
            info = plistlib.load(stream)
        self.assertEqual(info["CFBundleIdentifier"], "$(PRODUCT_BUNDLE_IDENTIFIER)")
        self.assertEqual(info["CFBundleExecutable"], "$(EXECUTABLE_NAME)")
        self.assertEqual(info["CFBundleShortVersionString"], "$(MARKETING_VERSION)")
        self.assertEqual(info["CFBundleVersion"], "$(CURRENT_PROJECT_VERSION)")
        with PRIVACY.open("rb") as stream:
            privacy = plistlib.load(stream)
        self.assertFalse(privacy["NSPrivacyTracking"])
        self.assertEqual(privacy["NSPrivacyCollectedDataTypes"], [])
        self.assertEqual(privacy["NSPrivacyAccessedAPITypes"], [])


if __name__ == "__main__":
    unittest.main()
