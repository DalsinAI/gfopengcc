# Open7 runtime qualification — 2026-11-07

This records the runtime gates in [the release notes](../releases/16.2.0-open7.md):
programs from the Open7 compiler run on AmigaOS 3.2.3, on the AmiCradle AC090
instance and on AROS 68k, including a deliberate canary corruption. It also
records the defect the runs found and its fix, the settled r3 confirmation
failure and supporting evidence from the local CI.

## Machines

All three are labs (scratch copies) on daletop's Cradle, running the AC090
engine (`ac090-native`). No live instance was changed.

| Lab | Copied from | System as the Amiga reports it | CPU |
| --- | --- | --- | --- |
| `open7-rt-ks323` | Instance-23, "OS 3.2.3 Validation" | Kickstart 47.115 (3.2.3), exec.library 47.13, Workbench 47.5 | 68040 68882 68040-MMU |
| `open7-rt-os32` | Instance-32, "Games Workshop" (the AmigaChrome AC090 instance) | GFOpenExec 47.13 (open Kickstart 47.2), Workbench 47.100 | 68040 68882 |
| `open7-rt-aros` | Instance-22 (AROS 68k, archived) | AROS Kickstart 51.51, exec.library amiga-m68k 51.9 | 68020, no FPU, reference timing |

## Compilers and programs

The programs are `tests/runtime/` (see its README), built by
`tests/runtime/build.sh`.

AmigaOS: Team 1's qualified offline prefix
(`open7-offline-repro-20261106-r2/run-1/prefix`), with the two runtime
corrections below applied exactly as the build now applies them (the
`libm040` seed of commit `5ba51d6`, and `libssp.a` rebuilt by
`scripts/install-ssp.sh` at `aee05df`). The fresh confirmation pair below
builds the same tree from scratch.

AROS: the clean offline AROS prefix (`open7-aros-offline-20261106/prefix`,
orchestration `45e57f6`). Later commits change no AROS compiler input
(`scripts/build-aros.sh` changed only how it reads `--version`).

Program SHA-256 (AmigaOS):

| Program | SHA-256 |
| --- | --- |
| `c_basic-000` | `c84294f855586613d489fcf37eaeba5b825fa6cfc42fbcecb610aa2b49097946` |
| `c_basic-020` | `62c69dd9c9ccf5d8eed5bbed397d7f2e4f9a90cffd618ead6f0f35ff32dc0ee9` |
| `c_basic-040` | `bb1596ba4b85968930f46b2e9716d383c8faaf55d3f65ff6fdaf571716da9e57` |
| `c_basic-040auto` | `2f8f13403f4bf76ee2ae677d95e651ba4756652f96c320bbf36f0aec6775ef5f` |
| `c_basic-040br` | `5b0c74a38bd3e8ea449afeb80151c5e4cba2a4328ccc26046a4da82ae9d29fb8` |
| `cxx_eh_threads` | `691b5a5cd56ffa16859b6548a7483fb33f6354e93eded60ce318e3587e03e7e6` |
| `ssp_canary-000` | `4e0b65f20f1a9a33eb8cea1376f2c12b2d13c51ffadc8795ab15186c9cc0cb30` |
| `ssp_canary-040` | `417af970fd0d50ed521da20f11688aef5ce667f8e8972abea06e0fe9d6347d26` |
| `ubsan_trap-040` | `7f4c10deb77dff4f0cdcc8888e91e15dec1c52f0868406b7d8281f3408909c07` |
| `FPUAutoBench-auto` | `b956b411c1c14fb04be9b623d28bbf7acbe0056e638ab3c8ad6cc16f54d35560` |
| `FPUAutoBench-plain` | `ab07b801ad6ca3623178ed874dd76a4d99251d241b30d3c45de487ac1ce25f90` |
| `FPUAutoBench-hard` | `bafc1135125be7f2cf8b0b4334c4a5752ee634ba072fec7f35b84e7eea34c11a` |

AROS (`-m68020 -msoft-float -O2`, for the lab's FPU-less 68020):
`c_basic-020soft` `78ee74c716af375454b91d178e68e5434b042626452d4bf319110a8d63a041ee`,
`cxx_eh_threads-020soft` `1b7a263d6da20f0365d30688ab170108a6f281c249b8bceb89e0be75fc1cd862`,
`ubsan_trap-020soft` `4aa013bf565037f39931d2760991396a5193cc80ff0338112b22d8070c4793fc`.

## Defect found: `-m68040 -m68881` linked soft-float maths

The first AmigaOS run of `c_basic-040` (`-m68040 -m68881`, the AC090
profile) failed its `sin` and `exp`/`log` checks on the AC090 instance. A
probe printed the same wrong value for `sin(0.5)`, `log(2)`, `exp(1)` and
`cos(0.5)` (`-2.4794255386042026` on the first boot, `NaN` on the next).

`scripts/build.sh` seeds the new `libm040` C-runtime folders from libnix's
68020 build. It copied the soft-float `libm020` files into both `libm040`
and `libm040/libm881`. A hard-float link searches `libm040/libm881` first and
so took the soft `libm.a`, whose routines return doubles in `d0`/`d1`; the
caller reads `fp0`. In `libm020/libm881`, `_sin` ends with
`fmoved sp@+,%fp0`; in the shipped `libm040/libm881` it did not. The same was
true for the base-relative variants. Open6 had no `libm040` and is not
affected.

On Kickstart 3.2.3 the broken programs happened to print correct results:
that system's maths library leaves its result in `fp0` as well as `d0`/`d1`.
On the open Kickstart it does not. The ABI mismatch is a defect either way.

Commit `5ba51d6` seeded each `libm040` folder as an exact copy of its
`libm020` folder. The first confirmation build (r6) then showed that
`libm040/libm881` must also hold libnix and libpthread themselves:
`tests/amigaos-multilib.sh` found `-m68040 -m68881` taking the 68000
`libpthread.a`. The final seed gives `libm040/libm881` the 68020 files with
`libm020/libm881`'s hard-float members on top, checks each file against its
source, and the build now fails unless a hard-float `sin` returns in `fp0` for 68020,
68040 (plain, `-fbaserel`, `-fbaserel32`) and 68060. Before the fix, 68040
hard float and both base-relative variants returned in `d0`/`d1`; after it,
all return in `fp0` and take `libnix.a` from their own `libm040/libm881`
folder, and `-m68040` soft float still (correctly) uses `d0`/`d1`. Every
runtime program was rebuilt with the final seed; all are byte-identical to
the ones that ran (hashes below).

Team 1's matched r2 archives (`0bf5a4d5...`) and the
`os32-gcc16-16.2.0-open7-candidate` stove on amigachromebuild contain this
defect and must not be published or promoted.

## Results

### AmigaOS 3.2.3 (Kickstart 47.115)

| Test | Result |
| --- | --- |
| `c_basic` 000, 020+881, 040+881, 040 fpuauto, 040+881 base-relative | `c_basic OK`, rc 0 each |
| Before the fix: `before/c_basic-040` | `c_basic OK` (masked, see above) |
| `cxx_eh_threads` three times | `cxx_eh_threads OK (destructors 11, total 10000, thread catches 4)`, rc 0 each |
| `ssp_canary-040 ok`, `ssp_canary-000 ok` | `ssp control OK`, rc 0 |
| `ssp_canary-040 smash`, `ssp_canary-000 smash` | `Program aborted`, rc 127; `ssp NOT DETECTED` never printed |
| `ubsan_trap-040 ok` | `ubsan control OK`, rc 0 |
| `ubsan_trap-040 overflow` | Software Failure requester: "ubsan_trap-040 Program failed (error #80000027)" (exception vector 39, `trap #7`); nothing printed |
| `FPUAutoBench-auto` | `fpuauto: FPU`; sums 76330846 c8788fb3 b9f1ce28 16c825cf b99ed337 |
| `FPUAutoBench-auto 200000 s` (forced soft path) | the same five sums |
| `FPUAutoBench-plain` | the same five sums |
| `FPUAutoBench-hard` | the same first four; `corners` 7128cbd0 (inline FPU conversion of NaN/out-of-range values, by design) |

### AC090 instance (Instance-32 copy, open Kickstart)

| Test | Result |
| --- | --- |
| Before the fix: `before/c_basic-040`, `before/o7diag-040` | `FAIL sin`, `FAIL exp/log`, rc 10; every result printed as the same stale value |
| After: probe | `sin(0.5)=0.47942553860420301`, `log 2=0.69314718055994529`, `exp(1)=2.7182818284590451`, `cos(0.5)=0.87758256189037276` |
| `c_basic` 000, 020+881, 040+881, 040 fpuauto, 040+881 base-relative | `c_basic OK`, rc 0 each |
| `cxx_eh_threads`, seven runs (before and after `std::function` was added) | `OK`, rc 0 each |
| `ssp_canary` ok / smash, 68000 and 68040 | `ssp control OK` rc 0 / `Program aborted` rc 127 |
| `ubsan_trap-040 ok` / `overflow` | `ubsan control OK` / the process stops at the trap and stays listed by `Status`, nothing printed (GFOpenExec parks a trapped task instead of showing a requester) |
| `FPUAutoBench` auto / forced soft / plain / hard | `fpuauto: FPU`; identical sums for auto, soft and plain; hard differs only in `corners` |

Timings on the AC090 vary with host load and are not a performance
qualification: fpuauto's FPU path took 0.037 s for mandel against 0.080 s
for plain soft float, and 0.015 s with `-m68881`.

### AROS 68k

`ACAgent`'s `Execute ... >file` did not capture output on AROS, so the lab ran
`SYS:Open7RT/run-tests` from `S:User-Startup` at boot, each command
redirecting into `SYS:Open7RT/out.txt`:

| Test | Result |
| --- | --- |
| `c_basic-020soft` | `c_basic OK`, rc 0 |
| `cxx_eh_threads-020soft` twice | `cxx_eh_threads OK (destructors 11, total 10000, thread catches 4)`, rc 0 |
| `ubsan_trap-020soft ok` | `ubsan control OK`, rc 0 |
| `ubsan_trap-020soft overflow` | AROS Software Failure requester for the program; its output file stayed empty and `Status` still listed it |

Not covered on AROS:

- Stack protector: `m68k-aros` installs no stack-protector runtime. A
  `-fstack-protector-strong` link fails with `__stack_chk_fail` and
  `__stack_chk_guard` undefined. The runtime is AmigaOS-only, as the release
  notes say.
- fpuauto is a libnix (AmigaOS) feature.
- Hard-float AROS programs: the only AROS 68k lab is a 68020 without an FPU.

## Stack guard entropy

The first runs printed different guards whose lowest five bits never
changed: `01001` in all eleven runs on the AC090 instance, `00101` in all
four on Kickstart 3.2.3: the guard's inputs (time, a stack address, ExecBase) change
little in their low bits and the final multiplication cannot move entropy
down. Commit `aee05df` folds the high half back into the low bits; later
guards vary in every nibble below the always-zero top byte. Two runs started
in the same timer tick at the same stack address still get the same guard
(seen once on Kickstart 3.2.3): the guard stops ordinary overruns; it is
not a secret against a local attacker who can observe timing.

## C++ link at the AC090 profile

`cxx_eh_threads` (exceptions, `std::function`, `std::thread`,
`condition_variable`, `thread_local`, `exception_ptr` across threads) compiled
and linked with `-m68040 -m68881 -O2 -fomit-frame-pointer -std=gnu++23
-lpthread -latomic` with no output at all, and the same link with
`-Wl,--fatal-warnings` produced identical bytes. This holds before and after
the `libm040` fix.

## The r3 confirmation failure

`open7-offline-repro-20261106-r3` stopped at 22:23 UTC on 6 November with
`[Errno 32] Broken pipe` in stage `run 1: repro`. Its full build had finished
(`build.log` ends with "GFOpenAmigaGCC built in ..."), and `repro.log` was
never created: no compiler or test ran in that stage. The error came from the
runner's own `print` of the next stage line, to a stdout pipe whose reader
had gone when the session that started it stopped. Python reports exactly
this (`BrokenPipeError: [Errno 32] Broken pipe`) when it prints to a closed
pipe; a test reproduced it.

This was a harness fault, not a regression. Commit `d9ff412` writes progress
lines to `progress.log` in the record and only best effort to the console,
for both the AmigaOS and AROS runners; with a closed stdout the runner keeps
going. The confirmation pair is re-run in the next section.

## Fresh confirmation pair

See [the offline receipt](open7-offline-20261106.md#fresh-confirmation-pair-7-november).

## Supporting evidence from the local CI

On 6 November a release-shaped candidate stove
(`~/AmigaChrome/stoves/os32-gcc16-16.2.0-open7-candidate` on
amigachromebuild), built from Team 1's integration prefix with the NDK 3.2
trees removed and the open NDK headers carried as `package.sh` ships them,
built and tested all 15 repositories the local CI watches
(`amicradle-ci` T0-T2) green, including amicradle-guest's 68k tests and 12
game ports, and `amicradle-ci stove verify` (the GCC 15 m68k autoincrement
wrong-code probe) was clean. That stove predates `5ba51d6` and has the soft
`libm040/libm881/libm.a`, so those runs did not exercise libm results at the
AC090 profile; they remain evidence for the rest of the toolchain.
