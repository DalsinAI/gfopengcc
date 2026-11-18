/* A freestanding aarch64 Linux program, built as the kernel builds its code
   (no C library, general registers only): it writes "aarch64 ok" with the
   write system call and exits 0. tests/aarch64-check.sh runs it under
   qemu-aarch64. The copy goes through a struct and a byte loop so -O2's
   fold-mem-offsets pass (GCC 0019) has base-plus-offset stores to fold.
   MIT licence, Copyright (c) 2026 AmiCradle Team. */
struct msg { char pad[8]; char text[16]; };

static long sys(long n, long a, long b, long c)
{
  register long x8 __asm__("x8") = n, x0 __asm__("x0") = a, x1 __asm__("x1") = b, x2 __asm__("x2") = c;
  __asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2) : "memory");
  return x0;
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
  unsigned long n = put(&m, "aarch64 ok", 0);
  long w = sys(64, 1, (long)m.text, (long)n);   /* write(1, text, n) */
  sys(93, w == (long)n ? 0 : 1, 0, 0);          /* exit */
  for (;;) ;
}
