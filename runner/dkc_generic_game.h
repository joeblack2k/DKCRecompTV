#pragma once

#include "common_cpu_infra.h"

#include <stddef.h>
#include <stdint.h>

const RtlGameInfo *DkcGenericGameInfo(void);
int DkcGenericLastLleResult(void);
void DkcGenericBeginDrawing(uint8_t *pixels, size_t pitch);
void DkcGenericDrawPpuFrame(void);

/* Implemented once by each title adapter linked with the generic runner. */
bool DkcTitleVideoCanWiden(const uint8_t *wram);
int DkcTitleVideoPresentationBias(const uint8_t *wram, int extra);
