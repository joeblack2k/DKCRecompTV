#include "dkc_game_core.h"

#include "common_cpu_infra.h"
#include "common_rtl.h"
#include "dkc_generic_game.h"
#include "sha256.h"

#include <limits.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>

enum {
  kRomSize = 0x400000,
  kFramebufferWidth = 342,
  kFramebufferHeight = 224,
  kFramebufferBytesPerPixel = 4,
  kFramebufferPitch = kFramebufferWidth * kFramebufferBytesPerPixel,
  kAudioRate = 32040,
  kAudioChannels = 2,
};

extern const size_t dkc_compiled_rom_size;
extern const uint8_t dkc_compiled_rom_sha256[32];

struct DKCGameCoreInstance {
  unsigned unused;
};

static DKCGameCoreInstance s_instance;
static bool s_boot_attempted;
static bool s_booted;

static const DKCGameCoreInfo kInfo = {
  .abi_version = DKC_GAME_CORE_ABI_VERSION,
  .title = "Donkey Kong Country 3: Dixie Kong's Double Trouble!",
  .id = "dkc3",
  .framebuffer_format = DKC_GAME_CORE_PIXEL_FORMAT_BGRA8,
  .framebuffer_width = kFramebufferWidth,
  .framebuffer_height = kFramebufferHeight,
  .framebuffer_bytes_per_pixel = kFramebufferBytesPerPixel,
  .framebuffer_pitch_bytes = kFramebufferPitch,
  .video_cadence_hz = 60.098811862,
  .audio_format = DKC_GAME_CORE_AUDIO_FORMAT_S16_INTERLEAVED,
  .audio_sample_rate_hz = kAudioRate,
  .audio_channels = kAudioChannels,
  .controller_mask_bits = DKC_SNES_CONTROLLER_MASK_BITS,
};

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
  if (config->rom_size != kRomSize || config->rom_size > INT_MAX ||
      dkc_compiled_rom_size != config->rom_size) {
    set_error(config, "ROM size does not match generated DKC3 code");
    return DKC_GAME_CORE_ROM_REJECTED;
  }
  uint8_t digest[32];
  sha256_compute(config->rom_bytes, config->rom_size, digest);
  if (memcmp(digest, dkc_compiled_rom_sha256, sizeof digest) != 0) {
    set_error(config, "ROM does not match generated DKC3 code");
    return DKC_GAME_CORE_ROM_REJECTED;
  }
  if (s_boot_attempted) {
    set_error(config, s_booted
                         ? "DKC3 core is already booted"
                         : "DKC3 core boot already failed; restart the process");
    return s_booted ? DKC_GAME_CORE_ALREADY_BOOTED
                    : DKC_GAME_CORE_RUNTIME_ERROR;
  }

  s_boot_attempted = true;
  RtlRegisterGame(DkcGenericGameInfo());
  RtlSetSaveRoot(config->save_directory);
  RtlEnsureSaveDir();
  if (!SnesInit(config->rom_bytes, (int)config->rom_size)) {
    set_error(config, "DKC3 SnesInit failed");
    return DKC_GAME_CORE_RUNTIME_ERROR;
  }

  RtlSetAudioOutputRate(kAudioRate);
  RtlReadSram();
  s_booted = true;
  *out_instance = &s_instance;
  if (config->error_message && config->error_message_capacity)
    config->error_message[0] = '\0';
  return DKC_GAME_CORE_OK;
}

static DKCGameCoreResult run_frame(DKCGameCoreInstance *instance,
                                   uint32_t controller_mask) {
  if (!valid_instance(instance))
    return DKC_GAME_CORE_NOT_BOOTED;
  (void)RtlRunFrame(controller_mask & DKC_SNES_CONTROLLER_MASK);
  return (g_fail || !DkcGenericLastLleResult())
             ? DKC_GAME_CORE_RUNTIME_ERROR
             : DKC_GAME_CORE_OK;
}

static DKCGameCoreResult draw_frame(DKCGameCoreInstance *instance,
                                    uint8_t *bgra_pixels,
                                    size_t pitch_bytes) {
  if (!valid_instance(instance) || !bgra_pixels)
    return DKC_GAME_CORE_INVALID_ARGUMENT;
  if (pitch_bytes < kFramebufferPitch || pitch_bytes > UINT_MAX)
    return DKC_GAME_CORE_BUFFER_TOO_SMALL;

  DkcGenericBeginDrawing(bgra_pixels, pitch_bytes);
  DkcGenericDrawPpuFrame();
  for (size_t y = 0; y < kFramebufferHeight; y++) {
    uint8_t *row = bgra_pixels + y * pitch_bytes;
    for (size_t x = 0; x < kFramebufferWidth; x++)
      row[x * kFramebufferBytesPerPixel + 3] = 0xff;
  }
  return DKC_GAME_CORE_OK;
}

static size_t render_audio(DKCGameCoreInstance *instance, int16_t *pcm,
                           size_t frames) {
  if (!valid_instance(instance) || !pcm || frames == 0 || frames > INT_MAX)
    return 0;
  RtlRenderAudio(pcm, (int)frames, kAudioChannels);
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

static const DKCGameCoreV2 kCore = {
  .abi_version = DKC_GAME_CORE_ABI_VERSION,
  .info = &kInfo,
  .boot = &boot_core,
  .run_frame = &run_frame,
  .draw_frame = &draw_frame,
  .render_audio = &render_audio,
  .checkpoint_save = &checkpoint_save,
  .suspend = &suspend_core,
  .resume = &resume_core,
};

const DKCGameCoreV2 *dkc3_game_core(void) {
  return &kCore;
}
