#!/bin/bash
# tests/aarch64-recipe-test.sh: tests/aarch64-recipe.sh passes this checkout and
# refuses a series, lock or build script that breaks the recipe's rules.
# No build, no network. GPL-3.0-or-later. Copyright (c) 2026 AmiCradle Team.
set -uo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
T=$HERE/tests/aarch64-recipe.sh
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
fails=0
pass() { if out=$(env "$@" "$T" 2>&1); then echo "ok   passes: ${*:-this checkout}"; else echo "FAIL should pass: $* ($out)"; fails=$((fails+1)); fi; }
refuse() { local why=$1; shift; if out=$(env "$@" "$T" 2>&1); then echo "FAIL should refuse: $why ($out)"; fails=$((fails+1)); else echo "ok   refuses: $why ($out)"; fi; }
S=$HERE/patches/aarch64/series; L=$HERE/scripts/aarch64.lock; B=$HERE/scripts/build-aarch64.sh
pass
# series
{ cat "$S"; echo "gcc       gcc/0001-amigaos-int32_t-is-int-no-mcrt-means-mcrt-nix20-stov.patch"; } > "$D/amigaos"
refuse "an AmigaOS-only patch" SERIES="$D/amigaos"
{ cat "$S"; echo "gcc       gcc/0003-m68k-early-clobber-the-m68040-fix_trunc-scratch-regi.patch"; } > "$D/m68k"
refuse "an m68k patch" SERIES="$D/m68k"
{ cat "$S"; echo "gcc       aros-stuff/0011-pthreads-every-cond-signal-wakes-a-thread-still-waiting.patch"; } > "$D/pthreads"
refuse "a pthreads patch" SERIES="$D/pthreads"
{ cat "$S"; echo "gcc       aros/gcc/0001-gcc-16.2.0-aros.diff"; } > "$D/aros"
refuse "AROS's diff" SERIES="$D/aros"
{ cat "$S"; echo "gcc       gcc/0099-not-there.patch"; } > "$D/missing"
refuse "a patch that is not there" SERIES="$D/missing"
{ cat "$S"; echo "libnix    gcc/0019-fold-mem-offsets-a-memory-to-memory-move-is-no-root.patch"; } > "$D/tree"
refuse "an unknown tree" SERIES="$D/tree"
grep -v 0019 "$S" > "$D/no0019"
refuse "a series without 0019" SERIES="$D/no0019"
# lock
sed 's/e6738e29/00000000/' "$L" > "$D/lock-gcc"
refuse "a GCC pin unlike m68k-aros's" LOCK="$D/lock-gcc"
{ cat "$L"; echo "isl https://example.org/isl.tar.xz 00 isl.tar.xz"; } > "$D/lock-extra"
refuse "a third source" LOCK="$D/lock-extra"
# build script
sed 's/^ID=.*/ID="GFOpenAmigaGCC 16.2.0-open8"/' "$B" > "$D/build-id"
refuse "another identity" BUILD="$D/build-id"
sed 's/--enable-languages=c /--enable-languages=c,c++ /' "$B" > "$D/build-cxx"
refuse "C++ too" BUILD="$D/build-cxx"
sed 's/^T=aarch64-linux-gnu$/T=aarch64-elf/' "$B" > "$D/build-target"
refuse "another target" BUILD="$D/build-target"
[ $fails -eq 0 ] && echo "aarch64-recipe-test: all passed" || { echo "aarch64-recipe-test: $fails failed"; exit 1; }
