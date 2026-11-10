# libnix patches

These apply to bebbo's libnix at commit `5707d0b` ("__amigapath: read NOIXPATHS after environ is filled"), the libnix the GCC 16.2 stove is built from. In amiga-gcc's `projects/libnix`:

```bash
git am /path/to/patches/libnix/*.patch      # or: patch -p1 < each file, in order
```

| Patch | Fixes | Notes |
| --- | --- | --- |
| `0001-swapstack-…` | `__stack` ignored; the stack swap clobbers A2 (80000004) | `docs/libnix-stack-swap.md` |
| `0002-nlbcrt0-…` | plain `-fbaserel32` programs return the stack size instead of their exit code | `docs/libnix-baserel32-exit.md` |
| `0003-nix20-math-…` | 32-bit multiply/divide jump through a NULL `UtilityBase` (80000004) | `docs/libnix-utilitybase.md` |
| `0004-__initlibraries-…` | soft-float doubles rounded to single precision (or toward zero) on an FPU Amiga, after OS 3.2's IEEE libraries set FPCR on open | `docs/libnix-fpcr.md` |
| `0005-__cxa_atexit-…` | no `__cxa_atexit` or `__dso_handle`, which C++ code built with `-fuse-cxa-atexit` (the compiler's default from gcc patch 0010) needs | `docs/cxa-atexit.md` |
| `0006-setlocale-…` | `setlocale()` from several threads at once (libstdc++ calls it for every number a stream converts) frees the same name twice and closes the same locale twice; the saved name can't be set back | `docs/libnix-setlocale.md` |
| `0007-cxxglue-__initcpp-…` | under `-fbaserel`/`-fbaserel32`, `__init_eh` and `__initcpp` addressed the `.list` sections (in the code hunk) from a4: `-fbaserel` C++ failed to link and `-fbaserel32` C++ hung before `main` | `tests/baserel/FINDINGS.md` |
| `0008-strtol-strtoul-…` | empty-input conversion leaves `endptr` untouched; `strtol` also consumes an uninitialised end pointer after whitespace-only input | `docs/libnix-strtol-endptr.md`; native original/fixed control in `tests/libnix/strtol_endptr.c` |
| `0009-libnix4-exclude-…` | `libnix4.library` exports and links `__vfwprintf_total_size` twice because `preplib` excludes a misspelled object name | `tests/libnix4-source-list.sh`; the `FULL_SPECIFIERS` math copy is retained, as for `__vfprintf_total_size` |
| `0010-socket-ioctl-…` | `ioctl()` in the socket library took ixemul's five-argument form, so POSIX's `ioctl(fd, FIONBIO, &on)` (Boost.Asio, aMule) passed a stray stack word as the argument: EFAULT, or a stray write for FIONREAD; libnix's `fcntl()` returned -1 for everything with errno untouched | `docs/libnix-socket-ioctl.md`; `tests/libnix/socket_ioctl.c` |

Then rebuild libnix (`make libnix` in amiga-gcc, or `Makefile.gcc6 all install`). Built with the GCC 16.2 stove at `-O2`, the unpatched source gives a `libnix20.a`, `libnix13.a` and start code byte-identical to the stove's.

**Licence:** libnix is public domain, as its README states. These patches are public domain too.
