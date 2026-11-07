# Open7 AmigaOS integration validation, 2026-11-06

This record covers the first complete seventeen-multilib AmigaOS integration
prefix.  It is strong integration evidence, but it is **not** one of the two
required clean reproducibility builds: the first invocation stopped before GCC
when the host `/tmp` quota was exhausted, and the retry reused its already
patched source trees.  The failed output was preserved separately as described
in `open7-clean-build-race-20261106.md`.

## Build identity

- orchestration branch: `team1/open7-determinism`
- orchestration commit at build start: `6c527a9`
- prefix: `/home/da1ek/Documents/ChatGPT/AmigaChrome/work/open7-prod-b-prefix`
- compiler: `m68k-amigaos-gcc (GFOpenAmigaGCC 16.2.0-open7) 16.2.0b 20260930174807`
- `cc1`: `4b9274287817482720d75cd9f31376962686f8583fafca2d35671c0f5aa690fb`
- `cc1plus`: `4a87eb0cee45dbbd50644815c266e5c4cde67f64e9d4dfe359616f819aabd67a`
- driver: `2e2031a8008c02ba6b27348f80113e7452545e6a11e0a3ed2a134194ad211944`
- pinned fpuauto source: `e62e5c24` on `team1/fpuauto-data-dispatch`
- installed provenance: 39 applied patches plus source heads and lock files

The build completed GCC, libgcc, libatomic, libstdc++, libobjc, libquadmath,
libnix, libpthread, GFOpenNDK `libamiga`, and the now-fatal
`libnix4.library` target.  All 17 stack-protector archives were installed.
The exact multilib set contains plain, baserel and baserel32 families with
68020, 68040 and 68060 soft-float variants and 68020/68040 hard-float
variants where supported.

## Gate discovery and correction

The first post-build gate correctly stopped because `-m68040 -m68881`
selected root `libpthread.a`.  The driver searches the nested
`libm040/libm881` directory, while the initial compatibility seed had created
only `libm040`.  `scripts/build.sh` now seeds both soft- and hard-float 68040
C-runtime directories for plain, baserel and baserel32, and requires all
twelve `libpthread.a`/`libnix.a` results before continuing.

After applying that correction to the integration prefix:

- all 17 `-print-multi-lib` entries matched exactly;
- compatibility ranges such as `-m68020-40` remained on `libm020`;
- true 68040 soft- and hard-float options selected `libm040` paths;
- `libgcc.a`, `libpthread.a` and `libnix.a` resolved beneath
  `libm040/libm881` for `-m68040 -m68881`;
- the pthread-heavy C++ link completed without a duplicate-COMDAT warning.

The first manual reproduction without the build's `TMPDIR` printed only
`collect2: error: ld returned 1 exit status`; a verbose retry linked cleanly.
This was another symptom of the exhausted host `/tmp` quota.  The official
gate passed with the build's workspace-local temporary directory.

## Host and QEMU regression results

Evidence is retained in
`open7-prod-b/regression-open7-20261106` outside the source repository.

- cost-model and hardening gates: passed;
- deterministic reproducer suite: passed both normally and with
  `-fno-tree-loop-distribute-patterns`;
- optimiser matrix: 32/32 CPU/profile combinations agreed on checksum
  `2472283987`;
- generated differential optimiser test: 192/192 cases passed;
- UBSan trap matrix: 120/120 cases passed;
- autoincrement scanner: 24/24 AmigaOS compilations passed;
- lean C++ profile: no forbidden exception, RTTI, constructor, guard or
  allocation dependency;
- baserel/resident exception links: all three modes passed, and 22
  libstdc++/libsupc++ archives contained no LDFCM sections;
- libnix self-call scan: 110 memory/calloc objects passed;
- GFOpenNDK validation: 20 `libamiga.a` copies were genuine and every
  advertised multilib selected its own copy;
- fpuauto: data dispatcher installed, 186 wrapped references, no code patch;
- provenance installer: passed with 39 applied build patches.

## Remaining release work

This prefix is suitable for payload compilation and runtime qualification.
It does not satisfy either clean-build reproducibility receipt.  Clean offline
AmigaOS builds, a full AROS SDK/runtime build, package comparison, and
AmigaOS/AROS/AC090 runtime evidence remain release gates.  Open7 must not be
published from this record alone.
