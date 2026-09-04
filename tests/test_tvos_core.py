#!/usr/bin/env python3
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
HEADER = ROOT / "tvos" / "include" / "dkc_game_core.h"
PREFLIGHT = ROOT / "scripts" / "tvos" / "preflight.sh"

V10_SHA256 = (
    "35421a9af9dd011b40b91f792192af9f99c93201d8d394026bdfb42cbf2d8633"
)
REV1_SHA256 = (
    "b79c2bb86f6fc76e1fc61c62fc16d51c664c381e58bc2933be643bbc4d8b610c"
)


class TvOSCoreContractTests(unittest.TestCase):
    def test_runtime_save_paths_fit_apple_container_paths(self):
        header = (
            ROOT / "snesrecomp" / "runner" / "src" / "common_rtl.h"
        ).read_text(encoding="utf-8")
        runtime = (
            ROOT / "snesrecomp" / "runner" / "src" / "common_rtl.c"
        ).read_text(encoding="utf-8")
        physical_path = (
            "/var/mobile/Containers/Data/Application/"
            "00000000-0000-0000-0000-000000000000/"
            "Library/Caches/DKCRecompTV/dkc2/Saves/save.srm"
        )

        self.assertGreater(len(physical_path), 96)
        self.assertIn("RTL_SAVE_PATH_CAPACITY = 1024", header)
        self.assertIn("static char s_save_root[768]", runtime)
        self.assertGreater(768, len(physical_path))
        self.assertGreater(1024, len(physical_path))

    def test_snesrecomp_reads_native_interrupt_vectors(self):
        runtime = (ROOT / "runner" / "dkc2_game.c").read_text(encoding="utf-8")

        for required in (
            "SnesRomPtr(0x00FFEA)",
            "SnesRomPtr(0x00FFFC)",
            ".initialize = &Dkc2Initialize",
            "s_nmi_pc =",
            "s_resume_pc =",
        ):
            self.assertIn(required, runtime)
        self.assertNotIn("kDkc2ResetPc", runtime)
        self.assertNotIn("kDkc2NmiPc", runtime)
        self.assertNotIn("0x0083F7", runtime)
        self.assertNotIn("0x00F37D", runtime)

    def test_public_abi_metadata_and_rom_profiles(self):
        header = HEADER.read_text(encoding="utf-8")
        self.assertIn("#define DKC_GAME_CORE_ABI_VERSION 2u", header)
        self.assertIn("DKC_GAME_CORE_PIXEL_FORMAT_BGRA8", header)
        self.assertIn("DKC_GAME_CORE_AUDIO_FORMAT_S16_INTERLEAVED", header)
        self.assertIn("DKCGameCoreResult (*run_frame)", header)
        self.assertIn("DKCGameCoreResult (*draw_frame)", header)
        self.assertIn("size_t (*render_audio)", header)
        self.assertIn("DKCGameCoreResult (*suspend)", header)
        self.assertIn("DKCGameCoreResult (*resume)", header)
        self.assertNotIn("(*shutdown)", header)
        self.assertNotIn("LunaGameCore", header)
        self.assertIn("const DKCGameCoreV2 *dkc2_game_core(void);", header)

        adapter = (ROOT / "tvos" / "core" / "dkc2_game_core.c").read_text(
            encoding="utf-8"
        )
        for required in (
            '#include "dkc_game_core.h"',
            "kDkc2FramebufferWidth = 342",
            "kDkc2FramebufferHeight = 224",
            "kDkc2FramebufferBytesPerPixel = 4",
            "kDkc2AudioRate = 32040",
            "framebuffer_width = kDkc2FramebufferWidth",
            "framebuffer_height = kDkc2FramebufferHeight",
            "framebuffer_pitch_bytes = kDkc2FramebufferPitch",
            "video_cadence_hz = 60.098811862",
            "audio_sample_rate_hz = kDkc2AudioRate",
            "RtlRegisterGame(Dkc2GameInfo())",
            "SnesInit(config->rom_bytes, (int)config->rom_size)",
            "Dkc2RomProfileMatchesCompiled(profile)",
            "Dkc2VideoSetAspect(kDkc2VideoAspect16x9)",
            "const DKCGameCoreV2 *dkc2_game_core(void)",
        ):
            self.assertIn(required, adapter)
        self.assertLess(
            adapter.index("Dkc2RomProfileMatchesCompiled(profile)"),
            adapter.index("SnesInit(config->rom_bytes, (int)config->rom_size)"),
        )
        self.assertLess(
            adapter.index("Dkc2RomProfileMatchesCompiled(profile)"),
            adapter.index("s_boot_attempted = true"),
        )
        self.assertNotIn("LunaGameCore", adapter)

        verified_rom = (ROOT / "runner" / "verified_rom.c").read_text(
            encoding="utf-8"
        )
        for required in (
            "0xb7, 0x9c, 0x2b, 0xb8",
            "0x1f, 0xc6, 0x1c, 0x62",
            "0xbe, 0x64, 0x3b, 0xbc",
            "Dkc2RomProfileForPayload",
            "Dkc2RomProfileMatchesCompiled",
            "Dkc2CompiledRomProfile",
            "payload_size != 0x400000u",
            "size_t skip = ((size_t)length % 1024u == 512u) ? 512u : 0u",
        ):
            self.assertIn(required, verified_rom)

        generator_ps1 = (
            ROOT / "scripts" / "generate_snesrecomp.ps1"
        ).read_text(encoding="utf-8")
        self.assertIn("generate_snesrecomp.py", generator_ps1)
        self.assertIn("--snesrecomp-root", generator_ps1)
        self.assertNotIn("$ExpectedHashes", generator_ps1)

        cmake = (ROOT / "CMakeLists.txt").read_text(encoding="utf-8")
        self.assertEqual(
            cmake.count(
                'if(NOT EXISTS "${DKC2_SNESRECOMP_GEN_DIR}/dkc2_rom_profile.c")'
            ),
            2,
            "both generated-source blocks must require the marker",
        )

        preflight = PREFLIGHT.read_text(encoding="utf-8")
        self.assertIn(V10_SHA256, preflight)
        self.assertIn(REV1_SHA256, preflight)
        self.assertIn("DKC2 USA v1.0", preflight)
        self.assertIn("DKC2 USA Rev 1/v1.1", preflight)


if __name__ == "__main__":
    unittest.main()
