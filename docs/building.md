# Building GFOpenAmigaGCC

The recipe builds GCC 16.2 for `m68k-amigaos` with binutils, libnix,
libpthread, libgcc and libstdc++, from bebbo's amiga-gcc line at pinned
commits, with the patches in `patches/`.

## What it needs

- An x86 or ARM64 Linux system with the usual GCC build tools (a C and C++
  compiler, make, bison, flex, gperf, texinfo, gmp/mpfr/mpc development
  files, rsync, git, lhasa).
- The AmigaOS 3.2 NDK archive, `NDK3.2.lha`, which you supply. It is not free
  software, so it is never fetched or kept here.
- About 9 GB of disk and 45 minutes on 8 cores.

## Steps

```bash
scripts/fetch.sh WORK                # clones the sources in scripts/sources.lock (network)
scripts/build.sh WORK PREFIX /path/to/NDK3.2.lha [JOBS]
```

For ARM64 Linux hosts, a Canadian cross on x86-64 (needs
`aarch64-linux-gnu-gcc` and `-g++`; GMP, MPFR and MPC are built in-tree from
their release tarballs):

```bash
scripts/build-arm64.sh WORK X86PREFIX ARMPREFIX TARBALLS
```

It builds the programs for ARM64 and copies the target libraries and headers,
which are the same for every host, from the x86-64 build.

`fetch.sh WORK MIRROR` clones from an earlier amiga-gcc checkout instead of
the network. When franke.ms does not answer, `fetch.sh` tries copies of bebbo's
repositories (`codeberg.org/bebbo`, then `github.com/AmigaPorts`) and uses one
only if it has the pinned commit. `build.sh` never fetches: when `unshare` is there it builds with
no network at all, so a missing source stops it.

`build.sh`:
1. checks every source is at its pinned commit;
2. applies `patches/gcc`, `patches/amiga-gcc` and `patches/libnix` (each once)
   and copies `sys-include/fenv.h` and `uchar.h`;
3. installs libnix's headers first (with no `-mcrt`, the driver means
   `-mcrt=nix20`, and libnix compiles some files that way);
4. runs amiga-gcc's `make binutils gcc gprof libnix libpthread ndk ndk13`;
5. builds libgcc, libstdc++ and the other target libraries against libnix's
   headers, and tells libstdc++ that the header-only `fenv.h` is there;
6. checks that a read of address 0 is not `trap #7`, that a C program links
   with libnix and that a C++23 program links.

Then `tests/repro/prove.sh PREFIX/bin` runs every reproducer (it needs
`qemu-m68k`).

## The m68k-aros target

From open6 the same repository builds `m68k-aros-gcc` (AROS 68k) from stock
GCC 16.2.0, AROS's diffs and `patches/aros/series`:

```bash
scripts/fetch-aros.sh WORK [TARBALLS]
scripts/build-aros.sh WORK PREFIX AROS_SDK|none [JOBS]
```

See [aros.md](aros.md).

## CI

`.github/workflows/build.yml` does all of this on every pull request and every
push to `main`: `fetch.sh`, then `scripts/fetch-ndk.sh` downloads `NDK3.2.lha`
from Aminet and checks it against `scripts/ndk.lock` (CI only: the NDK is
never kept here or put in a release), then `build.sh`, `prove.sh` (plain and
with `-fno-tree-loop-distribute-patterns`), `tests/cxx/lean-check.sh`, and a
compile of the tests that need a real AmigaOS to run (`tests/cxx`,
`tests/pthreads`, `tests/libnix/setlocale_threads.c`). Running those stays a
lab job.

## Using it

Programs are AmigaOS 3.x hunk executables linked with libnix:

```bash
m68k-amigaos-gcc -m68040 -O2 -o hello hello.c
```

Open3's built-in specs keep a soft-float `-m68040` link off libnix's FPU libm;
use `-m68881` when a hard-float program is intended
([m68040-soft-float-link.md](m68040-soft-float-link.md)).

The driver adds `-fno-delete-null-pointer-checks` and
`-fno-malloc-memset-to-calloc` unless a build passes the positive form; see
`m68k-amigaos-gcc -### -c x.c`. Loop distribution stays on; the build compiles
libnix and libpthread with `-fno-tree-loop-distribute-patterns` (see
`loop-distribution.md`).
