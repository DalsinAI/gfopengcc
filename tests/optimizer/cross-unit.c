/* Kept in a separate translation unit so the LTO profiles exercise actual
   cross-unit inlining and propagation instead of merely relabelling -O2/-O3. */
#include <stdint.h>

uint32_t
optimizer_cross_unit (uint32_t value, uint32_t salt)
{
  value += UINT32_C (0x9e3779b9) ^ salt;
  value = (value << 7) | (value >> 25);
  return value ^ (salt << 11);
}
