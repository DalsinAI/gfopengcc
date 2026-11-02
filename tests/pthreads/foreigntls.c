/* foreigntls: C __thread and pthread keys in processes pthreads did not make
 * (patches/aros-stuff/0008 and 0009). Copyright (c) 2026 AmiCradle Team.
 * zlib licence.
 *
 * GCC's emutls finds a thread's __thread block with pthread_getspecific().
 * The children are processes made with CreateNewProc and NP_Entry, as
 * SDL2.module makes SDL threads. With 0009 each such "foreign" task gets a
 * pthreads record of its own the first time it calls pthreads, and the record
 * is reclaimed (its key destructors run) once the task has ended. Before 0008,
 * pthread_self() gave such a task an id with no record and
 * pthread_getspecific() read NULL->tlsvalues[key], a longword of the CPU's
 * vector table (the "block" was 0x000C6000 on GFOpenKick full21-t5); with
 * 0008 alone every such task shared the main thread's block.
 *
 *   m68k-amigaos-gcc -m68040 -O2 -noixemul -o foreigntls foreigntls.c -lpthread
 *
 * "foreigntls" checks, each printing PASS or FAIL:
 *   own      three children alive at once: each its own id (not 0), its own
 *            __thread block (not the main thread's, in RAM, zeroed at first),
 *            its own pthread_setspecific value, and nothing written by one is
 *            seen by another;
 *   foreign  a child's id is not joinable (EINVAL) or cancellable (ESRCH);
 *   dtors    after the three have ended, a pthread_key_create (which sweeps)
 *            has run the key's destructor once for each child's value;
 *   reclaim  ten more rounds of three children reuse the same three records
 *            (ids 1-3), and every destructor has run: 33 of 33;
 *   thread   a pthread_create'd thread still gets its own id and block;
 *   main     the main thread is id 0 throughout, with its own block and key
 *            value unchanged.
 * "foreigntls full" also fills the table: PTHREAD_THREADS_MAX - 1 (2018)
 * children park with a record each; the next is refused one and is the main
 * thread (id 0, the main thread's block) and stays so after the others have
 * ended and their records are reclaimed; a child started then gets a record
 * of its own again. It needs about 14 MB.
 * The program prints "foreigntls OK" (rc 0) or "foreigntls FAILED" (rc 10).
 */
#include <exec/types.h>
#include <exec/memory.h>
#include <exec/execbase.h>
#include <dos/dostags.h>
#include <proto/exec.h>
#include <proto/dos.h>
#include <pthread.h>
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#define NCHILD 3
#define ROUNDS 10                       /* after the first */
#define TVN 136                         /* about the size of Allegro's thread state */
#define MAXPARK 2100
#define STACK 8192

static __thread int tv[TVN];
static pthread_key_t key;
static struct Task *parent;
static ULONG readysig, donesig;
static volatile int cur, nready, ndone;
static int cookie[NCHILD * (ROUNDS + 2)];
static int maincookie = 0x4d41;
static volatile int dtorcount, dtorbad;

static struct rec {
    pthread_t id;
    ULONG addr, kind, fresh, ok;
    int setrc;
} r[NCHILD];

static void dtor(void *v)
{
    int *c = v;
    if (c >= cookie && c < cookie + sizeof(cookie) / sizeof(cookie[0]) && *c == (int)(c - cookie) + 0x100) {
        *c = -1;                        /* a second call for the same value counts as bad */
        dtorcount++;
    } else
        dtorbad++;
}

static void child(void)
{
    int me = cur, k, ok;
    struct rec *p = &r[me % NCHILD];
    int *a;

    p->id = pthread_self();
    a = tv;                             /* emutls: pthread_getspecific() for this task */
    p->addr = (ULONG)a;
    p->kind = TypeOfMem(a);
    p->fresh = 1;
    for (k = 0; k < TVN; k++)
        if (a[k]) p->fresh = 0;
    for (k = 0; k < TVN; k++)
        a[k] = me * 1000 + k;
    p->setrc = pthread_setspecific(key, &cookie[me]);
    Forbid();
    nready++;
    Signal(parent, readysig);
    Permit();
    Wait(SIGBREAKF_CTRL_F);             /* the others have written theirs by now */
    a = tv;
    ok = (ULONG)a == p->addr && pthread_self() == p->id && pthread_getspecific(key) == &cookie[me];
    for (k = 0; k < TVN; k++)
        if (a[k] != me * 1000 + k) ok = 0;
    p->ok = ok;
    Forbid();                           /* gone before main looks again */
    ndone++;
    Signal(parent, donesig);
}

static struct Process *start(void (*entry)(void), const char *name)
{
    struct Process *p;
    Forbid();
    p = CreateNewProcTags(NP_Entry, (ULONG)entry, NP_Name, (ULONG)name, NP_StackSize, STACK, TAG_DONE);
    Permit();
    return p;
}

/* Wait (up to 5 s) until no task of that name is left: a child signals as it
   ends, but its process may take a moment more to go (dos's exit code). */
static int gone(const char *name)
{
    int t;
    for (t = 0; t < 250; t++) {
        struct Task *left;
        Forbid();
        left = FindTask((STRPTR)name);
        Permit();
        if (!left) return 1;
        Delay(1);
    }
    printf("  a \"%s\" task is still there after 5 s\n", name);
    return 0;
}

static void waitfor(volatile int *count, int n, ULONG sig)
{
    while (*count < n)
        Wait(sig);
}

static int fails;
static void check(const char *what, int ok, const char *fmt, ...)
{
    va_list ap;
    printf("%s %s: ", ok ? "PASS" : "FAIL", what);
    va_start(ap, fmt);
    vprintf(fmt, ap);
    va_end(ap);
    printf("\n");
    if (!ok) fails++;
}

static ULONG mainaddr;
static int mainok(void)
{
    return pthread_self() == 0 && (ULONG)tv == mainaddr && tv[0] == 0x5445 && tv[TVN - 1] == 0x354c
        && pthread_getspecific(key) == &maincookie;
}

static void sweep(void)
{
    pthread_key_t k2;                   /* pthread_key_create reclaims ended tasks' records */
    if (pthread_key_create(&k2, NULL) == 0)
        pthread_key_delete(k2);
}

/* One round: NCHILD children alive at once; ids returned in ids[]. */
static int round_(int rnd, pthread_t *ids, int print)
{
    struct Process *procs[NCHILD];
    int i, j, ok = 1;

    nready = ndone = 0;
    memset(r, 0, sizeof(r));
    for (i = 0; i < NCHILD; i++) {
        cur = rnd * NCHILD + i;
        cookie[cur] = cur + 0x100;
        procs[i] = start(child, "foreigntls child");
        if (!procs[i]) { printf("foreigntls: CreateNewProc failed\n"); return -1; }
        waitfor(&nready, i + 1, readysig);
    }
    for (i = 0; i < NCHILD; i++) {
        struct rec *p = &r[i];
        ids[i] = p->id;
        if (print)
            printf("  child %d: id %lu, __thread block at %08lx (%s, %s), %s, setspecific %d\n", i,
                   (unsigned long)p->id, (unsigned long)p->addr,
                   p->addr == mainaddr ? "the main thread's" : "its own",
                   p->kind ? "RAM" : "NOT MEMORY", p->fresh ? "zeroed" : "NOT ZEROED", p->setrc);
        if (!p->id || p->addr == mainaddr || !p->kind || !p->fresh || p->setrc) ok = 0;
        for (j = 0; j < i; j++)
            if (ids[j] == p->id || r[j].addr == p->addr) ok = 0;
    }
    if (rnd == 0) {
        int jr = pthread_join(ids[0], NULL), cr = pthread_cancel(ids[0]);
        check("foreign", jr == EINVAL && cr == ESRCH, "pthread_join on a child's id %d (EINVAL %d), pthread_cancel %d (ESRCH %d)",
              jr, EINVAL, cr, ESRCH);
    }
    if (!mainok()) ok = 0;
    for (i = 0; i < NCHILD; i++)
        Signal(&procs[i]->pr_Task, SIGBREAKF_CTRL_F);
    waitfor(&ndone, NCHILD, donesig);
    gone("foreigntls child");
    for (i = 0; i < NCHILD; i++)
        if (!r[i].ok) {
            ok = 0;
            if (print) printf("  child %d LOST what it wrote, or its key value or id changed\n", i);
        }
    return ok;
}

static void *threadfn(void *arg)
{
    struct rec *p = arg;
    p->id = pthread_self();
    p->addr = (ULONG)tv;
    p->fresh = tv[0] == 0;
    tv[0] = 77;
    return NULL;
}

/* "full": fill the table */
static volatile pthread_t pid[MAXPARK + 1];
static volatile ULONG paddr[MAXPARK + 1], pok[MAXPARK + 1];
static struct Process *pproc[MAXPARK + 1];

static void parker(void)
{
    int me = cur;
    pthread_t id = pthread_self();
    ULONG a = (ULONG)tv;
    pid[me] = id;
    paddr[me] = a;
    Forbid();
    nready++;
    Signal(parent, readysig);
    Permit();
    Wait(SIGBREAKF_CTRL_C);
    pok[me] = pthread_self() == id && (ULONG)tv == a;   /* the same answer later */
    Forbid();
    ndone++;
    Signal(parent, donesig);
}

/* Tasks of that name on exec's lists. */
static int CountTasks(const char *name)
{
    struct Node *nd;
    int k = 0;
    Forbid();
    for (nd = SysBase->TaskWait.lh_Head; nd->ln_Succ; nd = nd->ln_Succ)
        if (nd->ln_Name && !strcmp(nd->ln_Name, name)) k++;
    for (nd = SysBase->TaskReady.lh_Head; nd->ln_Succ; nd = nd->ln_Succ)
        if (nd->ln_Name && !strcmp(nd->ln_Name, name)) k++;
    Permit();
    return k;
}

static void full(void)
{
    struct DateStamp t0, t1;
    int n, i, distinct = 1, refused = -1;
    ULONG before = AvailMem(MEMF_ANY);

    DateStamp(&t0);
    nready = ndone = 0;
    for (n = 0; n < MAXPARK; n++) {
        cur = n;
        pproc[n] = start(parker, "foreigntls parker");
        if (!pproc[n]) { printf("  CreateNewProc failed after %d parkers\n", n); break; }
        waitfor(&nready, n + 1, readysig);
        if (pid[n] == 0) { refused = n; n++; break; }
    }
    DateStamp(&t1);
    for (i = 0; i < n && i != refused; i++)
        if (pid[i] != (pthread_t)(i + 1)) distinct = 0;
    printf("  %d parkers in %ld s, %lu KB used\n", n,
           (long)((t1.ds_Days - t0.ds_Days) * 86400 + (t1.ds_Minute - t0.ds_Minute) * 60 + (t1.ds_Tick - t0.ds_Tick) / 50),
           (unsigned long)((before - AvailMem(MEMF_ANY)) >> 10));
    check("full", refused == PTHREAD_THREADS_MAX - 1 && distinct && paddr[refused] == mainaddr,
          "parkers 0-%d got ids 1-%d (%s); parker %d was refused a record: id %lu, block %08lx (%s)",
          refused - 1, refused, distinct ? "each its own" : "NOT each its own", refused,
          refused >= 0 ? (unsigned long)pid[refused] : 99999UL, refused >= 0 ? (unsigned long)paddr[refused] : 0UL,
          refused >= 0 && paddr[refused] == mainaddr ? "the main thread's" : "NOT the main thread's");
    if (refused < 0) {
        /* release them all and give up */
        for (i = 0; i < n; i++) Signal(&pproc[i]->pr_Task, SIGBREAKF_CTRL_C);
        waitfor(&ndone, n, donesig);
        return;
    }
    /* the others end and their records are reclaimed; then the refused one looks again */
    for (i = 0; i < refused; i++) Signal(&pproc[i]->pr_Task, SIGBREAKF_CTRL_C);
    waitfor(&ndone, refused, donesig);
    {                                   /* until only the refused one is left */
        int t;
        for (t = 0; t < 250 && CountTasks("foreigntls parker") > 1; t++) Delay(1);
    }
    sweep();
    Signal(&pproc[refused]->pr_Task, SIGBREAKF_CTRL_C);
    waitfor(&ndone, refused + 1, donesig);
    gone("foreigntls parker");
    {
        int allok = 1;
        for (i = 0; i <= refused; i++) if (!pok[i]) allok = 0;
        check("full-stays", allok, "after the table emptied, the refused child is still the main thread, and every parker kept its id and block");
    }
    {
        pthread_t ids[NCHILD];
        int ok = round_(ROUNDS + 1, ids, 1);
        check("full-again", ok == 1, "three children started after that get records of their own (ids %lu %lu %lu)",
              (unsigned long)ids[0], (unsigned long)ids[1], (unsigned long)ids[2]);
    }
}

int main(int argc, char **argv)
{
    BYTE b1 = AllocSignal(-1), b2 = AllocSignal(-1);
    pthread_t ids[NCHILD];
    int rnd, i, ok, maxid = 0, allok = 1, want;

    if (b1 < 0 || b2 < 0) { printf("foreigntls: no signal free\n"); return 20; }
    parent = FindTask(NULL);
    readysig = 1UL << b1;
    donesig = 1UL << b2;
    if (pthread_key_create(&key, dtor)) { printf("foreigntls: pthread_key_create failed\n"); return 20; }
    pthread_setspecific(key, &maincookie);
    tv[0] = 0x5445;                     /* the main thread's block first */
    tv[TVN - 1] = 0x354c;
    mainaddr = (ULONG)tv;
    printf("main: id %lu, __thread block at %08lx\n", (unsigned long)pthread_self(), (unsigned long)mainaddr);

    ok = round_(0, ids, 1);
    if (ok < 0) return 20;
    check("own", ok, "three children alive at once, ids %lu %lu %lu, each its own block and key value", (unsigned long)ids[0],
          (unsigned long)ids[1], (unsigned long)ids[2]);
    i = dtorcount;
    sweep();
    check("dtors", i == 0 && dtorcount == NCHILD && !dtorbad, "%d before the sweep, %d of %d after it (%d bad)", i, dtorcount,
          NCHILD, dtorbad);

    for (i = 0; i < NCHILD; i++) if ((int)ids[i] > maxid) maxid = ids[i];
    for (rnd = 1; rnd <= ROUNDS; rnd++) {
        ok = round_(rnd, ids, 0);
        if (ok < 0) return 20;
        if (!ok) allok = 0;
        for (i = 0; i < NCHILD; i++) if ((int)ids[i] > maxid) maxid = ids[i];
        if (ids[0] > NCHILD || ids[1] > NCHILD || ids[2] > NCHILD)
            printf("  round %d: ids %lu %lu %lu\n", rnd, (unsigned long)ids[0], (unsigned long)ids[1], (unsigned long)ids[2]);
    }
    sweep();
    want = NCHILD * (ROUNDS + 1);
    check("reclaim", allok && maxid == NCHILD && dtorcount == want && !dtorbad,
          "%d children in %d rounds used ids 1-%d (%d records), every round right: %s; destructors %d of %d (%d bad)",
          want, ROUNDS + 1, maxid, maxid, allok ? "yes" : "NO", dtorcount, want, dtorbad);

    {
        pthread_t t;
        struct rec tr;
        memset(&tr, 0, sizeof(tr));
        ok = pthread_create(&t, NULL, threadfn, &tr) == 0 && pthread_join(t, NULL) == 0;
        check("thread", ok && tr.id != 0 && tr.addr != mainaddr && tr.fresh, "pthread_create'd thread: id %lu, block %08lx, %s",
              (unsigned long)tr.id, (unsigned long)tr.addr, tr.fresh ? "zeroed" : "NOT ZEROED");
    }

    if (argc > 1 && !strcmp(argv[1], "full"))
        full();

    check("main", mainok(), "main thread id %lu, block %08lx, its values and key value kept", (unsigned long)pthread_self(),
          (unsigned long)tv);
    FreeSignal(b1);
    FreeSignal(b2);
    printf(fails ? "foreigntls FAILED\n" : "foreigntls OK\n");
    return fails ? 10 : 0;
}
