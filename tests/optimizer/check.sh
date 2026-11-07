#!/bin/bash
# check.sh BINDIR
# Compile defined-behaviour kernels across CPUs and optimisation profiles, run
# each raw image under qemu-m68k, and require one checksum. Writes matrix.tsv.
set -euo pipefail

BIN=${1:?usage: $0 BINDIR}
CC=$BIN/m68k-amigaos-gcc
OBJDUMP=$BIN/m68k-amigaos-objdump
HERE=$(cd "$(dirname "$0")" && pwd)
REPRO=$HERE/../repro
OUT=${OUT:-$(mktemp -d)}
mkdir -p "$OUT"

[ -x "$CC" ] && [ -x "$OBJDUMP" ] || {
  echo "optimizer: incomplete compiler bin directory: $BIN"; exit 2;
}
command -v qemu-m68k >/dev/null || {
  echo "optimizer: qemu-m68k is required"; exit 2;
}

printf 'cpu\tprofile\ttext_bytes\thunk_bytes\tchecksum\n' > "$OUT/matrix.tsv"
expected=
count=0

for cpu in 68000 68020 68040 68060; do
  "$CC" -m"$cpu" -O1 -fno-builtin -c "$REPRO/rt.c" -o "$OUT/rt-$cpu.o"
  "$CC" -m"$cpu" -O1 -fno-builtin -c "$HERE/helpers.c" \
    -o "$OUT/helpers-$cpu.o"
  "$CC" -m"$cpu" -c "$REPRO/crt.s" -o "$OUT/crt-$cpu.o"
  for profile in O0 O2 O3 Os O2-lto O3-lto O2-lto-whole O3-lto-whole; do
    case $profile in
      O0|O2|O3|Os) flags=-$profile ;;
      O2-lto) flags='-O2 -flto' ;;
      O3-lto) flags='-O3 -flto' ;;
      O2-lto-whole) flags='-O2 -flto -fwhole-program' ;;
      O3-lto-whole) flags='-O3 -flto -fwhole-program' ;;
    esac
    stem=$OUT/$cpu-$profile
    # Intentional splitting of the profile's compiler switches.
    # shellcheck disable=SC2086
    "$CC" -m"$cpu" $flags -fno-builtin -c "$HERE/kernels.c" -o "$stem.o"
    # shellcheck disable=SC2086
    "$CC" -m"$cpu" $flags -fno-builtin -c "$HERE/cross-unit.c" \
      -o "$stem-cross.o"
    # shellcheck disable=SC2086
    "$CC" -m"$cpu" $flags -nostartfiles -nostdlib \
      -o "$stem.hunk" "$OUT/crt-$cpu.o" "$stem.o" "$stem-cross.o" \
      "$OUT/rt-$cpu.o" \
      "$OUT/helpers-$cpu.o"
    python3 "$REPRO/mkelf.py" "$stem.hunk" "$stem.elf"
    chmod +x "$stem.elf"
    output=$(timeout 30 qemu-m68k -cpu m"$cpu" "$stem.elf")
    checksum=${output#checksum=}
    checksum=${checksum%%$'\n'*}
    [[ $checksum =~ ^[0-9]+$ ]] || {
      echo "optimizer: $cpu/$profile produced invalid output: $output"; exit 1;
    }
    if [ -z "$expected" ]; then
      expected=$checksum
    elif [ "$checksum" != "$expected" ]; then
      echo "optimizer: WRONG $cpu/$profile checksum=$checksum expected=$expected"
      exit 1
    fi
    text_bytes=$(
      "$OBJDUMP" -h "$stem.hunk" | awk '$2 ~ /^\.text/ { print $3 }' |
        python3 -c 'import sys; print(sum(int(line, 16) for line in sys.stdin))'
    )
    hunk_bytes=$(stat -c %s "$stem.hunk")
    printf '%s\t%s\t%s\t%s\t%s\n' \
      "$cpu" "$profile" "$text_bytes" "$hunk_bytes" "$checksum" \
      >> "$OUT/matrix.tsv"
    echo "optimizer: $cpu/$profile right (text=$text_bytes, checksum=$checksum)"
    count=$((count + 1))
  done
done

echo "optimizer: $count profiles agree; matrix: $OUT/matrix.tsv"
