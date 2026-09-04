#include "verified_rom.h"

#include <stdio.h>
#include <string.h>

static Dkc2RomProfile g_compiled_profile;

Dkc2RomProfile Dkc2CompiledRomProfile(void) {
  return g_compiled_profile;
}

#define CHECK(condition)       \
  do {                         \
    if (!(condition)) return 1; \
  } while (0)

int main(void) {
  char path[256];
  char error[256] = {0};
  size_t size = 123;
  FILE *stream;
  uint8_t *rom;

  CHECK((int)DKC2_ROM_PROFILE_USA_V10 == 0);
  CHECK((int)DKC2_ROM_PROFILE_USA_REV1 == 1);
  CHECK((int)DKC2_ROM_PROFILE_UNSUPPORTED == -1);
  g_compiled_profile = DKC2_ROM_PROFILE_USA_V10;
  CHECK(Dkc2RomProfileMatchesCompiled(DKC2_ROM_PROFILE_USA_V10));
  CHECK(!Dkc2RomProfileMatchesCompiled(DKC2_ROM_PROFILE_USA_REV1));
  g_compiled_profile = DKC2_ROM_PROFILE_USA_REV1;
  CHECK(Dkc2RomProfileMatchesCompiled(DKC2_ROM_PROFILE_USA_REV1));
  CHECK(!Dkc2RomProfileMatchesCompiled(DKC2_ROM_PROFILE_USA_V10));
  g_compiled_profile = DKC2_ROM_PROFILE_UNSUPPORTED;
  CHECK(!Dkc2RomProfileMatchesCompiled(DKC2_ROM_PROFILE_USA_V10));
  CHECK(Dkc2RomProfileForPayload(NULL, 9) == DKC2_ROM_PROFILE_UNSUPPORTED);
  rom = Dkc2ReadVerifiedRom(NULL, &size, error, sizeof error);
  CHECK(rom == NULL);
  CHECK(size == 0);
  CHECK(strcmp(error, "invalid ROM path or output pointer") == 0);
  CHECK(snprintf(path, sizeof path, "%s", "verified-rom-test.sfc") <
        (int)sizeof path);
  stream = fopen(path, "wb");
  CHECK(stream != NULL);
  CHECK(fwrite("too small", 1, 9, stream) == 9);
  CHECK(fclose(stream) == 0);

  rom = Dkc2ReadVerifiedRom(path, &size, error, sizeof error);
  CHECK(rom == NULL);
  CHECK(size == 0);
  CHECK(strcmp(error,
               "unsupported ROM (size=9 "
               "sha256=b4e1b307efbc77df67ffa56cfb9fbeeae65b7cf2782229277e07c47504cba62f)") ==
        0);
  CHECK(remove(path) == 0);
  return 0;
}
