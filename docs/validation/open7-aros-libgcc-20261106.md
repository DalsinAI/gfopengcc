# Open7 AROS libgcc validation — 2026-11-06

Open6's release notes say that an AROS C++ program linked with `-m68040` was
left with `__divsi3` undefined. That finding does not match either compiler
artifact still present on daletop.

## Artifacts checked

- Archived predecessor:
  `AmiCradle/stoves/archive/aros68k-gcc16-before-open6-20261103T2335Z/toolchain`
- Open6:
  `AmiCradle/stoves/aros68k-gcc16-open6/toolchain`

For both artifacts, the vector/sort C++ probe from `scripts/build-aros.sh`
linked successfully at `-m68040 -O2 -std=c++23` with the AROS pthread and
atomic link options. Both selected an `m68040/libgcc.a` that defines
`__divsi3`.

The Open6 compiler advertises seven multilibs: default, 68020, 68040 and
68060, plus a soft-float variant for each explicit CPU. Every selected
`libgcc.a` defines `__divsi3`, `__modsi3`, `__mulsi3`, `__udivsi3` and
`__umodsi3`.

Open7 therefore treats this as a stale or transient historical result rather
than inventing a source fix. `tests/aros-libgcc.sh` now audits every multilib,
and the full AROS build now links the C++ probe at `-m68040` instead of avoiding
the reported condition.

## Clean Open7 compiler bootstrap

A fresh compiler-only AROS work folder was populated from the pinned inputs:

- GCC archive SHA-256
  `e6738e29597f733270731aa90600f37ffdc045079dfc27ec7e8192cc81085c3e`;
- binutils archive SHA-256
  `3068128c75cda9f898ccb4211d360246e8e195ffcc9dfb655b23ae23a54800e8`;
- isl archive SHA-256
  `6d8babb59e7b672e8cb7870e874f3f7b813b6e00e6af3f8b04f7579965643d5c`;
- AROS `c8860e674d7c5fbab304e2bf201f7a9c81c98629`.

`scripts/build-aros.sh WORK PREFIX none 8` applied the seven patches selected
by `patches/aros/series`, then built binutils, `collect-aros` and
`m68k-aros-gcc (GFOpenAmigaGCC 16.2.0-open7) 16.2.0` into a new prefix.
`tests/aros-series.sh` accounted for all seventeen GCC-patch decisions and the
autoincrement scanner passed all 24 combinations of 68000, 68020, 68040 and
68060 at `-O2`, `-O3` and `-Os` for both probes.

This is the same compiler-only gate used by CI because no complete AROS SDK
was supplied. It proves the clean compiler bootstrap and generated-instruction
checks; it does not replace a full AROS SDK/libgcc/libstdc++ build or target
runtime qualification.

## Full-SDK integration build

The compiler-only prefix was removed and the source/build folders were reset.
An isolated copy of
`AmiCradle/stoves/aros68k-gcc16-open6/sdk/Developer` supplied the complete
AROS SDK at the pinned AROS commit. The clean build then completed binutils,
collect-aros, GCC, all seven libgcc/libstdc++ multilibs and all seven libatomic
multilibs. The installed compiler identifies itself as
`m68k-aros-gcc (GFOpenAmigaGCC 16.2.0-open7) 16.2.0`.

The first final C++ link exposed a host-tool defect rather than a target-code
failure. The no-libiberty `collect-aros` fallback hardcoded
`/tmp/catmpXXXXXX`; a syscall trace showed the linker write failing with
`EDQUOT` even after the build volume had 16 GiB free. A new AROS series patch
makes collect-aros honor nonempty `TMPDIR` while retaining `/tmp` as its
fallback, and `scripts/build-aros.sh` supplies a work-folder temporary
directory by default.

After rebuilding only collect-aros with that patch:

- a traced 68040 C++/pthread/atomic link succeeded;
- every `catmp` open was below `open7-aros/.tmp`, with none below `/tmp`;
- all seven multilibs contained the five required integer helpers;
- the C and C++ SDK links succeeded;
- all 24 AROS autoincrement compile/scan cases passed.

Artifact hashes for this full integration prefix are:

- `cc1`: `e1af4fe0519989a9114100842fee72897bdefba086b56f04301ce8682214c58e`
- `cc1plus`: `46f00e3ba4d23e76cc7c7606ffb7caadc916a81fd4396929b6f018f9a7078b0c`
- fixed `collect-aros`:
  `72f7787fdb90bc69751a22d37e859d60b2945ecd9b6d0948eac73686098c4a7e`

The compiler and target libraries came from an empty build/prefix reset, but
the final collect-aros binary was corrected after that run. This is complete
full-SDK integration evidence, not yet the uninterrupted clean receipt for the
new eight-patch series. A clean rerun and AROS runtime execution remain open.
