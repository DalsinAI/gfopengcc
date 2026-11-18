# The newest pthreads patch for an existing stove

A patch in `patches/aros-stuff` reaches a new toolchain through
`scripts/build.sh`. These scripts put the newest one into a stove that was
built before it (first `0010`: at exit, pthreads cancels the threads still
running and removes any left after 2 s; now `0011`: every
`pthread_cond_signal` wakes a thread that is still waiting), without rebuilding the
stove: only `pthread.o` in each `libpthread.a` changes.

- `build-amiga.sh` (`STOVE=... OUT=...`): builds and checks, changes nothing.
  It first rebuilds `pthread.c` at the patches before the newest with the stove's own
  flags (`-noixemul`, the vendor NDK, no `-O`) and stops unless the code
  matches the stove's `pthread.o` in every multilib. Output:
  `OUT/lib/<multilib>/libpthread.a`, and `OUT/tests/ExitCancel` and `CondSignal`
  (patched) with `ExitCancel-old` and `CondSignal-old` (the stove's), from
  `tests/pthreads/exitcancel.c` and `condsignal.c`. A stove more than one
  patch behind stops at that check: it needs a new toolchain.
  The `libm040` folders of a stove from the 68040 seed get a copy of their
  `libm020` folder's new archive, as they had before.
- `install-stove.sh [stove...]` (default `~/AmiCradle/kitchen/stoves/os32-gcc16`,
  or `~/AmiCradle/stoves/os32-gcc16-open6` on a machine with the old layout):
  builds, backs up each `libpthread.a` to `<stove>/pthreads-<patch>-backup-<time>/`,
  renames the new ones in, and checks that a plain `-lpthread` link now gives
  the patched tests byte for byte; any failure puts the stove back. A stove
  whose `pthread.o` already is the patched one is left alone.
- `install/build-amiga.sh`: the same through Cradle's `stove_build`
  (target `runtime/stove-pthreads/install`).

aros-stuff's sources come from `scripts/sources.lock`, or the open6 release's
source archive when that host can't be reached. A bare toolchain (the release
archive, not a stove) needs `EXTRA_INC` naming the NDK headers.

Programs link libpthread statically: a program has the fix once it is
relinked against the refreshed stove.
