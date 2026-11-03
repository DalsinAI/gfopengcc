# -mcas: atomics with CAS inline

**Patch:** `patches/gcc/0015-amigaos-mcas-atomics-with-CAS-inline-on-a-68020-to-6.patch`
**Reproducer:** `tests/repro/cas.c` (run by `tests/repro/prove.sh`)

## Why every atomic was a call

bebbo's `m68k.cc` builds the CPU flags for AmigaOS without `FL_CAS`:

```
#ifdef TARGET_AMIGAOS
/* SBF: no CAS on the AMIGA and no 68881 per default. */
#define FL_FOR_isa_20    (FL_FOR_isa_10 | FL_ISA_68020 | FL_BITFIELD )
```

The Amiga's chipset does not take CAS's locked read-modify-write cycle in
Chip RAM, so the default is right for code that may put an atomic there. But
it means `TARGET_CAS` is false for every AmigaOS CPU, even `-m68040`, and
`sync.md`'s `atomic_compare_and_swap` patterns are never used. Each C11 or
C++ atomic becomes a call into libatomic, and libatomic's AmigaOS build does
each one under `Forbid()` and `Permit()`: two library calls and two ROM calls
for each reference count change, lock or flag.

In GFOpenBrowser's engine that came to 168 four-byte and 43 one-byte call
sites, and 3% of a bbc load's time and 5% of reddit's (js-profile, 3 Nov 2026).

## The option

`-mcas` (off by default) gives a 68020, 68030, 68040 or 68060 `FL_CAS`
again. 1-, 2- and 4-byte compare-and-exchange is then one `cas`, and the
fetch-and-op forms become `cas` loops, all inline. 8-byte atomics stay
libatomic calls, because GCC has no `cas2` pattern. Without `-mcas`, or for
a 68000, 68010 or CPU32, nothing changes.

Use it only for a program whose atomics never live in Chip RAM: its heap and
data are in Fast RAM, and it never passes an atomic in a Chip RAM buffer.
Code built with `-mcas` and code built without it can share an atomic on one
CPU, because a CAS cannot run between another task's `Forbid()` and
`Permit()`.

## Proof

`prove.sh` builds `cas.c` at `-O1`, `-O2` and `-Os` with `-m68040 -mcas`. It
runs each build under `qemu-m68k` and checks the values. It checks that the
code holds at least ten `cas` instructions and no `__atomic` call. It also
checks that the same file still calls `___atomic_compare_exchange_4` without
`-mcas`, and with `-m68000 -mcas`.
