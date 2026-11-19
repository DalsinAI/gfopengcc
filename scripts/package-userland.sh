#!/bin/bash
# package-userland.sh WORK PREFIX OUT VERSION ARCH
# Makes the ARCH-linux-gnu userland release (glibc 2.35 sysroot) from a finished build-userland.sh run (ARCH x86_64 or aarch64):
#   OUT/gfopenamigagcc-VERSION-ARCH-linux-gnu-glibc2.35-x86_64-linux.tar.xz  the toolchain (PREFIX, with its sysroot)
#   OUT/gfopenamigagcc-VERSION-ARCH-linux-gnu-glibc2.35-src.tar     the GNU and Linux tarballs it was
#       built from, as they are (scripts/userland.lock), and this repository (its patches and scripts)
#   OUT/SHA256SUMS-ARCH-glibc
# GPL-3.0-or-later. Copyright (c) 2026 AmiCradle Team.
set -euo pipefail
umask 022
WORK=$(cd "$1" && pwd); PREFIX=$(cd "$2" && pwd); mkdir -p "$3"; OUT=$(cd "$3" && pwd); V=$4; ARCH=$5
HERE=$(cd "$(dirname "$0")/.." && pwd)
BIN=gfopenamigagcc-$V-$ARCH-linux-gnu-glibc2.35-x86_64-linux; SRC=gfopenamigagcc-$V-$ARCH-linux-gnu-glibc2.35-src
"$PREFIX/bin/$ARCH-linux-gnu-gcc" --version | sed -n 1p | grep -qF "GFOpenAmigaGCC $V)" \
  || { echo "the toolchain in $PREFIX is not $V"; exit 1; }
S=$(mktemp -d "$OUT/.stage.XXXXXX"); trap 'rm -rf "$S"' EXIT
mkdir -p "$S/$BIN" "$S/$SRC/gfopengcc"
rsync -a --no-group "$PREFIX/" "$S/$BIN/"
grep -v '^#' "$HERE/scripts/userland.lock" | while read -r name url pin dest; do
  [ -n "$name" ] || continue
  cp "$WORK/userland/$dest" "$S/$SRC/$dest"
  ( cd "$S/$SRC" && echo "$pin  $dest" | sha256sum -c --quiet ) || { echo "$dest is not the pinned $pin"; exit 1; }
done
rsync -a --no-group --exclude '.git' --exclude '__pycache__' "$HERE/" "$S/$SRC/gfopengcc/"
( cd "$S" && tar --mode=u+rwX,go+rX,go-w --owner=0 --group=0 -cJf "$OUT/$BIN.tar.xz" "$BIN" \
    && tar --mode=u+rwX,go+rX,go-w --owner=0 --group=0 -cf "$OUT/$SRC.tar" "$SRC" )
( cd "$OUT" && sha256sum "$BIN.tar.xz" "$SRC.tar" > SHA256SUMS-$ARCH-glibc && cat SHA256SUMS-$ARCH-glibc )
