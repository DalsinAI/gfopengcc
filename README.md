# GFOpenAmigaGCC

GCC 16.2 for AmigaOS 3.x (`m68k-amigaos`), with the Team's fixes. The table below lists every system it is meant for, and which ones are released. This is the compiler behind AmiCradle's `os32-gcc16` stove and the GFOpen family's builds.

It builds on bebbo's amiga-gcc line (GCC for `m68k-amigaos` with libnix) and adds patches for bugs the Team has found and proved while building the GFOpen family. The patches, the build recipe and the notes are here; GCC's and libnix's own sources are fetched from their upstreams by the recipe.

## Systems

| System | Target | Provided by | How to install | Status |
| --- | --- | --- | --- | --- |
| AmigaOS 3.2.3 (and AmigaOS 3.x) on 68k | `m68k-amigaos` | this repository's 16.2.0-open4 release: the x86-64 Linux toolchain and the complete source. For ARM64 Linux, 16.2.0-open1's toolchain. | unpack the toolchain and add the AmigaOS 3.2 NDK: [docs/install.md](docs/install.md) | open4, 30 October 2026 |
| AmiCradle (its 68k instances, which run AmigaOS 3.2.3) | `m68k-amigaos` | the same compiler, as ACKitchen's `os32-gcc16` stove, built from this repository's `scripts/build.sh`. AROS 68k instances use amicradle-stoves' `aros68k-gcc16` (`m68k-aros`) instead. | the stove is built on the Cradle machine into Cradle's Stoves folder, with its own copy of the NDK (never in git or a release); or install the release as for AmigaOS 3.2.3 | in use |
| GFOS (GirlfriendOS): the Team's own system, AmiCradle with the open ROM | `m68k-amigaos` | the `os32-gcc16` stove, as in the AmiCradle row: the open ROM's modules build with it against the stove's NDK 3.2 headers (there is no open ROM NDK yet), and its exec with `aros68k-gcc16` (`m68k-aros`) | as for the AmiCradle row | name not final |
| AmigaOS 4.1 on PowerPC | `ppc-amigaos` | amicradle-stoves' `os4-gcc16` recipe (GCC 16.2.0, binutils 2.47, clib2 and clib4), [amicradle-stoves #8](https://github.com/DalsinAI/amicradle-stoves/pull/8), open. amicradle's `scripts/build_os4_stove.sh` (amicradle #496, merged) builds it as ACKitchen's `os4` stove. | not yet in a release: build it from the recipe, which downloads Hyperion's AmigaOS 4.1 SDK on the building machine | not yet: [docs/ppc-amigaos.md](docs/ppc-amigaos.md) says what is missing |

## Status

**16.2.0-open4, 30 October 2026** ([notes](docs/releases/16.2.0-open4.md), [install](docs/install.md)): every fix below, adding the late-combine and vregs wrong-code fixes (GCC 0013, 0014) and libnix's `strtol`/`strtoul` end pointers (libnix 0008) to open3. `16.2.0-open3` (19 October 2026) added built-in 68020/68030/68040 soft-float library selection and an unambiguous compiler identity; `16.2.0-open2` (12 October 2026) added the thread, C++ and nested-call fixes; `16.2.0-open1` (9 October 2026) has GCC patches 0001-0009, libnix 0001-0003 and the two header fixes.

| Bug | Where | Status |
| --- | --- | --- |
| `-m68040` float-to-int saves FPCR into the register the store's address indexes with | GCC m68k back end | fixed ([docs](docs/fpcr-clash.md)) |
| An overlapping memmove of constant size copies forwards: shift-up loops at `-O2`, `__builtin_memmove` and `std::copy_backward` at any `-O` | GCC m68k back end | fixed ([docs](docs/memmove-direction.md)) |
| Provable NULL reads become `trap #7` (Software Failure 80000027) | GCC default (`-fdelete-null-pointer-checks`) | driver default changed ([docs](docs/null-trap7.md)) |
| A function's own `calloc` (malloc + memset) is turned into a call to `calloc`, recursing | GCC middle end | fixed, and off by default ([docs](docs/calloc-recursion.md)) |
| Loop distribution off by default (patch 0006) made shift-up and sorted-insert loops 3.8 and 1.3 times slower on the AC090 | GCC driver default | fixed: on again ([docs](docs/loop-distribution.md)) |
| `-resident32` alone links the plain `libm020` libraries | GCC multilib setup | fixed ([docs](docs/resident32-multilib.md)) |
| A 64-bit libcall argument pushed from a stack slot reads the wrong word (`-m68040`/`-m68060` tuning) | GCC m68k back end | fixed ([docs](docs/push64-stack-slot.md)) |
| A library call nested in another's arguments, as in `Stricmp(FilePart(x), ...)`, runs the outer call with the inner library's base in A6 | sfdc (the NDK's `inline/*.h`) | fixed by the recipe ([docs](docs/nested-inline-a6.md)) |
| Roadshow's socket inlines are refused by GCC 16 (argument registers in the clobber list) | amiga-netinclude headers | fixed by the recipe ([docs](docs/netinclude-inline-clobbers.md)) |
| `__stack` doesn't give a program its stack; the stack swap clobbers A2 (80000004) | libnix | fixed: `patches/libnix/0001` ([docs](docs/libnix-stack-swap.md)) |
| Plain `-fbaserel32` programs never return to the Shell (they return the stack size) | libnix start code | fixed: `patches/libnix/0002` ([docs](docs/libnix-baserel32-exit.md)) |
| A program's own `UtilityBase`, still NULL, crashes 32-bit multiply/divide (80000004) | libnix | fixed: `patches/libnix/0003` ([docs](docs/libnix-utilitybase.md)) |
| Soft-float doubles (`-m68060`, or `-m68020` without `-m68881`) rounded to single precision on an Amiga with an FPU: OS 3.2's IEEE libraries set FPCR when libnix opens them | libnix start code | fixed: `patches/libnix/0004` ([docs](docs/libnix-fpcr.md)) |
| A thread that was running when a later thread was created reads freed memory as it ends: C++ `thread_local` or `call_once` in several threads crashes (80000003, 80000006) or hangs | libpthread (aros-stuff) | fixed: `patches/aros-stuff/0001` ([docs](docs/pthreads-thread-table.md)) |
| `pthread_detach` was a stub (`std::thread::detach` threw "No such process"); a detached thread's slot was never given back; `pthread_join` returned errors with its semaphore held, hanging the next pthread call | libpthread (aros-stuff) | fixed: `patches/aros-stuff/0002` (amicradle-stoves' t19) |
| A `thread_local`'s destructor never ran (namespace scope or static member): GCC registers it only with `-fuse-cxa-atexit`, and libnix had no `__cxa_atexit` or `__dso_handle` | GCC default, libnix | fixed: `-fuse-cxa-atexit` by default (`patches/gcc/0010`), `__cxa_atexit` and `__dso_handle` in libnix (`patches/libnix/0005`) ([docs](docs/cxa-atexit.md)) |
| C++ streams formatting or reading numbers in several threads at once hang the program or the system (amicradle-stoves' t18): libstdc++ calls `setlocale()` for every number, and libnix's `setlocale()` freed its returned name and closed the locale in use on every call | libnix | fixed: `patches/libnix/0006` ([docs](docs/libnix-setlocale.md)) |
| C++ startup in base-relative programs read the exception-frame and constructor lists through A4, but they are in the code hunk: `-fbaserel` C++ failed to link, `-fbaserel32` C++ hung before `main` | libnix | fixed: `patches/libnix/0007` ([findings](tests/baserel/FINDINGS.md)) |
| A new thread in a base-relative program ran with no A4 of its own and hung reading its first global | libpthread (aros-stuff) | fixed: `patches/aros-stuff/0005` ([findings](tests/baserel/FINDINGS.md)) |
| `pthread_join` waited on Ctrl-F and cleared it: a Ctrl-F the program had pending, or was sent during the join, was lost; and a thread that ended sent its parent a Ctrl-F nobody had sent | libpthread (aros-stuff) | fixed: `patches/aros-stuff/0006`, a join signal of its own (`tests/pthreads/joinsig.c`) |
| Base-relative C++ (`-fbaserel`, `-fbaserel32`, `-resident`, `-resident32`): the exception tables reached their typeinfo pointers PC-relative across hunks ("reloc for .data.rel.local.LDFCM0 is out of range"), so catch by type could not match | GCC (m68k EH data format under `-fpic`) | fixed: `patches/gcc/0011`, EH data always `DW_EH_PE_absptr` on AmigaOS; CI runs `tests/baserel/eh-check.sh` ([findings](tests/baserel/FINDINGS.md)) |
| `strtol` and `strtoul` left `endptr` unset on empty or whitespace-only input, so a parser that stops when `end == input` ran past its last token | libnix | fixed: `patches/libnix/0008`, from open4 ([docs](docs/libnix-strtol-endptr.md)) |
| A move whose source post-increments or pre-decrements a register addressed its destination through it, as in `move.b (a2)+,(a0,a2.l)`: the 68k steps the register first, so each element landed one late (GFOffice showed 6.5 as "6.w"); GCC 15's late-combine made it at `-O2` | GCC m68k back end (PR123853) | fixed: `patches/gcc/0013`, from open4 ([docs](docs/autoinc-move.md)) |
| `strcat` into a local array (inlined at `-O1` and `-O2`, 68020 and up) wrote to an absolute address: the copy's `lea` kept `virtual-stack-vars` after the vregs pass, and combine dropped it | GCC middle end (vregs) | fixed: `patches/gcc/0014`, from open4 ([docs](docs/vregs-address.md)) |
| `libamiga.a` (GFOpenNDK) was built for the 68040 and put in every multilib folder, the 68000 default's too: a `-m68000` program calling `RangeRand`, `ArgArrayInit` or another helper got 68020 instructions and crashed on a 68000 | build.sh step 5b | fixed: one build per multilib with its own flags, checked in step 7, from the next release ([docs](docs/openndk-libamiga.md)) |

Each fix comes with a small reproducer that is wrong on the old compiler and right on the new one: `tests/repro/prove.sh` runs the GCC ones and libnix's FPCR one under `qemu-m68k`, the other libnix ones are in `tests/libnix/`, and the libpthread ones are `tests/pthreads/t3race.cpp` and `tests/pthreads/joinsig.c`. How to build: [docs/building.md](docs/building.md).

C++ destructors are registered the C++ ABI's way (`-fuse-cxa-atexit`, patch 0010): `thread_local` destructors run, and static objects are destroyed in the reverse order of construction, interleaved with `atexit()` functions. `-fno-use-cxa-atexit` gives the old way back.

The GFOpen family's libraries and apps use a lean C++ (no exceptions, no RTTI, no static constructors in libraries, C at each library's entry points): [docs/lean-cxx.md](docs/lean-cxx.md). `tests/cxx/lean-check.sh` checks a build against it.

The driver adds two safe defaults, each of which a build can turn back on with the positive option: `-fno-delete-null-pointer-checks` and `-fno-malloc-memset-to-calloc`. Loop distribution stays on (patch 0009): with the memmove fix it is correct, and a shift or insert loop that becomes one block move runs several times faster than the loop. A library that defines its own `memcpy`, `memmove`, `memset` or `calloc` as a loop builds with `-fno-tree-loop-distribute-patterns` (libnix's build does), or the loop becomes a call to itself.

## Mixing compilers

Programs built with GCC 6.5 (the older `os32` stove) calling libraries built with GCC 16 must avoid struct returns (GCC 6.5 passes the address in A0, GCC 16 in A1) and assume `-m68881` for floating point. See `docs/abi-notes.md`.

## Licence

GCC is GPL-3.0 (with the GCC Runtime Library Exception), and the patches to it here are GPL-3.0 too; see `LICENSE`. libnix's patches follow libnix's own licence, and the libpthread patch follows aros-stuff's pthreads licence (zlib-style). No AmigaOS NDK or other non-free files are kept here; the build recipe expects the NDK to be supplied separately.

Part of the GFOpen family by the Team · github.com/DalsinAI
