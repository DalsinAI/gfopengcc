#!/bin/bash
# build-aros.sh WORK PREFIX SYSROOT [JOBS]
# Builds GFOpenAmigaGCC's m68k-aros target (GCC 16.2.0 for AROS 68k) into PREFIX
# from the sources fetch-aros.sh put in WORK/aros, with patches/aros/series: AROS's
# own GCC and binutils diffs and this repository's m68k code generation fixes.
# It is configured as AROS's crosstools build configures it (tools/crosstools/gnu
# mmakefile.src), so the tools land in PREFIX itself (PREFIX/m68k-aros-gcc), with
# AROS's collect-aros as the linker driver.
#   SYSROOT  an AROS SDK: the AROS/Developer folder of an AROS m68k build of the
#            pinned AROS commit (include/ and lib/). GCC is configured with it, and
#            libgcc, libstdc++ and (as AROS does) libatomic are built against it;
#            libatomic is installed into SYSROOT/lib, so give it a copy of its own.
#            "none": only the compiler, binutils and collect-aros (enough to compile
#            and assemble; CI does this).
# AROS_FROM=libatomic picks a build up again at step 6 (libatomic), with steps 1-5's
# build folder and PREFIX as they were left.
# Nothing is fetched.
# GPL-3.0-or-later, like the patches it goes with. Copyright (c) 2026 AmiCradle Team.
set -euo pipefail
WORK=$(cd "$1" && pwd); PREFIX=$2; SYSROOT=$3; JOBS=${4:-$(nproc)}
HERE=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$PREFIX"; PREFIX=$(cd "$PREFIX" && pwd)
A=$WORK/aros; S=$A/src; B=$A/build; LOGS=$A/logs; mkdir -p "$LOGS"
# The identity scripts/build.sh gives the m68k-amigaos GCC (tests/release-names.sh keeps them in step).
ID="GFOpenAmigaGCC 16.2.0-open6"
T=m68k-aros
say() { echo "== $*"; }
if [ "$SYSROOT" = none ]; then
  # an empty one: GCC's fixincludes stops when the sysroot has no include folder
  FULL=0; SR=$PREFIX/no-sysroot; mkdir -p "$SR/include" "$SR/lib"
else
  FULL=1; SR=$(cd "$SYSROOT" && pwd)
  [ -d "$SR/include" ] && [ -d "$SR/lib" ] || { echo "$SR is not an AROS SDK (no include/ and lib/)"; exit 1; }
fi

AROS=$A/AROS
FROM=${AROS_FROM:-start}
case $FROM in start|libatomic) ;; *) echo "AROS_FROM=$FROM: start or libatomic"; exit 1 ;; esac
[ "$FROM" = start ] || [ "$FULL" = 1 ] || { echo "AROS_FROM=$FROM needs an AROS SDK"; exit 1; }
if [ "$FROM" = start ]; then
# 1. AROS's diffs here are AROS's, unchanged, at the pinned commit.
cmp -s "$HERE/patches/aros/gcc/0001-gcc-16.2.0-aros.diff" "$AROS/tools/crosstools/gnu/gcc-16.2.0-aros.diff" ||
  { echo "patches/aros/gcc/0001 is not AROS's tools/crosstools/gnu/gcc-16.2.0-aros.diff at $(git -C "$AROS" rev-parse --short HEAD)"; exit 1; }
cmp -s "$HERE/patches/aros/binutils/0001-binutils-2.47-aros.diff" "$AROS/tools/crosstools/gnu/binutils-2.47-aros.diff" ||
  { echo "patches/aros/binutils/0001 is not AROS's tools/crosstools/gnu/binutils-2.47-aros.diff"; exit 1; }

# 2. Fresh sources, then the series (each patch must apply exactly: no fuzz).
say "sources and patches/aros/series"
rm -rf "$S" "$B"; mkdir -p "$S" "$B"
tar -C "$S" -xf "$A/gcc-16.2.0.tar.xz"
tar -C "$S" -xf "$A/binutils-2.47.tar.bz2"
tar -C "$S" -xf "$A/isl-0.27.tar.xz" && mv "$S/isl-0.27" "$S/gcc-16.2.0/isl"   # built in tree
grep -v '^#' "$HERE/patches/aros/series" | while read -r tree p; do
  [ -n "$tree" ] || continue
  case $tree in gcc) d=$S/gcc-16.2.0 ;; binutils) d=$S/binutils-2.47 ;; *) echo "series: no tree $tree"; exit 1 ;; esac
  ( cd "$d" && patch -p1 -s -F0 -f --dry-run < "$HERE/patches/$p" > /dev/null ) || { echo "does not apply: patches/$p"; exit 1; }
  ( cd "$d" && patch -p1 -s -F0 -f --no-backup-if-mismatch < "$HERE/patches/$p" )
  echo "applied $p"
done

# 3. binutils, as AROS configures them.
say "binutils (logs in $LOGS)"
mkdir -p "$B/binutils"
( cd "$B/binutils" && "$S/binutils-2.47/configure" --prefix="$PREFIX" --target=$T --bindir="$PREFIX" --libdir="$PREFIX/lib" \
    --with-sysroot="$SR" --disable-werror --disable-nls && make -j"$JOBS" && make install ) > "$LOGS/binutils.log" 2>&1 \
  || { echo "binutils failed (see $LOGS/binutils.log)"; exit 1; }

# 4. collect-aros (AROS's linker driver: GCC's LINKER_NAME on AROS), with the paths
#    AROS's configure would give its env.h for this prefix.
say collect-aros
CA=$AROS/tools/collect-aros; G=$B/collect-aros; mkdir -p "$G" "$PREFIX/$T/bin"
sed -e "s|@aros_toolchain_ld@|$PREFIX/$T-ld|; s|@AROS_CROSSTOOLSDIR@|$PREFIX|g; s|@aros_target_cpu@|m68k|g; s|@aros_toolchain@|gnu|g" \
    -e "s|@orig_target_ld@|$PREFIX/$T-ld|; s|@aros_target_strip@|$PREFIX/$T-strip|" \
    -e "s|@aros_target_nm@|$PREFIX/$T-nm --demangle --undefined-only --line-numbers|; s|@aros_target_objdump@|$PREFIX/$T-objdump|" \
    "$CA/env.h.in" > "$G/env.h"
! grep -q '@' "$G/env.h" || { echo "collect-aros: env.h.in has a setting this script does not fill"; exit 1; }
( cd "$CA" && ${HOST_CC:-cc} -o "$G/collect-aros" -Wall -Wunused -O2 -D_CROSS_ -DOBJLIBDIR="\"$SR/lib\"" -I "$G" -I . \
    collect-aros.c gensets.c misc.c backend-generic.c docommand-exec.c ) > "$LOGS/collect-aros.log" 2>&1 \
  || { echo "collect-aros failed (see $LOGS/collect-aros.log)"; exit 1; }
strip "$G/collect-aros"
install -m 755 "$G/collect-aros" "$PREFIX/$T/bin/collect-aros"
install -m 755 "$G/collect-aros" "$PREFIX/$T-collect-aros"

# 5. GCC, with AROS's configure options (crosstools mmakefile.src's GCC_COMMON_OPTS
#    for m68k) and the release identity. AROS builds libatomic on its own (step 6).
say "gcc (logs in $LOGS)"
export PATH="$PREFIX:$PATH"
mkdir -p "$B/gcc"
( cd "$B/gcc" && enable_libatomic=no "$S/gcc-16.2.0/configure" --prefix="$PREFIX" --target=$T --with-dwarf2 \
    --with-sysroot="$SR" --with-native-system-header-dir=/include --bindir="$PREFIX" --libdir="$PREFIX/lib" \
    --enable-languages=c,c++ --enable-long-long --enable-version-specific-runtime-libs --enable-frame-pointer \
    --disable-isl-version-check --disable-bootstrap --disable-sjlj-exceptions --disable-tls --disable-plugins \
    --disable-nls --disable-libssp --disable-libstdcxx-pch --disable-build-with-cxx --disable-build-poststage1-with-cxx \
    --with-pkgversion="$ID" ) > "$LOGS/gcc-configure.log" 2>&1 || { echo "gcc configure failed (see $LOGS/gcc-configure.log)"; exit 1; }
( cd "$B/gcc" && make -j"$JOBS" all-gcc && make -j1 install-gcc ) > "$LOGS/gcc.log" 2>&1 \
  || { echo "gcc failed (see $LOGS/gcc.log)"; exit 1; }
"$PREFIX/$T-gcc" --version | head -1 | grep -Fq "($ID)" || { echo "m68k-aros-gcc does not identify itself as $ID"; exit 1; }

if [ "$FULL" = 1 ]; then
  say "libgcc and libstdc++ against $SR"
  ( cd "$B/gcc" && make -j"$JOBS" all && make -j1 install ) > "$LOGS/gcc-target.log" 2>&1 \
    || { echo "the target libraries failed (see $LOGS/gcc-target.log)"; exit 1; }
fi
fi   # AROS_FROM=start
export PATH="$PREFIX:$PATH"
if [ "$FULL" = 1 ]; then

  # 6. libatomic, as AROS's crosstools build makes it (configured on its own, with
  #    AROS's target flags, one per multilib), into SYSROOT/lib. Its build folder is
  #    where AROS puts it, in GCC's (TARGET/libatomic, the multilibs in
  #    TARGET/MULTIDIR/libatomic), which its libtool install step expects.
  say "libatomic into $SR/lib"
  LA=$B/gcc/$T; rm -rf "$LA/libatomic" "$LA"/*/libatomic "$LA"/*/*/libatomic; mkdir -p "$LA/libatomic"
  ( cd "$LA/libatomic" && CC="$PREFIX/$T-gcc" CCAS="$PREFIX/$T-gcc" AR="$PREFIX/$T-ar" RANLIB="$PREFIX/$T-ranlib" \
      CFLAGS="-msoft-float -fno-strict-aliasing -ffreestanding -fomit-frame-pointer -fbuiltin -Wno-pointer-sign -Wno-parentheses -Wno-volatile-register-var -Os" \
      CPPFLAGS="-DAROS_BUILD_TYPE=AROS_BUILD_TYPE_PERSONAL -DNOLIBINLINE" LDFLAGS="-msoft-float -L$SR/lib -s" \
      "$S/gcc-16.2.0/libatomic/configure" --prefix="$B/libatomic-prefix" --target=$T --build="$("$S/gcc-16.2.0/config.guess")" --host=$T \
      --without-pic --disable-shared --disable-nls --without-x && make -j"$JOBS" ) > "$LOGS/libatomic.log" 2>&1 \
    || { echo "libatomic failed (see $LOGS/libatomic.log)"; exit 1; }
  "$PREFIX/$T-gcc" -print-multi-lib | while IFS=';' read -r dir _; do
    lb=$LA/libatomic; [ "$dir" = . ] || lb=$LA/$dir/libatomic
    [ -f "$lb/.libs/libatomic.a" ] || { echo "libatomic: no build for multilib '$dir'"; exit 1; }
    mkdir -p "$SR/lib/$dir"
    for f in libatomic.a libatomic_asneeded.a; do
      [ -f "$lb/.libs/$f" ] || [ -f "$lb/$f" ] || continue
      rm -f "$SR/lib/$dir/$f"; cp "$( [ -f "$lb/.libs/$f" ] && echo "$lb/.libs/$f" || echo "$lb/$f")" "$SR/lib/$dir/$f"
    done
  done
fi

# 7. Checks.
say checks
C=$LOGS/check; mkdir -p "$C"
printf 'int f(int *p, int n) { int s = 0; while (n--) s += *p++; return s; }\n' > "$C/sum.c"
"$PREFIX/$T-gcc" -m68040 -O2 -c -o "$C/sum.o" "$C/sum.c"
"$PREFIX/$T-objdump" -f "$C/sum.o" | grep -q 'elf32-m68k' || { echo "$T-gcc did not make an m68k ELF object"; exit 1; }
if [ "$FULL" = 1 ]; then
  "$HERE/tests/aros-libgcc.sh" "$PREFIX"
  printf '#include <stdio.h>\nint main(void) { printf("hello\\n"); return 0; }\n' > "$C/hello.c"
  "$PREFIX/$T-gcc" -m68040 -O2 -o "$C/hello" "$C/hello.c"
  # C++ as the aros68k-gcc16 stove's tests link it (libstdc++ locks through
  # pthread, whose init entry only an early reference keeps).  Keep -m68040:
  # Open6's notes recorded an unresolved __divsi3 here, although the installed
  # Open6 and archived predecessor now both pass this exact link.
  "$PREFIX/$T-g++" -m68040 -O2 -std=c++23 -o "$C/hellocxx" -x c++ - -x none -Wl,-u,__pthread_Init_Func -lpthread -latomic <<'CXX'
#include <vector>
#include <algorithm>
#include <cstdio>
int main() { std::vector<int> v{3, 1, 2}; std::sort(v.begin(), v.end()); std::printf("%d%d%d\n", v[0], v[1], v[2]); }
CXX
  echo "linked a C and a C++ program against $SR"
fi
echo "$("$PREFIX/$T-gcc" --version | head -1) built in $PREFIX"
