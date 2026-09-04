#!/usr/bin/env python3
from __future__ import annotations

import math
import plistlib
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HOST = ROOT / "tvos" / "apple" / "DKCTVApp.mm"
SHADER = ROOT / "tvos" / "apple" / "DKCTVShaders.metal"
INFO = ROOT / "tvos" / "apple" / "Info.plist"
PRIVACY = ROOT / "tvos" / "apple" / "PrivacyInfo.xcprivacy"
VIDEO_HZ = 60.098811862
AUDIO_RATE = 32040
MAX_CATCH_UP = 4


def viewport(width: int, height: int, source_width: int, source_height: int):
    display_aspect = (source_width / source_height) * (7.0 / 6.0)
    viewport_width = width
    viewport_height = math.floor(viewport_width / display_aspect)
    if viewport_height > height:
        viewport_height = height
        viewport_width = math.floor(viewport_height * display_aspect)
    return (
        (width - viewport_width) / 2.0,
        (height - viewport_height) / 2.0,
        viewport_width,
        viewport_height,
    )


def simulate_cadence(display_hz: float, seconds: int):
    frame_period = 1.0 / VIDEO_HZ
    audio_per_frame = AUDIO_RATE / VIDEO_HZ
    next_deadline = 0.0
    audio_fraction = 0.0
    game_frames = 0
    audio_frames = 0
    double_catch_ups = 0
    maximum_catch_up = 0

    for callback in range(round(display_hz * seconds)):
        now = (callback + 1) / display_hz
        if next_deadline == 0.0:
            next_deadline = now
        processed = 0
        while now >= next_deadline and processed < MAX_CATCH_UP:
            processed += 1
            game_frames += 1
            audio_fraction += audio_per_frame
            requested = math.floor(audio_fraction)
            audio_fraction -= requested
            audio_frames += requested
            next_deadline += frame_period
        if processed == 2:
            double_catch_ups += 1
        maximum_catch_up = max(maximum_catch_up, processed)

    return game_frames, audio_frames, double_catch_ups, maximum_catch_up


class TvOSAppleHostTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.host = HOST.read_text(encoding="utf-8")
        cls.shader = SHADER.read_text(encoding="utf-8")

    def test_compile_time_core_selection_and_abi(self):
        for required in (
            "#ifndef DKC_CORE_FUNCTION",
            "#define DKC_CORE_FUNCTION dkc2_game_core",
            "extern \"C\" const DKCGameCoreV2 *DKC_CORE_FUNCTION(void);",
            "core_ = DKC_CORE_FUNCTION();",
            "DKC_GAME_CORE_ABI_VERSION",
            "DKC_GAME_CORE_PIXEL_FORMAT_BGRA8",
            "DKCGameCoreInstance *instance_",
        ):
            self.assertIn(required, self.host)
        version_check = self.host.index(
            "core_->abi_version != DKC_GAME_CORE_ABI_VERSION"
        )
        callback_check = self.host.index("!core_->info")
        self.assertLess(version_check, callback_check)

    def test_private_rom_and_sibling_saves(self):
        for required in (
            "NSCachesDirectory",
            "DKCRecompTV",
            "stringByAppendingPathComponent:coreID",
            "stringByAppendingPathComponent:@\"Game.sfc\"",
            "stringByAppendingPathComponent:@\"Saves\"",
            "stringByAppendingPathComponent:@\"save.srm\"",
            '[NSString stringWithFormat:@"DKCRecompTV.%@.SRAM", coreID]',
            "createDirectoryAtPath:saveDirectoryPath_",
            "dataForKey:saveDefaultsKey_",
            "writeToFile:saveFilePath_",
            "options:NSDataWritingAtomic",
            "dataWithContentsOfFile:romPath_",
            "bootConfig.save_directory",
        ):
            self.assertIn(required, self.host)
        restore = self.host.index("dataForKey:saveDefaultsKey_")
        restore_write = self.host.index("writeToFile:saveFilePath_")
        boot = self.host.index("core_->boot(&bootConfig")
        self.assertLess(restore, restore_write)
        self.assertLess(restore_write, boot)

        mirror_read = self.host.index("dataWithContentsOfFile:saveFilePath_")
        mirror_write = self.host.index("setObject:sram", mirror_read)
        mirror_flush = self.host.index("[defaults synchronize]", mirror_write)
        self.assertLess(mirror_read, mirror_write)
        self.assertLess(mirror_write, mirror_flush)
        suspend = self.host.index("core_->suspend(instance_)")
        suspend_mirror = self.host.index("[self mirrorSram]", suspend)
        self.assertLess(suspend, suspend_mirror)
        self.assertIn("core_->checkpoint_save(instance_)", self.host)
        self.assertIn("kSaveCheckpointIntervalSeconds", self.host)
        self.assertIn("if (sram.length == 0)", self.host)
        self.assertNotIn("pathForResource:", self.host)
        self.assertNotIn("NSBundle", self.host)
        self.assertNotIn("NSApplicationSupportDirectory", self.host)

    def test_metal_frame_path_and_core_cadence(self):
        for required in (
            "MTKViewDelegate",
            "MTLPixelFormatBGRA8Unorm",
            "newDefaultLibrary",
            "dkc_vertex_main",
            "dkc_fragment_main",
            "replaceRegion",
            "bytesPerRow:info_->framebuffer_pitch_bytes",
            "video_cadence_hz",
            "CACurrentMediaTime",
            "controllerMaskForFrame",
            "run_frame(instance_, controllerMask)",
            "draw_frame(instance_, framebuffer_.data()",
            "MTLPrimitiveTypeTriangleStrip",
            "setViewport:DkcViewportForSize",
            "kMaxGameFramesPerDisplay",
            "while (now >= nextFrameTime_",
            "framesProcessed < kMaxGameFramesPerDisplay",
            "nextFrameTime_ += framePeriod_",
        ):
            self.assertIn(required, self.host)
        for forbidden in (
            "newLibraryWithSource",
            "SDL",
            "OpenGL",
            "Dawn",
        ):
            self.assertNotIn(forbidden, self.host)
        self.assertNotIn("nextFrameTime_ < now - framePeriod_", self.host)

    def test_one_hour_cadence_and_fractional_audio_balance(self):
        game_frames, audio_frames, double_catch_ups, maximum_catch_up = (
            simulate_cadence(60.0, 3600)
        )
        self.assertLessEqual(
            abs(game_frames - round(VIDEO_HZ * 3600)),
            1,
        )
        self.assertLessEqual(
            abs(audio_frames - AUDIO_RATE * 3600),
            math.ceil(AUDIO_RATE / VIDEO_HZ),
        )
        self.assertGreater(double_catch_ups, 300)
        self.assertLess(double_catch_ups, 400)
        self.assertEqual(maximum_catch_up, 2)

    def test_native_audio_is_rate_paced_and_realtime_safe(self):
        for required in (
            '#import <AVFAudio/AVFAudio.h>',
            '#include "audio_ring.hpp"',
            "AVAudioEngine *audioEngine_",
            "AVAudioSourceNode *audioSourceNode_",
            "std::shared_ptr<DKCAudioRing> audioRing_",
            "AVAudioPCMFormatFloat32",
            "sampleRate:static_cast<double>(info_->audio_sample_rate_hz)",
            "channels:2",
            "interleaved:NO",
            "audioFramesPerVideoFrame_",
            "audioFrameAccumulator_",
            "core_->render_audio",
            "audioRing_->push",
            "renderRing->pop",
            "std::memset",
            "startAndReturnError",
            "stopAudio",
            "first nonzero audio",
        ):
            self.assertIn(required, self.host)

        render_block = re.search(
            r"renderBlock:\^OSStatus.*?return noErr;\s+\}\]",
            self.host,
            flags=re.DOTALL,
        )
        self.assertIsNotNone(render_block)
        self.assertIn("renderRing->pop", render_block.group(0))
        self.assertIn("std::memset", render_block.group(0))
        self.assertNotIn("core_->", render_block.group(0))
        self.assertNotIn("render_audio", render_block.group(0))
        for forbidden in (
            "owner",
            "self",
            "core",
            "new",
            "malloc",
            "mutex",
            "lock",
            "NSLog",
        ):
            self.assertIsNone(
                re.search(rf"\b{re.escape(forbidden)}\b",
                          render_block.group(0), flags=re.IGNORECASE)
            )
        self.assertNotIn("__unsafe_unretained", self.host)

    def test_audio_lifecycle_preserves_resume_node_and_has_final_teardown(self):
        for required in (
            "teardownAudio",
            "[self stopAudio]",
            "disconnectNodeOutput:audioSourceNode_",
            "detachNode:audioSourceNode_",
            "audioSourceNode_ = nil",
            "audioEngine_ = nil",
            "audioRing_.reset()",
            "removeObserver:self",
        ):
            self.assertIn(required, self.host)
        teardown = re.search(
            r"- \(void\)teardownAudio \{.*?\n\}",
            self.host,
            flags=re.DOTALL,
        )
        self.assertIsNotNone(teardown)
        teardown_text = teardown.group(0)
        self.assertLess(
            teardown_text.index("[self stopAudio]"),
            teardown_text.index("disconnectNodeOutput:audioSourceNode_"),
        )
        self.assertLess(
            teardown_text.index("disconnectNodeOutput:audioSourceNode_"),
            teardown_text.index("detachNode:audioSourceNode_"),
        )
        self.assertLess(
            teardown_text.index("detachNode:audioSourceNode_"),
            teardown_text.index("audioRing_.reset()"),
        )
        self.assertGreaterEqual(self.host.count("nextFrameTime_ = 0.0"), 3)

    def test_game_controller_poll_is_frame_serialized_and_two_player(self):
        for required in (
            '#import <GameController/GameController.h>',
            "GCControllerDidConnectNotification",
            "GCControllerDidDisconnectNotification",
            "DkcMaskForPressType",
            "UIPressTypeSelect",
            "UIPressTypePlayPause",
            "pressesBegan",
            "pressesEnded",
            "remoteMask_",
            "canBecomeFirstResponder",
            "becomeFirstResponder",
            "[GCController controllers]",
            "playerIndex",
            "GCControllerPlayerIndex1",
            "GCControllerPlayerIndex2",
            "GCExtendedGamepad",
            "buttonA",
            "buttonB",
            "buttonX",
            "buttonY",
            "leftShoulder",
            "rightShoulder",
            "buttonMenu",
            "buttonOptions",
            "dkc_pack_controllers(samples, 2)",
            "const uint32_t controllerMask = [self controllerMaskForFrame]",
        ):
            self.assertIn(required, self.host)
        self.assertEqual(self.host.count("controllerMaskForFrame"), 3)

    def test_shader_is_precompiled_nearest_sampled(self):
        self.assertIn("vertex DKCVertexOutput dkc_vertex_main", self.shader)
        self.assertIn("fragment float4 dkc_fragment_main", self.shader)
        self.assertIn("filter::nearest", self.shader)
        self.assertIn("address::clamp_to_edge", self.shader)

    def test_viewport_is_centered_and_preserves_snes_pixel_aspect(self):
        self.assertIn("constexpr double kSnesPixelAspect = 7.0 / 6.0", self.host)
        self.assertEqual(viewport(1280, 720, 342, 224), (0.0, 1.0, 1280, 718))
        self.assertEqual(viewport(1920, 1080, 342, 224), (0.0, 1.5, 1920, 1077))

    def test_lifecycle_and_first_screen_behavior(self):
        for required in (
            '[NSString stringWithFormat:@"Unable to start game.\\n%@"',
            "errorLabel_.textAlignment = NSTextAlignmentCenter",
            "sceneWillResignActive",
            "sceneDidEnterBackground",
            "sceneWillEnterForeground",
            "sceneDidBecomeActive",
            "pauseForLifecycle",
            "resumeForLifecycle",
            "core_->suspend(instance_)",
            "core_->resume(instance_)",
            "render cadence restarted",
            "first active video",
        ):
            self.assertIn(required, self.host)

    def test_plists_are_minimal_tvOS_metadata(self):
        with INFO.open("rb") as stream:
            info = plistlib.load(stream)
        self.assertEqual(info["CFBundleIdentifier"], "$(PRODUCT_BUNDLE_IDENTIFIER)")
        self.assertEqual(info["CFBundleExecutable"], "$(EXECUTABLE_NAME)")
        self.assertEqual(info["CFBundleName"], "$(PRODUCT_NAME)")
        self.assertEqual(info["UIDeviceFamily"], [3])
        self.assertEqual(info["UIRequiredDeviceCapabilities"], ["arm64", "metal"])
        self.assertTrue(info["GCSupportsControllerUserInteraction"])
        self.assertEqual(
            info["GCSupportedGameControllers"],
            [{"ProfileName": "ExtendedGamepad"}],
        )
        self.assertTrue(info["GCSupportsGameMode"])
        self.assertTrue(info["LSSupportsGameMode"])
        self.assertEqual(info["UIUserInterfaceStyle"], "Dark")
        self.assertEqual(info["LSApplicationCategoryType"], "public.app-category.games")
        scene = info["UIApplicationSceneManifest"]
        self.assertFalse(scene["UIApplicationSupportsMultipleScenes"])
        config = scene["UISceneConfigurations"]["UIWindowSceneSessionRoleApplication"][0]
        self.assertEqual(config["UISceneDelegateClassName"], "DKCSceneDelegate")

        with PRIVACY.open("rb") as stream:
            privacy = plistlib.load(stream)
        self.assertFalse(privacy["NSPrivacyTracking"])
        self.assertEqual(privacy["NSPrivacyCollectedDataTypes"], [])
        self.assertEqual(privacy["NSPrivacyAccessedAPITypes"], [])


if __name__ == "__main__":
    unittest.main()
