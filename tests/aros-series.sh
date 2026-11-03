#!/bin/bash
# tests/aros-series.sh
# patches/aros/series decides every GCC patch for the m68k-aros target: each
# patches/gcc/*.patch is either applied there (as it is, or as a port under
# patches/aros/gcc) or named in a "# not:" note with the reason it is
# m68k-amigaos only, and every patch the series names exists. A new
# patches/gcc patch fails this until someone decides it for m68k-aros too.
# GPL-3.0-or-later. Copyright (c) 2026 AmiCradle Team.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
SER=$HERE/patches/aros/series
fail() { echo "aros series: $*"; exit 1; }
grep -v '^#' "$SER" | while read -r tree p; do
  [ -n "$tree" ] || continue
  [ -f "$HERE/patches/$p" ] || fail "names patches/$p, which is not there"
done
n=0
for f in "$HERE"/patches/gcc/*.patch; do
  b=$(basename "$f"); num=${b%%-*}; n=$((n+1))
  if grep -v '^#' "$SER" | grep -qE "[[:space:]]gcc/$b\$"; then continue; fi
  if grep -v '^#' "$SER" | grep -qE "[[:space:]]aros/gcc/$num-"; then continue; fi
  grep -qE "^# not: $b[[:space:]]+[^[:space:]]" "$SER" && continue
  fail "patches/gcc/$b is neither in patches/aros/series nor in a \"# not:\" note there"
done
echo "aros series: all $n patches/gcc patches decided for m68k-aros; $(grep -vc '^#' "$SER") patches in the series"
