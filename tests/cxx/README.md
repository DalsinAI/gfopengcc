# C++ runtime tests

These need a real AmigaOS: qemu-m68k's user mode has no exec tasks. Build each test with the stove's usual C++ flags and nothing else. In particular, don't add `-fuse-cxa-atexit` or a `__dso_handle`: what is being tested is the default.

```bash
m68k-amigaos-g++ -m68040 -m68881 -O2 -fomit-frame-pointer -std=gnu++23 -o dtors dtors.cpp -lpthread
```

`dtors.cpp` tests C++ destructors at thread exit and at program exit ([docs/cxa-atexit.md](../../docs/cxa-atexit.md)). It prints two lines.

| Line | With gcc 0010 and libnix 0005 | Before |
| --- | --- | --- |
| first | `thread_local destroyed when its thread ended: yes` | `... no` |
| second, printed at exit | `dtors OK` | `dtors FAILED: g (want tm b g a )` |

It returns 0 when the thread's `thread_local` was destroyed in time, and 20 otherwise.

## lean.cpp

`lean-check.sh` compiles `lean.cpp` with the lean C++ library profile ([docs/lean-cxx.md](../../docs/lean-cxx.md)) and fails if the object needs exception or RTTI support, a static constructor, a guarded function-local static or libstdc++'s `operator new`. It only compiles, so it needs no Amiga:

```bash
CXX=m68k-amigaos-g++ NM=m68k-amigaos-nm tests/cxx/lean-check.sh
```

## stoll.cpp

`scripts/libstdcxx-c99-stdlib.sh` (step 6 of `scripts/build.sh`) turns on libstdc++'s C99 stdlib, which its configure leaves off for libnix, so `std::stoll`, `std::stoull` and `std::stold` exist for `std::string`. It compiles `stoll.cpp` with the new g++ and puts every `c++config.h` back if that fails. `c99-stdlib-check.sh` tests the script on the host with stand-in files (and runs `stoll.cpp` with the host's g++):

```bash
sh tests/cxx/c99-stdlib-check.sh
```
