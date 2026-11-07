# Runtime qualification programs

Small programs for running an Open7 compiler's output on a real AmigaOS (and,
for the C and C++ programs, on AROS 68k). `qemu-m68k` user mode cannot run
them: they need exec tasks, dos.library, the maths libraries and the CPU's
exception handling.

```sh
tests/runtime/build.sh /path/to/prefix/bin OUT [amicradle-guest/common/fpuauto/FPUAutoBench.c]
```

builds into `OUT`:

| Program | Built with | Expected on the Amiga |
| --- | --- | --- |
| `c_basic-000`, `-020`, `-040`, `-040auto`, `-040br`, `-060` | `-m68000`; `-m68020 -m68881`; `-m68040 -m68881`; `-m68040` (soft float, fpuauto); `-m68040 -m68881 -fbaserel`; `-m68060` | `c_basic OK`, rc 0 |
| `cxx_eh_threads` | `-m68040 -m68881 -O2 -fomit-frame-pointer -std=gnu++23 -lpthread -latomic` (the AC090 profile) | `cxx_eh_threads OK ...`, rc 0 |
| `ssp_canary-040`, `-000` | `-fstack-protector-strong` | `ok`: `ssp control OK`, rc 0. `smash`: `Program aborted`, rc 127, and never `ssp NOT DETECTED` |
| `ubsan_trap-040` | `-fsanitize=undefined -fsanitize-undefined-trap-on-error` | `ok`: `ubsan control OK`. `overflow`: the program stops at `trap #7` (AmigaOS: "Program failed (error #80000027)"), never `ubsan NOT TRAPPED` |
| `FPUAutoBench-auto`, `-plain`, `-hard` | `-m68040` with fpuauto; `-DNO_FPUAUTO`; `-m68881` | the same checksums from `auto` (FPU path), `auto 200000 s` (forced soft path) and `plain`; `hard` differs only in `corners`, where inline FPU conversions of NaN and out-of-range values are not the soft routines' |

`build.sh` fails if anything does not build, if the C++ compile and link print
anything at all, if the stack-protector array is not directly below the
canary (the `smash` overrun is four bytes, so it changes the canary and
nothing else), or if the UBSan program references a sanitizer runtime. A
second C++ link with `-Wl,--fatal-warnings` must give the same bytes.

`c_basic` checks results, not just that calls return: on 6-7 November 2026 its
`sin` and `exp`/`log` checks found that the `-m68040 -m68881` link took the
soft-float `libm.a`, whose results come back in `d0`/`d1` while the caller
reads `fp0`.

Run them from a Shell with `FailAt 300` (the stack-protector abort returns
127). Start `ubsan_trap-040 overflow` with `Run`: the trapped program waits
for its requester.

MIT licence, Copyright (c) 2026 AmiCradle Team.
