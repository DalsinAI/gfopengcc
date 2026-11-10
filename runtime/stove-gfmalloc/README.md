# gfmalloc's size-wrap fix for an existing stove

The stoves got gfmalloc on 7 November 2026, from amicradle-guest's
`common/gfmalloc/install-stove.sh`. That gfmalloc wraps a size near 4 GB into a
small block: `malloc(0xFFFFFFFE)` returned 8 bytes, not NULL. GFOpenCalc's
save guru came from it (LV-426, amicradle-guest #687).

These scripts put the fixed gfmalloc into such a stove. Only `libgfmalloc.a`
changes; gcc's specs file (the `*gfmalloc:` block) stays as it is.

- `build-amiga.sh` (`STOVE=... OUT=...`) builds and checks, and changes nothing:
  - It rebuilds `gfmalloc.c` at the commits a stove's copy can be from
    (amicradle-guest e138c4c4 and 8b5c2b8d), and stops unless one of them
    matches the stove's `gfmalloc.o`.
  - It builds the fix (7ce01b17) the same way.
  - Output: `OUT/lib/libgfmalloc.a`, `OUT/tests/malloctest` (the fix, linked
    by name) and `OUT/tests/malloctest-old` (a plain link, so the stove's own).
- `install-stove.sh [stove...]` (default: os32-gcc16-open6, os32-gcc16 and os32
  in `~/AmiCradle/stoves`):
  - It builds, backs up `libgfmalloc.a` to `<stove>/gfmalloc-0687-backup-<time>/`
    with `PUT-BACK.txt`, and renames the new one in.
  - It checks that the stove's archive now holds the fixed code and that a
    plain link still takes gfmalloc. Any failure puts the stove back.
  - It leaves a plain-link `malloctest` in `<stove>/gfmalloc-0687-tests/` for
    the lab. That test should print `huge sizes: NULL, as they should`.
  - A stove that already has the fix is left alone.
- `install/build-amiga.sh` does the same through Cradle's `stove_build`
  (target `runtime/stove-gfmalloc/install`).

A stove that gets gfmalloc from amicradle-guest main after 10 November already
has the fix.
