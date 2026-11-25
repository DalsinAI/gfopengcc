#!/bin/sh
# tests/selfcalls/check.sh PREFIX
# No function a program can link from the stove calls itself at its start
# (a wrapper GCC folded into a call to itself, which runs until the stack is
# gone: libstdc++'s floorf, ceilf and sqrtf in open9, gcc patch 0020).
# Links tests/selfcalls/floatmath.cpp with g++ for each 68040 multilib and
# runs check_selfcalls.py (a copy of amigawarmux's tools/check_selfcalls.py)
# on the program. MIT. Copyright (c) 2026 AmiCradle Team.
set -eu
PREFIX=$1
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CXX=$PREFIX/bin/m68k-amigaos-g++
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
python3 "$HERE/test_check_selfcalls.py"
for fl in "-m68040" "-m68040 -m68881" "-m68020"; do
  "$CXX" $fl -O2 -fno-builtin -noixemul -o "$T/floatmath" "$HERE/floatmath.cpp" -lm -lpthread -latomic
  python3 "$HERE/check_selfcalls.py" "$T/floatmath" || { echo "selfcalls ($fl): a function the stove links calls itself"; exit 1; }
done
echo "selfcalls: no float function a g++ link takes calls itself"
