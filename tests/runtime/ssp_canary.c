/* ssp_canary.c: the stack-protector runtime on a real AmigaOS.
   "ssp_canary ok" calls a protected function normally: it must print
   "ssp control OK" and return 0. "ssp_canary smash" writes 'A' over the
   bytes after a 16-byte array, up to and including the canary, and nothing
   beyond it. The epilogue check must call __stack_chk_fail, whose abort()
   prints libnix's "Program aborted" and exits with 127. "ssp NOT DETECTED"
   means the corruption went unnoticed.
   The guard is printed: its first byte is always 0 and it differs between runs.
   MIT licence, Copyright (c) 2026 AmiCradle Team. */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

extern uintptr_t __stack_chk_guard;
static volatile unsigned int extra;

__attribute__((noinline)) static int victim(const char *text)
{
  char buffer[16];
  char *volatile write = buffer;
  unsigned int i, end = sizeof buffer + extra;

  strncpy(buffer, text, sizeof buffer - 1);
  buffer[sizeof buffer - 1] = 0;
  for (i = sizeof buffer; i < end; i++)
    write[i] = 'A';
  return (int) strlen(buffer);
}

int main(int argc, char **argv)
{
  int smash = argc > 1 && strcmp(argv[1], "smash") == 0;

  printf("guard %08lx\n", (unsigned long) __stack_chk_guard);
  fflush(stdout);
  extra = smash ? SSP_REACH : 0;
  if (victim("open7 canary") != 12)
    return 10;
  if (smash)
    {
      printf("ssp NOT DETECTED\n");
      return 10;
    }
  printf("ssp control OK\n");
  return 0;
}
