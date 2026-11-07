/* Freestanding signed division helper for m68000 UBSan test images. */
#include <stdint.h>

int32_t
__divsi3 (int32_t numerator, int32_t denominator)
{
  uint32_t dividend = numerator < 0
    ? UINT32_C (0) - (uint32_t) numerator : (uint32_t) numerator;
  uint32_t divisor = denominator < 0
    ? UINT32_C (0) - (uint32_t) denominator : (uint32_t) denominator;
  uint32_t quotient = 0;
  uint32_t bit = 1;

  while (divisor <= (dividend >> 1))
    {
      divisor <<= 1;
      bit <<= 1;
    }
  while (bit != 0)
    {
      if (dividend >= divisor)
        {
          dividend -= divisor;
          quotient |= bit;
        }
      divisor >>= 1;
      bit >>= 1;
    }
  if ((numerator < 0) != (denominator < 0))
    quotient = UINT32_C (0) - quotient;
  return (int32_t) quotient;
}
