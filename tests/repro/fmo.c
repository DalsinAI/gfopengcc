/* fold-mem-offsets must not fold an address add into a memory-to-memory move.
   p = out + here + 8 is an add the pass folds into the four byte stores
   through p, then deletes; it took the store whose source is memory too,
   move.b (a1),2(a0), as a root for its source's base register, so that
   store kept its displacement without the 8 and landed 8 bytes early
   (2(a0) for 10(a0)).  GFOpenBench's P7 row wrote its WBNC chunk id as
   "WB\0C" (gfopenbench #216).  -O2 and -O3 with -m68040 or -m68060.
   The case is Lorien's (Team 5) cut down from PREFSWB_judge.c; g is in
   fmo_g.c so that f is compiled knowing nothing of it, and f is noipa so
   that at -O3 main calls this f, not a specialised copy of it.
   MIT licence, Copyright (c) 2026 AmiCradle Team. */
extern void puts_(const char *);
extern int g(unsigned char *out, long *n);

__attribute__((noinline, noipa)) long f(unsigned char *out, long n, unsigned long v, unsigned long a, int k, const unsigned char *m)
{
  int done = 0;
  while (k--) {
    long here = n;
    if (!g(out, &n)) return 0;
    if (!done) { unsigned char *p = out + here + 8; p[0] = v >> 24, p[1] = v >> 16, p[2] = *m, p[3] = v; done = 1; }
    else { out[0] = a >> 24, out[1] = a >> 16, out[2] = a >> 8, out[3] = a; }
  }
  return n;
}

int main(void)
{
  static unsigned char out[128];
  static const unsigned char m = 0x5a;
  static const unsigned char want[16] = { 0x11, 0x22, 0x33, 0x44, 'W', 'B', 'N', 'C', 0, 0, 0, 0x32, 0x00, 0x01, 0x5a, 0x00 };
  long n = f(out, 4, 0x00010000UL, 0x11223344UL, 2, &m);
  int bad = n != 4 + 2 * 58, i;
  for (i = 0; i < 16; i++)
    if (out[i] != want[i]) bad = 1;
  puts_(bad ? "fmo: WRONG (a memory-to-memory store lost its folded offset)\n"
            : "fmo: right (all four stores through p at p's offsets)\n");
  return bad;
}
