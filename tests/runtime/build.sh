#!/bin/bash
# build.sh BINDIR OUT [FPUAUTOBENCH_C]
# Builds the Open7 runtime qualification programs with BINDIR's compilers into
# OUT, for running on a real AmigaOS (see README.md). The C++ program is built
# with the AC090 profile (-m68040 -m68881); its compile and link must print
# nothing, and it is linked a second time with --fatal-warnings to prove it.
# FPUAUTOBENCH_C (amicradle-guest common/fpuauto/FPUAutoBench.c) adds the
# fpuauto benchmark as auto (soft float, wrapped), plain (-DNO_FPUAUTO) and hard.
# Exits 1 if anything fails to build or a check fails.
# MIT licence, Copyright (c) 2026 AmiCradle Team.
set -u
B=$1; O=$2; BENCH=${3:-}
D=$(cd "$(dirname "$0")" && pwd)
CC="$B/m68k-amigaos-gcc"; CXX="$B/m68k-amigaos-g++"; NM="$B/m68k-amigaos-nm"
mkdir -p "$O"; bad=0
build() {   # build NAME COMPILER FLAGS...: quiet build into $O/NAME, its messages in $O/NAME.log
  local n=$1 c=$2; shift 2
  if "$c" "$@" -o "$O/$n" >"$O/$n.log" 2>&1; then
    if [ -s "$O/$n.log" ]; then echo "$n: built, with messages:"; sed 's/^/  /' "$O/$n.log"
    else echo "$n: built, no messages"; fi
  else echo "$n: FAILED to build"; sed 's/^/  /' "$O/$n.log"; bad=1; fi
}

build c_basic-000     "$CC" -m68000 -O2 -noixemul "$D/c_basic.c" -lm
build c_basic-020     "$CC" -m68020 -m68881 -O2 -noixemul "$D/c_basic.c" -lm
build c_basic-040     "$CC" -m68040 -m68881 -O2 -noixemul "$D/c_basic.c" -lm
build c_basic-040auto "$CC" -m68040 -O2 -noixemul "$D/c_basic.c" -lm
build c_basic-040br   "$CC" -m68040 -m68881 -O2 -noixemul -fbaserel "$D/c_basic.c" -lm
build c_basic-060     "$CC" -m68060 -O2 -noixemul "$D/c_basic.c" -lm

CXXFLAGS="-m68040 -m68881 -O2 -fomit-frame-pointer -std=gnu++23 -noixemul"
build cxx_eh_threads "$CXX" $CXXFLAGS "$D/cxx_eh_threads.cpp" -lpthread -latomic
[ -s "$O/cxx_eh_threads.log" ] && { echo "cxx_eh_threads: the AC090 profile link is not warning-free"; bad=1; }
build cxx_eh_threads-fatal "$CXX" $CXXFLAGS -Wl,--fatal-warnings "$D/cxx_eh_threads.cpp" -lpthread -latomic
cmp -s "$O/cxx_eh_threads" "$O/cxx_eh_threads-fatal" && echo "cxx_eh_threads: --fatal-warnings link is byte-identical"

build ssp_canary-040 "$CC" -m68040 -m68881 -O2 -noixemul -fstack-protector-strong -DSSP_REACH=4 "$D/ssp_canary.c"
build ssp_canary-000 "$CC" -m68000 -O2 -noixemul -fstack-protector-strong -DSSP_REACH=4 "$D/ssp_canary.c"
# SSP_REACH=4 must end exactly on the canary: the guard is stored 16 bytes above the array
for cpu in -m68040 -m68000; do
  asm=$("$CC" $cpu -O2 -noixemul -fstack-protector-strong -DSSP_REACH=4 -S -o - "$D/ssp_canary.c" | awk '/^_victim/,/rts/')
  g=$(printf '%s\n' "$asm" | sed -n 's/.*move.l ___stack_chk_guard,\([0-9]*\)(sp).*/\1/p' | head -1)
  a=$(printf '%s\n' "$asm" | sed -n 's/.*lea (\([0-9]*\),sp),a3.*/\1/p' | head -1)
  if [ -n "$g" ] && [ -n "$a" ] && [ $((a + 16)) -eq "$g" ]; then echo "ssp_canary $cpu: array at sp+$a, canary at sp+$g: the 4-byte overrun covers the canary only"
  else echo "ssp_canary $cpu: cannot confirm the canary is right after the array (array $a, guard $g)"; bad=1; fi
done

build ubsan_trap-040 "$CC" -m68040 -m68881 -O2 -noixemul -fsanitize=undefined -fsanitize-undefined-trap-on-error "$D/ubsan_trap.c"
if "$NM" "$O/ubsan_trap-040" 2>/dev/null | grep -q __ubsan; then echo "ubsan_trap: references a sanitizer runtime"; bad=1
else echo "ubsan_trap: no sanitizer runtime referenced"; fi

if [ -n "$BENCH" ]; then
  build FPUAutoBench-auto  "$CC" -m68040 -O2 -noixemul -DFPUAUTO "$BENCH" -lm
  build FPUAutoBench-plain "$CC" -m68040 -O2 -noixemul -DNO_FPUAUTO "$BENCH" -lm
  build FPUAutoBench-hard  "$CC" -m68040 -m68881 -O2 -noixemul -DHARD "$BENCH" -lm
  for v in auto plain; do
    echo "FPUAutoBench-$v: $("$NM" "$O/FPUAutoBench-$v" | grep -c ' ___wrap_') wrapped routines"
  done
fi
( cd "$O" && sha256sum $(ls | grep -v -e '\.log$' -e '^SHA256SUMS') ) > "$O/SHA256SUMS.new" && mv "$O/SHA256SUMS.new" "$O/SHA256SUMS"
exit $bad
