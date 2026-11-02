/* foreigntls: C __thread in a process pthreads did not make
 * (patches/aros-stuff/0008). Copyright (c) 2026 AmiCradle Team. zlib licence.
 *
 * GCC's emutls finds a thread's __thread block with pthread_getspecific().
 * Three processes made with CreateNewProc and NP_Entry (as SDL2.module makes
 * SDL threads) each take the address of a __thread array, write to it and
 * read it back. With 0008 such a process is pthreads' main thread (id 0), so
 * each child must get the main thread's block. Before it, pthread_self() gave
 * an id with no record and pthread_getspecific() read NULL->tlsvalues[key],
 * a longword of the CPU's vector table: the "block" came out of low memory
 * or the ROM (0x000C6000 on GFOpenKick full21-t5).
 *
 *   m68k-amigaos-gcc -m68040 -O2 -noixemul -o foreigntls foreigntls.c -lpthread
 *
 * Prints a line a child, then "foreigntls OK" (rc 0) or "foreigntls FAILED"
 * (rc 10).
 */
#include <exec/types.h>
#include <exec/memory.h>
#include <dos/dostags.h>
#include <proto/exec.h>
#include <proto/dos.h>
#include <stdio.h>

static __thread int tv[136];            /* about the size of Allegro's thread state */
static struct Task *parent;
static ULONG sig;
static volatile ULONG addr, kind, ok;

static void child(void)
{
    int *a = tv;                        /* emutls: pthread_getspecific() for this task */
    addr = (ULONG)a;
    kind = TypeOfMem(a);
    a[0] = 0x5445;
    a[135] = 0x354c;
    ok = a[0] == 0x5445 && a[135] == 0x354c;
    Forbid();                           /* gone before main looks again */
    Signal(parent, sig);
}

int main(void)
{
    BYTE bit = AllocSignal(-1);
    int fails = 0, i;
    if (bit < 0) { printf("foreigntls: no signal free\n"); return 20; }
    tv[0] = 1;                          /* the main thread's block first */
    printf("main: __thread block at %08lx\n", (unsigned long)tv);
    parent = FindTask(NULL);
    sig = 1UL << bit;
    for (i = 0; i < 3; i++) {
        struct Process *p;
        addr = kind = ok = 0;
        SetSignal(0, sig);
        Forbid();
        p = CreateNewProcTags(NP_Entry, (ULONG)child, NP_Name, (ULONG)"foreigntls child", NP_StackSize, 32768, TAG_DONE);
        Permit();
        if (!p) { printf("foreigntls: CreateNewProc failed\n"); return 20; }
        Wait(sig);
        Delay(2);
        printf("child %d: __thread block at %08lx (%s), %s, %s\n", i, (unsigned long)addr,
               addr == (ULONG)tv ? "the main thread's" : "NOT the main thread's",
               kind ? "RAM" : "NOT MEMORY", ok ? "kept what it wrote" : "LOST what it wrote");
        if (!kind || !ok || addr != (ULONG)tv) fails++;
    }
    FreeSignal(bit);
    printf(fails ? "foreigntls FAILED\n" : "foreigntls OK\n");
    return fails ? 10 : 0;
}
