# A move addressed its destination through the register its source steps

**Fixed by** `patches/gcc/0013-m68k-no-move-addresses-its-destination-through-the-r.patch`.

## What went wrong

GCC's late-combine pass (new in GCC 15) substitutes a register's definition
into the instructions that use it. After register allocation it put a store's
address, `a0 + a2`, into the byte copy that post-increments `a2`:

```
lea (a0,a2.l),a3           | before: the address in a register of its own
move.b (a2)+,(a3)
move.b (a2)+,(a0,a2.l)     | after late-combine
```

In GCC's RTL the destination's `a2` is the value from before the increment,
but the 68k works the destination out after the source's increment, so each
byte landed one late. GFOffice's `owf_number_text` (libowf) showed 6.5 as
"6.w" and pi as "3.w1415926535897" on the Amiga: the first digit after the
point was never written and the last went over the NUL. `owf_booknum.c` had
`move.b (a0)+,(a0,d2.l)` the same way.

A pre-decrement goes wrong the same way, in every move size:
`move.l -(a0),(a0,d1.l)` broke glibc on m68k-linux
([PR123853](https://gcc.gnu.org/bugzilla/show_bug.cgi?id=123853)) and hung
CPython ([PR123076](https://gcc.gnu.org/bugzilla/show_bug.cgi?id=123076)), and
the 64-bit and 96-bit moves (`long long`, `double`, `long double`) give
`move.l -(a0),4(a0,d1.l)`. It shows at `-O2` and `-O3`, for the 68000 to the
68060; not at `-O1`, where late-combine does not run, and not in these loops
at `-Os`. `-fno-late-combine-instructions` hid it.

## The fix

The move instructions (all sizes, not ColdFire) refuse a source that
post-increments or pre-decrements a register their destination mentions, so
late-combine, or any other pass, leaves the address in a register of its own,
as above.

This is Mikael Pettersson's patch for PR123853 (Bugzilla attachment 64643,
sent to gcc-patches as v2 on 7 July 2026), which guards the 32-bit moves.
GCC has not committed it.
[AmigaPorts/gcc #56](https://github.com/AmigaPorts/gcc/pull/56) (open), which
puts the same guard on the 16-bit, 8-bit and `float` moves, reports that
upstream turned it down for future work that lets a back end filter an
operand's registers, and that Debian carries it. GFOpenAmigaGCC also puts the
guard on the 64-bit and 96-bit moves.

## Reproducer

`tests/repro/autoinc.c` is `owf_number_text`'s text part, reduced, and
PR123853's copy loops in every move size, downwards and upwards.
`tests/repro/prove.sh` runs it under `qemu-m68k` (`-m68040` and `-m68000`)
and checks the compiler's code for an instruction that names a register again
after `(An)+` or `-(An)`.

| Compiler | `-O2 -m68040` code | `-O2 -m68000` code |
| --- | --- | --- |
| GCC 16.2.0b as released (GFOpenAmigaGCC 16.2.0-open3) | wrong: 21 instructions, `move.b (a5)+,(a2,a5.l)` in `fmt` among them | wrong: 20 instructions |
| GFOpenAmigaGCC with patch 0013 | right: none | right: none |

GFOffice's libowf (its 41 sources, built as owf.library is): with patch 0013
no instruction names a stepped register again, and the two that did are the
only change in its code.

## m68k-aros (from open6)

The `aros68k-gcc16` stove (stock GCC 16.2.0 with AROS's diff) had the same bug:
it compiled GFOpenKick's exec `oe_AlertText` (`exec_alert.c`, before
amicradle-guest #582) at `-m68040 -O2` into `move.b (a1)+,(0,a1,d0.l)`. From
open6 the `m68k-aros` compiler is built here with this patch
([aros.md](aros.md)). `tests/autoinc/pr-autoinc.c` is that function reduced;
`tests/autoinc/check.sh` compiles it and `tests/repro/autoinc.c` for both
targets, every CPU, at `-O2`, `-O3` and `-Os`, and scans the code with
amicradle-guest's `scan_autoinc_overlap.py` (copied into `tests/autoinc`).

| Compiler | `pr-autoinc.c`, `-m68040 -O2` |
| --- | --- |
| `m68k-aros-gcc (GCC) 16.2.0` (the `aros68k-gcc16` stove) | wrong: `move.b (a0)+,(a0,d0.l)` |
| `m68k-aros-gcc (GFOpenAmigaGCC 16.2.0-open6) 16.2.0` | right: `lea (a0,d0.l),a1` and `move.b (a0)+,(a1)`, the only change in its code |
