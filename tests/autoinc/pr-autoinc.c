/* m68k wrong code: move.b (%aN)+,(%aN,%dM.l) -- the source's post-increment
   register is reused as the destination base, so the 680x0 stores one byte
   too far.  m68k-aros-gcc 16.2.0 -m68040 -O2 -fomit-frame-pointer -S.
   With -DRUN, main() returns 0 when correct ("Software Failure.Error: "). */
struct line { unsigned char t[60]; unsigned n; };

static void put_s(struct line *l, const char *s)
{
    while (*s && l->n < sizeof l->t)
        l->t[l->n++] = (unsigned char)*s++;
}

static unsigned char *emit(unsigned char *p, const struct line *l)
{
    for (unsigned i = 0; i < l->n; i++)
        *p++ = l->t[i];
    return p;
}

__attribute__((noinline))
unsigned char *v1(unsigned char *buf, unsigned code, unsigned task)
{
    struct line a, b;
    a.n = b.n = 0;
    put_s(&a, "Software Failure.");
    put_s(&b, "Error: ");
    unsigned char *p = emit(buf, &a);
    p = emit(p, &b);
    return p;
}

#ifdef RUN
int main(void)
{
    static const char want[] = "Software Failure.Error: ";
    unsigned char buf[64] = { 0 };
    unsigned char *e = v1(buf, 0, 0);
    if (e - buf != (long)sizeof want - 1)
        return 2;
    for (unsigned i = 0; i < sizeof want - 1; i++)
        if (buf[i] != (unsigned char)want[i])
            return 1;
    return 0;
}
#endif
