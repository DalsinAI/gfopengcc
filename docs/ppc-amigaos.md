# AmigaOS 4.1 (`ppc-amigaos`): not yet in a release

GFOpenAmigaGCC's releases so far hold only the `m68k-amigaos` compiler. The Team's
GCC 16.2 for AmigaOS 4.1 on PowerPC exists as a recipe and as a built stove, but
it is not part of 16.2.0-open2 or any other release here yet.

## Where it is now

- **The recipe:** amicradle-stoves' `os4-gcc16/`
  ([amicradle-stoves #8](https://github.com/DalsinAI/amicradle-stoves/pull/8),
  open, not merged, no CI). GCC 16.2.0 and binutils 2.47 from the GNU releases,
  pinned by SHA-256 and checked against GNU's signatures. Two patches ported from
  AmigaLabs' adtools (`binutils/2.40` at `063184c1`, `gcc/15` at `87ac263c`).
  clib2 (`1a42c693`, BSD 3-Clause) and clib4 (`30e487d2`, BSD 3-Clause; it also
  carries `LICENSE-GPL` and `LICENSE-OPENLIBM`) built from source. `-mcrt=` picks newlib, clib2 or clib4.
- **The stove:** amicradle's `scripts/build_os4_stove.sh` (amicradle #496,
  merged) runs the recipe into Cradle's Stoves folder as ACKitchen's `os4` stove.
  Until amicradle-stoves #8 is merged, it needs
  `OS4_STOVE_REF=origin/team3/os4-gcc16`, because `origin/main` has no
  `os4-gcc16/` yet.
- **Built and tested:** one full build on the Cradle machine, 14 October 2026,
  from recipe `cc1452c` with Hyperion's SDK 54.25. Every smoke test passed: C
  with newlib, clib2 and clib4; C++ with newlib and clib2; a device-style link;
  and `-mbaserel` with clib2. The compiler reports itself as
  `ppc-amigaos-gcc (AmiCradle os4-gcc16) 16.2.0`; binutils as 2.47.
- **Not yet tested:** programs running on AmigaOS 4.1. The recipe's README says
  run-time tests on an AC460 come next.

## What a release would hold

| File | What |
| --- | --- |
| `openamigagcc-16.2.0-openN-ppc-amigaos-x86_64-linux.tar.xz` | `bin/`, `libexec/`, `lib/gcc/ppc-amigaos/16.2.0/` (libgcc, and its clib2 build), `ppc-amigaos/lib/` (libstdc++, libatomic and libssp, and their clib2 builds), `ppc-amigaos/include/c++/`, the clib2 and clib4 headers, libraries and start-up files, and `clib4.library` |
| `openamigagcc-16.2.0-openN-ppc-amigaos-src.tar.xz` | the recipe (`build.sh`, `sources.lock`, both patches, `PORTING.md`, the smoke tests), and the exact inputs it built from: `gcc-16.2.0.tar.xz`, `binutils-2.47.tar.bz2`, `gmp-6.3.0.tar.bz2`, `mpfr-4.2.2.tar.bz2`, `mpc-1.4.1.tar.xz`, `isl-0.27.tar.xz` (built into the compiler), and clib2 and clib4 at their pinned commits |
| `SHA256SUMS` | the checksums of both |

Every input above is already on the machine that built the stove, so making the
two tarballs needs no download. Licences: GPL-3.0-or-later for GCC, binutils
and both patches (the patches are ported from adtools, which is GPL), with the
GCC Runtime Library Exception for libgcc and libstdc++; LGPL-3.0-or-later for
gmp, mpfr and mpc; MIT for isl; BSD 3-Clause for clib2; clib4's own licence
files.

Left out, by design: Hyperion's AmigaOS 4.1 SDK (the OS headers, newlib and its
start-up code). It is a free download, but it is not the Team's to
redistribute. The user downloads it and puts it in place, as with the AmigaOS
3.2 NDK for `m68k-amigaos`.

## What is missing before it can be released

1. **The recipe merged, with CI.** amicradle-stoves #8 is open and has no CI.
   A release should be built from a merged commit that CI has built.
2. **A compiler that can move.** The built stove's specs hold the SDK's full
   path (`base_sdk`, the stove's own `prefix/ppc-amigaos/SDK/`), and the
   recipe's README says to build the stove in place. A release build needs a
   prefix and an SDK path that work wherever the tarball is unpacked, for
   example an SDK path relative to the compiler, or a documented
   `--sysroot`-style option.
3. **The SDK kept apart.** The stove puts clib2, clib4 and Hyperion's SDK in the
   same `SDK/` folder. Packaging must copy the clib2 and clib4 parts and leave
   every SDK file out, with a check that no SDK file is in the tarball.
4. **An install step for the SDK,** like `scripts/install-ndk.sh` for the NDK:
   it takes `SDK_54.25.lha` (or later), checks it, and puts it where the
   compiler looks.
5. **A version string for the release.** The stove's compiler says
   `AmiCradle os4-gcc16`; a release build would name the GFOpenAmigaGCC release.
6. **Run-time tests on AmigaOS 4.1:** the smoke tests run on an AC460, at least
   for newlib, clib2 and clib4, C and C++.
7. **The decision to publish,** and where: in this repository's next release,
   beside the `m68k-amigaos` toolchain, or as amicradle-stoves releases (that
   repository's README says built stoves are published as releases there).
