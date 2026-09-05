#include "dkc_generic_game.h"

#include <stdio.h>
#include <string.h>

static int CheckLevel(uint16_t level, bool expected) {
  uint8_t wram[0x20000];
  memset(wram, 0, sizeof wram);
  wram[0x003e] = (uint8_t)level;
  if (DkcTitleVideoCanWiden(wram) == expected)
    return 0;
  fprintf(stderr, "FAIL: DKC1 current level $%04x widescreen classification\n",
          level);
  return 1;
}

static int CheckCamera(uint16_t camera_x, int expected) {
  uint8_t wram[0x20000];
  memset(wram, 0, sizeof wram);
  wram[0x00be] = (uint8_t)camera_x;
  wram[0x00bf] = (uint8_t)(camera_x >> 8);
  const int actual = DkcTitleVideoPresentationBias(wram, 43);
  if (actual == expected)
    return 0;
  fprintf(stderr, "FAIL: DKC1 camera $%04x bias %d, expected %d\n",
          camera_x, actual, expected);
  return 1;
}

int main(void) {
  return CheckLevel(0x0000, false) ||
         CheckLevel(0x0001, true) ||
         CheckLevel(0x0016, true) ||
         CheckLevel(0x00eb, true) ||
         CheckLevel(0xffff, true) ||
         CheckCamera(0, 43) ||
         CheckCamera(20, 23) ||
         CheckCamera(42, 1) ||
         CheckCamera(43, 0) ||
         CheckCamera(0xffff, 0);
}
