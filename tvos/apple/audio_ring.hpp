#ifndef DKC_AUDIO_RING_HPP
#define DKC_AUDIO_RING_HPP

#include <array>
#include <atomic>
#include <cstddef>

struct DKCFloatStereoFrame {
  float left;
  float right;
};

/*
 * Fixed-storage single-producer/single-consumer ring. The producer owns
 * write_index_ and the consumer owns read_index_; no locks or allocation are
 * needed on either side.
 */
template <typename T, std::size_t Capacity>
class DKCSpscRing {
  static_assert(Capacity > 0, "SPSC ring capacity must be positive");

 public:
  bool push(const T &value) noexcept {
    return push(&value, 1) == 1;
  }

  std::size_t push(const T *values, std::size_t count) noexcept {
    if (!values || count == 0)
      return 0;

    const std::size_t write = write_index_.load(std::memory_order_relaxed);
    const std::size_t read = read_index_.load(std::memory_order_acquire);
    const std::size_t used = write - read;
    const std::size_t free = used < Capacity ? Capacity - used : 0;
    const std::size_t pushed = count < free ? count : free;
    for (std::size_t i = 0; i < pushed; i++)
      storage_[(write + i) % Capacity] = values[i];
    write_index_.store(write + pushed, std::memory_order_release);
    return pushed;
  }

  bool pop(T *value) noexcept {
    return pop(value, 1) == 1;
  }

  std::size_t pop(T *values, std::size_t count) noexcept {
    if (!values || count == 0)
      return 0;

    const std::size_t read = read_index_.load(std::memory_order_relaxed);
    const std::size_t write = write_index_.load(std::memory_order_acquire);
    const std::size_t used = write - read;
    const std::size_t popped = count < used ? count : used;
    for (std::size_t i = 0; i < popped; i++)
      values[i] = storage_[(read + i) % Capacity];
    read_index_.store(read + popped, std::memory_order_release);
    return popped;
  }

  std::size_t readable() const noexcept {
    const std::size_t read = read_index_.load(std::memory_order_acquire);
    const std::size_t write = write_index_.load(std::memory_order_acquire);
    return write - read;
  }

  static constexpr std::size_t capacity() noexcept {
    return Capacity;
  }

 private:
  std::array<T, Capacity> storage_{};
  alignas(64) std::atomic<std::size_t> write_index_{0};
  alignas(64) std::atomic<std::size_t> read_index_{0};
};

using DKCAudioRing = DKCSpscRing<DKCFloatStereoFrame, 4096>;

#endif
