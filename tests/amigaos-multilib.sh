#!/bin/bash
# Validate the dedicated 68040 AmigaOS target libraries and their selection.
set -euo pipefail

P=${1:?usage: tests/amigaos-multilib.sh PREFIX}
CC=$P/bin/m68k-amigaos-gcc
CXX=$P/bin/m68k-amigaos-g++
HERE=$(cd "$(dirname "$0")/.." && pwd)
O=$(mktemp -d)
trap 'rm -rf "$O"' EXIT

expected='.
libb
libm020
libm040
libm060
libm020/libm881
libm040/libm881
libb/libm020
libb/libm040
libb/libm060
libb/libm020/libm881
libb/libm040/libm881
libb32/libm020
libb32/libm040
libb32/libm060
libb32/libm020/libm881
libb32/libm040/libm881'
actual=$($CC -print-multi-lib | cut -d';' -f1)
if ! diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$actual"); then
  echo 'AmigaOS multilib set is not the expected seventeen-library Open7 set'
  exit 1
fi

check_dir() {
  local want=$1; shift
  local got
  got=$($CC "$@" -print-multi-directory)
  [ "$got" = "$want" ] || {
    echo "$* selects '$got', expected '$want'"; exit 1;
  }
}

check_dir libm020 -m68030
check_dir libm020 -m68020-40
check_dir libm020 -m68020-60
check_dir libm040 -m68040
check_dir libm040 -mcpu=68040
check_dir libm040 -march=68040
check_dir libm040/libm881 -m68040 -m68881
check_dir libb/libm040/libm881 -m68040 -m68881 -fbaserel
check_dir libb32/libm040/libm881 -m68040 -m68881 -fbaserel32
check_dir libm060 -m68060

link_spec=$($CC -m68040 -m68881 -### -x c /dev/null 2>&1)
grep -Fq -- '-fl libm040' <<<"$link_spec" || {
  echo 'a true 68040 link does not select the libm040 C-runtime directory'; exit 1;
}
if grep -Fq -- '-fl libm020' <<<"$link_spec"; then
  echo 'a true 68040 link still selects the libm020 C-runtime directory'; exit 1
fi
for library in libgcc.a libpthread.a libnix.a; do
  selected=$($CC -m68040 -m68881 -print-file-name="$library")
  case "$selected" in
    */libm040/*) ;;
    *) echo "68040/68881 selects $selected for $library"; exit 1 ;;
  esac
done

log=$O/t3race.log
if ! $CXX -m68040 -m68881 -O2 -std=gnu++23 \
    -o "$O/t3race" "$HERE/tests/pthreads/t3race.cpp" \
    -lpthread -latomic -lstdc++ >"$log" 2>&1; then
  echo 'the dedicated 68040 C++ link failed'
  sed -n '1,40p' "$log"
  exit 1
fi
if grep -q "duplicate section .* has different contents" "$log"; then
  echo 'the 68040 C++ link still mixes differently tuned COMDAT sections'
  sed -n '1,40p' "$log"
  exit 1
fi

echo 'AmigaOS multilib: 17 entries; true 68040 targets and range targets select correctly'
echo 'AmigaOS multilib: 68040/68881 C++ link is warning-free'
