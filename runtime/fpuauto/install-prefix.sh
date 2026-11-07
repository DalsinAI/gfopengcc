#!/bin/sh
# Copyright (c) 2026 AmiCradle Team. MIT licence (see LICENSE in this folder).
# Build, validate and install fpuauto into a complete GFOpenAmigaGCC prefix.
# This is for clean compiler builds; install-stove.sh remains the backed-up,
# recoverable updater for an existing Cradle stove.
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
P=$(CDPATH= cd -- "${1:?usage: $0 PREFIX OUT}" && pwd)
OUT=${2:?usage: $0 PREFIX OUT}
mkdir -p "$OUT"

PREFIX="$P" OUT="$OUT/build" sh "$HERE/build-amiga.sh"

CC="$P/bin/m68k-amigaos-gcc"
OD="$P/bin/m68k-amigaos-objdump"
GLIB=$(dirname "$("$CC" -print-libgcc-file-name)")
SPECS="$GLIB/specs"
LIBDIR="$P/m68k-amigaos/libnix/lib"
[ -d "$LIBDIR" ] || { echo "fpuauto: no libnix directory: $LIBDIR" >&2; exit 1; }

# GCC's own specs file replaces the built-ins.  Start from the existing file,
# or from the complete built-in dump, and replace any older fpuauto block.
if [ -s "$SPECS" ]; then
  BASE="$SPECS"
else
  "$CC" -dumpspecs > "$OUT/specs.dump"
  BASE="$OUT/specs.dump"
fi
awk 'index($0,"*fpuauto:")==1{exit} {a[++n]=$0}
     END{while(n>0&&a[n]=="")n--; for(i=1;i<=n;i++)print a[i]}' \
  "$BASE" > "$OUT/specs.base"
{ cat "$OUT/specs.base"; echo; cat "$HERE/fpuauto.specs"; } > "$OUT/specs.new"

cp "$OUT/build/lib/libfpuauto.a" "$LIBDIR/libfpuauto.a"
cp "$OUT/specs.new" "$SPECS"

# The installed default must wrap soft-float 68040 maths, while the explicit
# opt-out remains entirely unwrapped.
CF="-m68040 -O2 -noixemul -fno-delete-null-pointer-checks"
# shellcheck disable=SC2086
"$CC" $CF -o "$OUT/installed-auto" "$HERE/FPUAutoBench.c" -lm
# shellcheck disable=SC2086
"$CC" $CF -DNO_FPUAUTO -o "$OUT/installed-off" "$HERE/FPUAutoBench.c" -lm
auto=$("$OD" -d "$OUT/installed-auto" | grep -c '<___wrap_' || true)
off=$("$OD" -d "$OUT/installed-off" | grep -c '<___wrap_' || true)
[ "$auto" -gt 0 ] && [ "$off" -eq 0 ] || {
  echo "fpuauto: installed specs validation failed (auto $auto, opt-out $off)" >&2; exit 1;
}
echo "fpuauto: installed data dispatcher ($auto wrapped references; opt-out $off)"
