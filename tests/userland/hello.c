/* tests/userland/hello.c: a C program over the glibc 2.35 sysroot: threads,
 * dlopen, libm, a TLS variable and stdio, as AmiCradle's runtimes use them.
 * Prints "<arch> c ok". GPL-3.0-or-later. Copyright (c) 2026 AmiCradle Team. */
#include <dlfcn.h>
#include <math.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>

static __thread int tls = 7;
static double sum;

static void *work(void *arg)
{
    double s = 0;
    for (int i = 1; i <= 1000; i++)
        s += sqrt((double)i) * fmod((double)i, 7.0);
    sum = s + tls + *(int *)arg;
    return NULL;
}

int main(void)
{
    pthread_t t;
    int x = 1;
    if (pthread_create(&t, NULL, work, &x) || pthread_join(t, NULL))
        return 2;
    void *h = dlopen("libm.so.6", RTLD_NOW);
    if (!h || !dlsym(h, "cos"))
        return 3;
    if (sum < 1000.0)
        return 4;
    printf("%s c ok\n", ARCH);
    return 0;
}
