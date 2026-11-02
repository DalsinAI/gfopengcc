#!/bin/bash
# build.sh WORK PREFIX NDK_LHA [JOBS]
# Builds GFOpenAmigaGCC (GCC 16.2 for m68k-amigaos with libnix) into PREFIX from
# the sources fetch.sh put in WORK, with the patches in this repository.
#   NDK_LHA  the AmigaOS 3.2 NDK archive (NDK3.2.lha), which you supply: it is
#            not free software and is never fetched or kept here.
# Nothing is fetched: the build runs without network access when `unshare` can
# take it away, so a missing source stops the build instead of downloading.
# Extra libnix patches can be given in LIBNIX_PATCHES (a folder of *.patch).
# GPL-3.0-or-later, like the patches it goes with. Copyright (c) 2026 AmiCradle Team.
set -euo pipefail
WORK=$(cd "$1" && pwd); PREFIX=$2; NDK=$3; JOBS=${4:-$(nproc)}
HERE=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$PREFIX"; PREFIX=$(cd "$PREFIX" && pwd)
LOGS=$WORK/openamigagcc-logs; mkdir -p "$LOGS"
NOFETCH=""
if unshare -n --map-current-user true 2>/dev/null; then NOFETCH="unshare -n --map-current-user"; fi
say() { echo "== $*"; }

# 1. The pinned commits.
grep -v '^#' "$HERE/scripts/sources.lock" | while read -r name url commit dir; do
  [ -n "$name" ] || continue
  have=$(git -C "$WORK/$dir" rev-parse HEAD 2>/dev/null || echo none)
  # gcc and libnix may already carry this repository's patches as commits on top
  if [ "$have" != "$commit" ] && ! git -C "$WORK/$dir" merge-base --is-ancestor "$commit" HEAD 2>/dev/null; then
    echo "$name is at $have, not $commit (scripts/sources.lock)"; exit 1
  fi
done

# 2. Patches, each applied once: WORK/.openamigagcc-applied lists the ones in.
STAMP=$WORK/.openamigagcc-applied; touch "$STAMP"
same_stamped_diff() {   # PATCH: an older revision has the same diff and its exact hash is stamped
  local p=$1 rel=${1#"$HERE"/} now commit old_hash old_patch_id
  now=$(git patch-id --stable < "$p" | awk '{print $1}')
  [ -n "$now" ] || return 1
  while read -r commit; do
    old_hash=$(git -C "$HERE" show "$commit:$rel" 2>/dev/null | sha256sum | cut -c1-16) || continue
    grep -qxF "$(basename "$p") $old_hash" "$STAMP" || continue
    old_patch_id=$(git -C "$HERE" show "$commit:$rel" 2>/dev/null | git patch-id --stable | awk '{print $1}')
    [ "$old_patch_id" = "$now" ] && return 0
  done < <(git -C "$HERE" log --format=%H -- "$rel")
  return 1
}
apply() {   # apply DIR PATCH...
  local d=$1; shift
  for p in "$@"; do
    [ -f "$p" ] || continue
    local id; id="$(basename "$p") $(sha256sum < "$p" | cut -c1-16)"
    if grep -qxF "$id" "$STAMP"; then echo "already in: $(basename "$p")"; continue; fi
    # A release may change only a patch's mail header (for example its
    # copyright line) while leaving the diff itself unchanged.  An older
    # source cache then has the same named patch applied under its old hash.
    # Accept it only when the current diff reverses cleanly, and record the
    # new identity so later runs remain exact.
    if grep -qF "$(basename "$p") " "$STAMP" &&
       { git -C "$d" apply --reverse --check "$p" 2>/dev/null || same_stamped_diff "$p"; }; then
      echo "$id" >> "$STAMP"; echo "already in (verified): $(basename "$p")"; continue
    fi
    git -C "$d" apply --check "$p" 2>/dev/null || { echo "does not apply: $p"; exit 1; }
    git -C "$d" apply "$p"; echo "$id" >> "$STAMP"; echo "applied $(basename "$p")"
  done
}
say patches
apply "$WORK/projects/gcc" "$HERE"/patches/gcc/*.patch
apply "$WORK" "$HERE"/patches/amiga-gcc/*.patch
apply "$WORK/projects/libnix" "$HERE"/patches/libnix/*.patch ${LIBNIX_PATCHES:+"$LIBNIX_PATCHES"/*.patch}
apply "$WORK/projects/aros-stuff" "$HERE"/patches/aros-stuff/*.patch
cp "$HERE"/sys-include/*.h "$WORK/sys-include/"
# Roadshow's bsdsocket.h and usergroup.h inlines (amiga-netinclude, installed
# beside the NDK's) clobber registers their arguments sit in; GCC 16 refuses
# that. Make those registers dummy outputs (idempotent).
python3 "$HERE/scripts/fix_inline_clobbers.py" "$WORK"/projects/amiga-netinclude/include/inline/*.h
# sfdc's GCC inlines (the NDK's inline/*.h are made with it) bound A6 before
# evaluating the arguments, so Stricmp(FilePart(x), ...) ran with DOSBase in A6.
# Bind it after them (idempotent; stops if the code is not as expected).
python3 "$HERE/scripts/fix_sfdc_base_order.py" "$WORK"/projects/sfdc/MacroGCC.pl "$WORK"/projects/sfdc/sfdc

# 2b. amiga-gcc's framework carries a prebuilt Commodore amiga.lib in lib/ and
#     lib/libb/, which its libamiga step would install. Take them out of the
#     work folder: GFOpenAmigaGCC's libamiga.a is GFOpenNDK's, built in step 5b.
rm -f "$WORK/lib/libamiga.a" "$WORK/lib/libb/libamiga.a"

# 3. The NDK, from you.
mkdir -p "$WORK/download"
[ -f "$WORK/download/NDK3.2.lha" ] || cp "$NDK" "$WORK/download/NDK3.2.lha"

# 4. libnix's headers go in first: with no -mcrt the driver means -mcrt=nix20
#    (patch 0001), which looks for them, and libnix's own build has files
#    compiled without -mcrt.
mkdir -p "$PREFIX/m68k-amigaos/libnix/include"
rsync -a --no-group "$WORK/projects/libnix/sources/headers/" "$PREFIX/m68k-amigaos/libnix/include/"

# 5. The toolchain: binutils, GCC, libnix, libpthread, the NDK's headers and
#    libraries.
#    The driver leaves loop distribution on (patch 0009), so the C library is
#    built without it: libnix defines memcpy, memmove, memset, calloc, bcopy
#    and bzero itself, and a loop in one of them must never become a call to
#    memset/memcpy/memmove (that is, to itself). CFLAGS_FOR_TARGET reaches
#    libnix and libpthread; libgcc and libstdc++ define none of these and take
#    the default.
say "amiga-gcc (logs in $WORK/log)"
( cd "$WORK" && $NOFETCH make -j"$JOBS" binutils gcc gprof libnix libpthread ndk ndk13 \
    PREFIX="$PREFIX" THREADS=posix NDK=3.2 CFLAGS_FOR_TARGET="-O2 -fomit-frame-pointer -fno-tree-loop-distribute-patterns" ) > "$LOGS/make.log" 2>&1 || true
grep -aE '(make|install) [a-z0-9 ]*\.\.\.(done|failed)' "$LOGS/make.log" | sed 's/\x1b\[[0-9;]*[mK]//g' | sort -u
for d in binutils/_done gcc/_done libnix/_done libpthread/_done; do
  [ -f "$WORK/build-Linux-m68k-amigaos/$d" ] || { echo "the amiga-gcc build stopped at ${d%/_done} (see $LOGS/make.log and $WORK/log)"; exit 1; }
done
# gprof, ndk and ndk13 leave no _done marker: check what they install.
for f in bin/m68k-amigaos-gprof m68k-amigaos/ndk-include/exec/types.h m68k-amigaos/ndk13-include/exec/types.h; do
  [ -e "$PREFIX/$f" ] || { echo "the amiga-gcc build did not install $f (see $LOGS/make.log and $WORK/log)"; exit 1; }
done

# 5b. libamiga.a, from GFOpenNDK (projects/gfopensdk, pinned in
#     scripts/sources.lock), in every multilib folder, each built with that
#     multilib's own flags: "libm020/libm881;@mcpu=68020@m68881" gets
#     -mcpu=68020 -m68881, "libb;@fbaserel" -fbaserel. GFOpenNDK's lib/build.sh puts
#     -m68040 first, so a multilib that names no CPU gets -m68000 (this
#     GCC's default) after it: the last CPU flag wins. Each old file is
#     removed first, so a link to it (a stove's) is replaced, never written
#     through. docs/openndk-libamiga.md.
say "libamiga.a from GFOpenNDK"
OPENNDK=$WORK/projects/gfopensdk/OpenNDK
T=$PREFIX/m68k-amigaos
"$PREFIX/bin/m68k-amigaos-gcc" -print-multi-lib | while IFS=';' read -r dir flags; do
  fl=${flags//@/ -}
  case " $fl " in *" -mcpu="*|*" -m680"[0-6]"0 "*) ;; *) fl="-m68000$fl" ;; esac
  log=$LOGS/openndk-libamiga-$([ "$dir" = . ] && echo plain || echo "${dir//\//-}").log
  ( PREFIX="$PREFIX/bin/m68k-amigaos-" EXTRA_CFLAGS="$fl" sh "$OPENNDK/lib/build.sh" ) > "$log" 2>&1 \
    || { echo "GFOpenNDK's libamiga.a for multilib '$dir' ($fl) failed (see $log)"; exit 1; }
  mkdir -p "$T/lib/$dir"
  rm -f "$T/lib/$dir/libamiga.a"
  cp "$OPENNDK/lib/build/m68k-amigaos/libamiga.a" "$T/lib/$dir/libamiga.a"
done

# 6. libgcc, libstdc++ and the other target libraries, against libnix's
#    headers, so libstdc++'s configure sees C99 maths, dirent and chdir.
say "target libraries against libnix"
T=$PREFIX/m68k-amigaos
FFT="-B$T/bin/ -B$T/lib/ -B$T/libnix/lib/ -isystem $T/include -isystem $T/libnix/include -isystem $T/ndk-include -isystem $T/sys-include"
B=$WORK/build-Linux-m68k-amigaos/gcc
( cd "$B" && $NOFETCH make -j"$JOBS" all-target FLAGS_FOR_TARGET="$FFT" && $NOFETCH make install-target FLAGS_FOR_TARGET="$FFT" ) > "$LOGS/target-libs.log" 2>&1 \
  || { echo "target libraries failed (see $LOGS/target-libs.log)"; exit 1; }
# fenv.h (sys-include) is header-only: tell libstdc++ it is there.
for f in $(find "$PREFIX/lib/gcc/m68k-amigaos" -path "*include/c++*" -name c++config.h); do
  for d in _GLIBCXX_HAVE_FENV_H _GLIBCXX_USE_C99_FENV _GLIBCXX_USE_C99_FENV_TR1; do
    grep -q "define $d 1" "$f" || sed -i "s|^/\* #undef $d \*/|#define $d 1|" "$f"
  done
done

# 6b. libnix4.a (the static part of the shared libnix, for -mcrt=library). The
#     shared libnix4.library itself does not link (a duplicate
#     __vfwprintf_total_size export); static programs don't need it.
echo done > "$WORK/build-Linux-m68k-amigaos/gcc/_libgcc_done"   # step 6 built and installed them
( cd "$WORK" && $NOFETCH make libnix4.library PREFIX="$PREFIX" THREADS=posix NDK=3.2 ) > "$LOGS/libnix4.log" 2>&1 || true
if [ -f "$WORK/build-Linux-m68k-amigaos/libnix/libb/libnix4.a" ]; then
  cp "$WORK/build-Linux-m68k-amigaos/libnix/libb/libnix4.a" "$PREFIX/m68k-amigaos/libnix/lib/libb/"
fi

# 7. Checks.
say checks
CC="$PREFIX/bin/m68k-amigaos-gcc"
C=$LOGS/check; mkdir -p "$C"
"$CC" --version | head -1 | grep -Fq '(OpenAmigaGCC 16.2.0-open4)' || {
  echo "gcc does not identify itself as OpenAmigaGCC 16.2.0-open4"; exit 1;
}
link_cpu=$("$CC" -dumpspecs | sed -n '/^\*link_cpu:/{n;p;q;}')
case "$link_cpu" in
  *'mhard-float|m68881|mcpu=6804'* )
    echo "-m68040 still selects the hard-float libm881"; exit 1 ;;
esac
printf 'volatile unsigned long s;\nint main(void) { s = *(volatile unsigned long *)0; return 0; }\n' > "$C/nullread.c"
"$CC" -O2 -c -o "$C/nullread.o" "$C/nullread.c"
if "$PREFIX/bin/m68k-amigaos-objdump" -d "$C/nullread.o" | grep -qE 'trap +#7'; then echo "a read of address 0 still compiles to trap #7"; exit 1; fi
printf '#include <stdio.h>\n#include <stdlib.h>\nint main(void) { char *p = calloc(4, 4); printf("hello %%d\\n", p ? p[3] : -1); free(p); return 0; }\n' > "$C/hello.c"
"$CC" -O2 -o "$C/hello" "$C/hello.c" -Wl,-Map,"$C/hello.map"
grep -q 'libnix' "$C/hello.map" || { echo "hello did not link libnix"; exit 1; }
"$PREFIX/bin/m68k-amigaos-g++" -O2 -std=c++23 -o "$C/hellocxx" -x c++ - -x none -lpthread -latomic <<'CXX'
#include <vector>
#include <algorithm>
#include <cstdio>
int main() { std::vector<int> v{3, 1, 2}; std::sort(v.begin(), v.end()); std::printf("%d%d%d\n", v[0], v[1], v[2]); }
CXX
# libnix's own memcpy, memmove, memset, calloc, bcopy, bzero and wmem*: none may call itself,
# and the block functions none of memset/memcpy/memmove (loop distribution would make that).
selfcalls() {   # selfcalls OBJECT: the mem* functions OBJECT calls (a relocation to one, or a call/jump to its start)
  "$PREFIX/bin/m68k-amigaos-objdump" -dr "$1" | grep -E 'R_68K[A-Z0-9_]* +_?(memcpy|memmove|memset|calloc|bcopy|bzero)$|(jsr|bsr|jbsr|jra|jmp).*<_?(memcpy|memmove|memset|calloc|bcopy|bzero)>' \
    | grep -oE '(memcpy|memmove|memset|calloc|bcopy|bzero)(>|$)' | tr -d '>' | sort -u | tr '\n' ' ' || true
}
n=0
while IFS= read -r a; do
  D=$(mktemp -d "$C/libnix-members.XXXXXX")
  ( cd "$D" && "$PREFIX/bin/m68k-amigaos-ar" x "$a" bcopy.o bzero.o calloc.o memcpy.o memmove.o mempcpy.o memset.o wmemcpy.o wmemmove.o wmemset.o 2>/dev/null )
  for o in "$D"/*.o; do
    [ -f "$o" ] || continue; f=$(basename "$o" .o); n=$((n+1)); refs=" $(selfcalls "$o")"
    case $f in   # the calls the sources make on purpose
      calloc)  refs=${refs/ memset / } ;;       # calloc fills what malloc gave it
      mempcpy) refs=${refs/ memcpy / } ;;       # mempcpy is memcpy plus a pointer
      memmove) refs=${refs/ bcopy / } ;;        # memmove is bcopy
    esac
    if [ -n "${refs// /}" ]; then echo "libnix: $f.o in $a calls$refs (loop distribution made a library function call itself?)"; exit 1; fi
  done
done < <(find "$PREFIX/m68k-amigaos/libnix/lib" -name libnix.a)
echo "libnix: $n mem*/calloc objects checked; none calls itself or a block function"
# Every libamiga.a is GFOpenNDK's (its rexxvar.o; Commodore's amiga.lib has no
# such member), and each multilib links the one in its own folder.
n=0
while IFS= read -r a; do
  "$PREFIX/bin/m68k-amigaos-ar" t "$a" | grep -qx rexxvar.o || { echo "$a is not GFOpenNDK's libamiga.a"; exit 1; }
  n=$((n+1))
done < <(find "$PREFIX/m68k-amigaos" "$PREFIX/lib" -name 'libamiga.a' -not -path '*/ndk*')
"$CC" -print-multi-lib | while IFS=';' read -r dir flags; do
  got=$("$CC" ${flags//@/ -} -print-file-name=libamiga.a)
  [ "$(readlink -f "$got")" = "$(readlink -f "$T/lib/$dir/libamiga.a")" ] || { echo "multilib '$dir' links $got, not its own libamiga.a"; exit 1; }
done
# The 68000 multilibs' libamiga.a (every one that names no 68020 or later)
# has nothing a 68000 lacks: no address objdump's 68000 table can't decode
# (".short") where its 68040 table finds an instruction (mulu.l, tst.l An,
# ...; strings in .text are ".short" to both), and no scaled index or
# memory indirection.
m68kdis() { # CPU LIB: "object/address S|I" for every word objdump shows
  "$PREFIX/bin/m68k-amigaos-objdump" -d -m "m68k:$1" "$2" \
    | awk '/file format/ { f = $1 } /^ +[0-9a-f]+:/ { print f "/" $1, (/\.short/ ? "S" : "I") }'
}
"$CC" -print-multi-lib | while IFS=';' read -r dir flags; do
  case "$flags" in *680[2-6]0*) continue ;; esac
  a=$T/lib/$dir/libamiga.a
  bad=$(join <(m68kdis 68000 "$a" | awk '$2 == "S" { print $1 }' | sort) <(m68kdis 68040 "$a" | awk '$2 == "I" { print $1 }' | sort)
        "$PREFIX/bin/m68k-amigaos-objdump" -d -m m68k:68000 "$a" | grep -E '^ +[0-9a-f]+:.*(:[wl]:[248]\)|\)@\()' || true)
  [ -z "$bad" ] || { echo "multilib '$dir' libamiga.a has 68020+ code:"; echo "$bad" | head -5; exit 1; }
done
printf '#include <proto/exec.h>\n#include <clib/alib_protos.h>\nint main(void) { struct List l; NewList(&l); return IsListEmpty(&l) ? 0 : 1; }\n' > "$C/alib.c"
"$CC" -m68040 -O2 -I"$OPENNDK/Include_H" -o "$C/alib" "$C/alib.c" -Wl,-Map,"$C/alib.map"
grep -q 'gfopensdk/OpenNDK\|libamiga.a(newlist.o)' "$C/alib.map" || { echo "a NewList program did not link GFOpenNDK's libamiga.a"; exit 1; }
echo "libamiga.a: $n copies, all GFOpenNDK's; every multilib links its own"
echo "defaults: $("$CC" -### -c -x c /dev/null 2>&1 | grep -o -- '-fno-[a-z-]*' | sort -u | tr '\n' ' ')"
echo "GFOpenAmigaGCC built in $PREFIX"
