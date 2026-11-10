/* pthreads patch 0010: exit ends the threads still running, as Linux's exit()
 * does. Run it from a Shell; each case prints what it expects.
 *   exitcancel cond      a worker waits in pthread_cond_wait; main returns.
 *                        The program is back at the Shell at once, and the
 *                        worker's clean-up handler does not run.
 *   exitcancel sem       the same, waiting in sem_wait
 *   exitcancel join      a worker waits in pthread_join for another worker,
 *                        which waits in pthread_cond_wait
 *   exitcancel nocancel  the worker disabled cancellation first: exit gives it
 *                        2 s, then removes it, with one line on the output and
 *                        in T:pthreads-exit.log
 *   exitcancel ctrlc     main waits for Ctrl-C (Break the process), then returns
 *   exitcancel cancel    pthread_cancel while the program runs: the worker
 *                        leaves pthread_cond_wait with the mutex held, its
 *                        clean-up handler runs, and pthread_join gives
 *                        PTHREAD_CANCELED
 * Copyright (c) 2026 AmiCradle Team. zlib licence, as aros-stuff's pthreads. */
#include <exec/types.h>
#include <exec/nodes.h>
#include <pthread.h>
#include <semaphore.h>
#include <stdio.h>
#include <string.h>
#include <proto/exec.h>
#include <proto/dos.h>

static pthread_mutex_t m = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t c = PTHREAD_COND_INITIALIZER;
static sem_t s;
static pthread_t b;
static volatile int held_in_cleanup = -1;

static void say(const char *t) { Write(Output(), (APTR)t, strlen(t)); }

static void cleanup(void *arg)
{
    (void)arg;
    say("exitcancel: clean-up handler ran\n");
    held_in_cleanup = pthread_mutex_unlock(&m) == 0;   /* 0: the canceled wait held it */
}

static void *condwait(void *arg)
{
    if (arg) pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, NULL);
    pthread_mutex_lock(&m);
    pthread_cleanup_push(cleanup, NULL);
    for (;;) pthread_cond_wait(&c, &m);
    pthread_cleanup_pop(1);
    return NULL;
}

static void *semwait(void *arg) { (void)arg; for (;;) sem_wait(&s); return NULL; }
static void *joiner(void *arg) { (void)arg; pthread_join(b, NULL); return NULL; }

int main(int argc, char **argv)
{
    const char *k = argc > 1 ? argv[1] : "cond";
    pthread_t a;
    void *ret = NULL;

    if (!strcmp(k, "cond") || !strcmp(k, "ctrlc")) {
        pthread_create(&a, NULL, condwait, NULL);
    } else if (!strcmp(k, "sem")) {
        sem_init(&s, 0, 0);
        pthread_create(&a, NULL, semwait, NULL);
    } else if (!strcmp(k, "join")) {
        pthread_create(&b, NULL, condwait, NULL);
        pthread_create(&a, NULL, joiner, NULL);
    } else if (!strcmp(k, "nocancel")) {
        pthread_create(&a, NULL, condwait, (void *)1);
    } else if (!strcmp(k, "cancel")) {
        pthread_create(&a, NULL, condwait, NULL);
        Delay(25);
        pthread_cancel(a);
        pthread_join(a, &ret);
        printf("exitcancel cancel: join gave %s, mutex %s in the handler: %s\n",
               ret == PTHREAD_CANCELED ? "PTHREAD_CANCELED" : "something else",
               held_in_cleanup == 1 ? "held" : "not held",
               ret == PTHREAD_CANCELED && held_in_cleanup == 1 ? "PASS" : "FAIL");
        return ret == PTHREAD_CANCELED && held_in_cleanup == 1 ? 0 : 10;
    } else {
        printf("exitcancel: cond, sem, join, nocancel, ctrlc or cancel\n");
        return 20;
    }
    Delay(25);   /* the workers are waiting by now */
    if (!strcmp(k, "ctrlc")) {
        printf("exitcancel ctrlc: waiting for Ctrl-C\n"); fflush(stdout);
        Wait(SIGBREAKF_CTRL_C);
    }
    printf("exitcancel %s: main returns; %s\n", k, !strcmp(k, "nocancel")
           ? "expect one removal line, back at the Shell after about 2 s"
           : "expect no clean-up line, back at the Shell at once");
    fflush(stdout);
    return 0;
}
