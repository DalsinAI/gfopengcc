#!/bin/bash
# tests/userland-recipe.sh
# The Linux userland compilers' recipe (x86_64, aarch64) is what it says it is, before any build:
# - scripts/userland.lock pins the same GCC and binutils as scripts/aros.lock
#   (and so the kernel compilers'), glibc 2.35 and Linux 5.15, and nothing else;
# - scripts/build-userland.sh applies patches/linux/series (tests/linux-recipe.sh
#   checks that series), gives the release identity, builds C and C++ over a
#   sysroot inside the prefix, and has the two targets.
# LOCK and BUILD (paths) override the files checked; tests/userland-recipe-test.sh uses them.
# GPL-3.0-or-later. Copyright (c) 2026 AmiCradle Team.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
LOCK=${LOCK:-$HERE/scripts/userland.lock}
BUILD=${BUILD:-$HERE/scripts/build-userland.sh}
fail() { echo "userland recipe: $*"; exit 1; }
pin() { grep -v '^#' "$1" | awk -v n="$2" '$1 == n { print $3 }'; }
file() { grep -v '^#' "$1" | awk -v n="$2" '$1 == n { print $4 }'; }
for n in gcc binutils; do
  a=$(pin "$LOCK" $n); r=$(pin "$HERE/scripts/aros.lock" $n)
  [ -n "$a" ] || fail "$(basename "$LOCK") pins no $n"
  [ "$a" = "$r" ] || fail "$n: $(basename "$LOCK") pins $a, scripts/aros.lock $r"
done
[ "$(file "$LOCK" glibc)" = glibc-2.35.tar.xz ] || fail "$(basename "$LOCK") does not pin glibc 2.35 (the floor)"
[ "$(file "$LOCK" linux)" = linux-5.15.tar.gz ] || fail "$(basename "$LOCK") does not pin Linux 5.15's headers"
[ -n "$(pin "$LOCK" glibc)" ] && [ -n "$(pin "$LOCK" linux)" ] || fail "glibc or linux has no SHA-256"
[ "$(grep -v '^#' "$LOCK" | awk 'NF' | wc -l)" -eq 4 ] || fail "$(basename "$LOCK") pins something other than gcc, binutils, glibc and linux"
for f in $(grep -v '^#' "$LOCK" | awk 'NF { print $4 }'); do
  grep -qF "\$A/$f\"" "$BUILD" || fail "$(basename "$BUILD") does not unpack $f"
done
grep -qF '"$HERE/patches/linux/series"' "$BUILD" || fail "$(basename "$BUILD") does not apply patches/linux/series"
pkg=$(sed -n 's/^+.*--with-pkgversion="\([^"]*\)".*/\1/p' "$HERE"/patches/amiga-gcc/0002-*-pkgversion.patch)
grep -qxF "ID=\"$pkg\"" "$BUILD" || fail "$(basename "$BUILD") does not build ($pkg)"
[ "$(grep -cF -- "--with-pkgversion='\$ID'" "$BUILD")" -eq 2 ] || fail "$(basename "$BUILD") does not configure both GCC passes with its ID"
grep -qF -- '--enable-languages=c,c++ ' "$BUILD" || fail "$(basename "$BUILD") does not build C and C++"
grep -qxF 'SYSROOT=$PREFIX/$CT/sysroot' "$BUILD" || fail "$(basename "$BUILD") does not keep the sysroot inside the prefix"
grep -qF -- '--with-sysroot="$SYSROOT"' "$BUILD" || fail "$(basename "$BUILD") does not configure with the sysroot"
grep -qF -- '--enable-default-pie' "$BUILD" || fail "$(basename "$BUILD") does not make PIE by default"
for t in "x86_64)  T=x86_64-linux-gnu;  CT=x86_64-gfopen-linux-gnu; KARCH=x86_64 ;;" "aarch64) T=aarch64-linux-gnu; CT=\$T; KARCH=arm64 ;;"; do
  grep -qxF "  $t" "$BUILD" || fail "$(basename "$BUILD") does not build ${t%%)*} as it should (${t#*) })"
done
echo "userland recipe: GCC 16.2.0 and binutils 2.47 as m68k-aros, glibc 2.35, Linux 5.15 headers, identity ($pkg)"
