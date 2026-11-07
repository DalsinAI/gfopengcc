#!/bin/bash
# check.sh BINDIR
#
# A compiler must ignore ambient cost-model files in its current directory,
# while an explicit M68K_COSTS_FILE must still select a different model.
# Invalid values must be diagnosed and ignored.
set -euo pipefail

BIN=${1:?usage: $0 BINDIR}
CC=$BIN/m68k-amigaos-gcc
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$(mktemp -d)}
trap 'rm -rf "$OUT"' EXIT

[ -x "$CC" ] || { echo "no compiler: $CC"; exit 2; }
mkdir -p "$OUT/clean" "$OUT/ambient" "$OUT/explicit" "$OUT/invalid"
cp "$HERE/extreme-costs.txt" "$OUT/ambient/m68k-costs-speed.txt"
cp "$HERE/extreme-costs.txt" "$OUT/ambient/m68k-costs-size.txt"

compile_clean() {
  local dir=$1
  ( cd "$dir" && env -u M68K_COSTS_FILE "$CC" -m68040 -m68881 -O2 \
      -c "$HERE/probe.c" -o probe.o )
}

compile_clean "$OUT/clean"
compile_clean "$OUT/ambient"
if ! cmp -s "$OUT/clean/probe.o" "$OUT/ambient/probe.o"; then
  echo "cost model: WRONG (ambient current-directory file changed code)"
  exit 1
fi

( cd "$OUT/explicit" && M68K_COSTS_FILE="$HERE/extreme-costs.txt" \
    "$CC" -m68040 -m68881 -O2 -c "$HERE/probe.c" -o probe.o )
if cmp -s "$OUT/clean/probe.o" "$OUT/explicit/probe.o"; then
  echo "cost model: WRONG (explicit override did not change this probe)"
  exit 1
fi

( cd "$OUT/invalid" && M68K_COSTS_FILE="$HERE/invalid-costs.txt" \
    "$CC" -m68040 -m68881 -O2 -c "$HERE/probe.c" -o probe.o \
    2> diagnostics.txt )
if ! cmp -s "$OUT/clean/probe.o" "$OUT/invalid/probe.o"; then
  echo "cost model: WRONG (invalid values changed code)"
  exit 1
fi
if ! grep -q 'cost value -1 is outside 0\.\.' "$OUT/invalid/diagnostics.txt" ||
   ! grep -q 'cost value 999999999999 is outside 0\.\.' "$OUT/invalid/diagnostics.txt"; then
  echo "cost model: WRONG (one or more invalid values were not diagnosed)"
  sed -n '1,10p' "$OUT/invalid/diagnostics.txt"
  exit 1
fi

echo "cost model: right (ambient files ignored; explicit override selected; invalid values rejected)"
