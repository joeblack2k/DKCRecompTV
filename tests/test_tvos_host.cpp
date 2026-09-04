#define CHECK(condition)       \
  do {                         \
    if (!(condition)) return 1; \
  } while (0)

#include "audio_ring.hpp"
#include "dkc_game_core.h"
#include "input_mapper.hpp"

int main() {
  DKCSpscRing<DKCFloatStereoFrame, 4> ring;
  const DKCFloatStereoFrame frames[] = {
      {1.0f, -1.0f}, {2.0f, -2.0f}, {3.0f, -3.0f}, {4.0f, -4.0f},
  };
  CHECK(ring.readable() == 0);
  CHECK(ring.push(frames, 4) == 4);
  CHECK(!ring.push(frames[0]));
  CHECK(ring.readable() == 4);

  DKCFloatStereoFrame popped[2] = {};
  CHECK(ring.pop(popped, 2) == 2);
  CHECK(popped[0].left == 1.0f && popped[1].right == -2.0f);
  CHECK(ring.push(frames[0]));
  CHECK(ring.readable() == 3);
  CHECK(ring.pop(popped, 2) == 2);
  CHECK(popped[0].left == 3.0f && popped[1].left == 4.0f);
  CHECK(ring.pop(popped) && popped[0].left == 1.0f);
  CHECK(!ring.pop(popped));

  DKCControllerSample first;
  first.connected = true;
  first.apple_a = true;
  first.apple_b = true;
  first.apple_x = true;
  first.apple_y = true;
  first.left_shoulder = true;
  first.right_shoulder = true;
  first.options = true;
  first.menu = true;
  first.stick_x = 0.75f;
  first.stick_y = -0.75f;
  const uint16_t first_bits = dkc_map_controller(first);
  CHECK((first_bits & DKC_SNES_BUTTON_B) != 0);
  CHECK((first_bits & DKC_SNES_BUTTON_A) != 0);
  CHECK((first_bits & DKC_SNES_BUTTON_Y) != 0);
  CHECK((first_bits & DKC_SNES_BUTTON_X) != 0);
  CHECK((first_bits & DKC_SNES_BUTTON_L) != 0);
  CHECK((first_bits & DKC_SNES_BUTTON_R) != 0);
  CHECK((first_bits & DKC_SNES_BUTTON_SELECT) != 0);
  CHECK((first_bits & DKC_SNES_BUTTON_START) != 0);
  CHECK((first_bits & DKC_SNES_BUTTON_RIGHT) != 0);
  CHECK((first_bits & DKC_SNES_BUTTON_DOWN) != 0);

  DKCControllerSample second;
  second.connected = true;
  second.up = true;
  second.left = true;
  const DKCControllerSample pads[] = {first, second};
  const uint32_t packed = dkc_pack_controllers(pads, 2);
  CHECK((packed & DKC_SNES_CONTROLLER_MASK) == packed);
  CHECK((packed & first_bits) == first_bits);
  CHECK((packed & (static_cast<uint32_t>(DKC_SNES_BUTTON_UP)
                  << DKC_SNES_PLAYER2_SHIFT)) != 0);
  CHECK((packed & (static_cast<uint32_t>(DKC_SNES_BUTTON_LEFT)
                  << DKC_SNES_PLAYER2_SHIFT)) != 0);

  second.connected = false;
  CHECK(dkc_map_controller(second) == 0);
  CHECK(dkc_pack_controllers(&second, 1) == 0);
  static_assert(DKC_GAME_CORE_ABI_VERSION == 1u, "ABI version changed");
  return 0;
}
