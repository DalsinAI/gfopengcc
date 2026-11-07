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

## Corrected integration result

Commit `3e1d37a` was applied to the fresh work folder after the overlapping
legacy invocation had cleared. The successful GCC/binutils bootstrap was
retained; the patched GFOpenNDK stage and every later build stage were rerun.
The completed integration reported:

- eleven warning-free GFOpenNDK archives, all selected from their own
  multilib folders;
- eleven stack-protector runtimes with all three required symbols;
- deterministic cost-model and hardening checks passed;
- 50 libnix memory/calloc objects checked with no recursive block call;
- multicore-safe `fpuauto` installed with 186 wrapped references and no code
  patch/cache flush;
- 37 applied build patches and every resolved source head installed in the
  provenance bundle.

The post-build host/QEMU checks also passed:

- both Open6 reproducer runs, with and without loop-distribution patterns;
- 32 optimiser CPU/profile combinations with checksum `2472283987`;
- 192 defined-behaviour differential optimiser executions;
- 120 trap-mode UBSan executions across five CPU/ABI profiles;
- 24 autoincrement compiles, fourteen strtol/strtoul controls, lean C++ and
  all base-relative exception/archive checks.

This proves that the corrected integration can complete from the fresh source
set. Because the build was resumed after the race fix rather than restarted
from an empty build directory, it does not satisfy the first of the two
uninterrupted reproducibility builds required for release.

## Newly exposed 68040 multilib gap

Six AmigaOS-only runtime payloads compiled successfully for
`-m68040 -m68881`, but four C++ links warned that
`.text._ZNSt14_Function_baseD2Ev` had different contents in the application
and libstdc++'s `mutex.o`. The application used `addaw #12,sp`; the library
used `lea sp@(12),sp`. Both are equivalent and the isolated 68020 link was
warning-free, but the result confirms that 68040 applications currently reuse
the `libm020/libm881` library built for 68020.

No runtime wrong-code was demonstrated. The warning and missed 68040 library
optimisation remain an explicit AC090 qualification gap rather than being
waived silently.

## Shared libnix defect exposed after integration

The integration log also showed that `libnix4.library` still failed while the
build deliberately ignored its status. `preplib` excluded the nonexistent
`__vwfprintf_total_size.o` rather than `__vfwprintf_total_size.o`. The normal
helper and the math library's deliberate `FULL_SPECIFIERS` copy consequently
produced duplicate C exports and a duplicate linker definition.

Open7 patch `0009` corrects that source list. The real shared-library rebuild
then completed, installed a 210,484-byte `libnix4.library`, and `nm` found one
code definition of `__vfwprintf_total_size`. `scripts/build.sh` now stops if
the target fails or either the shared library or static support archive is
missing; `tests/libnix4-source-list.sh` preserves the source-list invariant.
This repairs a limitation recorded in the Open2 through Open6 release notes.

## Host temporary-directory failure

The first empty-build-tree attempt after adding the dedicated 68040 multilibs
stopped before GCC. The host compiler exhausted the account quota on `/tmp`
while configuring fd2sfd: `config.status` could not finish its Makefile, and a
parallel binutils configure then misreported the working host GCC and MPFR as
unsupported. The build volume still had 18 GiB free, so this was not evidence
of a source or compiler failure.

`scripts/build.sh` now defaults `TMPDIR` to a directory inside its exclusively
locked work folder while still honoring an explicit caller setting. The
aborted build is retained as failure evidence and does not count as either
required uninterrupted reproducibility build.
