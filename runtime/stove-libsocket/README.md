# libnix patch 0010 for an existing stove

`patches/libnix/0010` (socket `ioctl()` with POSIX's three arguments, `fcntl()`
for sockets, [docs](../../docs/libnix-socket-ioctl.md)) reaches a new toolchain
through `scripts/build.sh`. These scripts put it into a stove that was built
before it, without rebuilding the stove: only `libsocket.a` changes (`ioctl.o`
rebuilt from the patched source, `fcntl.o` added).

- `build-amiga.sh` (`STOVE=... OUT=...`): builds and checks, changes nothing.
  It first rebuilds the unpatched `ioctl.c` with libnix's own flags and stops
  unless the code matches the stove's `ioctl.o` in every multilib. Output:
  `OUT/lib/<multilib>/libsocket.a`, `OUT/tests/SocketIoctl` (patched) and
  `SocketIoctl-old` (the stove's), from `tests/libnix/socket_ioctl.c`.
- `install-stove.sh [stove...]` (default `~/AmiCradle/stoves/os32-gcc16-open6`):
  builds, backs up each `libsocket.a` to `<stove>/libsocket-0010-backup-<time>/`,
  renames the new ones in, and checks that a plain `-lsocket` link now gives
  the patched test byte for byte; any failure puts the stove back. A stove
  that already has `fcntl.o` in `libsocket.a` is left alone.
- `install/build-amiga.sh`: the same through Cradle's `stove_build`
  (target `runtime/stove-libsocket/install`).

libnix's sources come from `scripts/sources.lock`, or the open6 release's
source archive when that host can't be reached. A bare toolchain (the release
archive, not a stove) needs `EXTRA_INC` naming the NDK and network headers.
A stove whose `<sys/socket.h>` needs network headers kept in a folder of their
own (`sys/netinclude_types.h`, as amigachromebuild's os32-gcc16 stoves have
them) has that folder found in the stove and used, as `EXTRA_INC` would.
The 68040 copies (`libm040`, and from open7 `libm040/libm881`) get the new
copy of their `libm020` folder's archive; any other `libsocket.a` stops it.
