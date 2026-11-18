#!/bin/bash
# build-userland.sh WORK PREFIX ARCH [JOBS]
# Builds one of GFOpenAmigaGCC's Linux userland compilers into PREFIX: a cross
# compiler on x86-64 Linux for programs (C and C++), from the stock GCC 16.2.0
# and binutils 2.47 with patches/linux/series and the release identity, over a
# sysroot of glibc 2.35 and Linux 5.15's headers (Ubuntu 22.04's, the glibc
# floor of AmiCradle's runtimes), all from scripts/userland.lock in WORK/userland
# (scripts/fetch-userland.sh). ARCH is
#   x86_64   x86_64-linux-gnu: daletop, the CI runners, the AMD x86 appliance
#   aarch64  aarch64-linux-gnu: the CM4 and Pi 5 cards
# Unlike scripts/build-linux.sh (a kernel compiler: C only, no C library) it has
# C and C++, libgcc_s, libstdc++, libatomic and libgomp, and every program it
# links asks for no glibc symbol above 2.35, so it starts on Ubuntu 22.04 and on
# every newer system. The sysroot's glibc is only linked against: a program
# loads the system's own glibc when it runs. A C++ program that must start on
# 22.04 links libstdc++ with -static-libstdc++ (GCC 16's is newer than 22.04's).
# Programs are PIE by default, as Ubuntu's and Debian's GCC make them.
# x86_64 is built as x86_64-gfopen-linux-gnu (so GCC does not take it for a
# native compiler on an x86-64 host), and every program is also linked as
# x86_64-linux-gnu-NAME. The sysroot is inside PREFIX, so the prefix can be moved.
# GMP, MPFR and MPC are linked in statically. Nothing is fetched (no network
# when unshare can take it away).
# GPL-3.0-or-later, like the patches it goes with. Copyright (c) 2026 AmiCradle Team.
set -euo pipefail
WORK=$(cd "$1" && pwd); PREFIX=$2; ARCH=${3:?usage: build-userland.sh WORK PREFIX ARCH [JOBS]}; JOBS=${4:-$(nproc)}
HERE=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$PREFIX"; PREFIX=$(cd "$PREFIX" && pwd)
case $ARCH in
  x86_64)  T=x86_64-linux-gnu;  CT=x86_64-gfopen-linux-gnu; KARCH=x86_64 ;;
  aarch64) T=aarch64-linux-gnu; CT=$T; KARCH=arm64 ;;
  *) echo "ARCH $ARCH: x86_64 or aarch64"; exit 1 ;;
esac
A=$WORK/userland; S=$A/src-$ARCH; B=$A/build-$ARCH; LOGS=$A/logs-$ARCH; mkdir -p "$LOGS"
SYSROOT=$PREFIX/$CT/sysroot
# The identity scripts/build.sh gives the m68k-amigaos GCC (tests/release-names.sh keeps them in step).
ID="GFOpenAmigaGCC 16.2.0-open9"
say() { echo "== $*"; }
NOFETCH=""
if unshare -n --map-current-user true 2>/dev/null; then NOFETCH="unshare -n --map-current-user"; fi
log() { local name=$1; shift; ( "$@" ) > "$LOGS/$name.log" 2>&1 || { echo "$name failed (see $LOGS/$name.log)"; tail -30 "$LOGS/$name.log"; exit 1; }; }

# 1. The recipe is the one the tests check, then fresh sources and the series
#    (each patch must apply exactly: no fuzz).
"$HERE/tests/userland-recipe.sh"
say "sources and patches/linux/series"
rm -rf "$S" "$B"; mkdir -p "$S" "$B"
tar -C "$S" -xf "$A/gcc-16.2.0.tar.xz"
tar -C "$S" -xf "$A/binutils-2.47.tar.bz2"
tar -C "$S" -xf "$A/glibc-2.35.tar.xz"
tar -C "$S" -xf "$A/linux-5.15.tar.gz"
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
GMP=(--with-gmp-include=/usr/include --with-gmp-lib="$SL" --with-mpfr-include=/usr/include --with-mpfr-lib="$SL"
     --with-mpc-include=/usr/include --with-mpc-lib="$SL")
COMMON=(--prefix="$PREFIX" --target=$CT --with-sysroot="$SYSROOT" --disable-nls --disable-multilib --without-isl --without-zstd)

# 3. binutils, looking for libraries in the sysroot.
say "binutils (logs in $LOGS)"
mkdir -p "$B/binutils"
log binutils sh -c "cd '$B/binutils' && '$S/binutils-2.47/configure' ${COMMON[*]} \
    --disable-werror --disable-gdb --disable-gdbserver --disable-sim --disable-gprofng \
  && $NOFETCH make -j$JOBS && make install"
export PATH="$PREFIX/bin:$PATH"

# 4. Linux 5.15's headers into the sysroot.
say "linux 5.15 headers"
log linux-headers make -C "$S/linux-5.15" ARCH=$KARCH INSTALL_HDR_PATH="$SYSROOT/usr" headers_install

# 5. A first GCC, C only, without a C library, to build glibc with (step 7's
#    GCC is installed over it).
say "gcc, first pass"
mkdir -p "$B/gcc1"
log gcc1-configure sh -c "cd '$B/gcc1' && '$S/gcc-16.2.0/configure' ${COMMON[*]} \
    --enable-languages=c --without-headers --with-newlib --disable-shared --disable-threads --disable-bootstrap \
    --disable-libssp --disable-libgomp --disable-libquadmath --disable-libatomic --disable-libitm \
    --disable-libsanitizer --disable-libvtv --disable-libcc1 --disable-decimal-float ${GMP[*]} --with-pkgversion='$ID'"
log gcc1 sh -c "cd '$B/gcc1' && $NOFETCH make -j$JOBS all-gcc all-target-libgcc && make -j1 install-gcc install-target-libgcc"

# 6. glibc 2.35 into the sysroot, built by the first GCC. GCC 16 warns where
#    GCC 12 did not, so its warnings are not errors.
say "glibc 2.35"
mkdir -p "$B/glibc"
BINUTILS_FOR=(AR="$PREFIX/bin/$CT-ar" RANLIB="$PREFIX/bin/$CT-ranlib" AS="$PREFIX/bin/$CT-as" LD="$PREFIX/bin/$CT-ld"
              NM="$PREFIX/bin/$CT-nm" OBJCOPY="$PREFIX/bin/$CT-objcopy" OBJDUMP="$PREFIX/bin/$CT-objdump" READELF="$PREFIX/bin/$CT-readelf")
log glibc-configure sh -c "cd '$B/glibc' && CC='$PREFIX/bin/$CT-gcc' CXX=false ${BINUTILS_FOR[*]} \
    '$S/glibc-2.35/configure' --prefix=/usr --host=$CT --build=$(${HOST_CC:-cc} -dumpmachine) \
    --with-headers='$SYSROOT/usr/include' --with-binutils='$PREFIX/bin' --enable-kernel=3.2 --disable-werror \
    --disable-crypt --disable-nscd --disable-build-nscd --disable-timezone-tools --disable-profile"
log glibc sh -c "cd '$B/glibc' && $NOFETCH make -j$JOBS && make install install_root='$SYSROOT'"
rm -rf "$SYSROOT/usr/share" "$SYSROOT/usr/libexec" "$SYSROOT/usr/sbin" "$SYSROOT/sbin" "$SYSROOT/usr/bin" "$SYSROOT/var" "$SYSROOT/etc"

# 7. The GCC that ships: C and C++, shared libgcc_s and libstdc++, POSIX threads,
#    PIE by default, over the sysroot.
say "gcc"
mkdir -p "$B/gcc"
log gcc-configure sh -c "cd '$B/gcc' && '$S/gcc-16.2.0/configure' ${COMMON[*]} \
    --enable-languages=c,c++ --enable-shared --enable-threads=posix --enable-__cxa_atexit --enable-default-pie \
    --enable-linker-build-id --enable-gnu-unique-object --disable-bootstrap --disable-libsanitizer --disable-libvtv \
    --disable-libcc1 --disable-libssp --with-glibc-version=2.35 ${GMP[*]} --with-pkgversion='$ID'"
log gcc sh -c "cd '$B/gcc' && $NOFETCH make -j$JOBS && make -j1 install-strip"

# x86_64: the programs also go by x86_64-linux-gnu-NAME.
if [ "$CT" != "$T" ]; then
  for f in "$PREFIX/bin/$CT-"*; do ln -sfn "$(basename "$f")" "$PREFIX/bin/$T-${f##*/$CT-}"; done
fi

# 8. Checks.
say checks
"$HERE/tests/userland-check.sh" "$PREFIX" "$ARCH"
echo "$("$PREFIX/bin/$T-gcc" --version | sed -n '1p') (glibc 2.35 sysroot) built in $PREFIX"
