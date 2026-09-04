#ifndef DKC_INPUT_MAPPER_HPP
#define DKC_INPUT_MAPPER_HPP

#include <cstddef>
#include <cstdint>

#include "dkc_game_core.h"

struct DKCControllerSample {
  bool connected = false;
  bool apple_a = false;
  bool apple_b = false;
  bool apple_x = false;
  bool apple_y = false;
  bool left_shoulder = false;
  bool right_shoulder = false;
  bool options = false;
  bool menu = false;
  bool start = false;
  bool up = false;
  bool down = false;
  bool left = false;
  bool right = false;
  float stick_x = 0.0f;
  float stick_y = 0.0f;
};

inline uint16_t dkc_map_controller(const DKCControllerSample &sample) noexcept {
  if (!sample.connected)
    return 0;

  uint16_t result = 0;
  if (sample.apple_a)
    result |= DKC_SNES_BUTTON_B;
  if (sample.apple_b)
    result |= DKC_SNES_BUTTON_A;
  if (sample.apple_x)
    result |= DKC_SNES_BUTTON_Y;
  if (sample.apple_y)
    result |= DKC_SNES_BUTTON_X;
  if (sample.left_shoulder)
    result |= DKC_SNES_BUTTON_L;
  if (sample.right_shoulder)
    result |= DKC_SNES_BUTTON_R;
  if (sample.options)
    result |= DKC_SNES_BUTTON_SELECT;
  if (sample.menu || sample.start)
    result |= DKC_SNES_BUTTON_START;

  constexpr float kStickThreshold = 0.5f;
  if (sample.up || sample.stick_y >= kStickThreshold)
    result |= DKC_SNES_BUTTON_UP;
  if (sample.down || sample.stick_y <= -kStickThreshold)
    result |= DKC_SNES_BUTTON_DOWN;
  if (sample.left || sample.stick_x <= -kStickThreshold)
    result |= DKC_SNES_BUTTON_LEFT;
  if (sample.right || sample.stick_x >= kStickThreshold)
    result |= DKC_SNES_BUTTON_RIGHT;
  return result;
}

inline uint32_t dkc_pack_controllers(const DKCControllerSample *samples,
                                     std::size_t count) noexcept {
  if (!samples || count == 0)
    return 0;

  uint32_t result = dkc_map_controller(samples[0]);
  if (count > 1)
    result |= static_cast<uint32_t>(dkc_map_controller(samples[1]))
              << DKC_SNES_PLAYER2_SHIFT;
  return result & DKC_SNES_CONTROLLER_MASK;
}

#endif
