#!/bin/sh
# Copyright (c) 2026 AmiCradle Team. MIT licence (see LICENSE at the repository root).
# aros-stuff patch 0010 (at exit, pthreads cancels the threads still running
# and removes any left after 2 s) for a stove that was built before it,
# without rebuilding the stove: for each libpthread.a the stove has, pthread.o
# is rebuilt from the patched source with the flags the stove's was built
# with. sched.o and semaphore.o stay the stove's own.
#
# Before it builds anything patched it rebuilds pthread.c at 0001-0009 the
# same way and checks the code matches the stove's own pthread.o in every
# multilib, so the new member is made exactly as the stove's was. A stove
# whose pthread.o already matches the patched build is left alone.
#
# Builds and checks only; install-stove.sh puts the result into the stove.
#   STOVE=<stove folder> OUT=<folder> sh build-amiga.sh
# Output: OUT/lib/<multilib>/libpthread.a, OUT/tests/ExitCancel (patched
# library) and OUT/tests/ExitCancel-old (the stove's), from
# tests/pthreads/exitcancel.c.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
STOVE=${STOVE:-"$HOME/AmiCradle/stoves/os32-gcc16-open6"}
P="$STOVE/prefix"
CC="$P/bin/m68k-amigaos-gcc"; AR="$P/bin/m68k-amigaos-ar"; OD="$P/bin/m68k-amigaos-objdump"
[ -x "$CC" ] || { echo "build-amiga.sh: no $CC" >&2; exit 2; }
LIB="$P/m68k-amigaos/lib"
echo "built on $(hostname) as $(id -un), stove $STOVE ($("$CC" --version | head -1))"
OUT=${OUT:-"$HERE/build-amiga"}; rm -rf "$OUT/lib" "$OUT/obj" "$OUT/tests"; mkdir -p "$OUT/lib" "$OUT/tests" "$OUT/obj"
NEWP=$(ls "$ROOT"/patches/aros-stuff/0010-*.patch)

# aros-stuff's pthreads at the commit the stove was built from
SRC="$OUT/obj/aros-stuff"
URL=$(awk '$1=="aros-stuff"{print $2}' "$ROOT/scripts/sources.lock")
SHA=$(awk '$1=="aros-stuff"{print $3}' "$ROOT/scripts/sources.lock")
got=0
if command -v git >/dev/null 2>&1; then
  mkdir -p "$SRC" && ( cd "$SRC" && git init -q && git fetch -q --depth 1 "$URL" "$SHA" && git checkout -q FETCH_HEAD ) >/dev/null 2>&1 && got=1
fi
if [ $got = 0 ]; then
  # the same tree, from the open6 release's source archive
  rm -rf "$SRC"; mkdir -p "$SRC"
  U=https://github.com/DalsinAI/gfopengcc/releases/download/v16.2.0-open6/gfopenamigagcc-16.2.0-open6-src.tar.xz
  curl -fsSL "$U" | tar -xJ -C "$SRC" --strip-components=4 \
    gfopenamigagcc-16.2.0-open6-src/amiga-gcc/projects/aros-stuff/pthreads
  echo "aros-stuff sources: open6 source archive"
else
  echo "aros-stuff sources: $URL $SHA"
fi
# 0001-0009, as scripts/build.sh applies them (a tree that already has one keeps it)
for p in "$ROOT"/patches/aros-stuff/000[1-9]-*.patch; do
  if ( cd "$SRC" && patch -s -p1 --dry-run < "$p" ) >/dev/null 2>&1; then ( cd "$SRC" && patch -s -p1 < "$p" )
  elif ( cd "$SRC" && patch -s -p1 -R --dry-run < "$p" ) >/dev/null 2>&1; then :
  else echo "$(basename "$p") does not apply to the sources; stopping" >&2; exit 1; fi
done
mkdir -p "$OUT/obj/new"; cp -R "$SRC/pthreads" "$OUT/obj/new/"
( cd "$OUT/obj/new" && patch -s -p1 < "$NEWP" )
echo "patch: $(basename "$NEWP")"

# libpthread's Makefile: -noixemul, the pthreads folder, the NDK; no -O.
# The NDK is the folder holding inline/alib.h: ndk-include.vendor on open6,
# found by name on a stove that keeps it elsewhere
NDK="$P/m68k-amigaos/ndk-include.vendor"
if [ ! -f "$NDK/inline/alib.h" ]; then
  a=$(find "$P/m68k-amigaos" -path '*/inline/alib.h' 2>/dev/null | sort | head -1)
  [ -n "$a" ] || { echo "no inline/alib.h in the stove: name the NDK with EXTRA_INC" >&2; [ -n "${EXTRA_INC:-}" ] || exit 1; }
  [ -n "$a" ] && NDK=$(dirname "$(dirname "$a")")
fi
echo "NDK headers: $NDK"
BASE="-noixemul -isystem $NDK"
# a bare toolchain (the release archive) names its NDK: EXTRA_INC="dir dir"
for i in ${EXTRA_INC:-}; do BASE="$BASE -isystem $i"; done
n=0
for v in ".:" "libb:-fbaserel" "libm020:-m68020" "libb/libm020:-fbaserel -m68020" "libb32/libm020:-fbaserel32 -m68020"; do
  d=${v%%:*}; f=${v#*:}
  [ -f "$LIB/$d/libpthread.a" ] || { echo "$d: the stove has no libpthread.a, left alone"; continue; }
  w="$OUT/obj/$d"; mkdir -p "$w/old" "$w/new" "$w/stove"
  ( cd "$w/stove" && "$AR" x "$LIB/$d/libpthread.a" pthread.o )
  # shellcheck disable=SC2086
  ( cd "$w/old" && "$CC" -c $BASE -I"$SRC/pthreads" $f "$SRC/pthreads/pthread.c" -o pthread.o )
  # shellcheck disable=SC2086
  ( cd "$w/new" && "$CC" -c $BASE -I"$OUT/obj/new/pthreads" $f -Wall "$OUT/obj/new/pthreads/pthread.c" -o pthread.o )
  "$OD" -d "$w/stove/pthread.o" | tail -n +4 > "$w/a"; "$OD" -d "$w/old/pthread.o" | tail -n +4 > "$w/b"
  "$OD" -d "$w/new/pthread.o" | tail -n +4 > "$w/c"
  if cmp -s "$w/a" "$w/c"; then
    echo "$d: the stove's pthread.o already has patch 0010, left alone"; n=$((n+1)); continue
  fi
  cmp -s "$w/a" "$w/b" || { echo "$d: pthread.c at 0001-0009 does not rebuild as the stove's pthread.o; stopping" >&2; diff "$w/a" "$w/b" | head -20 >&2; exit 1; }
  mkdir -p "$OUT/lib/$d"; cp "$LIB/$d/libpthread.a" "$OUT/lib/$d/libpthread.a"
  ( cd "$w/new" && "$AR" r "$OUT/lib/$d/libpthread.a" pthread.o && "$P/bin/m68k-amigaos-ranlib" "$OUT/lib/$d/libpthread.a" )
  o=$("$AR" t "$LIB/$d/libpthread.a" | tr '\n' ' '); nw=$("$AR" t "$OUT/lib/$d/libpthread.a" | tr '\n' ' ')
  [ "$o" = "$nw" ] || { echo "$d: members changed ($o -> $nw)" >&2; exit 1; }
  echo "$d: the stove's pthread.o rebuilt the same; new libpthread.a $(wc -c < "$OUT/lib/$d/libpthread.a") bytes (was $(wc -c < "$LIB/$d/libpthread.a"))"
  n=$((n+1))
done
[ $n -gt 0 ] || { echo "no libpthread.a in $LIB" >&2; exit 1; }
# a stove from scripts/build.sh's 68040 seed has libm040 folders holding
# copies of their libm020 folders' files: they get the same new copy
for d in libm040 libm040/libm881 libb/libm040 libb/libm040/libm881 libb32/libm040 libb32/libm040/libm881; do
  s=$(echo "$d" | sed 's#libm040.*#libm020#')
  [ -f "$LIB/$d/libpthread.a" ] || continue
  [ -f "$OUT/lib/$s/libpthread.a" ] || { echo "$d: $s already has patch 0010, left alone"; continue; }
  cmp -s "$LIB/$d/libpthread.a" "$LIB/$s/libpthread.a" || { echo "$d: libpthread.a is not a copy of $s's; stopping" >&2; exit 1; }
  mkdir -p "$OUT/lib/$d"; cp "$OUT/lib/$s/libpthread.a" "$OUT/lib/$d/libpthread.a"
  echo "$d: a copy of $s's, as the stove had it"
done
# any libpthread.a in the stove this script doesn't know is a reason to stop
for f in $(cd "$LIB" && find . -name libpthread.a | sed 's|^\./||'); do
  case "$f" in libpthread.a|libb/libpthread.a|libm020/libpthread.a|libb/libm020/libpthread.a|libb32/libm020/libpthread.a) ;;
    libm040/libpthread.a|libb/libm040/libpthread.a|libb32/libm040/libpthread.a) ;;
    libm040/libm881/libpthread.a|libb/libm040/libm881/libpthread.a|libb32/libm040/libm881/libpthread.a) ;;
    *) echo "$f: a libpthread.a this script doesn't know; stopping" >&2; exit 1 ;; esac
done

# the lab test, against the new library and the stove's
T="$ROOT/tests/pthreads/exitcancel.c"
CF="-noixemul -m68040 -O2"
EXTRA_CF=""; for i in ${EXTRA_INC:-}; do EXTRA_CF="$EXTRA_CF -isystem $i"; done
# shellcheck disable=SC2086
MD=$("$CC" $CF -print-multi-directory); NEWLIB="$OUT/lib/$MD/libpthread.a"
[ -f "$NEWLIB" ] || NEWLIB="$LIB/$MD/libpthread.a"   # the stove already has it
echo "test multilib: $MD"
# shellcheck disable=SC2086
"$CC" $CF $EXTRA_CF -o "$OUT/tests/ExitCancel" "$T" "$NEWLIB"
# shellcheck disable=SC2086
"$CC" $CF $EXTRA_CF -o "$OUT/tests/ExitCancel-old" "$T" -lpthread
( cd "$OUT" && find tests lib -type f | sort | xargs sha256sum )
