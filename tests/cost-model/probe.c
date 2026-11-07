#include <stddef.h>
#include <stdint.h>

static uint32_t fold(uint32_t h, uint32_t value)
{
    return ((h ^ value) << 7 | (h ^ value) >> 25) * 0x9e3779b1u;
}

uint32_t cost_model_probe(unsigned char *buffer, size_t size, uint32_t seed)
{
    uint32_t h = seed;
    for (size_t i = 1; i < size; ++i) {
        uint32_t value = buffer[i] * 37u + (uint32_t)i * 101u;
        value ^= value << (i & 15u);
        value += value / ((i & 31u) + 1u);
        buffer[i - 1] = (unsigned char)value;
        h = fold(h, value);
    }
    __builtin_memmove(buffer + 7, buffer + 3, size > 31 ? 24 : 0);
    return fold(h, buffer[7]);
}
