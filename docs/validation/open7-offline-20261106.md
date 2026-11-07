# Open7 offline build campaign — 2026-11-06

## Pinned inputs and isolation

The initial native pair, `open7-offline-repro-20261106-r2`, froze orchestration
at `206b866d97323399dff57fd46064cc1344a7c581` and used
`SOURCE_DATE_EPOCH=1793990361`. Each compilation started with eleven fresh,
verified pinned source checkouts, an empty build tree and an empty prefix.
The same absolute work/prefix paths were reused sequentially. No compiler
cache or previous compilation outputs were reused. Eight workers were used.

NDK input SHA-256:
`96cabd4ad683dced632e147bf86dee0f50dcb1254386216c25c362916a6409bb`.
The NDK remains excluded from release archives.

An inherited seccomp filter disabled `socket` and `connect` before source
preparation. Both IPv4 and IPv6 probes received `ENETDOWN`. This establishes
offline compilation even where the host refuses network namespaces.

## Initial pair and discovered defects

The first native build completed its build script, all target libraries and
all regression suites. The second completed compilation and target libraries,
then exited 141 in the validation script's early-closing `gcc -dumpspecs`
reader. Under `pipefail`, the unread tail sometimes kills GCC with SIGPIPE.
Commit `6c699926b37d25e4cf96f66fe2a839e65cab6e96` drains the complete stream;
its stress test also checks malformed specs and genuine compiler failures.
The second build's post-build validation and regression suites then passed
without recompiling the compiler. This is a recorded validation retry, not an
uninterrupted second build-script pass.

Both compilers passed the deterministic reproducers twice (default and loop
distribution disabled), 32 optimiser profiles, 192 generated differential
cases, 120 UBSan trap cases, 24 autoincrement builds, built-libnix end-pointer
tests, lean C++ and base-relative exception handling. Build checks also
covered 17 multilibs, stack-protector links, warning-free 68040/hard-float C++,
libnix self-calls, GFOpenNDK libraries, fpuauto and installed provenance.

Raw installed manifests contained 4,470 entries each. All compiler and normal
target-library bytes matched, but 18 entries differed:

- All 17 `libssp.a` archives embedded their random absolute temporary object
  paths in Hunk member names. `install-ssp.sh` now compiles/archives with
  relative `ssp.o` names from its selected object folder.
- Parallel upstream `install-info` invocations lost different entries from
  `share/info/dir`. The final build step now creates a complete index serially
  from all 13 installed manuals.

Commit `21d8cd08debc1638aa10694fe2c0e8091ddc5939` fixes both steps. Rebuilding
the affected components independently in both prefixes produced identical
complete manifests, including file modes, symlinks and hashes. Both corrected
prefixes again passed hardening links for all 17 multilibs. A Hunk-level
comparison confirmed that all 34 runtime payloads (17 per run) were unchanged
by removing the random member paths. Raw differences
and original copies of all 18 affected files remain in
`final-install-retry/` alongside the component rebuild logs.

The validation retry initially inherited umask 0002 rather than the campaign's
0022. The 68 mode-only differences were restored and recorded in
`validation-retry/umask-recovery.json`. File bytes were not changed by that
correction. Packaging now sets umask 0022 explicitly, canonicalises archive
permissions and excludes build scratch/Python caches. Original first-run
archives remain in `run-1/packages-original/`.

A packaging attempt failed because its script was changed while Bash was
executing it. The failed log remains preserved; the replacement uses the
immutable `packaging-frozen/` checkout. This packaging error is separate from
the compiled outputs and passed regressions.

The first corrected binary archives match at SHA-256
`0bf5a4d5072d9ee6f470bd3a65ace3f9f20504ccde69c64d09318f330038695d`.
Their source archives initially differed in six entries, all under
`projects/fd2sfd`: one build's checkout timestamps triggered automatic
regeneration of the tracked Autoconf 2.52 `configure` script using host
Autoconf 2.72. The other retained the tracked script. The remaining five
entries were the generated cache directory/files and `configure~` backup.

Commit `c288ff1` makes Autoconf regeneration an explicit build step and omits
its temporary cache/backup from packaging. Applying this preparation to both
source payloads produced the same `configure` SHA-256:
`48b66cb08a357efd91d69ba08c3203e211f413bdeaa330f170e3beda274b54c9`.
Fresh out-of-tree fd2sfd configure/compile runs produced identical host tools,
also matching both original installed binaries at SHA-256
`0a3a2e5145114a3566681c507a34349c6147e5875b234cd883db0943b92c4045`.
These preparation/build logs and hashes are in `autoconf-retry/`; the raw
source archive differences and earlier archives remain preserved. Source
archives refreshed after this step explicitly include regenerated build
configuration rather than claiming to be unchanged original payloads.

## Matching final artifacts

The corrected campaign completed with status `matched-after-recorded-fixes`.
All 4,470 installed entries match, including bytes, modes and symlink targets.
Both independently packaged artifact sets in `run-1/packages-qualified/` and
`run-2/packages-qualified/` have identical hashes:

| Artifact | SHA-256 in both runs |
| --- | --- |
| `gfopenamigagcc-16.2.0-open7-x86_64-linux.tar.xz` | `0bf5a4d5072d9ee6f470bd3a65ace3f9f20504ccde69c64d09318f330038695d` |
| `gfopenamigagcc-16.2.0-open7-src.tar.xz` | `f19f25f5373d5268808eeea125fb5a3b037bb5a8aa4f0d347faedf1bfb2340cc` |

Packaging froze `c288ff154cf7366b3fe5d118f4bb110b4d8380f7` and retained the
original epoch. `comparison.json` records the matching final hashes and the
earlier source mismatch. Both package logs passed the NDK exclusion and
GFOpenNDK/provenance checks. These are candidate artifacts, not a published
release or a substitute for the outstanding runtime gates.

## Fresh uninterrupted confirmation

A new pair, `open7-offline-repro-20261106-r3`, started at 21:20 UTC from the
fixed `21d8cd0` recipe with 12 workers. It regenerates every component from
fresh sources, runs the complete validation sequence and compares installed
manifests and final archive hashes automatically. Its `status.json` and
`comparison.json` are authoritative. At the time of this entry it is running;
the repaired initial pair is not counted as two uninterrupted full-script
passes.
This confirmation pair froze before the later fd2sfd preparation change;
the latter has the separate clean component rebuild evidence above.

### What happened to r3

r3 stopped at 22:23 UTC with status `failed`, stage `run 1: repro` and error
`[Errno 32] Broken pipe`. Run 1's full build had completed; `repro.log` was
never created. The runner raised the error itself, printing its next stage
line to a stdout pipe whose reader had gone with the session that started
it. It was a harness fault, not a regression: commit `d9ff412` records
progress in `progress.log` and treats the console as best effort. See
[the runtime record](open7-runtime-20261107.md#the-r3-confirmation-failure).

## Fresh confirmation pair (7 November)

`open7-offline-repro-20261107-r6` on amigachromebuild (12 cores, 10
workers) froze orchestration at `a0a648a`, which includes the harness fix,
the fd2sfd preparation, the 68040 maths seed fix (`5ba51d6`) and the stack
guard mixing (`aee05df`). It uses the same pinned source commits from a
local mirror and the same NDK input
(`96cabd4ad683dced632e147bf86dee0f50dcb1254386216c25c362916a6409bb`),
with the same socket-disabling filter. Two earlier attempts on 7 November
(r4 and r5) were stopped by us when the runtime runs found the 68040 maths
and stack guard defects, so that the pair would build the corrected tree.

Status: running at the time of writing.

## AROS and remaining release work

The separate clean AROS full-SDK offline build passed uninterrupted at
21:08:53 UTC. See [the AROS receipt](open7-aros-libgcc-20261106.md).

Runtime qualification on AmigaOS, AROS and the AC090 instance, including
the deliberate canary corruption, is recorded in
[open7-runtime-20261107.md](open7-runtime-20261107.md). An AC090
elapsed-time matrix is needed only before a future optimisation default
change; Open7 changes none.
