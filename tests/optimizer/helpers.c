/* Freestanding arithmetic helper for the 68000 matrix.  Later CPUs lower the
   tested 32-bit multiplies directly; the 68000 backend emits this libcall. */
#include <stdint.h>

uint32_t
__mulsi3 (uint32_t left, uint32_t right)
{
  uint32_t product = 0;

  while (right != 0)
    {
      if ((right & UINT32_C (1)) != 0)
        product += left;
      left <<= 1;
      right >>= 1;
    }
  return product;
}
