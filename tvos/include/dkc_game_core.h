#ifndef DKC_GAME_CORE_H
#define DKC_GAME_CORE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define DKC_GAME_CORE_ABI_VERSION 1u

typedef enum DKCGameCorePixelFormat {
  DKC_GAME_CORE_PIXEL_FORMAT_BGRA8 = 1u,
} DKCGameCorePixelFormat;

typedef enum DKCGameCoreAudioFormat {
  DKC_GAME_CORE_AUDIO_FORMAT_S16_INTERLEAVED = 1u,
} DKCGameCoreAudioFormat;

typedef enum DKCGameCoreResult {
  DKC_GAME_CORE_OK = 0,
  DKC_GAME_CORE_INVALID_ARGUMENT,
  DKC_GAME_CORE_ALREADY_BOOTED,
  DKC_GAME_CORE_ROM_REJECTED,
  DKC_GAME_CORE_NOT_BOOTED,
  DKC_GAME_CORE_BUFFER_TOO_SMALL,
  DKC_GAME_CORE_RUNTIME_ERROR,
} DKCGameCoreResult;

/* RtlRunFrame uses the same order for both SNES controller ports. */
enum {
  DKC_SNES_BUTTON_B = 1u << 0,
  DKC_SNES_BUTTON_Y = 1u << 1,
  DKC_SNES_BUTTON_SELECT = 1u << 2,
  DKC_SNES_BUTTON_START = 1u << 3,
  DKC_SNES_BUTTON_UP = 1u << 4,
  DKC_SNES_BUTTON_DOWN = 1u << 5,
  DKC_SNES_BUTTON_LEFT = 1u << 6,
  DKC_SNES_BUTTON_RIGHT = 1u << 7,
  DKC_SNES_BUTTON_A = 1u << 8,
  DKC_SNES_BUTTON_X = 1u << 9,
  DKC_SNES_BUTTON_L = 1u << 10,
  DKC_SNES_BUTTON_R = 1u << 11,
  DKC_SNES_PLAYER2_SHIFT = 12,
  DKC_SNES_CONTROLLER_MASK_BITS = 24,
};

#define DKC_SNES_CONTROLLER_MASK 0x00ffffffu

typedef struct DKCGameCoreInfo {
  uint32_t abi_version;
  const char *title;
  const char *id;
  uint32_t framebuffer_format;
  uint32_t framebuffer_width;
  uint32_t framebuffer_height;
  uint32_t framebuffer_bytes_per_pixel;
  uint32_t framebuffer_pitch_bytes;
  double video_cadence_hz;
  uint32_t audio_format;
  uint32_t audio_sample_rate_hz;
  uint32_t audio_channels;
  uint32_t controller_mask_bits;
} DKCGameCoreInfo;

typedef struct DKCGameCoreBootConfig {
  /*
   * The ROM is borrowed for the boot call only. SnesInit copies it into the
   * existing cartridge runtime before boot returns.
   */
  const uint8_t *rom_bytes;
  size_t rom_size;
  const char *save_directory;
  char *error_message;
  size_t error_message_capacity;
} DKCGameCoreBootConfig;

typedef struct DKCGameCoreInstance DKCGameCoreInstance;

typedef struct DKCGameCoreV1 {
  uint32_t abi_version;
  const DKCGameCoreInfo *info;
  DKCGameCoreResult (*boot)(const DKCGameCoreBootConfig *config,
                            DKCGameCoreInstance **out_instance);
  DKCGameCoreResult (*run_frame)(DKCGameCoreInstance *instance,
                                 uint32_t controller_mask);
  DKCGameCoreResult (*draw_frame)(DKCGameCoreInstance *instance,
                                  uint8_t *bgra_pixels,
                                  size_t pitch_bytes);
  size_t (*render_audio)(DKCGameCoreInstance *instance,
                         int16_t *pcm,
                         size_t frames);
  DKCGameCoreResult (*suspend)(DKCGameCoreInstance *instance);
  DKCGameCoreResult (*resume)(DKCGameCoreInstance *instance);
} DKCGameCoreV1;

/*
 * v1 deliberately has no shutdown callback. The shared runner owns global
 * state and snes_free does not clear every global bridge pointer. The host
 * must treat a booted core as process-lifetime; suspend flushes SRAM only.
 * Calls are serialized by the caller. Threading and audio buffering belong
 * to the host.
 */
const DKCGameCoreV1 *dkc2_game_core(void);

#ifdef __cplusplus
}
#endif

#endif
