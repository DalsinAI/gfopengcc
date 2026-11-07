/* Stack-protector runtime for m68k AmigaOS/libnix.
   GPL-3.0-or-later. Copyright (c) 2026 AmiCradle Team. */
#include <stdint.h>
#include <stdlib.h>
#include <sys/time.h>

/* A non-zero terminator canary is valid even before constructors run.  Its
   first byte in memory is zero on big-endian m68k, frustrating disclosure by
   unterminated byte-string operations. */
uintptr_t __stack_chk_guard = (uintptr_t) 0x00d3a10aUL;

static void __attribute__((constructor, no_stack_protector))
init_stack_guard (void)
{
  struct timeval tv;
  uintptr_t mixed = __stack_chk_guard;

  if (gettimeofday (&tv, 0) == 0)
    {
      mixed ^= (uintptr_t) tv.tv_sec;
      mixed = (mixed << 11) | (mixed >> (sizeof (mixed) * 8 - 11));
      mixed ^= (uintptr_t) tv.tv_usec;
    }
  mixed ^= (uintptr_t) &tv;
  mixed ^= *(volatile uintptr_t *) 4; /* ExecBase. */
  mixed *= (uintptr_t) 0x9e3779b1UL;
  /* A multiplication never moves entropy downwards, and the inputs' low
     bits barely change between runs (aligned addresses, the timer's
     granularity): fold the high half back down before the top byte goes. */
  mixed ^= mixed >> 16;
  mixed *= (uintptr_t) 0x85ebca6bUL;
  mixed ^= mixed >> 13;
  mixed &= ~((uintptr_t) 0xff << (sizeof (mixed) * 8 - 8));
  if (mixed == 0)
    mixed = (uintptr_t) 0x00d3a10aUL;
  __stack_chk_guard = mixed;
}

void __attribute__((noreturn, no_stack_protector))
__stack_chk_fail (void)
{
  abort ();
  __builtin_unreachable ();
}

void __attribute__((noreturn, no_stack_protector))
__stack_chk_fail_local (void)
{
  __stack_chk_fail ();
}
