/* ubsan_trap.c: -fsanitize=undefined -fsanitize-undefined-trap-on-error on a
   real AmigaOS. "ubsan_trap ok" adds within range and prints "ubsan control
   OK". "ubsan_trap overflow" overflows a signed int: the check must stop the
   program with a trap before "ubsan NOT TRAPPED" is printed. There is no
   sanitizer runtime; AmigaOS reports the trap as a CPU exception.
   MIT licence, Copyright (c) 2026 AmiCradle Team. */
#include <limits.h>
#include <stdio.h>
#include <string.h>

static volatile int addend = 1;

__attribute__((noinline)) static int add(int a, int b) { return a + b; }

int main(int argc, char **argv)
{
  int overflow = argc > 1 && strcmp(argv[1], "overflow") == 0;
  int result = add(overflow ? INT_MAX : 41, addend);

  if (overflow)
    {
      printf("ubsan NOT TRAPPED (%d)\n", result);
      return 10;
    }
  printf("ubsan control %s\n", result == 42 ? "OK" : "FAILED");
  return result == 42 ? 0 : 10;
}
