#!/bin/bash
# prove.sh BINDIR [extra flags...]
# Builds each reproducer with BINDIR's m68k-amigaos-gcc/g++ and runs it as a raw
# 68k image under qemu-m68k -cpu m68040; checks the code where running can't
# show the bug (a read of address 0 is not mapped under qemu-m68k).
# Prints one line per reproducer, "right" or "WRONG", and exits 1 if any is wrong.
# Extra flags go to every compile: run it plain (loop distribution is on by
# default) and with -fno-tree-loop-distribute-patterns; the memmove and shift
# reproducers must be right either way.
# NIXOBJ (optional): objects linked ahead of the stove's libnix in the softfloat
# reproducer, such as a fixed __initlibraries.o, to prove a libnix fix before a
# stove rebuild.
# MIT licence, Copyright (c) 2026 AmiCradle Team.
set -u
B=$1; shift
D=$(cd "$(dirname "$0")" && pwd)
O=${OUT:-$(mktemp -d)}; mkdir -p "$O"
CC="$B/m68k-amigaos-gcc"; CXX="$B/m68k-amigaos-g++"; OBJDUMP="$B/m68k-amigaos-objdump"
bad=0

image() {   # image NAME [CPU [LIBS]]: link $O/NAME.o into $O/NAME.elf
  local n=$1 cpu=${2:--m68040} libs=${3:-}
  "$CC" $cpu -O1 -fno-builtin -c "$D/rt.c" -o "$O/rt.o" || return 2
  "$CC" $cpu -nostartfiles -nostdlib -o "$O/$n.hunk" "$D/crt.s" "$O/$n.o" "$O/rt.o" $libs || return 2
  python3 "$D/mkelf.py" "$O/$n.hunk" "$O/$n.elf" && chmod +x "$O/$n.elf"
}
run() {     # run NAME LABEL [QEMUCPU]: run the image, print its line
  local out; out=$(timeout 20 qemu-m68k -cpu "${3:-m68040}" "$O/$1.elf" 2>&1); local rc=$?
  out=$(printf '%s' "$out" | grep -m1 -E 'right|WRONG' || echo "$2: WRONG (crashed, exit $rc)")
  echo "$out"; case $out in *WRONG*) bad=1;; esac
}
built() {   # built LABEL: a reproducer that did not compile, link or convert is a failure too
  echo "$1: WRONG (did not build)"; bad=1
}

for opt in -O1 -O2 -Os; do
  "$CC" -m68040 $opt "$@" -c "$D/shift.c" -o "$O/shift.o" && image shift && echo -n "[$opt] " && run shift shift || built "[$opt] shift"
  "$CC" -m68040 $opt "$@" -c "$D/memmove.c" -o "$O/memmove.o" && image memmove && echo -n "[$opt] " && run memmove memmove || built "[$opt] memmove"
  "$CXX" -m68040 $opt "$@" -fno-exceptions -c "$D/copyback.cpp" -o "$O/copyback.o" && image copyback && echo -n "[$opt] " && run copyback copy_backward || built "[$opt] copy_backward"
done

# a nested inline library call, Stricmp(FilePart(x), ...), with the NDK's own inline headers
NDKINC="-isystem $B/../m68k-amigaos/ndk-include"
for opt in -O1 -O2 -Os; do
  "$CC" -m68040 $opt "$@" $NDKINC -c "$D/nested.c" -o "$O/nested.o" && image nested && echo -n "[$opt] " && run nested nested || built "[$opt] nested"
done

# 68000: byte copies when the alignment is unknown, and odd sizes backwards
for opt in -O2 -Os; do
  "$CC" -m68000 $opt "$@" -c "$D/shift.c" -o "$O/shift.o" && image shift -m68000 && echo -n "[$opt -m68000] " && run shift shift m68000 || built "[$opt -m68000] shift"
  "$CC" -m68000 $opt "$@" -c "$D/memmove.c" -o "$O/memmove.o" && image memmove -m68000 && echo -n "[$opt -m68000] " && run memmove memmove m68000 || built "[$opt -m68000] memmove"
done

for opt in -O1 -O2; do
  rm -f "$O/fpcr.o"
  "$CC" -m68040 -m68881 $opt "$@" -c "$D/fpcr.c" -o "$O/fpcr.o" 2>/dev/null && image fpcr && echo -n "[$opt -m68040] " && run fpcr fpcr || built "[$opt -m68040] fpcr"
  # and the static check every -m68040 build can run: no float-to-int store through the saved FPCR register
  if [ ! -f "$O/fpcr.o" ]; then built "[$opt -m68040] fpcr code"
  elif "$OBJDUMP" -m m68k:68040 -d "$O/fpcr.o" | awk '
      /fmovel %?fpcr,%?d[0-7]/ { match($0, /d[0-7]$/); r = substr($0, RSTART, 2); next }
      r != "" && /fmovel %?fp[0-7],/ { split($0, a, ","); if (index(substr($0, index($0, ",")), r)) bad = 1; r = "" }
      END { exit bad ? 1 : 0 }'; then echo "[$opt -m68040] fpcr code: right (no store through the FPCR register)"
  else echo "[$opt -m68040] fpcr code: WRONG (a store indexes with the FPCR register)"; bad=1; fi
done

# 64-bit libcall arguments pushed from stack slots, when tuned for the 68040/060
for opt in "-O1 -m68040" "-O2 -m68040" "-O1 -m68060" "-O2 -m68060" "-Os -m68060"; do
  "$CC" $opt "$@" -c "$D/push64.c" -o "$O/push64.o" && image push64 -m68040 -lgcc && echo -n "[$opt] " && run push64 push64 || built "[$opt] push64"
done

# soft-float doubles (-m68060, and -m68040 without -m68881) on a machine with an FPU:
# libnix's own __initlibraries opens the IEEE libraries (mathieee.s models OS 3.2.3's,
# which set the task's FPCR when opened) and must leave FPCR at 0 for their FPU code
NIXLIBS="${NIXOBJ:-} -L$B/../m68k-amigaos/libnix/lib -Wl,--start-group -lm -lnix -lstubs -lgcc -Wl,--end-group"
for c in "-m68060 m68060" "-m68040 m68040"; do
  cpu=${c% *}; qcpu=${c#* }
  # -m68040 soft float links libnix's soft libm020 only with the specs file (docs/m68040-soft-float-link.md)
  sp=; [ "$cpu" = -m68040 ] && sp="-specs=$D/../../build/m68k-soft-m68040.specs"
  "$CC" $cpu $sp -O2 "$@" -c "$D/softfloat.c" -o "$O/softfloat.o" && "$CC" $cpu -c "$D/mathieee.s" -o "$O/mathieee.o" &&
    image softfloat "$cpu $sp" "$O/mathieee.o $NIXLIBS" && echo -n "[-O2 $cpu] " && run softfloat softfloat "$qcpu" || built "[-O2 $cpu] softfloat"
done

rm -f "$O/calloc.o"
"$CC" -m68040 -O2 "$@" -c "$D/calloc.c" -o "$O/calloc.o" && image calloc && echo -n "[-O2] " && run calloc calloc || built "[-O2] calloc"
if [ ! -f "$O/calloc.o" ]; then built "[-O2] calloc code"
elif "$OBJDUMP" -d "$O/calloc.o" | awk '/<_calloc>:/,/rts/' | grep -q 'jsr.*_calloc\|jra.*_calloc\|bsr.*_calloc'; then
  echo "[-O2] calloc code: WRONG (calloc calls calloc)"; bad=1
else echo "[-O2] calloc code: right (calloc doesn't call itself)"; fi

# a library's own memset with a helper loop: -fno-tree-loop-distribute-patterns keeps the loop a loop
for opt in -O2 -Os; do
  rm -f "$O/selfmem.s"
  if ! "$CC" -m68040 $opt "$@" -fno-tree-loop-distribute-patterns -S -o "$O/selfmem.s" "$D/selfmem.c"; then built "[$opt] selfmem"
  elif awk '/^_fill_bytes:/,/rts/' "$O/selfmem.s" | grep -q 'jsr.*_memset\|jbsr.*_memset\|bsr.*_memset'; then
    echo "[$opt] selfmem: WRONG (the helper loop became a call to memset)"; bad=1
  else echo "[$opt] selfmem: right (with -fno-tree-loop-distribute-patterns an own memset loop stays a loop)"; fi
done

for opt in -O2 -Os; do
  rm -f "$O/null.o"
  if ! "$CC" -m68040 $opt "$@" -c "$D/null.c" -o "$O/null.o"; then built "[$opt] null"
  elif "$OBJDUMP" -d "$O/null.o" | grep -qE 'trap +#7'; then echo "[$opt] null: WRONG (trap #7)"; bad=1
  else echo "[$opt] null: right (address 0 is read, no trap #7)"; fi
done

# a move whose source post-increments or pre-decrements a register must not address
# its destination through it: the 68k works the destination out after the step.
# late-combine made "move.b (a2)+,(a0,a2.l)" (GFOffice's owf_number_text, 6.5 shown as "6.w")
autoinc_code() {   # autoinc_code FILE.s: print each instruction that names a register again after (An)+ or -(An)
  awk '/^\t[a-z]/ {
      ops = $0; sub(/^\t[a-z][a-z0-9.]*[ \t]+/, "", ops)
      n = 0; depth = 0; cur = ""
      for (i = 1; i <= length(ops); i++) {
        ch = substr(ops, i, 1)
        if (ch == "(") depth++; else if (ch == ")") depth--
        if (ch == "," && depth == 0) { op[++n] = cur; cur = "" } else cur = cur ch
      }
      op[++n] = cur
      for (k = 1; k < n; k++)
        if (op[k] ~ /^-\(%?(a[0-7]|sp)\)$/ || op[k] ~ /^\(%?(a[0-7]|sp)\)\+$/) {
          r = op[k]; gsub(/[-+()%]/, "", r)
          for (j = k + 1; j <= n; j++) if (op[j] ~ ("(^|[^a-z0-9])" r "([^a-z0-9]|$)")) { print; break }
        }
    }' "$1"
}
for c in "-m68040 m68040" "-m68000 m68000"; do
  cpu=${c% *}; qcpu=${c#* }
  "$CC" $cpu -O2 "$@" -c "$D/autoinc.c" -o "$O/autoinc.o" && image autoinc "$cpu" -lgcc && echo -n "[-O2 $cpu] " && run autoinc autoinc "$qcpu" || built "[-O2 $cpu] autoinc"
  rm -f "$O/autoinc.s"
  if ! "$CC" $cpu -O2 "$@" -S -o "$O/autoinc.s" "$D/autoinc.c"; then built "[-O2 $cpu] autoinc code"
  elif [ -n "$(autoinc_code "$O/autoinc.s")" ]; then
    echo "[-O2 $cpu] autoinc code: WRONG ($(autoinc_code "$O/autoinc.s" | wc -l) instructions name the stepped register again, as in $(autoinc_code "$O/autoinc.s" | head -1 | tr -d '\t'))"; bad=1
  else echo "[-O2 $cpu] autoinc code: right (no instruction names a register again after (An)+ or -(An))"; fi
done

# vregs must leave no virtual register: strcat into a local array became an lea of
# virtual-stack-vars + length - 600, vregs left it, and combine dropped the frame
for opt in -O1 -O2; do
  "$CC" -m68040 $opt "$@" -c "$D/vregs.c" -o "$O/vregs.o" && image vregs && echo -n "[$opt] " && run vregs vregs || built "[$opt] vregs"
  rm -f "$O"/vregs.c.*.vregs
  if ! "$CC" -m68040 $opt "$@" -fdump-rtl-vregs -dumpdir "$O/" -S -o "$O/vregs.s" "$D/vregs.c" || ! ls "$O"/vregs.c.*.vregs >/dev/null 2>&1; then built "[$opt] vregs dump"
  elif grep -q 'virtual-' "$O"/vregs.c.*.vregs; then echo "[$opt] vregs dump: WRONG (a virtual register is left after vregs)"; bad=1
  else echo "[$opt] vregs dump: right (no virtual register after vregs)"; fi
done
# -mcas (patches/gcc/0015): a 68040's 1-, 2- and 4-byte atomics as CAS inline,
# with the right values; without -mcas, and on a 68000, they stay libatomic calls
for opt in -O1 -O2 -Os; do
  rm -f "$O/cas.o"
  "$CC" -m68040 -mcas $opt "$@" -c "$D/cas.c" -o "$O/cas.o" && image cas && echo -n "[$opt -mcas] " && run cas cas || built "[$opt -mcas] cas"
  if [ ! -f "$O/cas.o" ]; then built "[$opt -mcas] cas code"
  elif "$OBJDUMP" -dr "$O/cas.o" | grep -q '__atomic'; then echo "[$opt -mcas] cas code: WRONG (a libatomic call is left)"; bad=1
  elif [ "$("$OBJDUMP" -m m68k:68040 -d "$O/cas.o" | grep -cE 'cas[bwl]')" -lt 10 ]; then echo "[$opt -mcas] cas code: WRONG (fewer than 10 cas)"; bad=1
  else echo "[$opt -mcas] cas code: right (cas inline, no libatomic call)"; fi
done
if "$CC" -m68040 -O2 "$@" -S -o - "$D/cas.c" | grep -q '___atomic_compare_exchange_4'; then echo "[-O2] cas default: right (libatomic calls without -mcas)"
else echo "[-O2] cas default: WRONG (no libatomic call without -mcas)"; bad=1; fi
if "$CC" -m68000 -mcas -O2 "$@" -S -o - "$D/cas.c" | grep -q '___atomic_compare_exchange_4'; then echo "[-O2 -m68000] cas: right (-mcas leaves a 68000 alone)"
else echo "[-O2 -m68000] cas: WRONG (a 68000 has no CAS)"; bad=1; fi
exit $bad
