# The aarch64-linux-gnu target

From open9 the repository also builds `aarch64-linux-gnu-gcc`, a cross compiler on x86-64 Linux for the 64-bit ARM Linux kernels of the CM4 and Pi 5 cards. It is stock GCC 16.2.0 and binutils 2.47 (`scripts/aarch64.lock`, the m68k-aros pins) with `patches/aarch64/series`: fold-mem-offsets (`patches/gcc/0019`) and nothing AmigaOS-specific.

```bash
scripts/fetch-aarch64.sh WORK [TARBALLS]
scripts/build-aarch64.sh WORK PREFIX [JOBS]
make ARCH=arm64 CROSS_COMPILE=PREFIX/bin/aarch64-linux-gnu- ...
```

It needs the usual GCC build tools and `libgmp-dev`, `libmpfr-dev` and `libmpc-dev` (their static archives are linked in). C only, libgcc without a C library: a kernel compiler, not one for Linux programs.

- `tests/aarch64-recipe.sh` (and `tests/aarch64-recipe-test.sh`, its refusals): the pins are m68k-aros's, every patch in the series is a `patches/gcc` one the m68k-aros series applies to stock GCC, none changes an m68k or AmigaOS file, 0019 is in, and the build gives the release identity.
- `tests/aarch64-check.sh PREFIX`: runs after the build (see `docs/releases/16.2.0-open9-aarch64.md`).

The build workflow's `aarch64` job builds and checks it on every PR. Dispatched with `aarch64_rc=N` it builds only this target and publishes it as a pre-release tagged `v<version>-aarch64-rcN`.
