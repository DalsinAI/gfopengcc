# Open7 UBSan trap validation — 2026-11-06

## Defect and candidate

The recovered Open7 compiler rejected even
`-fsanitize=undefined -fsanitize-undefined-trap-on-error`. The cause was the
unconditional `flag_sanitize` rejection in `gcc/config/m68k/amigaos.h`.
Patch 0017 permits only undefined-behaviour checks whose enabled sanitizer
bits all request trap mode. Checks that require a sanitizer runtime remain
rejected. This is an application opt-in; release defaults do not change.

## Evidence run in the resumed session

- Repository baseline: `e992cbd` on `team1/open7-determinism`, with patch 0017
  added. This follows the determinism, AROS, fpuauto, hardening, identity and
  optimiser commits recovered from the preceding session.
- Baseline preflight reproduced the target rejection.
- Candidate: the existing Open7 development compiler's target translation
  unit was rebuilt and linked into a separate `cc1`. To avoid modifying the
  shared source/build tree while the recovered work was still progressing,
  the patched `SUBTARGET_OVERRIDE_OPTIONS` macro was expanded at its single
  call site in a temporary copy of `m68k.cc`. The other compiler objects were
  unchanged. This is equivalent at that call site, but is not a clean full
  compiler build applying patch 0017 through the production build script.
- Tested frontend SHA-256:
  `987052329f56f8e36a3c16ba41ad471cde5e8dcdea80f73518bef1ec2aa8a35a`.
- 120 executable tests passed: five CPU/ABI profiles, four optimisation
  levels, and six cases per combination. All 20 valid controls returned zero;
  all 100 deliberately invalid cases stopped with SIGILL. A different crash
  signal would fail the test.
- The five invalid cases cover signed overflow, excessive shift count,
  division by zero, out-of-bounds array access and null dereference.
- Four unsupported-mode controls passed: ordinary UBSan without traps,
  ASan even with trap-all, TSan, and a partially trapped UB selection were
  all rejected.
- No instrumented object referred to a UBSan handler. The raw QEMU harness
  linked a freestanding division helper, with no target library, sanitizer
  runtime or AmigaOS startup. The 68040 FPU profile checks option/ABI
  compatibility of these integer probes, not floating-point instrumentation.

Command:

```sh
OUT=/tmp/open7-ubsan-committed-20261106 \
python3 tests/ubsan-trap/check.py /tmp/tmp.fYlQ2a4xsT/prefix/bin \
  -B/tmp/open7-ubsan-candidate/ -B/tmp/open7-resume-tools/ \
  -specs=/tmp/open7-specs -fno-use-linker-plugin
```

The baseline was a disposable complete Open6 prefix plus the rebuilt Open7
driver and candidate frontend. Plugin use was disabled for this mixed
development prefix. The test and its evidence upload are now part of the
full-build CI workflow, where no candidate overrides are supplied.

The resumed session also reran `tests/hardening/check.sh` with the rebuilt
Open7 frontend: all four stack-protector modes linked, all 11 multilibs
linked the strong-protector probe, and `-fhardened` stopped in the driver.

## Remaining qualification

The production build must apply patch 0017 and pass the same matrix without
development overrides. AmigaOS/AROS/AC090 exception handling, C++ sanitizer
behaviour and the broader ABI cases remain separate gates. GCC's aggregate
trap setting disables C++ vptr instrumentation. This receipt does not claim
ASan support, a sanitizer reporting runtime, or an Open7 release qualification.
