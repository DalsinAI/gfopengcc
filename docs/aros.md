# The m68k-aros target

From 16.2.0-open6 GFOpenAmigaGCC is one compiler for two 68k systems:
`m68k-amigaos` (AmigaOS 3.x, as before) and `m68k-aros` (AROS 68k, and GFOpenKick's
exec, which is built as an AROS module). Both carry the same m68k code
generation fixes from the same patch files, and both say
`GFOpenAmigaGCC 16.2.0-open6`.

Before open6, `m68k-aros-gcc` was AmiCradle's `aros68k-gcc16` stove: stock GCC
16.2.0 with AROS's `gcc-16.2.0-aros.diff`, built by AROS's own crosstools build
on the Cradle machine and from no repository of ours. It had none of the fixes
here, and it compiled exec's `oe_AlertText` into `move.b (a1)+,(0,a1,d0.l)`
(PR123853, [autoinc-move.md](autoinc-move.md)).

## What it is built from

| Part | Source | Pinned in |
| --- | --- | --- |
| GCC | stock GCC 16.2.0 from ftp.gnu.org | `scripts/aros.lock` (SHA-256) |
| binutils | binutils 2.47 from ftp.gnu.org | `scripts/aros.lock` (SHA-256) |
| isl | isl 0.27, built in GCC's tree | `scripts/aros.lock` (SHA-256) |
| AROS's GCC and binutils changes | AROS's `tools/crosstools/gnu/gcc-16.2.0-aros.diff` and `binutils-2.47-aros.diff`, kept here unchanged as `patches/aros/*/0001-*.diff` | `scripts/aros.lock` (AROS commit); `build-aros.sh` compares them with AROS's files at that commit |
| collect-aros (AROS's linker driver) | AROS's `tools/collect-aros` | `scripts/aros.lock` (AROS commit) |
| AROS headers and link libraries (the sysroot) | an AROS m68k build of the same AROS commit: its `AROS/Developer` folder | supplied to `build-aros.sh`, like the NDK to `build.sh` |

The GCC is stock GCC, not bebbo's `16.2.0b` that the `m68k-amigaos` target
builds from. bebbo's tree changes the middle end and the m68k back end for every
m68k target (register allocation costs, LRA, CSE, the loop passes), and AROS's
diff is made for stock GCC; AROS code from stock GCC plus our fixes changes only
where a fix changes it.

## The patches

`patches/aros/series` lists them in order, and names every `patches/gcc` patch,
applied or not, with the reason; `tests/aros-series.sh` fails when a new
`patches/gcc` patch has not been decided for `m68k-aros`.

| Patch | For `m68k-aros` |
| --- | --- |
| AROS's `gcc-16.2.0-aros.diff`, `binutils-2.47-aros.diff` | as AROS has them |
| `gcc/0003` -m68040 `fix_trunc` scratch registers early-clobbered ([fpcr-clash.md](fpcr-clash.md)) | the same file |
| `gcc/0005` `-fmalloc-memset-to-calloc`, and never in `calloc` itself ([calloc-recursion.md](calloc-recursion.md)) | the same file (the option is on by default, as in stock GCC; the AmigaOS driver's default of off is `0006`) |
| `gcc/0008` a DImode shift by 32 pushed from a stack slot ([push64-stack-slot.md](push64-stack-slot.md)) | `aros/gcc/0008-stock-*`: the same change; its function goes at the end of stock `m68k.cc` |
| `gcc/0013` no move addresses its destination through the register its source steps, PR123853 ([autoinc-move.md](autoinc-move.md)) | the same file |
| `gcc/0014` vregs instantiates virtual registers inside an address operand ([vregs-address.md](vregs-address.md)) | the same file |
| `gcc/0004` movmemsi copies overlapping blocks the right way | not needed: it fixes bebbo's own `movmemsi` expander; stock GCC has none, so a `memmove` stays a call |
| `gcc/0001`, `0002`, `0006`, `0007`, `0009`-`0012` | AmigaOS only (`m68kamigaos.h`, `t-amigaos`, libnix, hunk objects) |

## Building

```bash
scripts/fetch-aros.sh WORK [TARBALLS]      # the tarballs (checked) and AROS's two folders at the pin
scripts/build-aros.sh WORK PREFIX SYSROOT [JOBS]
```

`build-aros.sh` configures binutils and GCC with the options AROS's crosstools
build gives them (`tools/crosstools/gnu/mmakefile.src`), so the tools land in
`PREFIX` itself (`PREFIX/m68k-aros-gcc`, as in the `aros68k-gcc16` stove), and
adds `--with-pkgversion`. With an AROS SDK as `SYSROOT` it also builds libgcc,
libstdc++ and, as AROS does, libatomic with AROS's flags, which it installs into
`SYSROOT/lib` (give it a copy of its own). With `SYSROOT` `none` it builds the
compiler, binutils and collect-aros only, which compile and assemble; CI does
that, since an AROS SDK comes from an AROS build.

About 2 GB of disk and 30 minutes on 5 cores with an SDK.

## Checks

- `tests/autoinc/check.sh --aros PREFIX` (CI) and `--amigaos PREFIX/bin` (CI):
  `tests/autoinc/pr-autoinc.c` (exec's `oe_AlertText`, reduced) and
  `tests/repro/autoinc.c` for every CPU at `-O2`, `-O3` and `-Os`, scanned as
  `-S` text and as objects by `tests/autoinc/scan_autoinc_overlap.py`
  (amicradle-guest's scanner). `--expect-wrong` shows the test sees the bug in
  an unfixed compiler: the `aros68k-gcc16` stove's gives
  `move.b (a0)+,(a0,d0.l)` for `pr-autoinc.c`.
- `build-aros.sh`'s own: the identity, an m68k ELF object, and with an SDK a C
  and a C++23 program linked.
