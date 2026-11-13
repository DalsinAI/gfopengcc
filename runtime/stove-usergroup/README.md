# libnix patch 0011 for an existing stove

`patches/libnix/0011` fixes the socket library's user and group calls when there is no usergroup.library ([docs](../../docs/libnix-usergroup.md)). It reaches a new toolchain through `scripts/build.sh`. These scripts put it into a stove that was built before it, without rebuilding the stove. Only `libsocket.a` changes: `getgrent.o`, `getpwent.o`, `__inituser.o` and `crypt.o` are rebuilt from the patched sources.

- `build-amiga.sh` (`STOVE=... OUT=...`): builds and checks, and changes nothing.
  - First it rebuilds the four unpatched sources with libnix's own flags. It stops unless each one matches the stove's member in every multilib. `same-code.sh` does the check: byte for byte, or the same symbols and the same structure and library offsets.
    - `__inituser.o` and `crypt.o` rebuild byte for byte.
    - `getgrent.o` and `getpwent.o` rebuild with their blocks in another order, because the stove's libnix came from an earlier build of the same GCC.
  - Output: `OUT/lib/<multilib>/libsocket.a`, plus `OUT/tests/UsergroupCalls` (the patched library) and `UsergroupCalls-old` (the stove's), from `tests/libnix/usergroup_calls.c`.
- `install-stove.sh [stove...]` (default `~/AmiCradle/stoves/os32-gcc16-open6`):
  - Builds, backs up each `libsocket.a` to `<stove>/libsocket-0011-backup-<time>/`, and renames the new ones in.
  - Then checks that a plain `-lsocket` link gives the patched test byte for byte. Any failure puts the stove back.
  - A stove whose `getgrent.o` and `getpwent.o` are already the new ones is left alone.

Sources, network headers and the 68040 (`libm040`, `libm040/libm881`) copies are handled as in [stove-libsocket](../stove-libsocket/README.md).

## Lab check

`UsergroupCalls` prints each call before it makes it and ends with `usergroup: ALL RETURNED`.

Run in a lab with GFOpenSocket (bsdsocket.library, no usergroup.library):
- `UsergroupCalls-old` stops at its first call, `getgrgid(getgid())`.
- `UsergroupCalls` returns at once.
