#!/bin/sh
# Copyright (c) 2026 AmiCradle Team. MIT licence (see LICENSE at the repository root).
# same-code.sh OBJDUMP NM A.o B.o: whether two builds of one source agree.
# "same": byte-identical disassembly. "layout": the same symbols, defined and
# used, and the same set of displacements (structure offsets and library
# vector offsets), so both builds saw the same headers and differ only in how
# the compiler laid the code out. The stove's getgrent.o and getpwent.o
# rebuild that way (its libnix came from an earlier build of the same GCC);
# __inituser.o and crypt.o, which use the same SocketSettings fields, rebuild
# byte for byte. Anything else is "different" (exit 1).
set -eu
OD=$1; NM=$2; A=$3; B=$4
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
"$OD" -d "$A" | tail -n +4 > "$T/a"; "$OD" -d "$B" | tail -n +4 > "$T/b"
if cmp -s "$T/a" "$T/b"; then echo same; exit 0; fi
"$NM" "$A" | awk '{print $NF, (NF==3 ? $2 : $1)}' | sort > "$T/sa"
"$NM" "$B" | awk '{print $NF, (NF==3 ? $2 : $1)}' | sort > "$T/sb"
cmp -s "$T/sa" "$T/sb" || { echo different; diff "$T/sa" "$T/sb" | head -10 >&2; exit 1; }
grep -o '@([0-9-]*)' "$T/a" | sort -u > "$T/da"; grep -o '@([0-9-]*)' "$T/b" | sort -u > "$T/db"
cmp -s "$T/da" "$T/db" || { echo different; diff "$T/da" "$T/db" | head -10 >&2; exit 1; }
echo layout
