#!/bin/bash
# tests/aarch64-check.sh PREFIX
# Checks a scripts/build-aarch64.sh toolchain in PREFIX:
# - aarch64-linux-gnu-gcc --version names the release (patches/amiga-gcc/0002's identity);
# - its programs (gcc, cc1, as, ld) link no GMP, MPFR or MPC shared library;
# - it compiles with the arm64 kernel's own code flags to elf64-littleaarch64,
#   and assembles system-register and pointer-authentication instructions;
# - libgcc is installed;
# - tests/aarch64/hello.c, freestanding, links and (with qemu-aarch64) prints
#   "aarch64 ok" at -O2 and -Os.
# GPL-3.0-or-later. Copyright (c) 2026 AmiCradle Team.
set -euo pipefail
P=$(cd "$1" && pwd); HERE=$(cd "$(dirname "$0")/.." && pwd)
T=aarch64-linux-gnu; CC=$P/bin/$T-gcc
fail() { echo "aarch64 check: $*"; exit 1; }
O=$(mktemp -d); trap 'rm -rf "$O"' EXIT
pkg=$(sed -n 's/^+.*--with-pkgversion="\([^"]*\)".*/\1/p' "$HERE"/patches/amiga-gcc/0002-*-pkgversion.patch)
"$CC" --version | sed -n 1p | grep -qF "($pkg) 16.2.0" || fail "$T-gcc does not say ($pkg) 16.2.0: $("$CC" --version | sed -n 1p)"
echo "ok   identity: $("$CC" --version | sed -n 1p)"
for f in "$CC" "$("$CC" -print-prog-name=cc1)" "$P/bin/$T-as" "$P/bin/$T-ld"; do
  [ -x "$f" ] || fail "no $f"
  if ldd "$f" 2>/dev/null | grep -E 'libgmp|libmpfr|libmpc|libisl|libzstd'; then fail "$f needs a shared library the host may not have"; fi
done
echo "ok   gcc, cc1, as and ld need only the C library"
# the arm64 kernel's code flags (arch/arm64/Makefile and the top Makefile)
KF="-O2 -std=gnu11 -ffreestanding -nostdinc -fno-builtin -mgeneral-regs-only -mabi=lp64 -fno-pic -fno-asynchronous-unwind-tables \
 -fno-unwind-tables -mbranch-protection=pac-ret -fpatchable-function-entry=4,2 -fno-delete-null-pointer-checks -fno-strict-aliasing \
 -fno-stack-protector -fno-omit-frame-pointer -mstack-protector-guard=sysreg -mstack-protector-guard-reg=sp_el0 -mstack-protector-guard-offset=0"
printf 'int f(int *p, int n) { int s = 0; while (n--) s += *p++; return s; }\n' > "$O/sum.c"
"$CC" $KF -c -o "$O/sum.o" "$O/sum.c" || fail "the kernel's flags do not compile"
"$P/bin/$T-objdump" -f "$O/sum.o" | grep -q 'elf64-littleaarch64' || fail "$T-gcc did not make an aarch64 ELF object"
printf '\tmsr daifset, #2\n\tmrs x0, sctlr_el1\n\tpaciasp\n\tautiasp\n\tret\n' > "$O/sys.S"
"$CC" -march=armv8.3-a -c -o "$O/sys.o" "$O/sys.S" || fail "system-register or PAC instructions do not assemble"
echo "ok   kernel flags compile, system and PAC instructions assemble"
[ -f "$("$CC" -print-libgcc-file-name)" ] || fail "no libgcc.a"
echo "ok   libgcc: $("$CC" -print-libgcc-file-name)"
for opt in -O2 -Os; do
  "$CC" $opt -static -nostdlib -ffreestanding -mgeneral-regs-only -o "$O/hello$opt" "$HERE/tests/aarch64/hello.c" -lgcc || fail "hello.c does not link at $opt"
  "$P/bin/$T-readelf" -h "$O/hello$opt" | grep -q 'AArch64' || fail "hello$opt is not an AArch64 program"
  if command -v qemu-aarch64 > /dev/null; then
    out=$(qemu-aarch64 "$O/hello$opt") || fail "hello$opt exits with $?"
    [ "$out" = "aarch64 ok" ] || fail "hello$opt printed \"$out\""
    echo "ok   hello $opt under qemu-aarch64: $out"
  else
    echo "ok   hello $opt links (no qemu-aarch64 here to run it)"
  fi
done
echo "aarch64 check: all passed in $P"
