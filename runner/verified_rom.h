#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum Dkc2RomProfile {
  DKC2_ROM_PROFILE_USA_V10 = 0,
  DKC2_ROM_PROFILE_USA_REV1 = 1,
  DKC2_ROM_PROFILE_UNSUPPORTED = -1,
} Dkc2RomProfile;

/* Classifies an already headerless payload without parsing or copying it. */
Dkc2RomProfile Dkc2RomProfileForPayload(const uint8_t *payload,
                                        size_t payload_size);

/* Generated C source identifies the exact ROM profile used for AOT output. */
Dkc2RomProfile Dkc2CompiledRomProfile(void);

/* Returns nonzero only when the runtime profile is supported by that output. */
int Dkc2RomProfileMatchesCompiled(Dkc2RomProfile runtime_profile);

/* Loads the caller-owned private ROM, removes an optional 512-byte copier
 * header, and accepts only the two supported 4 MiB USA payload hashes. The
 * returned buffer belongs to the caller and must be released with free(). */
uint8_t *Dkc2ReadVerifiedRom(const char *path, size_t *size_out,
                             char *error, size_t error_size);

#ifdef __cplusplus
}
#endif
