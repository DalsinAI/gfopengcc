# Open7 determinism validation — 2026-11-06

This is evidence for the first Open7 development slice, not an Open7 release
qualification.

## Inputs

- GFOpenAmigaGCC repository base: `0615bdbbf2141f9ac403115aad293251183dfd7a`
- GCC source base: `1ff531f6e251e2a30414973208f45555c2bd6118`
- Candidate patch:
  `0015-m68k-cost-overrides-are-explicit-and-bounded.patch`
- Temporary compiler identity:
  `GFOpenAmigaGCC 16.2.0-open7-dev`
- Configure scope: `m68k-amigaos`, languages `c,lto`, without bootstrap,
  shared libraries, multilib or target headers
- Validated Open6 assembler and objdump supplied the target binary tools.

## Results

1. The patch applied cleanly after Open6 patches 0001–0014.
2. `make -j8 all-gcc` completed and linked `xgcc`, `cc1`, CPP and LTO.
3. `make install-gcc` completed into a disposable prefix.
4. The Open6 compiler failed the new control test because an ambient
   `m68k-costs-speed.txt` changed generated code.
5. The Open7 candidate passed the same test: ambient files were ignored, an
   explicit `M68K_COSTS_FILE` selected another model, and negative and
   excessive costs were rejected without changing generated code.
6. The existing autoincrement regression matrix passed all 24 compilations:
   68000, 68020, 68040 and 68060 at `-O2`, `-O3` and `-Os`, for both the
   reduced PR reproducer and the wider Open6 reproducer. Assembly and object
   scans reported zero failing instructions.
7. `tests/aros-series.sh`, shell syntax checks and `git diff --check` passed.

The full Open7 production build, C++/libnix reproducer suite, AROS build and
runtime qualification remain later release gates.
