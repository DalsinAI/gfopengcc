# GFOpenAmigaGCC 16.2.0-open7 plan

Open7 closes the correctness, reproducibility and hardening gaps found in the
Open6 audit before changing the default optimisation profile. Open6 remains
the comparison baseline.

## Release gates

### Determinism and provenance

- Cost-model overrides are accepted only through an explicit mechanism.
- Identical inputs and options generate identical code from every directory.
- Every applied patch and source commit is preserved in the installed
  provenance bundle and source release.
- Two clean offline builds reproduce after normalising release timestamps.

### Correctness

- The Open6 reproducer suite remains green.
- AROS C++ links at `-m68040` without an unresolved `__divsi3`, and every
  advertised multilib contains the selected integer runtime helpers.
- ABI tests cover structures, packed data, varargs, 64-bit arithmetic,
  nested functions, base-relative code, resident code and both float ABIs.
- Generated programs agree at `-O0`, `-O2`, `-O3` and `-Os` for every
  supported CPU profile.

### Runtime safety and hardening

- `fpuauto` uses a multicore-safe data dispatch path and never modifies code;
  the compiler build pins, installs and validates that source.
- `-fstack-protector-strong` has a libnix guard and failure path.
- `-fhardened` selects only supported Amiga protections or stops with one
  clear diagnostic.
- Trap-mode undefined-behaviour instrumentation is assessed and enabled if
  it can be supported without an unsuitable target runtime.

### AC090 performance

- The initial candidate profile is `-O2 -m68040 -m68881 -flto`.
- `-O2`, `-O3`, `-Os`, LTO and selected floating-point relaxations are
  measured using real applications on the same AC090 instance.
- No new default flag is accepted without a correctness comparison and a
  repeatable runtime or size improvement.
- A distinct `-mtune=ac090` is considered only after the representative
  workload corpus produces a stable cost table.

## Delivery order

1. Deterministic cost model and patch provenance.
2. AROS multilib/libgcc repair and expanded ABI tests.
3. Multicore-safe `fpuauto`.
4. Stack protector and hardened driver behaviour.
5. AC090/LTO benchmark programme and profile selection.
6. Generated differential-testing campaign.
7. Two reproducible builds and AmigaOS, AROS and AC090 runtime qualification.

An unfinished item is either fixed, explicitly unsupported, or recorded as a
deferred issue with a reproducer. Open7 will not inherit a silent known-issue
list.

## Current development state

The deterministic cost model, installed provenance, multicore-safe fpuauto,
stack-protector runtime, explicit unsupported `-fhardened` diagnostic and
trap-mode UBSan have candidate implementations with host/QEMU receipts.
Native validation covers seventeen target-library variants, warning-free
68040/hard-float C++ links, 32 optimiser profiles, 192 generated differential
cases, 120 UBSan trap cases, 24 autoincrement builds and the existing libnix,
lean C++ and base-relative exception suites. The shared libnix4 installation
is a fatal build gate and now passes.

The clean AROS full-SDK offline rerun passed uninterrupted on 2026-11-06:
GCC, collect-aros, all seven libgcc/libstdc++/libatomic variants, the 68040
C++/pthread/atomic link, integer-helper audits and 24 autoincrement scans.
See [the AROS receipt](validation/open7-aros-libgcc-20261106.md).

Two native offline compilations completed. The second required a validation
reader correction for SIGPIPE. Comparing their 4,470-entry installed prefixes
then exposed random Hunk member paths in seventeen SSP archives and a racy
Info index. Correcting and independently rebuilding those components made
the complete prefixes identical. A fresh pair using the fixed recipe from
the outset is running as `open7-offline-repro-20261106-r3`; the repaired pair
is not counted as two uninterrupted full-script passes. See
[the offline campaign receipt](validation/open7-offline-20261106.md).

AmigaOS, AROS and AC090 runtime qualification, the broader ABI execution
corpus, deliberate stack-canary corruption and representative AC090 runtime/
size measurements remain open. No optimisation default or release readiness
claim is justified by the offline compiler checks alone.
