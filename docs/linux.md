# The Linux kernel compilers

From open9 the repository also builds GCC 16.2.0-open9 cross compilers on x86-64 Linux for Linux kernels:

| ARCH | Target | For | Kernel |
| --- | --- | --- | --- |
| `aarch64` | `aarch64-linux-gnu` | the CM4 and Pi 5 cards | `make ARCH=arm64` |
| `x86_64` | `x86_64-linux-gnu` (built as `x86_64-gfopen-linux-gnu`) | the AMD x86 appliance | `make ARCH=x86_64` |
| `powerpc` | `powerpc-linux-gnu` (32-bit, big-endian) | the AC460's 460EX | `make ARCH=powerpc` |

Each is stock GCC 16.2.0 and binutils 2.47 (`scripts/linux.lock`, the m68k-aros pins) with `patches/linux/series`: fold-mem-offsets (`patches/gcc/0019`) and nothing AmigaOS-specific.

```bash
scripts/fetch-linux.sh WORK [TARBALLS]
scripts/build-linux.sh WORK PREFIX ARCH [JOBS]
make ARCH=... CROSS_COMPILE=PREFIX/bin/ARCH-linux-gnu- ...
```

It needs the usual GCC build tools and `libgmp-dev`, `libmpfr-dev` and `libmpc-dev` (their static archives are linked in). C only, libgcc without a C library: a kernel compiler, not one for Linux programs. The x86_64 one is configured as `x86_64-gfopen-linux-gnu`, because on an x86-64 host GCC would take `x86_64-linux-gnu` for a native build; every program is also linked as `x86_64-linux-gnu-NAME`.

- `tests/linux-recipe.sh` (and `tests/linux-recipe-test.sh`, its refusals): the pins are m68k-aros's, every patch in the series is a `patches/gcc` one the m68k-aros series applies to stock GCC, none changes an m68k or AmigaOS file, 0019 is in, and the build gives the release identity and the three targets.
- `tests/linux-check.sh PREFIX ARCH`: runs after each build: the identity, no shared GMP/MPFR/MPC, the kernel's code flags for that architecture, its system instructions (x86_64 also `-m32` and `-m16`), libgcc, and `tests/linux/hello-ARCH.c` at `-O2` and `-Os` (under qemu-aarch64 / qemu-ppc, natively on x86-64).

The build workflow's `linux` job builds and checks all three on every PR. Dispatched with `aarch64_rc=N`, `x86_64_rc=N` or `powerpc_rc=N` it builds only these and publishes that one as a pre-release tagged `v<version>-<arch>-rcN` (`gfopenamigagcc-<version>-<arch>-linux-gnu-x86_64-linux.tar.xz`, a source tar and `SHA256SUMS-<arch>`).
