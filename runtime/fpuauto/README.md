# fpuauto: one binary, the FPU when there is one

Copyright (c) 2026 AmiCradle Team. MIT licence.

This folder is AmiCradle's own fpuauto, carried in GFOpenAmigaGCC from
amicradle-guest `common/fpuauto` at commit `e62e5c24` (the multicore-safe
data dispatcher), so the compiler builds from public sources alone. The
Cradle stove updater (`install-stove.sh`) stays in amicradle-guest.
`build-amiga.sh` finds `m68k-soft-m68040.specs` in this repository's
`build/` folder.

## What a soft-float build does today

Our programs are built `-m68040` with `build/m68k-soft-m68040.specs`, so
they link libnix's soft `libm020`. Measured on the os32-gcc16 stove (job
j20261105T164801-b86586):

| Routine | Where it comes from | What it is |
| --- | --- | --- |
| `__adddf3` `__subdf3` `__muldf3` `__divdf3` (and the `sf3` singles) | libnix `libm020/libm.a` | a call of IEEEDPAdd... in mathieeedoubbas.library (IEEESP... in mathieeesingbas) |
| `__cmpdf2` `__eqdf2` `__nedf2` `__ltdf2` `__ledf2` `__gtdf2` `__gedf2` (one member, and the `sf2` singles) | libnix | IEEEDPCmp's -1, 0 or 1 |
| `__extendsfdf2` `__truncdfsf2` | libnix | IEEEDPFieee, IEEEDPTieee (mathieeedoubtrans) |
| `sqrt` | libnix | IEEEDPSqrt |
| `__fixdfsi` `__fixsfsi` `__floatsidf` `__floatsisf` | libgcc (`xfpgnulib`) | integer code: no library, no FPU |

So the arithmetic already reaches the FPU when there is one (the maths
libraries pick their FPU bodies at init), but through two calls and a
library jump per operation, and the conversions never do.

## What fpuauto does

`fpuauto.S` is linked with `--wrap` for each of those 29 routines
(`fpuauto.wraps`). Each wrapper loads an aligned data pointer and jumps to its
target. The pointer initially selects a resolver; its first call changes the
pointer to:

- On a 68040 or 68060 with its FPU (AttnFlags AFF_FPU40) that
  softfpu.library is not emulating (`sf_Flags & SFF_EMULATING`, as
  `libraries/openmathieee` checks): the FPU instruction, there and then
  (FDADD/FSADD..., FCMP, FMOVE.L under round-to-zero for the C cast,
  FMOVE.L for int to double, FSQRT then FMOVE.D, FMOVE.S/FMOVE.D).
- Otherwise: `__real_<name>`, the routine the program had before, so a
  68LC040 or a 68EC040 runs exactly as it does today.
- Any NaN, and a cast out of int range, goes to `__real_<name>` too, so
  NaN bits and out-of-range answers stay the library's.

The answer is looked up once per program, at the first call, into
`__fpuauto_hw` (1 FPU, -1 soft). Each routine then keeps its selected target
in data. No instruction is modified and no instruction-cache flush is needed;
concurrent first calls can only store the same aligned pointer. The FPU
instructions are the ones the maths libraries' own FPU bodies run, so the
bits are theirs.

## Build and bench

`sh build-amiga.sh` (os32-gcc16 stove): `libfpuauto.a` and
`FPUAutoBench` three ways: `-auto` (soft-float link + fpuauto: runs the
FPU path, then forces the soft path), `-plain` (the soft-float link as
today) and `-hard` (`-m68881`, the ceiling). Every test prints a checksum
of its results' bits: the FPU path and the soft path must print the same.

`sh install-prefix.sh PREFIX OUT` performs the same build and validation for
a complete compiler prefix, installs the archive and GCC specs, then proves
that the default link is wrapped and `-DNO_FPUAUTO` is not. Compiler release
builds use this path; `install-stove.sh` remains the recoverable updater for
an existing stove.

## Measured (5 November 2026, original self-patching dispatcher)

Lab `t3-fpuauto-20261105` (a copy of Instance-32, AmiCradle, 68040 with
its FPU, AttnFlags $807F), `FPUAutoBench 2000000`, best of three, seconds,
the range over two or three runs of each. "Soft" is the fpuauto program
forced onto the soft path; the native comparator is the same C built for
the build host (x86-64) and run there.

| Test | Today (soft-float link) | fpuauto, FPU path | fpuauto, soft path | `-m68881` | Native host |
| --- | --- | --- | --- | --- | --- |
| mandel (double mul/add/compare) | 0.353-0.365 | 0.222-0.272 | 0.360-0.365 | 0.092 | 0.0027 |
| conv (double/int casts, divide) | 0.370-0.392 | 0.310-0.352 | 0.383-0.398 | 0.132 | 0.0057 |
| float (single maths, casts) | 0.323-0.368 | 0.180-0.206 | 0.346-0.351 | 0.059 | 0.0036 |
| sqrt | 0.175-0.189 | 0.125-0.137 | 0.178-0.189 | 0.030 | 0.0040 |

With an FPU: 1.2 to 1.9 times today's speed. Every checksum of the FPU
path and the soft path is today's, the corner-value test (NaNs, signed
zeros, infinities, subnormals, the int range's edges, every compare)
included.

The same lab as a 68LC040 (`AC090_NOFPU=1`: softfpu.library 47.100
emulating, AttnFlags still $807F): fpuauto sees `SFF_EMULATING` and takes
the soft path.

| Test | Today | fpuauto (soft path) |
| --- | --- | --- |
| mandel | 0.318-0.325 | 0.325-0.343 |
| conv | 0.350-0.359 | 0.344-0.360 |
| float | 0.322-0.325 | 0.338-0.341 |
| sqrt | 0.162-0.170 | 0.165-0.171 |

These measurements predate the multicore-safe data dispatcher. They remain a
performance baseline, not a claim for the revised implementation. The old
soft path cost one `JMP abs.l` per call; the revised path costs one data load
and one indirect jump and must be measured again on the same instance before
release.

The link specs leave a program with no float maths, a `-m68881` link and
a `-DNO_FPUAUTO` link byte for byte as they were (`build-amiga.sh`
checks all three with `cmp`). `-nostdlib` links (ROM modules) never see
it, so no ROM grows.
