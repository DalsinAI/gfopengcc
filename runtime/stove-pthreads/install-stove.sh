#!/bin/sh
# Copyright (c) 2026 AmiCradle Team. MIT licence (see LICENSE at the repository root).
# Puts the newest aros-stuff patch (0011 today) into stoves: each libpthread.a gets build-amiga.sh's
# copy (pthread.o rebuilt from the patched source). sched.o and semaphore.o
# are the stove's own, unchanged.
# Each stove is built against first (build-amiga.sh, which proves the stove's
# pthread.o rebuilds the same before it patches anything), and checked after: a
# plain "-lpthread" link must now come out byte for byte as the test linked
# against the new archive by name. Any failure puts that stove back. Replaced
# files are kept in <stove>/pthreads-<patch>-backup-<time>/ with PUT-BACK.txt.
# Each archive is copied beside its target and renamed over it, so a link
# running at the same moment sees the old file or the new one, never half of one.
#   sh install-stove.sh [stove folder...]   (default: os32-gcc16 in ~/AmiCradle/kitchen/stoves,
#                                            or os32-gcc16-open6 in ~/AmiCradle/stoves)
set -eu
if [ -d "$HOME/AmiCradle/kitchen/stoves" ]; then DEF="$HOME/AmiCradle/kitchen/stoves/os32-gcc16"
elif [ -d "$HOME/AmiCradle/stoves" ]; then DEF="$HOME/AmiCradle/stoves/os32-gcc16-open6"
else echo "install-stove.sh: no ~/AmiCradle/kitchen/stoves or ~/AmiCradle/stoves on $(hostname): run it on a machine with the stoves" >&2; exit 2; fi
echo "install-stove.sh on $(hostname) as $(id -un)"
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
[ $# -gt 0 ] || set -- "$DEF"
NEWN=$(ls "$HERE"/../../patches/aros-stuff/[0-9][0-9][0-9][0-9]-*.patch | sort | tail -1 | xargs basename | cut -c1-4)
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
  [ -n "$todo" ] || { echo "   already has patch $NEWN: nothing to do"; rm -rf "$T"; trap - EXIT; return 0; }
  BK="$S/pthreads-$NEWN-backup-$STAMP"
  for f in $todo; do mkdir -p "$BK/$(dirname "$f")"; cp -p "$LIB/$f" "$BK/$f"; done
  printf 'Put back: for each libpthread.a under this folder, cp -p it to %s/<same path>\n' "$LIB" > "$BK/PUT-BACK.txt"
  putback() { for f in $todo; do cp -p "$BK/$f" "$LIB/$f.pthnew" && mv -f "$LIB/$f.pthnew" "$LIB/$f"; done; }
  for f in $todo; do cp "$T/b/lib/$f" "$LIB/$f.pthnew" && mv -f "$LIB/$f.pthnew" "$LIB/$f"; done
  ok=1
  CF="-noixemul -m68040 -O2"
  # shellcheck disable=SC2086
  for i in ${EXTRA_INC:-}; do CF="$CF -isystem $i"; done
  # shellcheck disable=SC2086
  "$CC" $CF -o "$T/after" "$HERE/../../tests/pthreads/exitcancel.c" -lpthread > "$T/after.log" 2>&1 || { ok=0; tail -5 "$T/after.log"; }
  if [ $ok = 1 ]; then
    cmp -s "$T/after" "$T/b/tests/ExitCancel" || { echo "   a plain -lpthread link does not match the patched test"; ok=0; }
    # shellcheck disable=SC2086
    "$CC" $CF -Wall -o "$T/after2" "$HERE/../../tests/pthreads/condsignal.c" -lpthread > "$T/after.log" 2>&1 \
      && cmp -s "$T/after2" "$T/b/tests/CondSignal" || { echo "   a plain -lpthread link of condsignal does not match the patched test"; ok=0; }
    for f in $todo; do cmp -s "$LIB/$f" "$T/b/lib/$f" || { echo "   $f is not the new one"; ok=0; }; done
  fi
  if [ $ok = 1 ]; then
    echo "   installed: $(echo $todo | wc -w) libpthread.a (backup $BK); -lpthread now links patch $NEWN"
  else
    putback; echo "   FAILED: put back as it was"; FAIL=1
  fi
  rm -rf "$T"; trap - EXIT
}

for s in "$@"; do one "$s"; done
exit $FAIL
