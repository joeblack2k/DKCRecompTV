#include "dkc_generic_game.h"

bool DkcTitleVideoCanWiden(const uint8_t *wram) {
  const uint16_t level =
      (uint16_t)wram[0x00c0] | ((uint16_t)wram[0x00c1] << 8);
  if (level < 0x001du || level > 0x00a0u)
    return false;
  return level < 0x004du || level > 0x004fu;
}
