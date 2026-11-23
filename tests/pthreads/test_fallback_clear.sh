#!/bin/bash
# tests/pthreads/test_fallback_clear.sh
# exec's SetSignal(newSignals, signalSet) changes only the bits in signalSet,
# so SetSignal(X, 0) changes nothing: to clear X it must be SetSignal(0, X).
# pthreads falls back to a fixed signal (SIGB_TIMER_FALLBACK,
# SIGB_COND_FALLBACK) when AllocSignal fails, and must clear it before the
# wait, or a stale one ends the wait at once (patches/aros-stuff/0012).
#
# Applies the patches/aros-stuff patches the tree does not already have, in
# order (the newest must apply), to aros-stuff's pthreads, then checks
# pthread.c: no SetSignal(X, 0) with X not 0, and both fallback signals are
# cleared with SetSignal(0, ...). Then checks the same tree without the newest
# patch fails, so the test sees the bug it is for.
#   SRC=<folder holding pthreads/>   use that tree (it is copied, not changed)
#   no SRC: the open6 release's source archive (as build-amiga.sh fetches it)
# GPL-3.0-or-later. Copyright (c) 2026 AmiCradle Team.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/../.." && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fail() { echo "fallback clear: FAIL: $*"; exit 1; }

mkdir -p "$W/src"
if [ -n "${SRC:-}" ]; then
  [ -f "$SRC/pthreads/pthread.c" ] || fail "no $SRC/pthreads/pthread.c"
  cp -R "$SRC/pthreads" "$W/src/"
else
  U=https://github.com/DalsinAI/gfopengcc/releases/download/v16.2.0-open6/gfopenamigagcc-16.2.0-open6-src.tar.xz
  curl -fsSL "$U" | tar -xJ -C "$W/src" --strip-components=4 \
    gfopenamigagcc-16.2.0-open6-src/amiga-gcc/projects/aros-stuff/pthreads \
    || fail "could not fetch the open6 source archive (give SRC=)"
fi

# check <pthread.c>: prints what is wrong, returns 1 if anything is
check() {
  local f=$1 bad=0
  # SetSignal(<not 0>, 0): sets nothing
  if grep -nE 'SetSignal\(\s*[^0[:space:]][^,]*,\s*0\s*\)' "$f"; then bad=1; fi
  for s in TIMER COND; do
    grep -qE "SetSignal\(\s*0\s*,\s*SIGF_${s}_FALLBACK\s*\)" "$f" \
      || { echo "SIGF_${s}_FALLBACK is not cleared with SetSignal(0, SIGF_${s}_FALLBACK)"; bad=1; }
  done
  return $bad
}

NEWP=$(ls "$HERE"/patches/aros-stuff/[0-9][0-9][0-9][0-9]-*.patch | sort | tail -1)
apply_all() {  # apply_all <tree> <skip-newest: 0|1>
  local p
  for p in $(ls "$HERE"/patches/aros-stuff/[0-9][0-9][0-9][0-9]-*.patch | sort); do
    [ "$2" = 1 ] && [ "$p" = "$NEWP" ] && continue
    if ( cd "$1" && patch -s -p1 --dry-run < "$p" ) >/dev/null 2>&1; then ( cd "$1" && patch -s -p1 < "$p" )
    elif [ "$p" = "$NEWP" ]; then fail "$(basename "$p") does not apply after the others"
    fi
    # an older patch that does not apply is already in the tree: the open6
    # archive holds 0001-0009, some of them changed again by later ones
  done
}
cp -R "$W/src" "$W/old"
apply_all "$W/src" 0
check "$W/src/pthreads/pthread.c" || fail "pthread.c with every patch"

# the newest patch is the fix only while 0012 is newest; then the tree
# without it must show the bug
if [ "$(basename "$NEWP" | cut -c1-4)" = 0012 ]; then
  apply_all "$W/old" 1
  if check "$W/old/pthreads/pthread.c" >/dev/null; then
    fail "pthread.c without 0012 passes too: the check does not see the bug"
  fi
  echo "fallback clear: without 0012 the check fails, as it should"
fi
echo "fallback clear: PASS: both fallback signals are cleared before a wait, and no SetSignal(X, 0) is left"
