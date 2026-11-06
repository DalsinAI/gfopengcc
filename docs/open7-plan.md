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

Items 1–6 have candidate implementations and host-side validation receipts.
That includes the deterministic cost model, AROS helper coverage,
multicore-safe `fpuauto`, all four stack-protector modes, an explicit
`-fhardened` diagnostic, trap-mode UBSan, the 32-profile optimiser matrix and
192 defined-behaviour differential executions.

The first item 7 clean integration attempt exposed two build-system gaps: the
work folder admitted concurrent builds, and OpenNDK's per-multilib library
builder passed a hardcoded `-m68040` before the selected CPU while compiling
1,303 objects serially. Open7 now has an exclusive work-folder lock and a
provenanced GFOpenNDK patch that selects one CPU and uses bounded parallel
compilation. The corrected integration completed from the fresh source work
folder and passed the host/QEMU regression matrices.

Compiling the AmigaOS runtime payloads then exposed a further AC090 gap:
`-m68040 -m68881` currently selects the `68020 + 68881` libstdc++ multilib.
Equivalent inline COMDAT code can therefore differ byte-for-byte (`addaw`
versus `lea` for the same stack adjustment), which makes the hunk linker emit
duplicate-section warnings. Open7 needs a dedicated 68040 multilib, or another
demonstrably safe warning-free design, before the AC090 profile is qualified.
An uninterrupted clean build, the second reproducibility build and
AmigaOS/AROS/AC090 runtime evidence also remain release qualification work.
