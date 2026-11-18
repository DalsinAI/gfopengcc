/* A freestanding x86-64 Linux program, built as the kernel builds its code
   (no C library, no SSE or red zone): it writes "x86_64 ok" with the write
   system call and exits 0. tests/linux-check.sh runs it (natively on an
   x86-64 host). The copy goes through a struct and a byte loop so -O2's
   fold-mem-offsets pass (GCC 0019) has base-plus-offset stores to fold.
   MIT licence, Copyright (c) 2026 AmiCradle Team. */
struct msg { char pad[8]; char text[16]; };

static long sys(long n, long a, long b, long c)
{
  long r;
  __asm__ volatile("syscall" : "=a"(r) : "a"(n), "D"(a), "S"(b), "d"(c) : "rcx", "r11", "memory");
  return r;
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
  unsigned long n = put(&m, "x86_64 ok", 0);
  long w = sys(1, 1, (long)m.text, (long)n);    /* write(1, text, n) */
  sys(60, w == (long)n ? 0 : 1, 0, 0);          /* exit */
  for (;;) ;
}
