# libpthread reproducer

`t3race.cpp`: one consumer and four producers on a `condition_variable`; each producer uses a `thread_local` and `std::call_once`, then a `std::async`. Creating the fifth thread grows libpthread's thread table while three threads run.

Build it with the C++ flags the stove uses, run it on an Amiga ten times with `Run`, and count the runs that print `t3 OK`:

```bash
m68k-amigaos-g++ -m68040 -m68881 -O2 -fomit-frame-pointer -std=gnu++23 -o t3race t3race.cpp -lpthread -latomic -lstdc++
```

This needs a real AmigaOS: qemu-m68k's user mode has no exec tasks.

`t3w_warm.cpp`: the same test after a warm-up that has five threads alive at once. With the stove's unpatched library it hung once on Instance-32 (11 Oct 2026), and the agent's next command, which needed DH1:, never ran. The warm-up is the case `patches/aros-stuff/0001` fixes: the stock library kept its threads in one array that it grew with `realloc` (1, 4, 10 slots, slot 0 being the main task), and the 4th warm-up thread is created while threads 1-3 still run. When those end, each writes `finished` into the freed array and `Signal`s the `parent` it reads from there, so a stale task pointer can be signalled and the whole machine, the agent with it, stops. With 0001 each ThreadInfo is allocated once and never moves. Run it 20 times with the patched library: every run should print `t3w OK`.

`joinsig.c` (`patches/aros-stuff/0006`): `pthread_join` and the program's own Ctrl-F. Each join waits for a thread of about half a second: with no Ctrl-F, with one already pending when the join starts, and with one that the thread sends the joining task a fifth of a second in, while it waits. Then a thread that has ended before its join, and 50 joins in a row. Then the first four again with every free signal taken, which is the Ctrl-F fallback. Each join must return 0 only once the thread has ended, with its value; the program's Ctrl-F must still be pending afterwards whenever it had one; a thread that ends must send nobody Ctrl-F; and the 50 joins must give back every signal they took.

```bash
m68k-amigaos-gcc -m68040 -specs=../../build/m68k-soft-m68040.specs -O2 -Wall -o joinsig joinsig.c -lpthread
```

It prints PASS or FAIL for each case, then `joinsig OK` (rc 0) or `joinsig FAILED` (rc 20). With the stove's library (0001-0004) the six Ctrl-F cases fail; with 0006 every case passes.

`exitpark.c` (`patches/aros-stuff/0007`): exit and a crashed thread, and `pthread_cond_timedwait`'s timeout.
- `exitpark crash`: a thread writes to 0xBBADBEEF and traps, as WTFCrash does. Exec's trap handling parks its task in `Wait(0)`. `main` then returns, and the program must return to the Shell; before 0007 it waited at exit for ever.
- `exitpark join`: a thread that ends normally is still joined at exit.
- `exitpark timed`: a timed wait for an absolute time 2 s in the past must give `ETIMEDOUT` at once (before 0007 it never returned), and one 200 ms ahead must give `ETIMEDOUT` after about 200 ms. It prints `EXITPARK timed PASS` (rc 0) or `FAIL` (rc 10).

```bash
m68k-amigaos-gcc -O2 -m68040 -noixemul -o exitpark exitpark.c -lpthread
```

Run it on an Amiga whose trap handling parks a crashed task (GFOpenKick does; Kickstart's own shows a requester first), with `Run`, and check that the Shell gets `RC` back.

`foreigntls.c` (`patches/aros-stuff/0008` and `0009`): C `__thread` and a pthread key in processes made with `CreateNewProc` and `NP_Entry`, as SDL2.module makes SDL threads. It prints PASS or FAIL for each check, then `foreigntls OK` (rc 0) or `foreigntls FAILED` (rc 10):
- `own`: three children alive at once each get an id of their own (not 0), a `__thread` block of their own (not the main thread's, in RAM, zeroed at first) and their own `pthread_setspecific` value, and none sees what another wrote;
- `foreign`: a child's id is not joinable (`EINVAL`) or cancellable (`ESRCH`);
- `dtors`: once the three have ended, a `pthread_key_create` (which sweeps) has run the key's destructor once for each child's value, and not before;
- `reclaim`: ten more rounds of three reuse the same three records (ids 1-3, 33 children) and every destructor runs (33 of 33);
- `thread`: a `pthread_create`'d thread still gets its own id and block;
- `main`: the main thread is id 0 throughout, with its own block and key value unchanged.

`foreigntls full` also fills the table: 2018 parked children each get a record (ids 1-2018); the next is refused one and is the main thread (id 0, the main thread's block), and stays so after the others have ended and their records are reclaimed; children started then get records of their own again. It needs about 20 MB.

With the stove's library (0001-0007) each child's block came out of low memory (0x000C6000 on GFOpenKick full21-t5); with 0008 alone every child shares the main thread's block (`own` fails); with 0009 every check passes.

```bash
m68k-amigaos-gcc -m68040 -O2 -noixemul -o foreigntls foreigntls.c -lpthread
```
