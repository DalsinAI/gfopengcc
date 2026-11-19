#!/bin/bash
# build-linux.sh WORK PREFIX ARCH [JOBS]
# Builds one of GFOpenAmigaGCC's Linux kernel compilers into PREFIX: a cross
# compiler on x86-64 Linux, from the stock GCC 16.2.0 and binutils 2.47
# fetch-linux.sh put in WORK/linux, with patches/linux/series (fold-mem-offsets,
# GCC 0019) and the release identity. ARCH is
#   aarch64  aarch64-linux-gnu: the CM4 and Pi 5 cards (make ARCH=arm64)
#   x86_64   x86_64-linux-gnu: the AMD x86 appliance (make ARCH=x86_64)
#   powerpc  powerpc-linux-gnu: 32-bit PowerPC, big-endian, such as the AC460's
#            460EX (make ARCH=powerpc; the kernel picks -mcpu=440 itself)
# It is a kernel compiler, as the kernel.org cross compilers are: C only,
# libgcc without a C library, no glibc and no C++ runtime. Use it with
# make ARCH=... CROSS_COMPILE=PREFIX/bin/ARCH-linux-gnu-.
# x86_64 is built as x86_64-gfopen-linux-gnu (so GCC does not take it for a
# native compiler on an x86-64 host), and every program is also linked as
# x86_64-linux-gnu-NAME, the name the kernel and the stove use.
# GMP, MPFR and MPC are linked in statically, so the programs need only the
# host's C library; the prefix can be moved.
# Nothing is fetched (no network when unshare can take it away).
# GPL-3.0-or-later, like the patches it goes with. Copyright (c) 2026 AmiCradle Team.
set -euo pipefail
WORK=$(cd "$1" && pwd); PREFIX=$2; ARCH=${3:?usage: build-linux.sh WORK PREFIX ARCH [JOBS]}; JOBS=${4:-$(nproc)}
HERE=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$PREFIX"; PREFIX=$(cd "$PREFIX" && pwd)
case $ARCH in
  aarch64) T=aarch64-linux-gnu; CT=$T ;;
  x86_64)  T=x86_64-linux-gnu;  CT=x86_64-gfopen-linux-gnu ;;
  powerpc) T=powerpc-linux-gnu; CT=$T ;;
  *) echo "ARCH $ARCH: aarch64, x86_64 or powerpc"; exit 1 ;;
esac
A=$WORK/linux; S=$A/src-$ARCH; B=$A/build-$ARCH; LOGS=$A/logs-$ARCH; mkdir -p "$LOGS"
# The identity scripts/build.sh gives the m68k-amigaos GCC (tests/release-names.sh keeps them in step).
ID="GFOpenAmigaGCC 16.2.0-open9"
say() { echo "== $*"; }
NOFETCH=""
if unshare -n --map-current-user true 2>/dev/null; then NOFETCH="unshare -n --map-current-user"; fi

# 1. The recipe is the one the tests check, then fresh sources and the series
#    (each patch must apply exactly: no fuzz).
"$HERE/tests/linux-recipe.sh"
say "sources and patches/linux/series"
rm -rf "$S" "$B"; mkdir -p "$S" "$B"
tar -C "$S" -xf "$A/gcc-16.2.0.tar.xz"
tar -C "$S" -xf "$A/binutils-2.47.tar.bz2"
grep -v '^#' "$HERE/patches/linux/series" | while read -r tree p; do
  [ -n "$tree" ] || continue
  case $tree in
    gcc) d=$S/gcc-16.2.0 ;;
    binutils) d=$S/binutils-2.47 ;;
    *) echo "series: no tree $tree"; exit 1 ;;
  esac
  ( cd "$d" && patch -p1 -s -F0 -f --dry-run < "$HERE/patches/$p" > /dev/null ) || { echo "does not apply: patches/$p"; exit 1; }
  ( cd "$d" && patch -p1 -s -F0 -f --no-backup-if-mismatch < "$HERE/patches/$p" )
  echo "applied $p"
done

# 2. GMP, MPFR and MPC from the host's static archives: a folder that holds only
#    the .a files, so the link takes them and not the shared libraries.
SL=$B/static-libs; mkdir -p "$SL"
for l in gmp mpfr mpc; do
  a=$(${HOST_CC:-cc} -print-file-name=lib$l.a)
  [ -f "$a" ] || { echo "no lib$l.a on this host (libgmp-dev, libmpfr-dev, libmpc-dev)"; exit 1; }
  ln -sf "$a" "$SL/lib$l.a"
done

# 3. binutils.
say "binutils (logs in $LOGS)"
mkdir -p "$B/binutils"
( cd "$B/binutils" && "$S/binutils-2.47/configure" --prefix="$PREFIX" --target=$CT \
    --disable-werror --disable-nls --disable-gdb --disable-gdbserver --disable-sim --disable-gprofng --without-zstd \
  && $NOFETCH make -j"$JOBS" && make install ) > "$LOGS/binutils.log" 2>&1 \
  || { echo "binutils failed (see $LOGS/binutils.log)"; exit 1; }

# 4. GCC and libgcc, with no C library (inhibit_libc), as a kernel needs it.
say "gcc (logs in $LOGS)"
export PATH="$PREFIX/bin:$PATH"
mkdir -p "$B/gcc"
( cd "$B/gcc" && "$S/gcc-16.2.0/configure" --prefix="$PREFIX" --target=$CT \
    --enable-languages=c --without-headers --with-newlib --disable-shared --disable-threads \
    --disable-bootstrap --disable-nls --disable-multilib --disable-libssp --disable-libgomp \
    --disable-libquadmath --disable-libatomic --disable-libitm --disable-libsanitizer --disable-libvtv \
    --disable-libcc1 --disable-decimal-float --without-isl --without-zstd \
    --with-gmp-include=/usr/include --with-gmp-lib="$SL" --with-mpfr-include=/usr/include --with-mpfr-lib="$SL" \
    --with-mpc-include=/usr/include --with-mpc-lib="$SL" \
    --with-pkgversion="$ID" ) > "$LOGS/gcc-configure.log" 2>&1 || { echo "gcc configure failed (see $LOGS/gcc-configure.log)"; exit 1; }
( cd "$B/gcc" && $NOFETCH make -j"$JOBS" all-gcc all-target-libgcc && make -j1 install-gcc install-target-libgcc ) > "$LOGS/gcc.log" 2>&1 \
  || { echo "gcc failed (see $LOGS/gcc.log)"; exit 1; }

# x86_64: the programs also go by x86_64-linux-gnu-NAME.
if [ "$CT" != "$T" ]; then
  for f in "$PREFIX/bin/$CT-"*; do ln -sfn "$(basename "$f")" "$PREFIX/bin/$T-${f##*/$CT-}"; done
fi

# 5. Checks.
say checks
"$HERE/tests/linux-check.sh" "$PREFIX" "$ARCH"
echo "$("$PREFIX/bin/$T-gcc" --version | sed -n '1p') built in $PREFIX"
