#include "dkc_game_core.h"

#include <limits.h>
#include <stdbool.h>
#include <stdio.h>

#include "common_cpu_infra.h"
#include "common_rtl.h"
#include "dkc2_game.h"
#include "dkc2_video.h"
#include "verified_rom.h"

enum {
  kDkc2RomSize = 0x400000,
  kDkc2FramebufferWidth = 342,
  kDkc2FramebufferHeight = 224,
  kDkc2FramebufferBytesPerPixel = 4,
  kDkc2FramebufferPitch = kDkc2FramebufferWidth *
                          kDkc2FramebufferBytesPerPixel,
  kDkc2AudioRate = 32040,
  kDkc2AudioChannels = 2,
};

struct DKCGameCoreInstance {
  unsigned unused;
};

static DKCGameCoreInstance s_instance;
static bool s_boot_attempted;
static bool s_booted;

static const DKCGameCoreInfo kDkc2Info = {
  .abi_version = DKC_GAME_CORE_ABI_VERSION,
  .title = "Donkey Kong Country 2: Diddy's Kong Quest",
  .id = "dkc2",
  .framebuffer_format = DKC_GAME_CORE_PIXEL_FORMAT_BGRA8,
  .framebuffer_width = kDkc2FramebufferWidth,
  .framebuffer_height = kDkc2FramebufferHeight,
  .framebuffer_bytes_per_pixel = kDkc2FramebufferBytesPerPixel,
  .framebuffer_pitch_bytes = kDkc2FramebufferPitch,
  .video_cadence_hz = 60.098811862,
  .audio_format = DKC_GAME_CORE_AUDIO_FORMAT_S16_INTERLEAVED,
  .audio_sample_rate_hz = kDkc2AudioRate,
  .audio_channels = kDkc2AudioChannels,
  .controller_mask_bits = DKC_SNES_CONTROLLER_MASK_BITS,
};

static void clear_error(const DKCGameCoreBootConfig *config) {
  if (config && config->error_message && config->error_message_capacity)
    config->error_message[0] = '\0';
}

static void set_error(const DKCGameCoreBootConfig *config,
                      const char *message) {
  if (config && config->error_message && config->error_message_capacity)
    snprintf(config->error_message, config->error_message_capacity, "%s",
             message);
}

static bool valid_instance(const DKCGameCoreInstance *instance) {
  return s_booted && instance == &s_instance;
}

static DKCGameCoreResult boot_core(const DKCGameCoreBootConfig *config,
                                   DKCGameCoreInstance **out_instance) {
  if (!out_instance) {
    set_error(config, "out_instance is required");
    return DKC_GAME_CORE_INVALID_ARGUMENT;
  }
  *out_instance = NULL;
  if (!config || !config->rom_bytes || config->rom_size == 0) {
    set_error(config, "ROM bytes and size are required");
    return DKC_GAME_CORE_INVALID_ARGUMENT;
  }
  if (config->rom_size != kDkc2RomSize || config->rom_size > INT_MAX) {
    set_error(config, "unsupported headerless DKC2 ROM size");
    return DKC_GAME_CORE_ROM_REJECTED;
  }
  Dkc2RomProfile profile =
      Dkc2RomProfileForPayload(config->rom_bytes, config->rom_size);
  if (profile == DKC2_ROM_PROFILE_UNSUPPORTED) {
    set_error(config, "unsupported headerless DKC2 ROM SHA-256");
    return DKC_GAME_CORE_ROM_REJECTED;
  }
  if (!Dkc2RomProfileMatchesCompiled(profile)) {
    set_error(config, "ROM profile does not match generated AOT profile");
    return DKC_GAME_CORE_ROM_REJECTED;
  }
  if (s_boot_attempted) {
    set_error(config, s_booted
                         ? "DKC2 core is already booted"
                         : "DKC2 core boot already failed; restart the process");
    return s_booted ? DKC_GAME_CORE_ALREADY_BOOTED
                    : DKC_GAME_CORE_RUNTIME_ERROR;
  }

  /*
   * The runner has process-global state and no safe post-snes_free reset.
   * Mark the one permitted attempt before entering SnesInit.
   */
  s_boot_attempted = true;
  Dkc2VideoSetAspect(kDkc2VideoAspect16x9);
  RtlRegisterGame(Dkc2GameInfo());
  RtlSetSaveRoot(config->save_directory);
  RtlEnsureSaveDir();
  if (!SnesInit(config->rom_bytes, (int)config->rom_size)) {
    set_error(config, "DKC2 SnesInit failed");
    return DKC_GAME_CORE_RUNTIME_ERROR;
  }

  RtlSetAudioOutputRate(kDkc2AudioRate);
  RtlReadSram();
  s_booted = true;
  *out_instance = &s_instance;
  clear_error(config);
  return DKC_GAME_CORE_OK;
}

static DKCGameCoreResult run_frame(DKCGameCoreInstance *instance,
                                   uint32_t controller_mask) {
  if (!valid_instance(instance))
    return DKC_GAME_CORE_NOT_BOOTED;
  (void)RtlRunFrame(controller_mask & DKC_SNES_CONTROLLER_MASK);
  return (g_fail || !Dkc2LastLleResult()) ? DKC_GAME_CORE_RUNTIME_ERROR
                                          : DKC_GAME_CORE_OK;
}

static DKCGameCoreResult draw_frame(DKCGameCoreInstance *instance,
                                    uint8_t *bgra_pixels,
                                    size_t pitch_bytes) {
  if (!valid_instance(instance) || !bgra_pixels)
    return DKC_GAME_CORE_INVALID_ARGUMENT;
  if (pitch_bytes < kDkc2FramebufferPitch || pitch_bytes > UINT_MAX)
    return DKC_GAME_CORE_BUFFER_TOO_SMALL;

  Dkc2BeginDrawing(bgra_pixels, pitch_bytes);
  Dkc2DrawPpuFrame();
  for (size_t y = 0; y < kDkc2FramebufferHeight; ++y) {
    uint8_t *row = bgra_pixels + y * pitch_bytes;
    for (size_t x = 0; x < kDkc2FramebufferWidth; ++x)
      row[x * kDkc2FramebufferBytesPerPixel + 3] = 0xff;
  }
  return DKC_GAME_CORE_OK;
}

static size_t render_audio(DKCGameCoreInstance *instance,
                           int16_t *pcm,
                           size_t frames) {
  if (!valid_instance(instance) || !pcm || frames == 0 || frames > INT_MAX)
    return 0;
  RtlRenderAudio(pcm, (int)frames, kDkc2AudioChannels);
  return frames;
}

static DKCGameCoreResult checkpoint_save(DKCGameCoreInstance *instance) {
  if (!valid_instance(instance))
    return DKC_GAME_CORE_NOT_BOOTED;
  RtlWriteSram();
  return DKC_GAME_CORE_OK;
}

static DKCGameCoreResult suspend_core(DKCGameCoreInstance *instance) {
  return checkpoint_save(instance);
}

static DKCGameCoreResult resume_core(DKCGameCoreInstance *instance) {
  return valid_instance(instance) ? DKC_GAME_CORE_OK
                                  : DKC_GAME_CORE_NOT_BOOTED;
}

static const DKCGameCoreV2 kDkc2Core = {
  .abi_version = DKC_GAME_CORE_ABI_VERSION,
  .info = &kDkc2Info,
  .boot = &boot_core,
  .run_frame = &run_frame,
  .draw_frame = &draw_frame,
  .render_audio = &render_audio,
  .checkpoint_save = &checkpoint_save,
  .suspend = &suspend_core,
  .resume = &resume_core,
};

const DKCGameCoreV2 *dkc2_game_core(void) {
  return &kDkc2Core;
}
