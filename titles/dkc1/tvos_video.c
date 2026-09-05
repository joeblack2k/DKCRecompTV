#include "dkc_generic_game.h"

#include <stdbool.h>
#include <stdint.h>

bool DkcTitleVideoCanWiden(const uint8_t *wram) {
  const uint8_t level = wram[0x003e];

  /*
   * DKC1 publishes a nonzero current-level value only for gameplay. Keep
   * menus, logos, fades, and other transitional states centered until a
   * scene-specific presentation proof exists.
   */
  return level != 0;
}

int DkcTitleVideoPresentationBias(const uint8_t *wram, int extra) {
  const uint16_t camera_x =
      (uint16_t)wram[0x00be] | ((uint16_t)wram[0x00bf] << 8);
  return camera_x < (uint16_t)extra ? extra - camera_x : 0;
}
