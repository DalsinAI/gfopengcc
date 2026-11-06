# Open7 clean-build race and GFOpenNDK validation — 2026-11-06

This records a clean offline AmigaOS integration attempt and the two build
defects it exposed. It is development evidence, not an Open7 release
qualification.

## Inputs

- GFOpenAmigaGCC branch `team1/open7-determinism`, starting at `361ac6b`.
- Fresh work folder populated from the canonical Open6 cache on the DevDrive.
- All eleven repositories matched `scripts/sources.lock`, including local
  `amicradle-guest` commit `e62e5c24`.
- AmigaOS NDK 3.2 archive from the canonical Open6 work folder.
- Build command: `scripts/build.sh WORK PREFIX NDK3.2.lha 8`.

Binutils, GCC, gprof, libnix and every libpthread variant built and installed.
The integration build then reached the eleven per-multilib GFOpenNDK archives.

## Concurrent-work-folder failure

A second build entered the same work folder while the first was compiling the
`libm060` archive. Its plain-archive log was truncated at the same timestamp
that the first build failed, and new objects continued appearing after the
first process had exited. Both invocations used GFOpenNDK's shared
`OpenNDK/lib/build/m68k-amigaos/obj` folder. The first build consequently
failed when GAS could not create an object in the directory removed by the
other invocation.

`scripts/build.sh` now takes a non-blocking `flock` on
`WORK/.gfopenamigagcc-build.lock` before changing any source or output. A
controlled lock-holder test made a second invocation stop immediately with
exit status 1 and the diagnostic `another GFOpenAmigaGCC build is using ...`.

## Contradictory CPU options

GFOpenNDK's builder hardcoded `-m68040`; the outer build then appended the
selected multilib CPU. For the 68020 library, `-###` showed both cc1 and GAS
receiving `-m68040` followed by `-m68020`. GAS emitted repeated mixed CPU/MMU
warnings. The Open7 GFOpenNDK patch removes the hardcoded CPU; the outer build
already supplies one explicit CPU for every multilib, including `-m68000` for
the default variants.

A patched isolated 68020 archive built all 1,303 objects without those
warnings. A same-directory serial-before/parallel-after comparison found:

- 1,301 objects byte-identical;
- `argarray.o` and `rand.o` with identical instructions, symbols, sections,
  architecture and relocation sets;
- the only difference in those two objects was relocation-record order.

No wrong instruction was demonstrated, but eliminating contradictory target
options removes an ambiguous and noisy source of non-reproducibility.

## Build-time result

The original builder compiled 1,303 objects serially for each of eleven
multilibs. The patch accepts a positive `JOBS` value and waits for bounded
batches while preserving the archive's sorted member order and failure
propagation.

- Patched 68000 archive, eight jobs and no competing build: 22 seconds.
- Patched 68020 archive, eight jobs while the legacy integration build was
  competing for CPU: 39 seconds.
- Legacy serial archives observed in the integration log: approximately
  63–129 seconds, with FPU variants slowed further by warning output.

The corrected full integration build and final per-multilib instruction scan
remain required before this gate is closed.
