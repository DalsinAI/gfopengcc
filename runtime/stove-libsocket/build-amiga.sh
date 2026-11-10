#!/bin/sh
# Copyright (c) 2026 AmiCradle Team. MIT licence (see LICENSE at the repository root).
# libnix patch 0010 (socket ioctl() with POSIX's three arguments, fcntl() for
# sockets) for a stove that was built before it, without rebuilding the stove:
# for each libsocket.a the stove has, ioctl.o is rebuilt from the patched
# source and fcntl.o is added, with the flags libnix's Makefile.gcc6 used.
#
# Before it builds anything patched it rebuilds the unpatched ioctl.c the same
# way and checks the code matches the stove's own ioctl.o in every multilib, so
# the new members are made exactly as the stove's were.
#
# Builds and checks only; install/ puts the result into the stove.
#   STOVE=<stove folder> OUT=<folder> sh build-amiga.sh
# Output: OUT/lib/<multilib>/libsocket.a, OUT/tests/SocketIoctl (patched
# library) and OUT/tests/SocketIoctl-old (the stove's), from
# tests/libnix/socket_ioctl.c.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
STOVE=${STOVE:-"$HOME/AmiCradle/stoves/os32-gcc16-open6"}
P="$STOVE/prefix"
CC="$P/bin/m68k-amigaos-gcc"; AR="$P/bin/m68k-amigaos-ar"; NM="$P/bin/m68k-amigaos-nm"; OD="$P/bin/m68k-amigaos-objdump"
[ -x "$CC" ] || { echo "build-amiga.sh: no $CC" >&2; exit 2; }
LIB="$P/m68k-amigaos/libnix/lib"; HDR="$P/m68k-amigaos/libnix/include"
echo "built on $(hostname) as $(id -un), stove $STOVE ($("$CC" --version | head -1))"
OUT=${OUT:-"$HERE/build-amiga"}; rm -rf "$OUT/lib" "$OUT/obj" "$OUT/extra-inc"; mkdir -p "$OUT/lib" "$OUT/tests" "$OUT/obj"
PATCH=$(ls "$ROOT"/patches/libnix/0010-*.patch)

# libnix's socket sources at the commit the stove was built from
SRC="$OUT/obj/libnix"
LNURL=$(awk '$1=="libnix"{print $2}' "$ROOT/scripts/sources.lock")
LNSHA=$(awk '$1=="libnix"{print $3}' "$ROOT/scripts/sources.lock")
got=0
if command -v git >/dev/null 2>&1; then
  mkdir -p "$SRC" && ( cd "$SRC" && git init -q && git fetch -q --depth 1 "$LNURL" "$LNSHA" && git checkout -q FETCH_HEAD ) >/dev/null 2>&1 && got=1
fi
if [ $got = 0 ]; then
  # the same tree, from the open6 release's source archive
  rm -rf "$SRC"; mkdir -p "$SRC"
  U=https://github.com/DalsinAI/gfopengcc/releases/download/v16.2.0-open6/gfopenamigagcc-16.2.0-open6-src.tar.xz
  curl -fsSL "$U" | tar -xJ -C "$SRC" --strip-components=4 \
    gfopenamigagcc-16.2.0-open6-src/amiga-gcc/projects/libnix/sources/socket
  echo "libnix sources: open6 source archive"
else
  echo "libnix sources: $LNURL $LNSHA"
fi
mkdir -p "$OUT/obj/new/sources"; cp -R "$SRC/sources/socket" "$OUT/obj/new/sources/"
( cd "$OUT/obj/new" && patch -s -p1 < "$PATCH" )
echo "patch: $(basename "$PATCH")"

# Makefile.gcc6: CFLAGS_FOR_TARGET (scripts/build.sh) + -I headers -fno-builtin
# -ffast-math -D__libnix__, -noixemul for the socket library, + the multilib's flags
BASE="-O2 -fomit-frame-pointer -fno-tree-loop-distribute-patterns -I$HDR -fno-builtin -ffast-math -D__libnix__ -noixemul"
# libnix was built before the toolchain's sys-include wrappers (gfopengcc's
# sys-include/utmp.h includes <sys/utmp.h>, which the stove doesn't have), so
# the target include folder comes first, as it did then
BASE="$BASE -isystem $P/m68k-amigaos/include"
# a stove has the NDK and network headers in its own search path; a bare
# toolchain (the release archive) needs them named: EXTRA_INC="dir dir"
for i in ${EXTRA_INC:-}; do BASE="$BASE -isystem $i"; done
# some stoves (os32-gcc16 on amigachromebuild) keep the network headers that
# their include/sys/socket.h needs (sys/netinclude_types.h) in a folder of
# their own: when <sys/socket.h> does not preprocess, that folder is found in
# the stove and named, as EXTRA_INC would
socket_h() { echo '#include <sys/socket.h>' | "$CC" -E $BASE -x c - >/dev/null 2>&1; }
# shellcheck disable=SC2086
if ! socket_h; then
  for h in $(find "$P" -path '*/sys/netinclude_types.h' 2>/dev/null | sort); do
    i=${h%/sys/netinclude_types.h}; BASE="$BASE -isystem $i"
    # shellcheck disable=SC2086
    if socket_h; then EXTRA_INC="${EXTRA_INC:-} $i"; echo "$i" >> "$OUT/extra-inc"; echo "network headers: $i (found in the stove)"; break; fi
    BASE=${BASE% -isystem $i}
  done
  socket_h || { echo "<sys/socket.h> does not preprocess with this stove; name its network headers with EXTRA_INC" >&2; exit 1; }
fi
n=0
for v in ".:" "libb:-fbaserel" "libm020:-m68020" "libb/libm020:-fbaserel -m68020" "libb32/libm020:-fbaserel32 -m68020"; do
  d=${v%%:*}; f=${v#*:}
  [ -f "$LIB/$d/libsocket.a" ] || { echo "$d: the stove has no libsocket.a, left alone"; continue; }
  if "$AR" t "$LIB/$d/libsocket.a" | grep -qx fcntl.o; then
    echo "$d: the stove's libsocket.a already has fcntl.o (patch 0010), left alone"; n=$((n+1)); continue
  fi
  w="$OUT/obj/$d"; mkdir -p "$w/old" "$w/new" "$w/stove"
  ( cd "$w/stove" && "$AR" x "$LIB/$d/libsocket.a" ioctl.o )
  # shellcheck disable=SC2086
  ( cd "$w/old" && "$CC" -c $BASE $f "$SRC/sources/socket/socket/ioctl.c" -o ioctl.o )
  "$OD" -d "$w/stove/ioctl.o" | tail -n +4 > "$w/a"; "$OD" -d "$w/old/ioctl.o" | tail -n +4 > "$w/b"
  cmp -s "$w/a" "$w/b" || { echo "$d: the unpatched ioctl.c does not rebuild as the stove's ioctl.o; stopping" >&2; diff "$w/a" "$w/b" | head -20 >&2; exit 1; }
  # shellcheck disable=SC2086
  ( cd "$w/new" && "$CC" -c $BASE $f -Wall "$OUT/obj/new/sources/socket/socket/ioctl.c" -o ioctl.o \
      && "$CC" -c $BASE $f -Wall "$OUT/obj/new/sources/socket/socket/fcntl.c" -o fcntl.o )
  mkdir -p "$OUT/lib/$d"; cp "$LIB/$d/libsocket.a" "$OUT/lib/$d/libsocket.a"
  ( cd "$w/new" && "$AR" r "$OUT/lib/$d/libsocket.a" ioctl.o fcntl.o && "$P/bin/m68k-amigaos-ranlib" "$OUT/lib/$d/libsocket.a" )
  "$NM" "$OUT/lib/$d/libsocket.a" | grep -q ' T _fcntl$' || { echo "$d: no _fcntl in the new libsocket.a" >&2; exit 1; }
  o=$("$AR" t "$LIB/$d/libsocket.a" | sort | tr '\n' ' '); nw=$("$AR" t "$OUT/lib/$d/libsocket.a" | grep -vx fcntl.o | sort | tr '\n' ' ')
  [ "$o" = "$nw" ] || { echo "$d: members changed beyond ioctl.o and fcntl.o" >&2; exit 1; }
  echo "$d: stove's ioctl.o rebuilt the same; new libsocket.a $(wc -c < "$OUT/lib/$d/libsocket.a") bytes (was $(wc -c < "$LIB/$d/libsocket.a"))"
  n=$((n+1))
done
[ $n -gt 0 ] || { echo "no libsocket.a in $LIB" >&2; exit 1; }
# a stove from scripts/build.sh's 68040 seed has libm040 folders, and (open7
# on) libm040/libm881 folders, holding copies of their libm020 folders' files
# (libm020/libm881 has no libsocket.a): they get the same new copy
for d in libm040 libb/libm040 libb32/libm040 libm040/libm881 libb/libm040/libm881 libb32/libm040/libm881; do
  s=${d%/libm881}; s=${s%libm040}libm020   # libm881 folders get the libm020 folder's soft files too
  [ -f "$LIB/$d/libsocket.a" ] || continue
  if "$AR" t "$LIB/$d/libsocket.a" | grep -qx fcntl.o; then echo "$d: already has fcntl.o (patch 0010), left alone"; continue; fi
  [ -f "$OUT/lib/$s/libsocket.a" ] && cmp -s "$LIB/$d/libsocket.a" "$LIB/$s/libsocket.a" \
    || { echo "$d: libsocket.a is not a copy of $s's; stopping" >&2; exit 1; }
  mkdir -p "$OUT/lib/$d"; cp "$OUT/lib/$s/libsocket.a" "$OUT/lib/$d/libsocket.a"
  echo "$d: a copy of $s's, as the stove had it"
done
# any libsocket.a in the stove this script doesn't know is a reason to stop
for f in $(cd "$LIB" && find . -name libsocket.a | sed 's|^\./||'); do
  case "$f" in libsocket.a|libb/libsocket.a|libm020/libsocket.a|libb/libm020/libsocket.a|libb32/libm020/libsocket.a|libm040/libsocket.a|libb/libm040/libsocket.a|libb32/libm040/libsocket.a) ;;
    libm040/libm881/libsocket.a|libb/libm040/libm881/libsocket.a|libb32/libm040/libm881/libsocket.a) ;;
    *) echo "$f: a libsocket.a this script doesn't know; stopping" >&2; exit 1 ;; esac
done

# the lab test, against the new library and the stove's (the archive itself:
# the stove's link line searches its own libnix/lib before any -L)
T="$ROOT/tests/libnix/socket_ioctl.c"
CF="-noixemul -m68040 -O2 -fno-delete-null-pointer-checks"
EXTRA_CF=""; for i in ${EXTRA_INC:-}; do EXTRA_CF="$EXTRA_CF -isystem $i"; done
# shellcheck disable=SC2086
MD=$("$CC" $CF -print-multi-directory); NEWLIB="$OUT/lib/$MD/libsocket.a"
[ -f "$NEWLIB" ] || NEWLIB="$LIB/$MD/libsocket.a"   # the stove already has it
echo "test multilib: $MD"
# shellcheck disable=SC2086
"$CC" $CF $EXTRA_CF -o "$OUT/tests/SocketIoctl" "$T" "$NEWLIB"
# shellcheck disable=SC2086
"$CC" $CF $EXTRA_CF -o "$OUT/tests/SocketIoctl-old" "$T" -lsocket
( cd "$OUT" && find tests lib -type f | sort | xargs sha256sum )
