/* Defined-behaviour integer kernels for cross-optimisation comparison.
   No libc is required; tests/repro/rt.c supplies the output routine. */
#include <stdint.h>

extern void puts_ (const char *);
extern void putu (unsigned long);
extern uint32_t optimizer_cross_unit (uint32_t, uint32_t);

static uint8_t bytes[256];
static uint32_t words[64];
static uint16_t left[8][8];
static uint16_t right[8][8];
static uint32_t product[8][8];
static volatile uint32_t result_sink;

static uint32_t
xorshift32 (uint32_t value)
{
  value ^= value << 13;
  value ^= value >> 17;
  value ^= value << 5;
  return value;
}

static uint32_t
crc32_bytes (const uint8_t *data, unsigned int length)
{
  uint32_t crc = UINT32_C (0xffffffff);
  unsigned int index;

  for (index = 0; index < length; ++index)
    {
      unsigned int bit;
      crc ^= data[index];
      for (bit = 0; bit < 8; ++bit)
        {
          uint32_t mask = UINT32_C (0) - (crc & UINT32_C (1));
          crc = (crc >> 1) ^ (UINT32_C (0xedb88320) & mask);
        }
    }
  return ~crc;
}

static void
sort_words (void)
{
  unsigned int outer;

  for (outer = 1; outer < 64; ++outer)
    {
      uint32_t value = words[outer];
      unsigned int inner = outer;
      while (inner > 0 && words[inner - 1] > value)
        {
          words[inner] = words[inner - 1];
          --inner;
        }
      words[inner] = value;
    }
}

static uint32_t
matrix_kernel (void)
{
  uint32_t checksum = 0;
  unsigned int row;

  for (row = 0; row < 8; ++row)
    {
      unsigned int column;
      for (column = 0; column < 8; ++column)
        {
          uint32_t value = 0;
          unsigned int lane;
          for (lane = 0; lane < 8; ++lane)
            value += (uint32_t) left[row][lane]
                     * (uint32_t) right[lane][column];
          product[row][column] = value;
          checksum = (checksum << 3) | (checksum >> 29);
          checksum ^= value;
        }
    }
  return checksum;
}

static uint32_t
bitmix_kernel (uint32_t value)
{
  unsigned int iteration;

  for (iteration = 0; iteration < 4096; ++iteration)
    {
      value = optimizer_cross_unit (value, iteration);
      value ^= value >> 16;
      value += value << 3;
      value ^= value >> 4;
      value *= UINT32_C (0x27d4eb2d);
      value ^= value >> 15;
    }
  return value;
}

int
main (void)
{
  uint32_t state = UINT32_C (0x13579bdf);
  uint32_t checksum;
  unsigned int index;

  for (index = 0; index < 256; ++index)
    {
      state = xorshift32 (state);
      bytes[index] = (uint8_t) state;
      if (index < 64)
        words[index] = state;
    }
  for (index = 0; index < 64; ++index)
    {
      left[index >> 3][index & 7] = (uint16_t) (bytes[index] & 31);
      right[index >> 3][index & 7] =
        (uint16_t) (bytes[index + 64] & 31);
    }

  checksum = crc32_bytes (bytes, 256);
  sort_words ();
  for (index = 0; index < 64; ++index)
    checksum = xorshift32 (checksum ^ words[index]);
  checksum ^= matrix_kernel ();
  checksum ^= bitmix_kernel (checksum);
  result_sink = checksum;

  puts_ ("checksum=");
  putu ((unsigned long) result_sink);
  puts_ ("\n");
  return 0;
}
