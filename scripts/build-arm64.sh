#!/bin/bash
# build-arm64.sh WORK X86PREFIX ARMPREFIX TARBALLS [JOBS]
# GFOpenAmigaGCC for ARM64 Linux hosts, as a Canadian cross on an x86-64 Linux
# system: build x86_64-pc-linux-gnu, host aarch64-linux-gnu, target m68k-amigaos.
#   WORK       the work folder scripts/build.sh built from (patched sources)
#   X86PREFIX  that x86-64 build: its target libraries (libgcc, libstdc++,
#              libnix, libpthread) and headers are the same for every host, so
#              they are copied; only the programs are built again for ARM64
#   ARMPREFIX  where the ARM64 toolchain goes (a copy of X86PREFIX with ARM64
#              programs); configured for the same prefix as X86PREFIX
#   TARBALLS   a folder with gmp-*.tar.*, mpfr-*.tar.* and mpc-*.tar.*: built
#              in-tree for the ARM64 host (LGPL; ship them with the source)
# Needs aarch64-linux-gnu-gcc and -g++. Nothing is fetched (no network when
# unshare can take it away).
# GPL-3.0-or-later. Copyright (c) 2026 AmiCradle Team.
set -euo pipefail
WORK=$(cd "$1" && pwd); X86=$(cd "$2" && pwd); ARM=$3; TB=$(cd "$4" && pwd); JOBS=${5:-$(nproc)}
HOST=aarch64-linux-gnu; BUILD=x86_64-pc-linux-gnu; TARGET=m68k-amigaos
command -v $HOST-gcc >/dev/null && command -v $HOST-g++ >/dev/null || { echo "needs $HOST-gcc and $HOST-g++"; exit 1; }
NOFETCH=""
if unshare -n --map-current-user true 2>/dev/null; then NOFETCH="unshare -n --map-current-user"; fi
PREFIX=$("$X86/bin/m68k-amigaos-gcc" -v 2>&1 | sed -n 's/.*--prefix=\([^ ]*\).*/\1/p')
echo "== configured prefix $PREFIX (the toolchain is relocatable)"
SRC=$WORK/projects
B=$WORK/build-arm64; mkdir -p "$B"; STAGE=$B/stage; mkdir -p "$STAGE"
LOGS=$WORK/gfopenamigagcc-logs; mkdir -p "$LOGS"
export PATH="$X86/bin:$PATH"     # the build -> target tools, for GCC's configure

# 1. GMP, MPFR and MPC in-tree for the ARM64 host.
for l in gmp mpfr mpc; do
  [ -d "$SRC/gcc/$l" ] && continue
  t=$(ls "$TB"/$l-[0-9]*.tar.* | head -1)
  tar --no-same-owner -C "$SRC/gcc" -xf "$t"
  mv "$SRC/gcc/$(basename "$t" | sed 's/\.tar\..*//')" "$SRC/gcc/$l"
  echo "in-tree $l: $(basename "$t")"
done

# 2. binutils (as, ld, ar, objdump...) and gprof.
echo "== binutils for $HOST"
mkdir -p "$B/binutils"
( cd "$B/binutils" && [ -f Makefile ] || "$SRC/binutils/configure" --build=$BUILD --host=$HOST --target=$TARGET \
    --prefix="$PREFIX" --disable-werror --disable-nls --enable-plugins --disable-gdb --disable-gdbserver \
    --disable-sim --without-zstd ) > "$LOGS/arm64-binutils-configure.log" 2>&1
( cd "$B/binutils" && $NOFETCH make -j"$JOBS" all-bfd all-opcodes all-gas all-binutils all-ld \
  && make install-gas install-binutils install-ld DESTDIR="$STAGE" ) > "$LOGS/arm64-binutils.log" 2>&1 \
  || { echo "binutils failed (see $LOGS/arm64-binutils.log)"; exit 1; }
# gprof is configured on its own, inside the binutils build, as amiga-gcc does
mkdir -p "$B/binutils/gprof"
( cd "$B/binutils/gprof" && { [ -f Makefile ] || "$SRC/binutils/gprof/configure" --build=$BUILD --host=$HOST --target=$TARGET \
    --prefix="$PREFIX" --disable-werror --disable-nls; } && $NOFETCH make -j"$JOBS" && make install DESTDIR="$STAGE" ) \
  > "$LOGS/arm64-gprof.log" 2>&1 || { echo "gprof failed (see $LOGS/arm64-gprof.log)"; exit 1; }

# 3. GCC: the driver, cc1, cc1plus, cc1obj, collect2, lto1 and the LTO plugin.
echo "== gcc for $HOST"
mkdir -p "$B/gcc"
( cd "$B/gcc" && [ -f Makefile ] || "$SRC/gcc/configure" --build=$BUILD --host=$HOST --target=$TARGET \
    --prefix="$PREFIX" --enable-languages=c,c++,objc --enable-version-specific-runtime-libs --disable-libssp \
    --disable-nls --disable-shared --enable-threads=posix ) > "$LOGS/arm64-gcc-configure.log" 2>&1
( cd "$B/gcc" && $NOFETCH make -j"$JOBS" all-gcc all-lto-plugin \
  && make install-gcc install-lto-plugin DESTDIR="$STAGE" ) > "$LOGS/arm64-gcc.log" 2>&1 \
  || { echo "gcc failed (see $LOGS/arm64-gcc.log)"; exit 1; }

# 4. fd2sfd and fd2pragma (sfdc is Perl, the same on every host).
echo "== fd2sfd and fd2pragma for $HOST"
mkdir -p "$B/fd2sfd"
# (fd2sfd's own install ignores DESTDIR and strips with the build's strip: copy it)
mkdir -p "$STAGE$PREFIX/bin"
( cd "$B/fd2sfd" && rsync -a --exclude .git "$SRC/fd2sfd/" . && ./configure --host=$HOST --prefix="$PREFIX" --target=$TARGET \
  && make fd2sfd ) > "$LOGS/arm64-fd2sfd.log" 2>&1 || { echo "fd2sfd failed (see $LOGS/arm64-fd2sfd.log)"; exit 1; }
install -m 755 "$B/fd2sfd/fd2sfd" "$STAGE$PREFIX/bin/fd2sfd"
$HOST-gcc -O2 -o "$STAGE$PREFIX/bin/fd2pragma" "$SRC/fd2pragma/fd2pragma.c" > "$LOGS/arm64-fd2pragma.log" 2>&1

# 5. The ARM64 toolchain: the x86-64 one with its programs replaced.
[ "${SKIP_ASSEMBLE:-}" ] && { echo "ARM64 programs built in $STAGE (SKIP_ASSEMBLE)"; exit 0; }
ls "$X86"/lib/gcc/$TARGET/*/libstdc++.a >/dev/null 2>&1 || { echo "$X86 has no libstdc++ yet: finish the x86-64 build first"; exit 1; }
echo "== assembling $ARM"
mkdir -p "$ARM"
rsync -a "$X86/" "$ARM/"
rsync -a "$STAGE$PREFIX/" "$ARM/"
# the programs without their debug information, as the x86-64 build's are
find "$ARM" -type f -exec file {} + | grep 'ELF.*aarch64' | cut -d: -f1 | xargs $HOST-strip --strip-unneeded
left=$(find "$ARM" -type f -exec file {} + | grep -E 'ELF.*x86-64' | cut -d: -f1 || true)
if [ -n "$left" ]; then echo "x86-64 programs left in $ARM:"; echo "$left"; exit 1; fi
echo "ARM64 programs: $(find "$ARM" -type f -exec file {} + | grep -c 'ELF.*aarch64')"
echo "GFOpenAmigaGCC for ARM64 in $ARM"
