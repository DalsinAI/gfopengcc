#!/bin/bash
# tests/userland-recipe-test.sh: tests/userland-recipe.sh passes this checkout and
# refuses a lock or build script that breaks the recipe's rules.
# No build, no network. GPL-3.0-or-later. Copyright (c) 2026 AmiCradle Team.
set -uo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
T=$HERE/tests/userland-recipe.sh
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
fails=0
pass() { if out=$(env "$@" "$T" 2>&1); then echo "ok   passes: ${*:-this checkout}"; else echo "FAIL should pass: $* ($out)"; fails=$((fails+1)); fi; }
refuse() { local why=$1; shift; if out=$(env "$@" "$T" 2>&1); then echo "FAIL should refuse: $why ($out)"; fails=$((fails+1)); else echo "ok   refuses: $why ($out)"; fi; }
L=$HERE/scripts/userland.lock; B=$HERE/scripts/build-userland.sh
pass
# lock
sed 's/e6738e29/00000000/' "$L" > "$D/lock-gcc"
refuse "a GCC pin unlike m68k-aros's" LOCK="$D/lock-gcc"
sed 's/3068128c/00000000/' "$L" > "$D/lock-binutils"
refuse "a binutils pin unlike m68k-aros's" LOCK="$D/lock-binutils"
sed 's/glibc-2\.35\.tar\.xz$/glibc-2.39.tar.xz/' "$L" > "$D/lock-glibc"
refuse "a glibc other than 2.35 (the floor)" LOCK="$D/lock-glibc"
grep -v '^linux ' "$L" > "$D/lock-nolinux"
refuse "no Linux headers" LOCK="$D/lock-nolinux"
{ cat "$L"; echo "isl https://example.org/isl.tar.xz 00 isl.tar.xz"; } > "$D/lock-extra"
refuse "a fifth source" LOCK="$D/lock-extra"
# build script
sed 's/^ID=.*/ID="GFOpenAmigaGCC 16.2.0-open8"/' "$B" > "$D/build-id"
refuse "another identity" BUILD="$D/build-id"
sed 's/--enable-languages=c,c++ /--enable-languages=c /' "$B" > "$D/build-c"
refuse "C only" BUILD="$D/build-c"
sed 's|^SYSROOT=.*|SYSROOT=/opt/sysroot|' "$B" > "$D/build-sysroot"
refuse "a sysroot outside the prefix" BUILD="$D/build-sysroot"
sed 's/ --enable-default-pie//' "$B" > "$D/build-pie"
refuse "no PIE by default" BUILD="$D/build-pie"
sed 's|"$HERE/patches/linux/series"|"$HERE/patches/aros/series"|' "$B" > "$D/build-series"
refuse "another patch series" BUILD="$D/build-series"
sed 's/T=aarch64-linux-gnu; CT=\$T; KARCH=arm64/T=aarch64-linux-musl; CT=$T; KARCH=arm64/' "$B" > "$D/build-target"
refuse "another aarch64 target" BUILD="$D/build-target"
sed "s/--with-pkgversion='\$ID'\"\$/\"/" "$B" > "$D/build-noid"
refuse "a GCC pass without the identity" BUILD="$D/build-noid"
[ "$fails" -eq 0 ] && echo "userland recipe test: all passed" || { echo "userland recipe test: $fails failed"; exit 1; }
