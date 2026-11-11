#!/bin/sh
# Copyright (c) 2026 AmiCradle Team. MIT licence (see LICENSE at the repository root).
# Puts aros-stuff patch 0010 into stoves: each libpthread.a gets build-amiga.sh's
# copy (pthread.o rebuilt from the patched source). sched.o and semaphore.o
# are the stove's own, unchanged.
# Each stove is built against first (build-amiga.sh, which proves the stove's
# pthread.o rebuilds the same before it patches anything), and checked after: a
# plain "-lpthread" link must now come out byte for byte as the test linked
# against the new archive by name. Any failure puts that stove back. Replaced
# files are kept in <stove>/pthreads-0010-backup-<time>/ with PUT-BACK.txt.
# Each archive is copied beside its target and renamed over it, so a link
# running at the same moment sees the old file or the new one, never half of one.
#   sh install-stove.sh [stove folder...]   (default: os32-gcc16-open6 in ~/AmiCradle/stoves)
set -eu
[ -d "$HOME/AmiCradle/stoves" ] || { echo "install-stove.sh: no ~/AmiCradle/stoves on $(hostname): run it on a machine with the stoves" >&2; exit 2; }
echo "install-stove.sh on $(hostname) as $(id -un)"
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
[ $# -gt 0 ] || set -- "$HOME/AmiCradle/stoves/os32-gcc16-open6"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
FAIL=0

one() {
  S=$1; P="$S/prefix"; CC="$P/bin/m68k-amigaos-gcc"
  LIB="$P/m68k-amigaos/lib"
  [ -x "$CC" ] || { echo "== $S: no m68k-amigaos-gcc, left alone"; return 0; }
  echo "== $S ($("$CC" --version | head -1))"
  T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
  if ! STOVE="$S" OUT="$T/b" sh "$HERE/build-amiga.sh" > "$T/build.log" 2>&1; then
    echo "   build-amiga.sh fails with this stove: left alone"; tail -8 "$T/build.log"; FAIL=1; rm -rf "$T"; trap - EXIT; return 0
  fi
  sed 's/^/   /' "$T/build.log" | grep -v '^   [0-9a-f]\{64\} ' || :
  todo=$(cd "$T/b/lib" && find . -name libpthread.a | sed 's|^\./||' | sort)
  [ -n "$todo" ] || { echo "   already has patch 0010: nothing to do"; rm -rf "$T"; trap - EXIT; return 0; }
  BK="$S/pthreads-0010-backup-$STAMP"
  for f in $todo; do mkdir -p "$BK/$(dirname "$f")"; cp -p "$LIB/$f" "$BK/$f"; done
  printf 'Put back: for each libpthread.a under this folder, cp -p it to %s/<same path>\n' "$LIB" > "$BK/PUT-BACK.txt"
  putback() { for f in $todo; do cp -p "$BK/$f" "$LIB/$f.0010new" && mv -f "$LIB/$f.0010new" "$LIB/$f"; done; }
  for f in $todo; do cp "$T/b/lib/$f" "$LIB/$f.0010new" && mv -f "$LIB/$f.0010new" "$LIB/$f"; done
  ok=1
  CF="-noixemul -m68040 -O2"
  # shellcheck disable=SC2086
  for i in ${EXTRA_INC:-}; do CF="$CF -isystem $i"; done
  # shellcheck disable=SC2086
  "$CC" $CF -o "$T/after" "$HERE/../../tests/pthreads/exitcancel.c" -lpthread > "$T/after.log" 2>&1 || { ok=0; tail -5 "$T/after.log"; }
  if [ $ok = 1 ]; then
    cmp -s "$T/after" "$T/b/tests/ExitCancel" || { echo "   a plain -lpthread link does not match the patched test"; ok=0; }
    for f in $todo; do cmp -s "$LIB/$f" "$T/b/lib/$f" || { echo "   $f is not the new one"; ok=0; }; done
  fi
  if [ $ok = 1 ]; then
    echo "   installed: $(echo $todo | wc -w) libpthread.a (backup $BK); -lpthread now links patch 0010"
  else
    putback; echo "   FAILED: put back as it was"; FAIL=1
  fi
  rm -rf "$T"; trap - EXIT
}

for s in "$@"; do one "$s"; done
exit $FAIL
