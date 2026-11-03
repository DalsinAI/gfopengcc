#!/bin/bash
# tests/autoinc/check.sh [--amigaos BINDIR] [--aros BINDIR] [--expect-wrong]
# PR123853 / PR123076 (patches/gcc/0013) for each target given: compiles
# pr-autoinc.c (exec's oe_AlertText reduced: "move.b (a1)+,(0,a1,d0.l)" from the
# aros68k-gcc16 stove) and ../repro/autoinc.c (GFOffice's owf_number_text and
# PR123853's copy loops, every move size) for every CPU at -O2, -O3 and -Os, and
# scans the assembler text (-S) and the object (objdump -d) with
# scan_autoinc_overlap.py: no move may address its destination through the
# register its source steps.
#   --amigaos BINDIR   the folder with m68k-amigaos-gcc and m68k-amigaos-objdump
#   --aros BINDIR      the folder with m68k-aros-gcc and m68k-aros-objdump
#   --expect-wrong     the compilers are unfixed ones (stock GCC 16.2): pass only
#                      if pr-autoinc.c's -m68040 -O2 code is WRONG, which shows
#                      the test can see the bug
# scan_autoinc_overlap.py is amicradle-guest's tools/scan_autoinc_overlap.py
# (pull request 587, c52e078), MIT licence, Copyright (c) 2026 AmiCradle Team.
# Prints one line per compile and exits 1 if any is wrong.
# MIT licence, Copyright (c) 2026 AmiCradle Team.
set -u
D=$(cd "$(dirname "$0")" && pwd)
O=${OUT:-$(mktemp -d)}; mkdir -p "$O"
SCAN="python3 -I $D/scan_autoinc_overlap.py"
targets=(); expect_wrong=0
while [ $# -gt 0 ]; do
  case $1 in
    --amigaos) targets+=("m68k-amigaos=$2"); shift 2 ;;
    --aros) targets+=("m68k-aros=$2"); shift 2 ;;
    --expect-wrong) expect_wrong=1; shift ;;
    *) echo "usage: $0 [--amigaos BINDIR] [--aros BINDIR] [--expect-wrong]"; exit 2 ;;
  esac
done
[ ${#targets[@]} -gt 0 ] || { echo "usage: $0 [--amigaos BINDIR] [--aros BINDIR] [--expect-wrong]"; exit 2; }
( cd "$O" && $SCAN --selftest ) || { echo "scanner selftest: WRONG"; exit 1; }
bad=0; n=0
for tb in "${targets[@]}"; do
  t=${tb%%=*}; b=${tb#*=}; CC=$b/$t-gcc; OBJDUMP=$b/$t-objdump
  [ -x "$CC" ] && [ -x "$OBJDUMP" ] || { echo "$t: no $CC or $OBJDUMP"; exit 2; }
  echo "$t: $("$CC" --version | head -1)"
  if [ "$expect_wrong" = 1 ]; then
    f=$O/$t-expect.s
    "$CC" -m68040 -O2 -fomit-frame-pointer -S -o "$f" "$D/pr-autoinc.c" || { echo "[$t] pr-autoinc: did not compile"; exit 1; }
    if ( cd "$O" && $SCAN --text "$f" > "$f.scan" 2>&1 ); then
      echo "[$t -m68040 -O2] pr-autoinc: right, but this compiler was expected to be unfixed"; bad=1
    else echo "[$t -m68040 -O2] pr-autoinc: WRONG as expected ($(grep -m1 WRONG "$f.scan" | tr -s ' \t' ' '))"; fi
    continue
  fi
  for src in "$D/pr-autoinc.c" "$D/../repro/autoinc.c"; do
    s=$(basename "$src" .c)
    for cpu in -m68000 -m68020 -m68040 -m68060; do
      for opt in -O2 -O3 -Os; do
        f=$O/$t-$s${cpu}${opt}; n=$((n+1)); what="[$t $cpu $opt] $s"
        if ! "$CC" $cpu $opt -fomit-frame-pointer -S -o "$f.s" "$src" || ! "$CC" $cpu $opt -fomit-frame-pointer -c -o "$f.o" "$src"; then
          echo "$what: WRONG (did not compile)"; bad=1; continue
        fi
        if ! ( cd "$O" && $SCAN --text "$f.s" > "$f.s.scan" 2>&1 ); then
          echo "$what: WRONG in -S ($(grep -m1 WRONG "$f.s.scan" | tr -s ' \t' ' '))"; bad=1
        elif ! ( cd "$O" && $SCAN --cpu "${cpu#-m}" --objdump "$OBJDUMP" "$f.o" > "$f.o.scan" 2>&1 ); then
          echo "$what: WRONG in the object ($(grep -m1 WRONG "$f.o.scan" | tr -s ' \t' ' '))"; bad=1
        else echo "$what: right ($(tail -n 1 "$f.o.scan" | sed 's/^# //'))"; fi
      done
    done
  done
done
[ "$expect_wrong" = 1 ] || echo "autoinc: $n compiles scanned"
exit $bad
