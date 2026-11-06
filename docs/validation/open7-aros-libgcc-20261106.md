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
