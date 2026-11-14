/* fmo.c's g: a chunk header at out + *n ("WBNC", size 50 the first time),
   then *n moves past it.  MIT licence, Copyright (c) 2026 AmiCradle Team. */
int g(unsigned char *out, long *n)
{
  static int calls;
  if (calls++ == 0) {
    unsigned char *c = out + *n;
    c[0] = 'W', c[1] = 'B', c[2] = 'N', c[3] = 'C', c[4] = 0, c[5] = 0, c[6] = 0, c[7] = 0x32;
  }
  *n += 58;
  return 1;
}
