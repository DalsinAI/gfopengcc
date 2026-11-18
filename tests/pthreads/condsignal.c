/* condsignal: every pthread_cond_signal wakes a thread that is still waiting
 * (patches/aros-stuff/0011).
 *   two signals: two threads wait, two things arrive, pthread_cond_signal is called
 *     twice before either thread has run. Both must wake.
 *   timed out:   the first waiter's timed wait runs out while the mutex is held, so it
 *     is awake but has not come back from the wait yet; then one thing arrives and
 *     pthread_cond_signal is called once. The second waiter must wake, and the first
 *     must get ETIMEDOUT.
 *   broadcast:   three threads wait, three things arrive, one pthread_cond_broadcast.
 *   destroy:     the same on a condition of its own, and pthread_cond_destroy straight
 *     after the broadcast, before any waiter has run. It must return 0 and all three
 *     must still wake.
 * Prints PASS or FAIL per case and "condsignal OK" (rc 0) or "condsignal FAILED" (rc 20).
 *
 *   m68k-amigaos-gcc -m68040 -O2 -Wall -noixemul -o condsignal condsignal.c -lpthread
 *
 * Copyright (c) 2026 AmiCradle Team. zlib licence, as aros-stuff's pthreads. */
#include <pthread.h>
#include <errno.h>
#include <stdio.h>
#include <sys/time.h>
#include <proto/dos.h>

static pthread_mutex_t mtx = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t cond = PTHREAD_COND_INITIALIZER;
static pthread_cond_t *cur = &cond;   /* the condition the takers wait on */
static int ready;       /* threads that hold the mutex and are about to wait, or wait */
static int things;      /* what the waiters wait for */
static int done;        /* waiters that took a thing */
static int timed_rc;    /* what the timed waiter's one wait returned */
static int fails;

static void check(int ok, const char *how, const char *what)
{
    printf("%s %s: %s\n", ok ? "PASS" : "FAIL", how, what);
    if (!ok) fails++;
}

/* Waits for one thing and takes it. */
static void *taker(void *arg)
{
    (void)arg;
    pthread_mutex_lock(&mtx);
    ready++;
    while (!things) pthread_cond_wait(cur, &mtx);
    things--;
    done++;
    pthread_mutex_unlock(&mtx);
    return NULL;
}

/* One timed wait of a second, and no look at things after it: a thread that gives up. */
static void *giver_up(void *arg)
{
    struct timeval now;
    struct timespec until;
    (void)arg;
    pthread_mutex_lock(&mtx);
    ready++;
    gettimeofday(&now, NULL);
    until.tv_sec = now.tv_sec + 1;
    until.tv_nsec = now.tv_usec * 1000;
    timed_rc = pthread_cond_timedwait(&cond, &mtx, &until);
    pthread_mutex_unlock(&mtx);
    return NULL;
}

/* Returns once n threads are in their wait: ready is counted with the mutex held, and
 * the wait gives the mutex up only after the thread is on the condition's list. */
static void wait_ready(int n)
{
    int r;
    do {
        Delay(1);
        pthread_mutex_lock(&mtx); r = ready; pthread_mutex_unlock(&mtx);
    } while (r < n);
}

/* Up to 2 s for n takers to finish; returns how many did. */
static int wait_done(int n)
{
    int i, d = 0;
    for (i = 0; i < 20; i++) {
        pthread_mutex_lock(&mtx); d = done; pthread_mutex_unlock(&mtx);
        if (d >= n) break;
        Delay(5);
    }
    return d;
}

/* Wakes whatever a failed case left asleep, so the joins return. */
static void let_go(int n)
{
    pthread_mutex_lock(&mtx);
    things += n;
    pthread_cond_broadcast(&cond);
    pthread_mutex_unlock(&mtx);
}

static void reset(void) { ready = things = done = 0; timed_rc = -1; }

static void two_signals(void)
{
    pthread_t a, b;
    int d;
    reset();
    if (pthread_create(&a, NULL, taker, NULL)) { check(0, "two signals", "pthread_create"); return; }
    wait_ready(1);
    if (pthread_create(&b, NULL, taker, NULL)) { check(0, "two signals", "pthread_create"); let_go(1); pthread_join(a, NULL); return; }
    wait_ready(2);
    pthread_mutex_lock(&mtx);
    things = 2;
    pthread_cond_signal(&cond);
    pthread_cond_signal(&cond);
    pthread_mutex_unlock(&mtx);
    d = wait_done(2);
    check(d == 2, "two signals", "two waiters, two signals in a row: both wake");
    if (d < 2) let_go(0);
    pthread_join(a, NULL);
    pthread_join(b, NULL);
}

static void timed_out(void)
{
    pthread_t a, b;
    int d, rc;
    reset();
    if (pthread_create(&a, NULL, giver_up, NULL)) { check(0, "timed out", "pthread_create"); return; }
    wait_ready(1);
    if (pthread_create(&b, NULL, taker, NULL)) { check(0, "timed out", "pthread_create"); pthread_join(a, NULL); return; }
    wait_ready(2);
    pthread_mutex_lock(&mtx);
    Delay(75);              /* 1.5 s with the mutex held: the timed wait runs out and cannot return */
    things = 1;
    pthread_cond_signal(&cond);
    pthread_mutex_unlock(&mtx);
    d = wait_done(1);
    check(d == 1, "timed out", "the signal wakes the thread still waiting, not the one whose wait had run out");
    if (d < 1) let_go(0);
    pthread_join(a, NULL);
    pthread_join(b, NULL);
    pthread_mutex_lock(&mtx); rc = timed_rc; pthread_mutex_unlock(&mtx);
    check(rc == ETIMEDOUT, "timed out", "the wait that ran out returns ETIMEDOUT");
}

static void broadcast(void)
{
    pthread_t t[3];
    int i, d, n = 0;
    reset();
    for (i = 0; i < 3; i++) {
        if (pthread_create(&t[i], NULL, taker, NULL)) break;
        n++;
        wait_ready(n);
    }
    pthread_mutex_lock(&mtx);
    things = n;
    pthread_cond_broadcast(&cond);
    pthread_mutex_unlock(&mtx);
    d = wait_done(n);
    check(n == 3 && d == 3, "broadcast", "three waiters, one broadcast: all wake");
    if (d < n) let_go(0);
    for (i = 0; i < n; i++) pthread_join(t[i], NULL);
}

/* A failed wake here leaves threads in a wait nothing can end, so they are not joined:
 * exit removes them. */
static void destroy(void)
{
    static pthread_cond_t own;
    pthread_t t[3];
    int i, d, rc, n = 0;
    reset();
    if (pthread_cond_init(&own, NULL)) { check(0, "destroy", "pthread_cond_init"); return; }
    cur = &own;
    for (i = 0; i < 3; i++) {
        if (pthread_create(&t[i], NULL, taker, NULL)) break;
        n++;
        wait_ready(n);
    }
    pthread_mutex_lock(&mtx);
    things = n;
    pthread_cond_broadcast(&own);
    rc = pthread_cond_destroy(&own);
    pthread_mutex_unlock(&mtx);
    d = wait_done(n);
    check(rc == 0, "destroy", "pthread_cond_destroy straight after a broadcast returns 0");
    check(n == 3 && d == 3, "destroy", "the three waiters still wake");
    if (d == n) for (i = 0; i < n; i++) pthread_join(t[i], NULL);
    cur = &cond;
}

int main(void)
{
    two_signals();
    timed_out();
    broadcast();
    destroy();
    puts(fails ? "condsignal FAILED" : "condsignal OK");
    return fails ? 20 : 0;
}
