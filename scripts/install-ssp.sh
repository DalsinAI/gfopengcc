#!/bin/bash
# install-ssp.sh PREFIX
# Build the AmigaOS stack-protector runtime for every advertised multilib.
set -euo pipefail

PREFIX=$(cd "${1:?usage: $0 PREFIX}" && pwd)
HERE=$(cd "$(dirname "$0")/.." && pwd)
CC=$PREFIX/bin/m68k-amigaos-gcc
AR=$PREFIX/bin/m68k-amigaos-ar
NM=$PREFIX/bin/m68k-amigaos-nm
OUT=${OUT:-$(mktemp -d)}
mkdir -p "$OUT"
declare -A destinations

[ -x "$CC" ] && [ -x "$AR" ] && [ -x "$NM" ] || {
  echo "ssp: incomplete compiler prefix: $PREFIX"; exit 2;
}

seen=0
while IFS=';' read -r dir options; do
  flags=${options//@/ -}
  objdir=$OUT/$dir
  mkdir -p "$objdir"
  # Intentional word splitting: -print-multi-lib encodes compiler switches.
  # shellcheck disable=SC2086
  # Hunk archives preserve the object argument as their member name. Keep
  # that name relative so neither OUT nor mktemp's random suffix is embedded.
  ( cd "$objdir"
    "$CC" $flags -O2 -fno-stack-protector -fno-tree-loop-distribute-patterns \
      -c "$HERE/runtime/ssp.c" -o ssp.o
    rm -f libssp.a
    "$AR" rcs libssp.a ssp.o
  )
  # Install beside the libgcc archive selected by precisely these flags.  The
  # libnix search collapses several CPU variants onto one directory; using it
  # here would let (for example) a 68060 build overwrite the 68000 runtime.
  # shellcheck disable=SC2086
  libgcc=$($CC $flags -print-libgcc-file-name)
  [ -f "$libgcc" ] || { echo "ssp: '$dir' selects no libgcc.a"; exit 1; }
  dest=$(dirname "$libgcc")/libssp.a
  [ -z "${destinations[$dest]:-}" ] || {
    echo "ssp: '$dir' and '${destinations[$dest]}' select the same destination: $dest"
    exit 1
  }
  destinations[$dest]=$dir
  # Replace, never write through: a prefix may link its files from a stove.
  rm -f "$dest"
  cp "$objdir/libssp.a" "$dest"
  for symbol in __stack_chk_guard __stack_chk_fail __stack_chk_fail_local; do
    # Amiga hunk symbols carry the ABI's leading underscore in nm output.
    "$NM" -g --defined-only "$dest" | grep -Eq "[[:space:]][A-Z][[:space:]]+_?$symbol$" || {
      echo "ssp: '$dir' has no $symbol in $dest"; exit 1;
    }
  done
  echo "ssp: '$dir' right ($dest)"
  seen=$((seen + 1))
done < <("$CC" -print-multi-lib)

[ "$seen" -gt 0 ] || { echo "ssp: compiler reported no multilibs"; exit 1; }
echo "ssp: $seen multilib runtimes installed"
