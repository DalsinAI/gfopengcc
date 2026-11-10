#!/bin/sh
# Copyright (c) 2026 AmiCradle Team. MIT licence (see LICENSE at the repository root).
# gfmalloc's size-wrap fix (amicradle-guest #687) for stoves that got gfmalloc
# before it, without touching anything else: only libgfmalloc.a changes (its one
# member, gfmalloc.o). The specs block that puts -lgfmalloc ahead of -lnix stays.
#
# Before it builds the new object, it rebuilds gfmalloc.c as the stove has it and
# checks that the code matches the stove's gfmalloc.o, so the new object is made
# the way the stove's was. A stove whose gfmalloc.o already matches the fixed
# source is reported and left alone.
#
# Builds and checks only; install-stove.sh puts the result into the stove.
#   STOVE=<stove folder> OUT=<folder> sh build-amiga.sh
# Output: OUT/lib/libgfmalloc.a (absent when the stove already has the fix),
# OUT/tests/malloctest (the fixed gfmalloc, linked by name) and
# OUT/tests/malloctest-old (a plain link: the stove's gfmalloc), from
# amicradle-guest's common/gfmalloc/malloctest.c at the fixed commit.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
STOVE=${STOVE:-"$HOME/AmiCradle/stoves/os32-gcc16-open6"}
P="$STOVE/prefix"
CC="$P/bin/m68k-amigaos-gcc"; AR="$P/bin/m68k-amigaos-ar"; NM="$P/bin/m68k-amigaos-nm"; OD="$P/bin/m68k-amigaos-objdump"
[ -x "$CC" ] || { echo "build-amiga.sh: no $CC" >&2; exit 2; }
LIB="$P/m68k-amigaos/libnix/lib"
[ -f "$LIB/libgfmalloc.a" ] || { echo "build-amiga.sh: $STOVE has no libgfmalloc.a (gfmalloc was never installed): nothing to refresh" >&2; exit 3; }
echo "built on $(hostname) as $(id -un), stove $STOVE ($("$CC" --version | head -1))"
OUT=${OUT:-"$HERE/build-amiga"}
rm -rf "${OUT:?}/lib" "${OUT:?}/obj" "${OUT:?}/tests"; mkdir -p "$OUT/lib" "$OUT/tests" "$OUT/obj"

# amicradle-guest common/gfmalloc: the fixed commit (#687, merged 10 Nov 2026)
# and the ones a stove's gfmalloc.o can be from (the first install, 7 Nov, and the guard build)
GUEST=https://github.com/DalsinAI/amicradle-guest
NEW=7ce01b174a5ae19cfb9c4de4acc5deaeadff5d5d
OLDS="e138c4c4026a042bb2cae2965d6f6aaf0b6f90cd 8b5c2b8dd81af702388caa3666b671a727332958"
src() { # SHA -> OUT/obj/src-SHA/common/gfmalloc
  d="$OUT/obj/src-$1"
  [ -d "$d/common/gfmalloc" ] && return 0
  mkdir -p "$d" && ( cd "$d" && git init -q && git fetch -q --depth 1 "$GUEST" "$1" && git checkout -q FETCH_HEAD -- common/gfmalloc ) \
    || { echo "build-amiga.sh: can't fetch amicradle-guest $1" >&2; exit 1; }
}
# install-stove.sh's flags (amicradle-guest common/gfmalloc/build-amiga.sh): 68000 code, so any CPU's link can take it
FLAGS="-m68000 -O2 -noixemul -fno-builtin -Wall -Wextra"
code() { "$OD" -d "$1" | tail -n +4; }   # the code, less objdump's file-name line
short() { printf '%.8s' "$1"; }
mkdir -p "$OUT/obj/stove"; ( cd "$OUT/obj/stove" && "$AR" x "$LIB/libgfmalloc.a" )
[ "$("$AR" t "$LIB/libgfmalloc.a")" = gfmalloc.o ] || { echo "build-amiga.sh: the stove's libgfmalloc.a holds more than gfmalloc.o; stopping" >&2; exit 1; }
code "$OUT/obj/stove/gfmalloc.o" > "$OUT/obj/stove.dis"

src $NEW
# shellcheck disable=SC2086
"$CC" $FLAGS -c -o "$OUT/obj/gfmalloc.o" "$OUT/obj/src-$NEW/common/gfmalloc/gfmalloc.c"
code "$OUT/obj/gfmalloc.o" > "$OUT/obj/new.dis"
if cmp -s "$OUT/obj/stove.dis" "$OUT/obj/new.dis"; then
  echo "the stove's gfmalloc.o is already amicradle-guest $(short $NEW)'s (the fix): nothing to change"
else
  from=""
  for o in $OLDS; do
    src "$o"
    # shellcheck disable=SC2086
    "$CC" $FLAGS -c -o "$OUT/obj/old-$o.o" "$OUT/obj/src-$o/common/gfmalloc/gfmalloc.c"
    code "$OUT/obj/old-$o.o" > "$OUT/obj/old-$o.dis"
    if cmp -s "$OUT/obj/stove.dis" "$OUT/obj/old-$o.dis"; then from=$o; break; fi
  done
  [ -n "$from" ] || { echo "build-amiga.sh: the stove's gfmalloc.o rebuilds from none of: $OLDS; stopping" >&2; exit 1; }
  echo "the stove's gfmalloc.o rebuilds the same from amicradle-guest $(short "$from")"
  "$AR" rcs "$OUT/lib/libgfmalloc.a" "$OUT/obj/gfmalloc.o"
  for s in _malloc _free _realloc ___gfmalloc; do
    "$NM" "$OUT/lib/libgfmalloc.a" | grep -q " [TDB] $s\$" || { echo "build-amiga.sh: no $s in the new libgfmalloc.a" >&2; exit 1; }
  done
  echo "new libgfmalloc.a from $(short $NEW): $(wc -c < "$OUT/lib/libgfmalloc.a") bytes (was $(wc -c < "$LIB/libgfmalloc.a"))"
fi

# the lab test: the fixed gfmalloc by name (the stove's link line searches its own
# libnix/lib before any -L, so -lgfmalloc would take the stove's copy) and a plain link
CF="-m68040 -O2 -noixemul -fno-delete-null-pointer-checks -Wall"
T="$OUT/obj/src-$NEW/common/gfmalloc/malloctest.c"
# shellcheck disable=SC2086
"$CC" $CF -o "$OUT/tests/malloctest" "$T" "$OUT/obj/gfmalloc.o"
# shellcheck disable=SC2086
"$CC" $CF -o "$OUT/tests/malloctest-old" "$T"
( cd "$OUT" && find tests lib -type f | sort | xargs sha256sum )
