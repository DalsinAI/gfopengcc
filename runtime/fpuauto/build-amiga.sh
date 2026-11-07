#!/bin/sh
# Copyright (c) 2026 AmiCradle Team. MIT licence (see LICENSE in this folder).
# fpuauto with the os32-gcc16 stove: libfpuauto.a (fpuauto.S) and
# FPUAutoBench three ways:
#   FPUAutoBench-auto    soft-float link + fpuauto (the FPU path and the soft path)
#   FPUAutoBench-plain   soft-float link as today (libnix's libm020 alone)
#   FPUAutoBench-hard    -m68881 (FPU instructions inline: needs an FPU)
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ -n "${PREFIX:-}" ]; then
  P=$(CDPATH= cd -- "$PREFIX" && pwd)
  WHERE="prefix $P"
else
  STOVE=${STOVE:-"$HOME/AmiCradle/stoves/os32-gcc16"}
  P="$STOVE/prefix"
  WHERE="stove $STOVE"
fi
CC="$P/bin/m68k-amigaos-gcc"; AR="$P/bin/m68k-amigaos-ar"; NM="$P/bin/m68k-amigaos-nm"; OD="$P/bin/m68k-amigaos-objdump"
echo "built on $(hostname) as $(id -un), $WHERE"
OUT=${OUT:-"$HERE/build-amiga"}; mkdir -p "$OUT/lib" "$OUT/tests" "$OUT/obj"
SPECS="$HERE/../../build/m68k-soft-m68040.specs"
WRAPS=$(sed 's/^/-Wl,/' "$HERE/fpuauto.wraps" | tr '\n' ' ')

# one member per routine, so a program links only the routines it calls
rm -f "$OUT/lib/libfpuauto.a" "$OUT"/obj/fa_*.o
# A Hunk object's unit name is the -o path and the archive keeps it: build
# and archive inside the object folder so no build path is installed.
( cd "$OUT/obj"
  "$CC" -m68040 -DFPUAUTO_COMMON -c "$HERE/fpuauto.S" -o fa_common.o
  for n in $(sed 's/^--wrap=//' "$HERE/fpuauto.wraps"); do
    "$CC" -m68040 -DR_$n -c "$HERE/fpuauto.S" -o "fa_$n.o"
  done
  "$AR" rcs ../lib/libfpuauto.a fa_*.o )
echo "libfpuauto.a: $("$NM" "$OUT/lib/libfpuauto.a" | grep -c ' T ___wrap_') routines, $(wc -c < "$OUT/lib/libfpuauto.a") bytes"
"$OD" -d "$OUT/obj/fa___muldf3.o" | sed -n '6,40p'
for o in "$OUT"/obj/fa_*.o; do
  "$OD" -dr "$o" > "$o.dump"
  ! grep -q 'CacheClear' "$o.dump" || {
    echo "fpuauto: data dispatch unexpectedly retains a cache-clear call in $o" >&2; exit 1;
  }
done
"$OD" -h "$OUT/obj/fa___muldf3.o" | grep -Eq '[[:space:]]\.data[[:space:]]+0*4[[:space:]]' || {
  echo "fpuauto: wrapper has no four-byte data dispatch target" >&2; exit 1;
}
echo "fpuauto: data dispatch target present; no code patch cache flush"

CF="-m68040 -O2 -noixemul -fno-delete-null-pointer-checks -Wall"
# shellcheck disable=SC2086
"$CC" $CF -specs="$SPECS" -DFPUAUTO -o "$OUT/tests/FPUAutoBench-auto" "$HERE/FPUAutoBench.c" $WRAPS -L"$OUT/lib" -lfpuauto -lm
# shellcheck disable=SC2086
"$CC" $CF -DNO_FPUAUTO -specs="$SPECS" -o "$OUT/tests/FPUAutoBench-plain" "$HERE/FPUAutoBench.c" -lm
# shellcheck disable=SC2086
"$CC" $CF -m68881 -DHARD -o "$OUT/tests/FPUAutoBench-hard" "$HERE/FPUAutoBench.c" -lm
# the same through the link specs alone (as a stove with libfpuauto.a in its lib folder would link)
# shellcheck disable=SC2086
"$CC" $CF -specs="$SPECS" -specs="$HERE/fpuauto.specs" -L"$OUT/lib" -DFPUAUTO -o "$OUT/tests/FPUAutoBench-specs" "$HERE/FPUAutoBench.c" -lm
# the specs leave alone: a program with no float maths, -m68881, and -DNO_FPUAUTO
printf '#include <stdio.h>\nint main(void){puts("hi");return 0;}\n' > "$OUT/obj/hi.c"
# shellcheck disable=SC2086
"$CC" $CF -specs="$SPECS" -o "$OUT/obj/hi-plain" "$OUT/obj/hi.c"
# shellcheck disable=SC2086
"$CC" $CF -specs="$SPECS" -specs="$HERE/fpuauto.specs" -L"$OUT/lib" -o "$OUT/obj/hi-specs" "$OUT/obj/hi.c"
cmp "$OUT/obj/hi-plain" "$OUT/obj/hi-specs" && echo "no float maths: the same program with and without fpuauto"
# shellcheck disable=SC2086
"$CC" $CF -m68881 -DHARD -specs="$SPECS" -specs="$HERE/fpuauto.specs" -L"$OUT/lib" -o "$OUT/obj/hard-specs" "$HERE/FPUAutoBench.c" -lm
cmp "$OUT/tests/FPUAutoBench-hard" "$OUT/obj/hard-specs" && echo "-m68881: the same program with and without fpuauto"
# shellcheck disable=SC2086
"$CC" $CF -DNO_FPUAUTO -specs="$SPECS" -specs="$HERE/fpuauto.specs" -L"$OUT/lib" -o "$OUT/obj/off-specs" "$HERE/FPUAutoBench.c" -lm
cmp "$OUT/tests/FPUAutoBench-plain" "$OUT/obj/off-specs" && echo "-DNO_FPUAUTO: the same program as without fpuauto"
# as install-stove.sh puts it: fpuauto.specs as gcc's own specs file (found through -B here)
GLIB=$(dirname "$("$CC" -print-libgcc-file-name)")
echo "gcc's own specs file: $([ -f "$GLIB/specs" ] && echo "$GLIB/specs ($(wc -l < "$GLIB/specs") lines)" || echo "none in $GLIB")"
# gcc reads its own specs file in place of the built-in specs, so it starts as their full dump
# (or the stove's own file, less any fpuauto block), then exactly one blank line, then ours
mkdir -p "$OUT/bdir"; { if [ -f "$GLIB/specs" ]; then cat "$GLIB/specs"; else "$CC" -dumpspecs; fi; } |
  awk 'index($0,"*fpuauto:")==1{exit} {a[++n]=$0} END{while(n>0&&a[n]=="")n--; for(i=1;i<=n;i++)print a[i]}' > "$OUT/bdir/specs.base"
{ cat "$OUT/bdir/specs.base"; echo; cat "$HERE/fpuauto.specs"; } > "$OUT/bdir/specs"
# shellcheck disable=SC2086
"$CC" $CF -B"$OUT/bdir/" -specs="$SPECS" -L"$OUT/lib" -o "$OUT/obj/gccspecs" "$HERE/FPUAutoBench.c" -lm
echo "as gcc's own specs: $("$OD" -d "$OUT/obj/gccspecs" | grep -c 'jsr.*<___wrap_' || true) wrapped calls"
for t in auto plain hard specs; do
  f="$OUT/tests/FPUAutoBench-$t"
  echo "FPUAutoBench-$t $(wc -c < "$f") bytes; wrapped calls: $("$OD" -d "$f" | grep -c 'jsr.*<___wrap_' || true); FPU instructions: $("$OD" -m m68k:68040 -d "$f" | awk -F'\t' '$3 ~ /^f[a-z]/' | wc -l)"
done
sha256sum "$OUT"/tests/* "$OUT"/lib/*
# the native comparator: the same bench built for this host and run here
if command -v cc >/dev/null 2>&1 && cc -O2 -DNATIVE -o "$OUT/obj/FPUAutoBench-host" "$HERE/FPUAutoBench.c" -lm; then
  echo "== native comparator ($(uname -m), this host)"; "$OUT/obj/FPUAutoBench-host" 2000000
fi
