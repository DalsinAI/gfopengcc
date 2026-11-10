#!/bin/sh
# Copyright (c) 2026 AmiCradle Team. MIT licence (see LICENSE at the repository root).
# Puts gfmalloc's size-wrap fix (amicradle-guest #687) into stoves: each
# libgfmalloc.a gets build-amiga.sh's copy. The specs file is not touched.
# Each stove is built against first (build-amiga.sh, which proves the stove's
# gfmalloc.o rebuilds the same from a known commit before it builds the fixed
# one), and checked after: the stove's libgfmalloc.a must hold the fixed code,
# and a plain link must still take gfmalloc. Any failure puts that stove back.
# The replaced file is kept in <stove>/gfmalloc-0687-backup-<time>/ with
# PUT-BACK.txt. The archive is copied beside its target and renamed over it,
# so a link running at the same moment sees the old file or the new one.
#   sh install-stove.sh [stove folder...]
#   (default: os32-gcc16-open6, os32-gcc16 and os32 in ~/AmiCradle/stoves, the stoves gfmalloc went into)
set -eu
[ -d "$HOME/AmiCradle/stoves" ] || { echo "install-stove.sh: no ~/AmiCradle/stoves on $(hostname): run it on a machine with the stoves" >&2; exit 2; }
echo "install-stove.sh on $(hostname) as $(id -un)"
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
[ $# -gt 0 ] || set -- "$HOME/AmiCradle/stoves/os32-gcc16-open6" "$HOME/AmiCradle/stoves/os32-gcc16" "$HOME/AmiCradle/stoves/os32"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
NEW=7ce01b174a5ae19cfb9c4de4acc5deaeadff5d5d
FAIL=0

one() {
  S=$1; P="$S/prefix"; CC="$P/bin/m68k-amigaos-gcc"; NM="$P/bin/m68k-amigaos-nm"; AR="$P/bin/m68k-amigaos-ar"; OD="$P/bin/m68k-amigaos-objdump"
  LIB="$P/m68k-amigaos/libnix/lib"
  [ -x "$CC" ] || { echo "== $S: no m68k-amigaos-gcc, left alone"; return 0; }
  [ -f "$LIB/libgfmalloc.a" ] || { echo "== $S: no libgfmalloc.a (gfmalloc never installed), left alone"; return 0; }
  echo "== $S ($("$CC" --version | head -1))"
  T=$(mktemp -d); trap 'rm -rf "${T:?}"' EXIT
  if ! STOVE="$S" OUT="$T/b" sh "$HERE/build-amiga.sh" > "$T/build.log" 2>&1; then
    echo "   build-amiga.sh fails with this stove: left alone"; tail -8 "$T/build.log"; FAIL=1; rm -rf "${T:?}"; trap - EXIT; return 0
  fi
  sed 's/^/   /' "$T/build.log" | grep -v '^   [0-9a-f]\{64\} ' || :
  [ -f "$T/b/lib/libgfmalloc.a" ] || { echo "   already has the fix: nothing to do"; rm -rf "${T:?}"; trap - EXIT; return 0; }
  BK="$S/gfmalloc-0687-backup-$STAMP"; mkdir -p "$BK"
  cp -p "$LIB/libgfmalloc.a" "$BK/libgfmalloc.a"
  printf 'Put back: cp -p %s/libgfmalloc.a %s/libgfmalloc.a\n' "$BK" "$LIB" > "$BK/PUT-BACK.txt"
  putback() { cp -p "$BK/libgfmalloc.a" "$LIB/libgfmalloc.a.0687new" && mv -f "$LIB/libgfmalloc.a.0687new" "$LIB/libgfmalloc.a"; }
  cp "$T/b/lib/libgfmalloc.a" "$LIB/libgfmalloc.a.0687new" && mv -f "$LIB/libgfmalloc.a.0687new" "$LIB/libgfmalloc.a"
  ok=1
  mkdir -p "$T/x"; ( cd "$T/x" && "$AR" x "$LIB/libgfmalloc.a" )
  "$OD" -d "$T/x/gfmalloc.o" | tail -n +4 > "$T/x/a"; "$OD" -d "$T/b/obj/gfmalloc.o" | tail -n +4 > "$T/x/b"
  cmp -s "$T/x/a" "$T/x/b" || { echo "   the stove's libgfmalloc.a does not hold the fixed code"; ok=0; }
  CF="-m68040 -O2 -noixemul -fno-delete-null-pointer-checks"
  # shellcheck disable=SC2086
  "$CC" $CF -o "$T/plain" "$T/b/obj/src-$NEW/common/gfmalloc/malloctest.c" > "$T/after.log" 2>&1 || { ok=0; tail -5 "$T/after.log"; }
  if [ $ok = 1 ] && ! "$NM" "$T/plain" | grep -q ' ___gfmalloc$'; then echo "   a plain link no longer takes gfmalloc"; ok=0; fi
  if [ $ok = 1 ]; then
    mkdir -p "$S/gfmalloc-0687-tests"; cp "$T/plain" "$S/gfmalloc-0687-tests/malloctest-stove"
    echo "   installed: libgfmalloc.a (backup $BK); a plain link takes the fixed gfmalloc ($S/gfmalloc-0687-tests/malloctest-stove for the lab)"
  else
    putback; echo "   FAILED: put back as it was"; FAIL=1
  fi
  rm -rf "${T:?}"; trap - EXIT
}

for s in "$@"; do one "$s"; done
exit $FAIL
