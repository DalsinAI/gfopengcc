# libnix: setlocale() from several threads (t18)

**Patch:** `patches/libnix/0006-setlocale-safe-from-several-threads-at-once-libstdc-.patch`
**Reproducer:** `tests/libnix/setlocale_threads.c` (on the Amiga), and amicradle-stoves' t18

## Symptom

amicradle-stoves' t18 has 8 threads format numbers with `ostringstream` and read them back with `istringstream`. It never finished on AmigaOS. It printed each thread's first line, then hung. Sometimes it took more with it: on 11 October the Shell running it ended, and on 12 October the agent's next command never ran and no new Shell would open.

## Cause

The bug is libnix's `setlocale()`. Nothing in it is safe when two threads call it at once, and libstdc++ calls it all the time.

The stove's libstdc++ uses the generic locale model. For every floating-point number a stream writes, `__convert_from_v` does this:
1. it asks `setlocale(LC_NUMERIC, NULL)` for the current name;
2. it copies the name, unless it is `"C"`;
3. it sets `"C"`;
4. it calls `vsnprintf`;
5. it sets the saved name back.

`__convert_to_v` does the same with `LC_ALL` around `strtod` for every number a stream reads. libnix starts every program in the user's locale (`setlocale(LC_ALL, "")` at startup). The name is never `"C"`, so every number takes all five steps.

libnix's `setlocale()` kept its state in globals, with no lock:
- **The returned name.** The name is a static `string`. Every call, a query included, starts with `free(string)`. Two threads in `setlocale()` free the same block twice. One thread's call also frees the name another thread has just been given and is still copying.
- **The locales.** Setting a category closes the locale in use (`CloseLocale(__localevec[i])`), then stores the new one. Two threads close the same locale twice.
- **The pointers into a locale.** `__decimalpoint`, `__lconv` and `strftime()` point into the current locale, which another thread may just have closed.

So libnix's heap and locale.library's counts were corrupted. That hangs the program's threads, or worse.

Three more faults made each conversion slow and wrong, even with one thread:
- **The name doesn't open.** Instance-32's default locale is called `united_states.country`, and `OpenLocale("united_states.country")` fails. Setting the saved name back returned NULL, so after the first number read every category was `"C"`.
- **Only the first part was read.** A name with one part per category, as `setlocale(LC_ALL, NULL)` returns it, set only the first category from its part. Every later category got `""`, the default locale. So from then on each number closed four locales and opened them again.
- **`"C"` kept the old decimal point.** It left `__decimalpoint`, which `printf()` and `scanf()` use, at the old locale's point. In a locale with a decimal comma, an `ostringstream` would print `0,25`.

A probe on Instance-32 shows this with the stove's libnix. It saves the name, sets `"C"` and sets the name back, once, then 200 times (newlines shown as `|`):

```
LC_ALL at start: united_states.country|united_states.country|...   (5 categories)
restore returns: (NULL)
LC_ALL after restore: C|C|C|C|C
200 save/C/restore: 7 ms
LC_ALL at end: C|united_states.country|united_states.country|...
```

With libnix 0006 the name is set back (`restore returns: united_states.country|...`), the locale is the same at the end as at the start, and 200 rounds take 1 ms.

## Fix

libnix 0006 rewrites the inside of `setlocale()` without changing what it returns:
- **A lock.** One `SignalSemaphore` makes calls one at a time. It is set up on first use under `Forbid()`.
- **Names stay valid.** A name `setlocale()` returns stays valid until the program ends. The same name is the same string, so the list stays as short as the number of different names.
- **Locales stay open.** A locale `setlocale()` opens stays open until `__exitlocale()` closes it at exit. A name `setlocale()` has opened or returned before finds that locale again; that includes the default locale's `loc_LocaleName`, which `OpenLocale()` can't open by name. Switching to `"C"` and back neither closes nor reloads a locale. `__decimalpoint`, `__lconv` and `strftime()` never point into a closed one.
- **Each category gets its part.** A name with one part per category sets each category to its own part.
- **`"C"` resets the decimal point.** `"C"` sets `__decimalpoint` back to `"."`.
- **A query changes nothing.** It no longer resets `__lconv`.

## What is still the generic model's

The locale is still one per program, as C has it. libstdc++'s generic model switches it to `"C"` around each conversion, and nothing makes a pair of switches atomic:
- one thread can save `"C"` while another thread is mid-conversion, and set `"C"` back at the end;
- a thread can run its conversion in the user's locale while another thread puts it back.

Both are harmless where the locale's decimal point is `.`, as on Instance-32. With a decimal comma, several threads converting at once may give a `,` now and then. The program may also end up in `"C"`. One thread alone is always right.

## Results

Lab `cxx`, a copy of Instance-32 (AmigaOS 3.2.3), 12 October 2026, `-m68020 -m68881 -O2`:

| Program | Stove's libnix | libnix 0006 |
| --- | --- | --- |
| t18 (8 threads, 300 numbers each; then 4 threads writing to `std::cout` unlocked) | hung 3 of 3 runs, after the first lines | `t18 OK` 272 of 272 runs |
| t18 with each thread's exceptions caught and printed | hung 1 of 1, no exception printed | not needed |
| t18 with 3000 numbers per thread and 400 unlocked lines per thread | not run | `t18 OK` 3 of 3, all 1,600 lines whole |
| `tests/libnix/setlocale_threads.c` (8 threads, 3000 rounds) | hung, 1 of 1 | `setlocale_threads OK` 2 of 2 |
| the same, 300 rounds | `OK` 1 of 1: the threads hardly overlap | `OK` 1 of 1 |
| t1-t7, t10, t11, t14-t17, t3 (the rest of the stove suite) | pass | pass |

How the hangs looked:
- In two of the four hung t18 runs the whole system stopped answering. The agent's next command never ran, and no Shell would open, though the screen and clock were alive and the CPU idle.
- In one, t18's process was gone and the script that started it never went on.
- The fourth was not examined.
- `setlocale_threads` spun instead.

The rows for libnix 0006 are from a copy of the stove whose `libnix20.a` and `libnix13.a` (five multilibs each) had `setlocale.o` replaced:
- The objects were built the way the stove builds libnix. The unpatched source, built the same way, gives the stove's `setlocale.o`, contents compared.
- 269 of the t18 runs were back to back, each a new process.

**Full rebuild.** `scripts/build.sh` with this patch and the `-fuse-cxa-atexit` PR's ran without network at the stove's paths. It took 35 minutes 45 seconds with 8 jobs on x86 cores. Its `setlocale.o` has the same code as the copy's. Built with it:
- t18 printed `t18 OK` 21 of 21 runs;
- t18 with 3000 numbers, `setlocale_threads` and the whole stove suite passed.

`build.sh` in `tests/libnix` now builds `setlocale-old` and `setlocale-new` too.
