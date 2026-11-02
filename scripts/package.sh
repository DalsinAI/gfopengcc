#!/bin/bash
# package.sh WORK PREFIX OUT VERSION
# Makes a release from a finished build.sh run: OUT/openamigagcc-VERSION-x86_64-linux.tar.xz
# (PREFIX without the NDK you supplied), OUT/openamigagcc-VERSION-src.tar.xz (amiga-gcc's
# framework and its modules as built, with this repository) and OUT/SHA256SUMS.
# It stops if either tarball would carry an NDK folder, an amiga.lib or a libamiga.a that is not
# GFOpenNDK's (docs/openndk-libamiga.md).
# GPL-3.0-or-later. Copyright (c) 2026 AmiCradle Team.
set -euo pipefail
WORK=$(cd "$1" && pwd); PREFIX=$(cd "$2" && pwd); mkdir -p "$3"; OUT=$(cd "$3" && pwd); V=$4
HERE=$(cd "$(dirname "$0")/.." && pwd)
BIN=openamigagcc-$V-x86_64-linux; SRC=openamigagcc-$V-src
S=$(mktemp -d "$OUT/.stage.XXXXXX"); trap 'rm -rf "$S"' EXIT

# The toolchain, without the NDK (m68k-amigaos/ndk, ndk-include, ndk13-include).
mkdir -p "$S/$BIN"
rsync -a --no-group --exclude '/m68k-amigaos/ndk/' --exclude '/m68k-amigaos/ndk-include/' \
  --exclude '/m68k-amigaos/ndk13-include/' --exclude '/m68k-amigaos/ndk-include.vendor/' "$PREFIX/" "$S/$BIN/"

# The source: amiga-gcc and its modules as built (patches applied), and this repository.
mkdir -p "$S/$SRC/amiga-gcc" "$S/$SRC/gfopengcc"
rsync -a --no-group --exclude '.git' --exclude '/build-*/' --exclude '/download/' --exclude '/log/' \
  --exclude '/openamigagcc-logs/' --exclude '/projects/NDK3.2*' --exclude '/projects/gfopensdk/OpenNDK/lib/build/' \
  "$WORK/" "$S/$SRC/amiga-gcc/"
rsync -a --no-group --exclude '.git' --exclude '__pycache__' "$HERE/" "$S/$SRC/gfopengcc/"

# Nothing of the NDK, and every libamiga.a GFOpenNDK's.
bad=$(cd "$S" && find . \( -path '*/projects/NDK3.2*' -o -name 'NDK3.2.lha' -o -iname 'amiga.lib' -o -name 'ndk-include' -o -name 'ndk13-include' \) -print | head -5)
[ -z "$bad" ] || { echo "NDK files in the release: $bad"; exit 1; }
n=0
while IFS= read -r a; do
  "$PREFIX/bin/m68k-amigaos-ar" t "$a" | grep -qx rexxvar.o || { echo "${a#"$S"/} is not GFOpenNDK's libamiga.a"; exit 1; }
  n=$((n+1))
done < <(find "$S" -name 'libamiga.a')
echo "libamiga.a: $n in the release, all GFOpenNDK's"

( cd "$S" && tar --owner=0 --group=0 -cJf "$OUT/$BIN.tar.xz" "$BIN" && tar --owner=0 --group=0 -cJf "$OUT/$SRC.tar.xz" "$SRC" )
( cd "$OUT" && sha256sum "$BIN.tar.xz" "$SRC.tar.xz" > SHA256SUMS && cat SHA256SUMS )
