#include "dkc_generic_game.h"

#include "common_rtl.h"
#include "cpu_state.h"
#include "snes/cart.h"
#include "snes/dma.h"
#include "snes/interp_bridge.h"
#include "snes/ppu.h"
#include "snes/saveload.h"
#include "snes/snes.h"

#include <stdbool.h>
#include <string.h>

#ifndef DKC_TITLE_ID
#error "DKC_TITLE_ID must name the compiled title"
#endif

#ifndef DKC_SAVE_PREFIX
#error "DKC_SAVE_PREFIX must name the title save-state files"
#endif

enum {
  kNtscFrameMasterClocks = 1364 * 262,
  kNativeWidth = 256,
  kWidescreenExtra = 43,
  kWidescreenWidth = kNativeWidth + 2 * kWidescreenExtra,
  kHeight = 224,
  kBytesPerPixel = 4,
};

static bool s_cpu_initialized;
static uint32_t s_resume_pc;
static uint32_t s_nmi_pc;
static uint32_t s_irq_pc;
static int s_last_lle_result = 1;
static uint64_t s_next_frame_master;

typedef struct DkcGenericHostSnapshot {
  CpuState cpu;
  uint32_t resume_pc;
  uint32_t nmi_pc;
  uint32_t irq_pc;
  uint64_t next_frame_master;
  uint64_t main_cpu_cycles_estimate;
  uint64_t apu_pace_cycles_estimate;
  uint64_t apu_last_sync_cycles;
  uint64_t apu_last_sync_master;
  int last_lle_result;
  int frame_counter;
  uint8_t cpu_initialized;
  uint8_t last_hdmaen;
  uint8_t memsel;
} DkcGenericHostSnapshot;

static uint32_t ReadVector(uint32_t address) {
  const uint8_t *vector = SnesRomPtr(address);
  return (uint32_t)vector[0] | ((uint32_t)vector[1] << 8);
}

static void DkcGenericInitialize(void) {
  s_nmi_pc = ReadVector(0x00ffea);
  s_irq_pc = ReadVector(0x00ffee);
  s_resume_pc = ReadVector(0x00fffc);
}

static void DkcGenericRunOneFrame(void) {
  const bool first_frame = !s_cpu_initialized;
  if (s_next_frame_master == 0)
    s_next_frame_master =
        g_cpu.master_cycles + kNtscFrameMasterClocks;
  while (s_next_frame_master <= g_cpu.master_cycles)
    s_next_frame_master += kNtscFrameMasterClocks;
  interp_bridge_set_master_deadline(s_next_frame_master);

  if (first_frame) {
    cpu_state_init(&g_cpu, g_ram);
    s_cpu_initialized = true;
  }

  if (!first_frame && g_snes->nmiEnabled) {
    g_snes->inNmi = true;
    cpu_push_interrupt_frame_at(&g_cpu, s_resume_pc);
    s_last_lle_result =
        interp_bridge_run_until_quiescent(&g_cpu, s_nmi_pc);
  } else if (!first_frame && g_snes->inIrq && !g_cpu._flag_I) {
    cpu_push_interrupt_frame_at(&g_cpu, s_resume_pc);
    s_last_lle_result =
        interp_bridge_run_until_quiescent(&g_cpu, s_irq_pc);
  } else {
    s_last_lle_result =
        interp_bridge_run_until_quiescent(&g_cpu, s_resume_pc);
  }

  interp_bridge_set_master_deadline(0);
  s_resume_pc = interp_bridge_lle_resume_pc();
  if (g_cpu.master_cycles < s_next_frame_master) {
    g_cpu.master_cycles = s_next_frame_master;
    snes_sync_master_clock(g_snes, g_cpu.master_cycles);
  }
  s_next_frame_master += kNtscFrameMasterClocks;
}

static void DkcGenericSaveExtra(SaveLoadInfo *sli) {
  DkcGenericHostSnapshot snapshot;
  memset(&snapshot, 0, sizeof snapshot);
  snapshot.cpu = g_cpu;
  snapshot.cpu.ram = NULL;
  snapshot.resume_pc = s_resume_pc;
  snapshot.nmi_pc = s_nmi_pc;
  snapshot.irq_pc = s_irq_pc;
  snapshot.next_frame_master = s_next_frame_master;
  snapshot.main_cpu_cycles_estimate = g_main_cpu_cycles_estimate;
  snapshot.apu_pace_cycles_estimate = g_apu_pace_cycles_estimate;
  snapshot.apu_last_sync_cycles = g_apu_last_sync_cycles;
  snapshot.apu_last_sync_master = g_apu_last_sync_master;
  snapshot.last_lle_result = s_last_lle_result;
  snapshot.frame_counter = snes_frame_counter;
  snapshot.cpu_initialized = s_cpu_initialized ? 1u : 0u;
  snapshot.last_hdmaen = g_snesrecomp_last_hdmaen;
  snapshot.memsel = g_memsel;
  sli->func(sli, &snapshot, sizeof snapshot);
}

static void DkcGenericLoadExtra(SaveLoadInfo *sli, uint32_t version) {
  (void)version;
  DkcGenericHostSnapshot snapshot;
  sli->func(sli, &snapshot, sizeof snapshot);
  g_cpu = snapshot.cpu;
  g_cpu.ram = g_ram;
  s_resume_pc = snapshot.resume_pc;
  s_nmi_pc = snapshot.nmi_pc;
  s_irq_pc = snapshot.irq_pc;
  s_next_frame_master = snapshot.next_frame_master;
  g_main_cpu_cycles_estimate = snapshot.main_cpu_cycles_estimate;
  g_apu_pace_cycles_estimate = snapshot.apu_pace_cycles_estimate;
  g_apu_last_sync_cycles = snapshot.apu_last_sync_cycles;
  g_apu_last_sync_master = snapshot.apu_last_sync_master;
  s_last_lle_result = snapshot.last_lle_result;
  snes_frame_counter = snapshot.frame_counter;
  s_cpu_initialized = snapshot.cpu_initialized != 0;
  g_snesrecomp_last_hdmaen = snapshot.last_hdmaen;
  g_memsel = snapshot.memsel;
}

static void DkcGenericOnStateLoaded(uint32_t version) {
  (void)version;
  g_cpu.ram = g_ram;
  g_apu_last_sync_master = g_cpu.master_cycles;
  g_snes->beamMasterLast = g_cpu.master_cycles;
  interp_bridge_set_master_deadline(0);
}

static const RtlGameInfo kGameInfo = {
  .title = DKC_TITLE_ID,
  .initialize = &DkcGenericInitialize,
  .run_frame = &DkcGenericRunOneFrame,
  .draw_ppu_frame = &DkcGenericDrawPpuFrame,
  .save_name_prefix = DKC_SAVE_PREFIX,
  .state_save_extra = &DkcGenericSaveExtra,
  .state_load_extra = &DkcGenericLoadExtra,
  .on_state_loaded = &DkcGenericOnStateLoaded,
};

const RtlGameInfo *DkcGenericGameInfo(void) {
  return &kGameInfo;
}

int DkcGenericLastLleResult(void) {
  return s_last_lle_result;
}

void DkcGenericBeginDrawing(uint8_t *pixels, size_t pitch) {
  PpuBeginDrawing(g_ppu, pixels, pitch, kPpuRenderFlags_NewRenderer);
}

void DkcGenericDrawPpuFrame(void) {
  SimpleHdma channels[8];
  bool active[8] = {false};
  uint8_t wide_layers = 0;
  uint8_t visible_layers = 0;
  if (DkcTitleVideoCanWiden(g_ram) && PPU_mode(g_ppu) == 1) {
    visible_layers =
        (uint8_t)(g_ppu->screenEnabled[0] | g_ppu->screenEnabled[1]);
    for (int layer = 0; layer < 3; layer++) {
      if ((visible_layers & (uint8_t)(1u << layer)) &&
          PPU_bgTilemapWider(g_ppu, layer))
        wide_layers |= (uint8_t)(1u << layer);
    }
  }
  const uint8_t repeat_layers =
      wide_layers ? (uint8_t)(visible_layers & ~wide_layers & 7u) : 0u;

  for (int y = 0; y < kHeight; y++) {
    memset(g_ppu->renderBuffer + (size_t)y * g_ppu->renderPitch, 0,
           (size_t)kWidescreenWidth * kBytesPerPixel);
  }
  if (wide_layers)
    PpuSetExtraSpace(g_ppu, kWidescreenExtra);
  else
    PpuSetExtraSpaceCentered(g_ppu, kWidescreenExtra);
  PpuSetWidescreenLayerMask(g_ppu, wide_layers);
  PpuSetWidescreenLayerRepeat(g_ppu, repeat_layers);
  PpuSetWidescreenLayerClamp(g_ppu, 0);
  PpuSetWidescreenBg3Widen(g_ppu, (wide_layers & 4u) ? 1u : 0u);
  PpuSetWidescreenPresentationXBias(g_ppu, 0);

  dma_startDma(g_dma, g_snesrecomp_last_hdmaen, true);
  for (int channel = 0; channel < 8; channel++) {
    active[channel] = g_dma->channel[channel].hdmaActive;
    if (active[channel])
      SimpleHdma_Init(&channels[channel], &g_dma->channel[channel]);
  }
  for (int line = 0; line <= kHeight; line++) {
    ppu_runLine(g_ppu, line);
    for (int channel = 0; channel < 8; channel++) {
      if (active[channel])
        SimpleHdma_DoLine(&channels[channel]);
    }
  }
  ppu_checkOverscan(g_ppu);
  ppu_handleVblank(g_ppu);
}

void RunOneFrameOfGame_Internal(void) {
  DkcGenericRunOneFrame();
}

void ResetSpritesFunc(int first) {
  (void)first;
}
