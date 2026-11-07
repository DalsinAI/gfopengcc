# UBSan trap validation

Run after building the AmigaOS compiler, with `qemu-m68k` on PATH:

```sh
OUT=/tmp/ubsan-trap python3 tests/ubsan-trap/check.py /path/to/prefix/bin
```

The matrix executes a valid control and five deliberately invalid programs
(signed overflow, excessive shift, zero divisor, array bounds and null read)
at O0, O2, O3 and Os on 68000, 68020, 68040 soft float, 68040 FPU and 68060.
The valid control must return zero; the invalid programs must trap with
SIGILL, not merely crash with another signal. No object may reference a
UBSan handler. Runtime-dependent and partially trapped modes must still be
rejected by the compiler.

The raw executable harness supplies Linux syscalls for QEMU and a small
freestanding integer-division helper, without AmigaOS startup, target
libraries or a sanitizer library. This verifies compiler instrumentation, not AmigaOS
exception handling or AC090 runtime behaviour. The FPU profile selects the
floating-point ABI; these integer probes do not test floating-point checks.

`receipt.json`, compiler identity, commands, diagnostics and generated images
are retained in OUT. An unsupported compiler returns 77; a test failure
returns 1. CI treats either as a failed gate. The build uses trap mode only
when an application requests it; this does not change default optimisation
or hardening flags. C++ vptr checks are disabled by GCC's aggregate trap
setting and are not provided by this change.
