#include "dkc_generic_game.h"

#include <stdio.h>
#include <string.h>

static int CheckLevel(uint16_t level, bool expected) {
  uint8_t wram[0x20000];
  memset(wram, 0, sizeof wram);
  wram[0x00c0] = (uint8_t)level;
  wram[0x00c1] = (uint8_t)(level >> 8);
  if (DkcTitleVideoCanWiden(wram) == expected)
    return 0;
  fprintf(stderr, "FAIL: DKC3 level $%04x widescreen classification\n",
          level);
  return 1;
}

int main(void) {
  return CheckLevel(0x0000, false) ||
         CheckLevel(0x001d, true) ||
         CheckLevel(0x0028, true) ||
         CheckLevel(0x004d, false) ||
         CheckLevel(0x004e, false) ||
         CheckLevel(0x004f, false) ||
         CheckLevel(0x0050, true) ||
         CheckLevel(0x00a0, true) ||
         CheckLevel(0x00a1, false);
}
