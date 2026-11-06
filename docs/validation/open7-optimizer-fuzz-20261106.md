# Open7 defined-behaviour optimiser fuzzing — 2026-11-06

## Purpose

Hand-written compiler regressions cover known failures but can miss interactions
between passes. `tests/optimizer/fuzz.py` deterministically generates distinct
freestanding C workloads using only defined `uint32_t` operations, legal fixed
shift counts and masked array indices. It compares each program at O0, O2, O3
and Os across 68000, 68020, 68040 and 68060.

This avoids a common differential-testing mistake: treating a disagreement
caused by undefined source behaviour as a compiler bug.

## Evidence

Command:

```sh
OUT=/tmp/open7-optimizer-fuzz-12 \
  python3 tests/optimizer/fuzz.py /tmp/open7-gcc-prefix/bin 12
```

Compiler frontend SHA-256:
`12521b133ccf0363695d680834b1effbf8e93c73d3dac552fef997478f120077`.

Result: 192 compile-link-execute cases, zero failures. All 16 builds for each
seed agreed, and the 12 seeds produced 12 distinct final checksums:

| Seed | Checksum |
|---|---:|
| `0x0a090000` | 1189261513 |
| `0x0a090001` | 422943604 |
| `0x0a090002` | 3077232258 |
| `0x0a090003` | 3454940778 |
| `0x0a090004` | 4041852404 |
| `0x0a090005` | 322397499 |
| `0x0a090006` | 228428160 |
| `0x0a090007` | 3252047818 |
| `0x0a090008` | 2120878185 |
| `0x0a090009` | 2769685706 |
| `0x0a09000a` | 2710865448 |
| `0x0a09000b` | 939857096 |

No optimiser defect was found in this batch. The generator, generated sources
and JSON receipt make any future mismatch reproducible. This is a QEMU compiler
correctness gate, not AC090 performance evidence.
