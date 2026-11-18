#!/bin/bash
# tests/userland-check.sh PREFIX ARCH
# Checks a scripts/build-userland.sh toolchain for ARCH (x86_64 or aarch64) in PREFIX:
# - ARCH-linux-gnu-gcc --version names the release (patches/amiga-gcc/0002's identity);
# - its programs (gcc, g++, cc1, cc1plus, as, ld) link no GMP, MPFR or MPC shared library;
# - the sysroot is inside PREFIX and holds glibc 2.35;
# - tests/userland/hello.c (threads, dlopen, libm, TLS) and hello.cpp (iostream,
#   std::thread, exceptions, -static-libstdc++) build at -O2, are PIE, ask for no
#   glibc symbol above 2.35, and print "ARCH c ok" / "ARCH c++ ok" (x86_64
#   natively on an x86-64 host; aarch64 under qemu-aarch64 with the sysroot's glibc).
# GPL-3.0-or-later. Copyright (c) 2026 AmiCradle Team.
set -euo pipefail
P=$(cd "$1" && pwd); ARCH=${2:-x86_64}; HERE=$(cd "$(dirname "$0")/.." && pwd)
T=$ARCH-linux-gnu; CC=$P/bin/$T-gcc; CXX=$P/bin/$T-g++
fail() { echo "$ARCH userland check: $*"; exit 1; }
O=$(mktemp -d); trap 'rm -rf "$O"' EXIT
case $ARCH in
  x86_64)  MACH='X86-64';  RUN="" ;;
  aarch64) MACH=AArch64;   RUN=qemu-aarch64 ;;
  *) fail "ARCH $ARCH: x86_64 or aarch64" ;;
esac
pkg=$(sed -n 's/^+.*--with-pkgversion="\([^"]*\)".*/\1/p' "$HERE"/patches/amiga-gcc/0002-*-pkgversion.patch)
"$CC" --version | sed -n 1p | grep -qF "($pkg) 16.2.0" || fail "$T-gcc does not say ($pkg) 16.2.0: $("$CC" --version | sed -n 1p)"
"$CXX" --version | sed -n 1p | grep -qF "($pkg) 16.2.0" || fail "$T-g++ does not say ($pkg) 16.2.0"
echo "ok   identity: $("$CC" --version | sed -n 1p)"
for f in "$CC" "$CXX" "$("$CC" -print-prog-name=cc1)" "$("$CXX" -print-prog-name=cc1plus)" "$P/bin/$T-as" "$P/bin/$T-ld"; do
  [ -x "$f" ] || fail "no $f"
  if ldd "$f" 2>/dev/null | grep -E 'libgmp|libmpfr|libmpc|libisl|libzstd'; then fail "$f needs a shared library the host may not have"; fi
done
echo "ok   gcc, g++, cc1, cc1plus, as and ld need only the C library"
SR=$("$CC" -print-sysroot)
SR=$(cd "$SR" && pwd)
case $SR in "$P"/*) ;; *) fail "the sysroot $SR is not inside $P (the prefix would not move)" ;; esac
ver=$(sed -n 's/^#define[[:space:]]*__GLIBC_MINOR__[[:space:]]*\([0-9]*\).*/\1/p' "$SR/usr/include/features.h")
[ "$ver" = 35 ] || fail "the sysroot's glibc is 2.$ver, not 2.35"
echo "ok   sysroot $SR: glibc 2.$ver"
glibc_max() { "$P/bin/$T-objdump" -T "$1" | grep -oE 'GLIBC_2\.[0-9]+(\.[0-9]+)?' | sort -t. -k2,2n -k3,3n | tail -1; }
check() {   # check NAME BINARY EXPECTED
  "$P/bin/$T-readelf" -h "$2" | grep -q "$MACH" || fail "$1 is not an $MACH program"
  "$P/bin/$T-readelf" -h "$2" | grep -q 'DYN (Position-Independent Executable' || fail "$1 is not PIE"
  local g; g=$(glibc_max "$2")
  [ -n "$g" ] || fail "$1 asks for no glibc version at all"
  local m=${g#GLIBC_2.}; m=${m%%.*}
  [ "$m" -le 35 ] || fail "$1 asks for $g, above the 2.35 floor"
  if "$P/bin/$T-readelf" -d "$2" | grep -q 'libstdc++'; then fail "$1 needs libstdc++.so (GCC 16's is newer than Ubuntu 22.04's)"; fi
  if [ -n "$RUN" ] && ! command -v "$RUN" > /dev/null; then echo "ok   $1 links, PIE, needs $g (no $RUN here to run it)"; return; fi
  if [ -z "$RUN" ] && [ "$(uname -m)" != x86_64 ]; then echo "ok   $1 links, PIE, needs $g (not an x86-64 host)"; return; fi
  local out
  if [ -n "$RUN" ]; then out=$("$RUN" -L "$SR" "$2") || fail "$1 exits with $?"; else out=$("$2") || fail "$1 exits with $?"; fi
  [ "$out" = "$3" ] || fail "$1 printed \"$out\""
  echo "ok   $1: PIE, needs $g, ${RUN:+under $RUN: }$out"
}
"$CC" -std=gnu11 -O2 -DARCH="\"$ARCH\"" -o "$O/hello-c" "$HERE/tests/userland/hello.c" -lm -lpthread -ldl || fail "hello.c does not build"
check hello.c "$O/hello-c" "$ARCH c ok"
"$CXX" -std=gnu++20 -O2 -DARCH="\"$ARCH\"" -static-libstdc++ -static-libgcc -o "$O/hello-cxx" "$HERE/tests/userland/hello.cpp" -lpthread \
  || fail "hello.cpp does not build"
check hello.cpp "$O/hello-cxx" "$ARCH c++ ok"
echo "$ARCH userland check: all passed in $P"
