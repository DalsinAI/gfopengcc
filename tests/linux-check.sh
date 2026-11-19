#!/bin/bash
# tests/linux-check.sh PREFIX ARCH
# Checks a scripts/build-linux.sh toolchain for ARCH (aarch64, x86_64 or powerpc) in PREFIX:
# - ARCH-linux-gnu-gcc --version names the release (patches/amiga-gcc/0002's identity);
# - its programs (gcc, cc1, as, ld) link no GMP, MPFR or MPC shared library;
# - it compiles with that architecture's kernel code flags to the right ELF
#   format, and assembles the kernel's system instructions (aarch64: system
#   registers and pointer authentication; x86_64: control registers, and the
#   32-bit and 16-bit code the vDSO and real-mode trampoline need; powerpc: the
#   440/460 MSR, SPR and TLB instructions, soft float, as the AC460's kernel);
# - libgcc is installed;
# - tests/linux/hello-ARCH.c, freestanding, links and prints "ARCH ok" at -O2
#   and -Os (aarch64 and powerpc under qemu-aarch64 / qemu-ppc when there; x86_64 natively).
# GPL-3.0-or-later. Copyright (c) 2026 AmiCradle Team.
set -euo pipefail
P=$(cd "$1" && pwd); ARCH=${2:-aarch64}; HERE=$(cd "$(dirname "$0")/.." && pwd)
T=$ARCH-linux-gnu; CC=$P/bin/$T-gcc
fail() { echo "$ARCH check: $*"; exit 1; }
O=$(mktemp -d); trap 'rm -rf "$O"' EXIT
case $ARCH in
  aarch64)
    ELF=elf64-littleaarch64; MACH=AArch64; RUN=qemu-aarch64
    KF="-mgeneral-regs-only -mabi=lp64 -mbranch-protection=pac-ret -fpatchable-function-entry=4,2 \
 -mstack-protector-guard=sysreg -mstack-protector-guard-reg=sp_el0 -mstack-protector-guard-offset=0"
    HF="-mgeneral-regs-only"
    ASM='\tmsr daifset, #2\n\tmrs x0, sctlr_el1\n\tpaciasp\n\tautiasp\n\tret\n'; AF="-march=armv8.3-a" ;;
  x86_64)
    ELF=elf64-x86-64; MACH='X86-64'; RUN=""
    KF="-mcmodel=kernel -mno-red-zone -mno-sse -mno-mmx -mno-sse2 -mno-3dnow -mno-avx -mno-80387 -mno-fp-ret-in-387 \
 -mskip-rax-setup -mindirect-branch=thunk-extern -mindirect-branch-register -mfunction-return=thunk-extern -mharden-sls=all \
 -fcf-protection=branch -mrecord-mcount -mfentry -mstack-protector-guard-reg=gs -mstack-protector-guard-symbol=__ref_stack_chk_guard"
    HF="-mno-sse -mno-mmx -mno-red-zone"
    ASM='\tcli\n\tmov %cr3, %rax\n\tmov %rax, %cr3\n\twrmsr\n\tendbr64\n\tsti\n\tret\n'; AF="" ;;
  powerpc)
    ELF=elf32-powerpc; MACH=PowerPC; RUN=qemu-ppc
    KF="-mcpu=440 -msoft-float -mno-altivec -ffixed-r2 -mno-prefixed -mno-pcrel -mbig-endian -mstack-protector-guard=tls -mstack-protector-guard-reg=r2"
    HF="-msoft-float"
    ASM='\tmfmsr 3\n\twrteei 0\n\tmtspr 0x3f0, 3\n\ttlbwe 3,4,0\n\tmsync\n\tisync\n\tblr\n'; AF="-mcpu=440" ;;
  *) fail "ARCH $ARCH: aarch64, x86_64 or powerpc" ;;
esac
pkg=$(sed -n 's/^+.*--with-pkgversion="\([^"]*\)".*/\1/p' "$HERE"/patches/amiga-gcc/0002-*-pkgversion.patch)
"$CC" --version | sed -n 1p | grep -qF "($pkg) 16.2.0" || fail "$T-gcc does not say ($pkg) 16.2.0: $("$CC" --version | sed -n 1p)"
echo "ok   identity: $("$CC" --version | sed -n 1p)"
for f in "$CC" "$("$CC" -print-prog-name=cc1)" "$P/bin/$T-as" "$P/bin/$T-ld"; do
  [ -x "$f" ] || fail "no $f"
  if ldd "$f" 2>/dev/null | grep -E 'libgmp|libmpfr|libmpc|libisl|libzstd'; then fail "$f needs a shared library the host may not have"; fi
done
echo "ok   gcc, cc1, as and ld need only the C library"
# the kernel's code flags (arch/*/Makefile and the top Makefile)
CF="-O2 -std=gnu11 -ffreestanding -nostdinc -fno-builtin -fno-pic -fno-asynchronous-unwind-tables -fno-delete-null-pointer-checks \
 -fno-strict-aliasing -fno-stack-protector -fno-omit-frame-pointer"
printf 'int f(int *p, int n) { int s = 0; while (n--) s += *p++; return s; }\n' > "$O/sum.c"
# shellcheck disable=SC2086
"$CC" $CF $KF -c -o "$O/sum.o" "$O/sum.c" || fail "the kernel's flags do not compile"
"$P/bin/$T-objdump" -f "$O/sum.o" | grep -q "$ELF" || fail "$T-gcc did not make an $ELF object"
printf '%b' "$ASM" > "$O/sys.S"
# shellcheck disable=SC2086
"$CC" $AF -c -o "$O/sys.o" "$O/sys.S" || fail "the kernel's system instructions do not assemble"
if [ "$ARCH" = x86_64 ]; then
  "$CC" -m32 -O2 -ffreestanding -fno-pic -c -o "$O/sum32.o" "$O/sum.c" || fail "-m32 (the 32-bit vDSO) does not compile"
  "$P/bin/$T-objdump" -f "$O/sum32.o" | grep -q elf32-i386 || fail "-m32 did not make an elf32-i386 object"
  "$CC" -m16 -Os -ffreestanding -fno-pic -c -o "$O/sum16.o" "$O/sum.c" || fail "-m16 (the real-mode code) does not compile"
  echo "ok   kernel flags compile, system instructions assemble, -m32 and -m16 compile"
else
  echo "ok   kernel flags compile, system and PAC instructions assemble"
fi
[ -f "$("$CC" -print-libgcc-file-name)" ] || fail "no libgcc.a"
echo "ok   libgcc: $("$CC" -print-libgcc-file-name)"
for opt in -O2 -Os; do
  # shellcheck disable=SC2086
  "$CC" $opt -static -nostdlib -ffreestanding $HF -o "$O/hello$opt" "$HERE/tests/linux/hello-$ARCH.c" -lgcc || fail "hello-$ARCH.c does not link at $opt"
  "$P/bin/$T-readelf" -h "$O/hello$opt" | grep -q "$MACH" || fail "hello$opt is not an $MACH program"
  if [ -n "$RUN" ] && ! command -v "$RUN" > /dev/null; then
    echo "ok   hello $opt links (no $RUN here to run it)"; continue
  fi
  if [ -z "$RUN" ] && [ "$(uname -m)" != x86_64 ]; then
    echo "ok   hello $opt links (not an x86-64 host)"; continue
  fi
  # shellcheck disable=SC2086
  out=$($RUN "$O/hello$opt") || fail "hello$opt exits with $?"
  [ "$out" = "$ARCH ok" ] || fail "hello$opt printed \"$out\""
  echo "ok   hello $opt${RUN:+ under $RUN}: $out"
done
echo "$ARCH check: all passed in $P"
