#!/bin/bash
# tests/linux-recipe.sh
# The Linux kernel compilers' recipe (aarch64, x86_64, powerpc) is what it says it is, before any build:
# - scripts/linux.lock pins the same GCC and binutils as scripts/aros.lock;
# - patches/linux/series names only patches that exist, go into the gcc or
#   binutils tree, and that the stock-GCC m68k-aros series applies as they are
#   (patches/gcc files, so no AROS port, no amiga-gcc, aros-stuff or libnix one);
# - none of them touches an m68k or AmigaOS file, and 0019 (fold-mem-offsets) is in;
# - scripts/build-linux.sh gives the release identity, builds C only, and has the three targets.
# SERIES, LOCK and BUILD (paths) override the files checked; tests/linux-recipe-test.sh uses them.
# GPL-3.0-or-later. Copyright (c) 2026 AmiCradle Team.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
SER=${SERIES:-$HERE/patches/linux/series}
LOCK=${LOCK:-$HERE/scripts/linux.lock}
BUILD=${BUILD:-$HERE/scripts/build-linux.sh}
fail() { echo "linux recipe: $*"; exit 1; }
pin() { grep -v '^#' "$1" | awk -v n="$2" '$1 == n { print $3 }'; }
for n in gcc binutils; do
  a=$(pin "$LOCK" $n); r=$(pin "$HERE/scripts/aros.lock" $n)
  [ -n "$a" ] || fail "$(basename "$LOCK") pins no $n"
  [ "$a" = "$r" ] || fail "$n: $(basename "$LOCK") pins $a, scripts/aros.lock $r"
done
[ "$(grep -v '^#' "$LOCK" | awk 'NF' | wc -l)" -eq 2 ] || fail "$(basename "$LOCK") pins something other than gcc and binutils"
n=0
while read -r tree p; do
  [ -n "$tree" ] || continue
  n=$((n+1))
  case $tree in gcc|binutils) ;; *) fail "series: no tree $tree ($p)" ;; esac
  case $p in gcc/*.patch) ;; *) fail "series: $p is not a patches/gcc patch (AmigaOS, AROS port, pthreads and libnix patches stay out)" ;; esac
  [ -f "$HERE/patches/$p" ] || fail "series names patches/$p, which is not there"
  grep -v '^#' "$HERE/patches/aros/series" | grep -qE "^gcc[[:space:]]+$p\$" \
    || fail "$p is not in patches/aros/series as it is, so it is not known to apply to stock GCC"
  bad=$(grep -E '^\+\+\+ ' "$HERE/patches/$p" | grep -Ei 'm68k|amiga' || true)
  [ -z "$bad" ] && continue
  fail "$p changes an m68k or AmigaOS file: $bad"
done < <(grep -v '^#' "$SER")
grep -v '^#' "$SER" | grep -qE '^gcc[[:space:]]+gcc/0019-fold-mem-offsets-' || fail "series has no fold-mem-offsets fix (0019)"
pkg=$(sed -n 's/^+.*--with-pkgversion="\([^"]*\)".*/\1/p' "$HERE"/patches/amiga-gcc/0002-*-pkgversion.patch)
grep -qxF "ID=\"$pkg\"" "$BUILD" || fail "$(basename "$BUILD") does not build ($pkg)"
grep -qF -- '--with-pkgversion="$ID"' "$BUILD" || fail "$(basename "$BUILD") does not configure GCC with its ID"
grep -qF -- '--enable-languages=c ' "$BUILD" || fail "$(basename "$BUILD") does not build C only"
for t in "aarch64) T=aarch64-linux-gnu; CT=\$T ;;" "x86_64)  T=x86_64-linux-gnu;  CT=x86_64-gfopen-linux-gnu ;;" "powerpc) T=powerpc-linux-gnu; CT=\$T ;;"; do
  grep -qxF "  $t" "$BUILD" || fail "$(basename "$BUILD") does not build ${t%%)*} as it should (${t#*) })"
done
echo "linux recipe: $n patch(es) on stock GCC 16.2.0 and binutils 2.47, identity ($pkg)"
