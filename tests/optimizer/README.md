# Open7 optimiser matrix

`check.sh BINDIR` compiles a defined-behaviour integer workload for the 68000,
68020, 68040 and 68060 at `-O0`, `-O2`, `-O3`, `-Os`, `-O2/-O3 -flto`, and
the same LTO profiles with `-fwhole-program`. It converts each Amiga hunk to a raw ELF envelope, runs it under
the matching qemu-m68k CPU, and requires every build to produce the same
checksum. `matrix.tsv` also records linked text and file sizes. A freestanding
shift-and-add `__mulsi3` keeps the compiler-only test independent of libc and
the target runtime build while still exercising 32-bit multiply lowering. A
hot function in `cross-unit.c` ensures the LTO profiles exercise cross-file
inlining opportunities. Keeping both ordinary LTO and closed-world LTO exposes
whether the Amiga linker plugin supplies enough symbol-resolution information;
`-fwhole-program` is not a general default because externally reached callbacks
must first be marked `externally_visible`.

This is a correctness and code-size screen, not an AC090 speed benchmark.
Host qemu timing is not accepted as evidence for a compiler default. Runtime
performance decisions require the same generated executables and workload
iterations on the agreed AmigaChrome AC090 instance.
