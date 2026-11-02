#!/bin/sh
# Copyright (c) 2026 AmiCradle Team. GPL-3.0-or-later, like the patches it goes with.
# Base-relative C++ with the os32-gcc16 stove: t3_threads.cpp (amicradle-stoves
# os32-gcc16/tests/src) built three ways.
#   build.sh [OUT]     STOVE: a stove folder with prefix/ and compat/ (default ~/AmiCradle/stoves/os32-gcc16)
#   t3-plain   links and runs (control)
#   t3-b32     -fbaserel32 (with compat/libb32): links ("out of range" lines remain), t3 OK with libnix 0007 + aros-stuff 0005
#   t3-b16     -fbaserel (with compat/libb): links and prints t3 OK with the same patches
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
STOVE=${STOVE:-$HOME/AmiCradle/stoves/os32-gcc16}
OUT=${1:-$HERE/out}
P=$STOVE/prefix/bin/m68k-amigaos-
WRAP="-los32compat -Wl,--wrap=malloc -Wl,--wrap=calloc -Wl,--wrap=realloc -Wl,--wrap=free -Wl,-u,___wrap_malloc -Wl,-u,___wrap_free -Wl,-u,___wrap_calloc -Wl,-u,___wrap_realloc"
# libos32compat must match the code model (FINDINGS.md: the absolute one hangs a
# base-relative program): compat/, compat/libb or compat/libb32 (amicradle-stoves #7).
compat_dir() { case $1 in *-fbaserel32*) echo "$STOVE/compat/libb32";; *-fbaserel*) echo "$STOVE/compat/libb";; *) echo "$STOVE/compat";; esac; }
F="-m68040 -m68881 -O2 -fno-delete-null-pointer-checks -fomit-frame-pointer -std=gnu++23"
mkdir -p "$OUT"
for v in plain:"" b32:-fbaserel32 b16:-fbaserel; do
    n=${v%%:*}; f=${v#*:}
    # shellcheck disable=SC2086
    if "${P}g++" $F $f -o "$OUT/t3-$n" "$HERE/t3_threads.cpp" -lpthread -latomic -lstdc++ -L"$(compat_dir "$f")" $WRAP -fexceptions > "$OUT/t3-$n.log" 2>&1; then
        echo "t3-$n: linked ($(wc -c < "$OUT/t3-$n") bytes, $(grep -c 'out of range' "$OUT/t3-$n.log") 'out of range' lines)"
    else
        echo "t3-$n: link FAILED:"; grep -v 'out of range' "$OUT/t3-$n.log"
    fi
done
