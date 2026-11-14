# fold-mem-offsets and a memory-to-memory move (GCC 0019, from open8)

Found 14 November 2026 by Team 2 (Lister) in GFOpenBench's WBGapTest (gfopenbench #216); traced and cut down by Team 5 (Lorien).

## What went wrong

GCC's fold-mem-offsets pass (on at `-O2` and up) looks for a constant add whose result is used only as the base of memory accesses, adds the constant to each access's displacement and deletes the add. It asks `get_fold_mem_root()` which accesses it may change. An instruction with a memory operand on both sides, which the 68k has (`move.b (a1),2(a0)`), was taken as an access through its source's base only. So an add feeding the destination's base saw all its uses accepted, was deleted, and the destination was never updated.

GFOpenBench's `PREFSWB_judge.c` stored four bytes through `p = out + here + 8`. Three stores became `8(a0)`, `9(a0)` and `11(a0)`; the one whose byte came from memory became `move.b (a1),2(a0)` instead of `10(a0)`. The Workbench prefs file's `WBNC` chunk id was written `WB\0C`, and the old stack's third byte stayed.

- Wrong: `-O2` with `-m68040` or `-m68060` (and `-O3` where the same code is made).
- Right: `-O1`, `-Os`, and `-O2` with `-m68020` or `-m68000`, which make different code here.
- `-fno-fold-mem-offsets` alone removes it.

## The fix

`patches/gcc/0019`: `get_fold_mem_root()` refuses an instruction whose destination is a MEM and whose source is a MEM or a sign or zero extend of one. An add feeding such an instruction is not deleted. It goes into both targets (`patches/aros/series`).

## The test

`tests/repro/fmo.c` (with `fmo_g.c`, so the store function knows nothing of its callee) runs under `qemu-m68k` from `tests/repro/prove.sh` at `-O2` and `-O3` with `-m68040` and `-m68060`, and `-Os`. On 16.2.0-open6, `-O2` with either CPU says `fmo: WRONG`; with 0019 every line says `right`.
