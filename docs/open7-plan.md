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

The same integration exposed a long-standing `libnix4.library` failure that
earlier builds ignored. A misspelled object exclusion admitted two
`__vfwprintf_total_size` implementations. Patch `0009` corrects the list, the
shared library now links and installs, and a missing or failed libnix4 target
is fatal to the build.

A fresh Open7 AROS compiler bootstrap has also completed from the pinned GCC,
binutils, isl and AROS commits. All seven selected AROS patches applied and 24
autoincrement combinations passed. Because that build intentionally had no
AROS SDK, the full target libraries and runtime qualification remain open.

Compiling the AmigaOS runtime payloads then exposed a further AC090 gap:
`-m68040 -m68881` currently selects the `68020 + 68881` libstdc++ multilib.
Equivalent inline COMDAT code can therefore differ byte-for-byte (`addaw`
versus `lea` for the same stack adjustment), which makes the hunk linker emit
duplicate-section warnings. Patch `0018` now defines six dedicated 68040
variants while deliberately keeping compatibility-range targets on 68020;
ABI-compatible 68020 C runtimes are installed into matching 68040 directories
while GCC builds the CPU-sensitive libraries for 68040. The regression gate
checks all seventeen directories, exact library selection and a warning-free
C++ link. That implementation still needs a clean full build before the AC090
profile is qualified. The second reproducibility build and AmigaOS/AROS/AC090
runtime evidence also remain release qualification work.

The first empty-build-tree attempt with patch `0018` stopped before GCC when
the host compiler exhausted the account quota on `/tmp`; fd2sfd's generated
Makefile was truncated and binutils' MPFR probe consequently failed. Builds
now place host temporary files inside their exclusively locked work folder.
That aborted attempt is not clean-build evidence and must be restarted.

The already-patched retry completed all target libraries, the fatal libnix4
gate and the seventeen stack-protector runtimes. Its first multilib check found
that the ABI-compatible C-runtime seed covered `libm040` but not the nested
hard-float `libm040/libm881` search directory. The seed now covers soft and
hard float for plain, baserel and baserel32. The corrected integration prefix
passes the warning-free pthread-heavy C++ link, both deterministic reproducer
passes, 32 optimiser profiles, 192 generated differential cases, 120 UBSan
trap cases, 24 autoincrement builds, lean C++, baserel EH, 110 libnix self-call
checks, all per-multilib libamiga checks, fpuauto installation and provenance.
This remains integration evidence rather than a clean-build receipt; the two
clean offline builds and runtime qualification are still open.

A clean AROS compiler/target-library build against an isolated complete SDK
also completed all seven libgcc, libstdc++ and libatomic variants. Its final
C++ gate exposed a host-only quota defect: collect-aros ignored `TMPDIR` and
always wrote a large intermediate link below `/tmp`. The AROS patch series now
makes collect-aros honor `TMPDIR`, and the AROS build supplies a work-folder
default. Rebuilding that host tool made the 68040 C++/pthread/atomic link pass;
all seven helper audits and 24 autoincrement cases pass. Because the host tool
was corrected after the clean target-library run, one uninterrupted clean
rerun of the eight-patch AROS series and AROS runtime execution are still open.
