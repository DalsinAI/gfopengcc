# pthreads patch 0010 for an existing stove

`patches/aros-stuff/0010` (at exit, pthreads cancels the threads still
running and removes any left after 2 s; `pthread_exit()`'s value reaches
`pthread_join()`) reaches a new toolchain through `scripts/build.sh`. These
scripts put it into a stove that was built before it, without rebuilding the
stove: only `pthread.o` in each `libpthread.a` changes.

- `build-amiga.sh` (`STOVE=... OUT=...`): builds and checks, changes nothing.
  It first rebuilds `pthread.c` at patches 0001-0009 with the stove's own
  flags (`-noixemul`, the vendor NDK, no `-O`) and stops unless the code
  matches the stove's `pthread.o` in every multilib. Output:
  `OUT/lib/<multilib>/libpthread.a`, `OUT/tests/ExitCancel` (patched) and
  `ExitCancel-old` (the stove's), from `tests/pthreads/exitcancel.c`.
  The `libm040` folders of a stove from the 68040 seed get a copy of their
  `libm020` folder's new archive, as they had before.
- `install-stove.sh [stove...]` (default `~/AmiCradle/stoves/os32-gcc16-open6`):
  builds, backs up each `libpthread.a` to `<stove>/pthreads-0010-backup-<time>/`,
  renames the new ones in, and checks that a plain `-lpthread` link now gives
  the patched test byte for byte; any failure puts the stove back. A stove
  whose `pthread.o` already is the patched one is left alone.
- `install/build-amiga.sh`: the same through Cradle's `stove_build`
  (target `runtime/stove-pthreads/install`).

aros-stuff's sources come from `scripts/sources.lock`, or the open6 release's
source archive when that host can't be reached. A bare toolchain (the release
archive, not a stove) needs `EXTRA_INC` naming the NDK headers.

Programs link libpthread statically: a program has the fix once it is
relinked against the refreshed stove.
