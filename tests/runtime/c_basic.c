/* c_basic.c: libnix startup, stdio, heap, 64-bit integers, qsort and maths
   on a real AmigaOS. Prints "c_basic OK" (rc 0) or "c_basic FAILED" (rc 10).
   MIT licence, Copyright (c) 2026 AmiCradle Team. */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int up(const void *a, const void *b)
{
  return *(const int *) a - *(const int *) b;
}

static int check(int ok, const char *what)
{
  if (!ok)
    printf("  FAIL %s\n", what);
  return ok;
}

int main(void)
{
  char text[64];
  int numbers[] = { 9, 3, 7, 1, 8, 2, 6, 4, 5, 0 };
  volatile double two = 2.0, half = 0.5;
  volatile long long big = 0x123456789LL;
  int ok = 1, i;
  char *heap;

  snprintf(text, sizeof text, "%d %s %.3f %lx", 42, "open7", 3.14159, 0xbeefUL);
  ok &= check(strcmp(text, "42 open7 3.142 beef") == 0, "snprintf");
  ok &= check(fabs(sqrt(two) * sqrt(two) - 2.0) < 1e-12, "sqrt");
  ok &= check(fabs(sin(half) - 0.479425538604203) < 1e-12, "sin");
  ok &= check(fabs(exp(log(two)) - 2.0) < 1e-12, "exp/log");
  ok &= check(big * 1000 / 1000 == 0x123456789LL, "64-bit multiply/divide");
  ok &= check((big >> 4) == 0x12345678LL && (big % 1000) == 4886718345LL % 1000,
              "64-bit shift/modulo");
  heap = malloc(200000);
  ok &= check(heap != 0, "malloc");
  if (heap)
    {
      memset(heap, 0x5a, 200000);
      ok &= check(heap[0] == 0x5a && heap[199999] == 0x5a, "heap contents");
      free(heap);
    }
  qsort(numbers, 10, sizeof numbers[0], up);
  for (i = 0; i < 10; i++)
    ok &= check(numbers[i] == i, "qsort");
  printf("c_basic %s\n", ok ? "OK" : "FAILED");
  return ok ? 0 : 10;
}
