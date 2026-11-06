#!/bin/bash
# check.sh BINDIR
set -euo pipefail

BIN=${1:?usage: $0 BINDIR}
CC=$BIN/m68k-amigaos-gcc
NM=$BIN/m68k-amigaos-nm
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$(mktemp -d)}
DRIVER_FLAGS=${DRIVER_FLAGS:-}
mkdir -p "$OUT"

# Intentional word splitting permits validation of a composite disposable
# prefix with an explicit candidate specs file. Production runs leave this
# empty and exercise the installed compiler normally.
# shellcheck disable=SC2086
"$CC" $DRIVER_FLAGS -m68040 -O2 -fstack-protector-strong -S \
  "$HERE/probe.c" -o "$OUT/probe.s"
grep -q '__stack_chk_guard' "$OUT/probe.s" || {
  echo "hardening: stack protector emitted no guard"; exit 1;
}
grep -q '__stack_chk_fail' "$OUT/probe.s" || {
  echo "hardening: stack protector emitted no failure path"; exit 1;
}

for mode in stack-protector stack-protector-all stack-protector-strong stack-protector-explicit; do
  source=$HERE/probe.c
  [ "$mode" = stack-protector-explicit ] && source=$HERE/explicit.c
  # shellcheck disable=SC2086
  "$CC" $DRIVER_FLAGS -m68040 -O2 -f"$mode" "$source" -o "$OUT/$mode"
  "$NM" "$OUT/$mode" | grep -Eq '[[:space:]][A-Z][[:space:]]+___stack_chk_guard$' || {
    echo "hardening: -f$mode linked no guard definition"; exit 1;
  }
  "$NM" "$OUT/$mode" | grep -Eq '[[:space:]][A-Z][[:space:]]+___stack_chk_fail$' || {
    echo "hardening: -f$mode linked no failure definition"; exit 1;
  }
done

seen=0
while IFS=';' read -r dir options; do
  flags=${options//@/ -}
  name=${dir//\//-}
  [ "$name" = . ] && name=plain
  # Intentional word splitting: -print-multi-lib encodes compiler switches.
  # shellcheck disable=SC2086
  "$CC" $DRIVER_FLAGS $flags -O2 -fstack-protector-strong \
    "$HERE/probe.c" -o "$OUT/probe-$name"
  "$NM" "$OUT/probe-$name" | grep -Eq '[[:space:]][A-Z][[:space:]]+___stack_chk_guard$' || {
    echo "hardening: '$dir' linked no guard definition"; exit 1;
  }
  "$NM" "$OUT/probe-$name" | grep -Eq '[[:space:]][A-Z][[:space:]]+___stack_chk_fail$' || {
    echo "hardening: '$dir' linked no failure definition"; exit 1;
  }
  seen=$((seen + 1))
done < <("$CC" -print-multi-lib)
[ "$seen" -gt 0 ] || { echo "hardening: compiler reported no multilibs"; exit 1; }

if "$CC" $DRIVER_FLAGS -m68040 -O2 -fhardened -c "$HERE/probe.c" -o "$OUT/hardened.o" \
     2> "$OUT/hardened.log"; then
  echo "hardening: unsupported -fhardened unexpectedly compiled"; exit 1;
fi
grep -q -- '-fhardened is not supported for m68k-amigaos' "$OUT/hardened.log" || {
  echo "hardening: -fhardened did not give the target diagnostic"; exit 1;
}
if grep -q 'Assembler messages' "$OUT/hardened.log"; then
  echo "hardening: -fhardened reached the assembler"; exit 1;
fi

echo "hardening: right ($seen multilibs link stack protector; -fhardened stops clearly)"
