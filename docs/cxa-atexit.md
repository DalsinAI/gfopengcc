# C++: thread_local destructors run by default (-fuse-cxa-atexit)

**Patches:** `patches/gcc/0010-amigaos-fuse-cxa-atexit-by-default-thread_local-dest.patch`, `patches/libnix/0005-__cxa_atexit-and-__dso_handle-C-destructors-register.patch`
**Test:** `tests/cxx/dtors.cpp` (on the Amiga), and amicradle-stoves' t12, t13 and t19

## Symptom

A plain `m68k-amigaos-g++` build never ran the destructor of a `thread_local` object declared at namespace scope or as a static data member. Not when its thread ended, and not at exit for the main program's own object. amicradle-stoves' qualification tests t12, t13 and t19 count constructions and destructions and failed: t13 reported "100 constructed, 0 destroyed", t19 "0 of 1150". Built with `-fuse-cxa-atexit` and a `__dso_handle` of the test's own (t12c, t13c, t19c) they passed.

A `thread_local` inside a function was not affected.

## Cause

The stove's GCC was configured with the default `-fno-use-cxa-atexit`. In that mode GCC destroys static objects from a `__DTOR_LIST__` function, which libnix runs at exit. Thread-local storage has no such pass. `handle_tls_init()` (`gcc/cp/decl2.cc`) registers a `thread_local`'s destructor only when `flag_use_cxa_atexit` is set. Otherwise the destructor is never registered.

`-fuse-cxa-atexit` alone was not enough. Code built with it calls `__cxa_atexit(dtor, object, &__dso_handle)` for every static object with a destructor. libnix had neither `__cxa_atexit` nor `__dso_handle`, so such a program didn't link (t12c and friends brought their own `__dso_handle`, and had no static object with a destructor).

## Fix

- **gcc 0010:** `default_use_cxa_atexit=yes` for `m68k*-*-amigaos*` in `gcc/config.gcc`, the way GCC sets it for every target whose C library has `__cxa_atexit`. `cc1plus` then starts with `-fuse-cxa-atexit`. A `thread_local`'s destructor is registered with libstdc++'s `__cxa_thread_atexit()` when the object is first used, and runs when its thread ends, or at exit for the main program. `-fno-use-cxa-atexit` turns the old way back on.
- **libnix 0005:**
  - `__cxa_atexit()` joins `atexit()` on one list, so `exit()` calls both kinds in the reverse order of registration. A function registered while the list is being run (a static object first used in a destructor) is called too. A new entry is added under `Forbid()`, since threads may register at the same time.
  - `__dso_handle` is its own archive member. A program that defines `__dso_handle` itself, such as t12c, still links.

### What else changes

- **Static objects** are destroyed in the reverse order of their construction, interleaved with `atexit()` functions, as C++ requires. Before, every `atexit()` function ran first, then `__DTOR_LIST__`.
- **Both patches go together.** Objects built with the new default need libnix's `__cxa_atexit` and `__dso_handle`. A stove built from these patches rebuilds libstdc++ with the new default too, so its own static objects are registered the same way.
- **Only libnix programs are covered** (`-mcrt=nix20`, the default, and `-mcrt=nix13`). A C++ program built with `-mcrt=clib2`, `ixemul`, `newlib` or `library` and a static object with a destructor needs `-fno-use-cxa-atexit`, or a `__cxa_atexit` and `__dso_handle` of its own.

### The other way, not taken

GCC has a target hook, `TARGET_CXX_USE_ATEXIT_FOR_CXA_ATEXIT`, that the MinGW targets use. With it, `-fuse-cxa-atexit` registers static destructors with plain `atexit()` and passes no `__dso_handle`, so nothing new is needed from the C library. It was not taken, for two reasons:
- `__cxa_atexit` is the standard C++ ABI, which code and libraries from other toolchains expect.
- The tests that bring their own `__dso_handle` keep working either way.

The hook remains an option if a C library other than libnix has to be supported.

## Results

Lab `cxx`, a copy of Instance-32 (AmigaOS 3.2.3, Kickstart 47.115), 12 October 2026. The stove tests are built by amicradle-stoves' `os32-gcc16/tests/build-tests.sh` and run by its `run-tests`; t8 and t9 were not built (no gfopentls checkout). `dtors.cpp` is built as `tests/cxx/README.md` says:

| Test | Live stove | Stove copy with the patches | Full rebuild |
| --- | --- | --- | --- |
| t12: `thread_local` in 80 threads, destroyed by `join()` | FAIL: "ctors 80 dtors 0" | PASS: "ctors 80 dtors 80" | PASS: "ctors 80 dtors 80" |
| t13: 50, then 100 threads at once | FAIL: "100 constructed, 0 destroyed" | PASS | PASS |
| t19: 1,150 short threads | FAIL: "0 of 1150" | PASS: "1150 of 1150" | PASS: "1150 of 1150" |
| t12c, t13c, t19c: `-fuse-cxa-atexit` and the test's own `__dso_handle` | PASS | PASS (it still links) | PASS |
| `tests/cxx/dtors.cpp` | "destroyed when its thread ended: no", "dtors FAILED: g" | "yes", "dtors OK" | "yes", "dtors OK" |
| t1-t7, t10, t11, t14-t17, t3a-t3f, t3 | PASS | PASS | PASS |
| t18: iostreams in 8 threads | hangs | PASS | PASS |
| t7 for the 020 and the 060: same as a PC | yes | yes | yes |

"Stove copy with the patches" is a copy of the live stove with three changes:
- `cc1plus` from the full rebuild (gcc 0010). Its configuration differs from the 9 October build's only by `DEFAULT_USE_CXA_ATEXIT` (`auto-host.h` compared).
- The new `atexit.o` and `__dso_handle.o` in `libnix.a`.
- libnix 0006's `setlocale.o` (#11), so that t18 runs too.

Its libstdc++ is the live stove's.

"Full rebuild" is `scripts/build.sh` with every patch on `main` plus these and libnix 0006 (#11), run without network at the stove's paths (`/opt/src`, `/opt/amiga`) as the 9 October release was. It took 35 minutes 45 seconds with 8 jobs on the Team's machine (x86 cores), and its own checks passed. Its libstdc++ is built with the new default: it calls `__cxa_atexit` (14 references in the 68020/68881 multilib, none in the live stove's). It has every file the live stove has, except the developer kits the stove installer adds afterwards (GFOpenGPU SDK, SDL2 and the other headers). It also has libpthread's aros-stuff 0003 and 0004, which are on `main` but not in the live stove.

A middle step checked libnix on its own. It used the copy's new libnix with the live stove's `cc1plus`, and built each test with an explicit `-fuse-cxa-atexit` and no `__dso_handle` of its own:
- t12, t13, t19 and `dtors` passed;
- with the live stove's libnix the same build doesn't link (`undefined reference to __dso_handle`, `__cxa_atexit`).

## How the patches were checked

- **Building libnix's members.** The new `atexit.o` and `__dso_handle.o` were compiled the way the stove builds libnix's `libnix.a`. Compiled the same way, the unpatched `atexit.c` gives the stove's `atexit.o` exactly, for all five multilibs (`objdump -dr` compared).
- **The stove copy.** These members went into a copy of the stove with `ar r`: `libnix.a` in lib, libb, libm020, libb/libm020 and libb32/libm020. The live stove was not touched.
- **The full rebuild.** `scripts/build.sh` with every patch, run without network at the stove's paths, as the 9 October release was built. Its `atexit.o`, `__dso_handle.o` and `setlocale.o` have the same code as the members put into the copy.
