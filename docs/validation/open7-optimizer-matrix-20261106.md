# Open7 optimiser matrix — 2026-11-06

## Scope

This is a compiler correctness and linked-code-size screen. It is not an
AC090 speed result. The Open7 compiler built from local commit `6503d2e` was
used to compile a defined-behaviour workload for 68000, 68020, 68040 and 68060.
Each CPU was tested at eight optimisation profiles and executed with its
matching `qemu-m68k` CPU. The test compiler identified itself as the temporary
development build `GFOpenAmigaGCC 16.2.0-open7-dev`.

Command:

```sh
OUT=/tmp/open7-optimizer-5 \
  tests/optimizer/check.sh /tmp/open7-gcc-prefix/bin
```

## Result

All 32 binaries returned checksum `2472283987`. No differential compiler
failure was found.

Linked `.text` bytes:

| CPU | O0 | O2 | O3 | Os | O2 LTO | O3 LTO | O2 LTO whole | O3 LTO whole |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 68000 | 1700 | 1200 | 2420 | 1152 | 1212 | 2452 | 1180 | 2420 |
| 68020 | 1536 | 1152 | 2416 | 1108 | 1160 | 2436 | 1128 | 2408 |
| 68040 | 1532 | 1148 | 2256 | 1104 | 1152 | 2280 | 1124 | 2248 |
| 68060 | 1524 | 1124 | 2256 | 1092 | 1128 | 2268 | 1096 | 2240 |

## Findings

- `-Os` is 2.8–4.0% smaller than `-O2` on this workload.
- `-O3` is roughly twice the size of `-O2`; that expansion needs AC090 timing
  evidence before it is used for release defaults.
- Plain `-flto` is 0.3–1.0% larger than its non-LTO peer and retains the hot
  external function. The Amiga hunk link does not provide enough closed-world
  resolution to unlock cross-unit inlining in this test.
- `-flto -fwhole-program` removes that limitation and makes the O2 result
  1.7–2.5% smaller than ordinary O2. It is an application opt-in, not a safe
  compiler default: callbacks reached from outside the visible link graph must
  be marked `externally_visible`.

The release default remains `-O2`. The next performance gate is elapsed-time
and stability testing on the agreed AmigaChrome AC090 runtime using matched
O2, Os, O3 and O2-LTO-whole application builds.
