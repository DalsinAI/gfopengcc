#!/bin/sh
# libstdc++'s configure leaves _GLIBCXX11_USE_C99_STDLIB (and the C++98 one)
# off for libnix, so <string> has no std::stoll, std::stoull or std::stold
# for std::string (the wstring ones are there) and ports carry their own
# (shiromino's amiga_stdstring.h). libnix has strtoll, strtoull and
# strtold under them (strtof and strtold in its libm, which g++ links), but
# configure also left _GLIBCXX_HAVE_STRTOF and _GLIBCXX_HAVE_STRTOLD off, and
# std::stold for std::string needs the second (on m68k long double is not
# double). This turns the four on in every installed c++config.h,
# then compiles tests/cxx/stoll.cpp with the new g++; if <cstdlib> or the
# test does not compile with them on, every c++config.h is put back as it
# was and it says why (the stove keeps building, as before).
#   scripts/libstdcxx-c99-stdlib.sh PREFIX
# MIT. Copyright (c) 2026 AmiCradle Team.
set -eu
PREFIX=$1
HERE=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CXX=${CXX:-$PREFIX/bin/m68k-amigaos-g++}
LOG=${LOG:-/dev/null}
files=$(find "$PREFIX/lib/gcc/m68k-amigaos" -path "*include/c++*" -name c++config.h)
[ -n "$files" ] || { echo "no c++config.h under $PREFIX/lib/gcc/m68k-amigaos"; exit 1; }
for f in $files; do
  cp "$f" "$f.c99-orig"
  for d in _GLIBCXX11_USE_C99_STDLIB _GLIBCXX98_USE_C99_STDLIB _GLIBCXX_HAVE_STRTOF _GLIBCXX_HAVE_STRTOLD; do
    grep -q "define $d 1" "$f" || sed -i "s|^/\* #undef $d \*/|#define $d 1|" "$f"
  done
done
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
ok=1
# each multilib has its own c++config.h: the 68040 soft-float and FPU ones both
for fl in "-m68040" "-m68040 -m68881"; do
  for std in gnu++23 gnu++11; do
    "$CXX" $fl -O2 -std=$std -c -o "$T/stoll.o" "$HERE/tests/cxx/stoll.cpp" >> "$LOG" 2>&1 || { ok=0; break 2; }
  done
done
for f in $files; do
  if [ $ok = 1 ]; then rm -f "$f.c99-orig"; else mv "$f.c99-orig" "$f"; fi
done
if [ $ok = 1 ]; then
  echo "libstdc++: C99 stdlib on (std::stoll, std::stoull, std::stold)"
else
  echo "libstdc++: C99 stdlib left off: tests/cxx/stoll.cpp does not compile with it (see $LOG)"
fi
