/* A freestanding 32-bit PowerPC Linux program, built as the kernel builds its
   code (no C library, soft float): it writes "powerpc ok" with the write system
   call and exits 0. tests/linux-check.sh runs it under qemu-ppc. The copy goes
   through a struct and a byte loop so -O2's fold-mem-offsets pass (GCC 0019)
   has base-plus-offset stores to fold.
   MIT licence, Copyright (c) 2026 AmiCradle Team. */
struct msg { char pad[8]; char text[16]; };

static long sys(long n, long a, long b, long c)
{
  register long r0 __asm__("r0") = n, r3 __asm__("r3") = a, r4 __asm__("r4") = b, r5 __asm__("r5") = c;
  __asm__ volatile("sc" : "+r"(r3), "+r"(r0), "+r"(r4), "+r"(r5) : : "cr0", "ctr", "r6", "r7", "r8", "r9", "r10", "r11", "r12", "memory");
  return r3;
}

__attribute__((noinline)) static unsigned long put(struct msg *m, const char *s, unsigned long here)
{
  char *p = m->text + here;
  while (*s) *p++ = *s++;
  *p++ = '\n';
  return p - m->text;
}

void _start(void)
{
  static struct msg m;
  unsigned long n = put(&m, "powerpc ok", 0);
  long w = sys(4, 1, (long)m.text, (long)n);    /* write(1, text, n) */
  sys(1, w == (long)n ? 0 : 1, 0, 0);           /* exit */
  for (;;) ;
}
