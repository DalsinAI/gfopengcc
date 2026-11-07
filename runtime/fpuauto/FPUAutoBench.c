/* Copyright (c) 2026 AmiCradle Team. MIT licence (see LICENSE in this folder).
 * FPUAutoBench: the same float work timed through each path fpuauto has,
 * with a checksum of every result's bits so the paths can be held together.
 *   FPUAutoBench [n] [soft]  (fpuauto build) the path the machine has, or the soft path
 *   FPUAutoBench [n]         (plain or -m68881 build) the one path it has; n loops (200000)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#ifdef NATIVE   /* the host's own build: the native comparator */
#include <time.h>
static double efreq = 1e9;
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1e9 + t.tv_nsec; }
#else
#include <exec/types.h>
#include <devices/timer.h>
#include <proto/exec.h>
#include <proto/timer.h>

struct Device *TimerBase;
static struct timerequest tr;
static ULONG efreq;
static double now(void) { struct EClockVal e; efreq = ReadEClock(&e); return ((double)e.ev_hi * 4294967296.0 + e.ev_lo); }
#endif

static volatile int N = 200000;
static unsigned int sum;
static void mix(const void *p, int n) { const unsigned char *b = p; while (n--) sum = sum * 31 + *b++; }

static void t_mandel(void)
{
    int it = 0;
    for (int y = 0; y < 60; y++)
        for (int x = 0; x < 80; x++) {
            double cr = -2.0 + x * (3.0 / 80), ci = -1.2 + y * (2.4 / 60), zr = 0, zi = 0;
            int k = 0;
            while (k < N / 2000 && zr * zr + zi * zi < 4.0) { double t = zr * zr - zi * zi + cr; zi = 2 * zr * zi + ci; zr = t; k++; }
            it += k; mix(&zr, 8);
        }
    mix(&it, 4);
}
static void t_conv(void)
{
    long acc = 0; double d = 0.37;
    for (int i = 0; i < N; i++) { d = d * 1.0001 + (double)(i & 1023); acc += (long)(d / 7.0); if (d > 1e6) d = 0.37; }
    mix(&acc, 4); mix(&d, 8);
}
static void t_float(void)
{
    float a = 1.0f, b = 0.5f; int c = 0;
    for (int i = 0; i < N; i++) { a = a * 1.00001f + b / (float)(i + 1); if (a > 1000.0f) { a = 1.0f; c++; } b = (float)(double)b; }
    mix(&a, 4); mix(&c, 4);
}
static void t_sqrt(void)
{
    double s = 0;
    for (int i = 1; i <= N; i++) s += sqrt((double)i);
    mix(&s, 8);
}
static void t_corners(void)
{
    static const double v[] = { 0.0, -0.0, 1.0, -1.0, 1e308, -1e308, 4.9e-324, 2.2250738585072014e-308, 2147483647.0, 2147483648.0,
                                -2147483648.0, -2147483649.0, 0.5, -0.5, 1.0/0.0, -1.0/0.0, 3.0e38, 1.0e39, 1.17549435e-38, 1e-46 };
    double nan = 0.0 / 0.0; int n = sizeof v / sizeof v[0];
    for (int i = 0; i <= n; i++) for (int j = 0; j <= n; j++) {
        double a = i < n ? v[i] : nan, b = j < n ? v[j] : nan; float fa = a, fb = b;
        double r[4] = { a + b, a - b, a * b, a / b }; float f[4] = { fa + fb, fa - fb, fa * fb, fa / fb };
        int c[6] = { a < b, a <= b, a == b, a != b, a > b, a >= b }; int fc[2] = { fa < fb, fa == fb };
        mix(r, sizeof r); mix(f, sizeof f); mix(c, sizeof c); mix(fc, sizeof fc);
        if (a > -2147483649.0 && a < 2147483648.0) { int k = (int)a; mix(&k, 4); }
        double e = fa; mix(&e, 8); double q = sqrt(a < 0 ? -a : a); mix(&q, 8);
    }
}

struct test { const char *name; void (*fn)(void); };
static const struct test tests[] = { { "mandel", t_mandel }, { "conv", t_conv }, { "float", t_float }, { "sqrt", t_sqrt }, { "corners", t_corners } };

#ifdef FPUAUTO
extern signed char __fpuauto_hw;
void __fpuauto_check(void);
#endif

static void run(const char *path)
{
    for (unsigned t = 0; t < sizeof tests / sizeof tests[0]; t++) {
        double best = 1e30;
        for (int r = 0; r < 3; r++) {
            sum = 0;
            double t0 = now(); tests[t].fn(); double t1 = now();
            if (t1 - t0 < best) best = t1 - t0;
        }
        printf("%-5s %-8s %9.4f s  sum %08x\n", path, tests[t].name, best / efreq, sum);
    }
}

int main(int argc, char **argv)
{
    if (argc > 1) N = atoi(argv[1]);
#ifdef NATIVE
    run("host");
    return 0;
#else
    if (OpenDevice((STRPTR)TIMERNAME, UNIT_ECLOCK, (struct IORequest *)&tr, 0)) return 20;
    TimerBase = tr.tr_node.io_Device;
    printf("AttnFlags %04x\n", SysBase->AttnFlags);
#ifdef FPUAUTO
    __fpuauto_check();
    printf("fpuauto: %s\n", __fpuauto_hw > 0 ? "FPU" : "soft");
    if (argc > 2 && argv[2][0] == 's') { __fpuauto_hw = -1; run("soft"); }
    else if (__fpuauto_hw > 0) run("fpu");
    else run("soft");
#elif defined(HARD)
    run("hard");
#else
    run("plain");
#endif
    CloseDevice((struct IORequest *)&tr);
    return 0;
#endif
}
