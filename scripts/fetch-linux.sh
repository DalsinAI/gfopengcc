#!/bin/bash
# fetch-linux.sh WORK [MIRROR]
# Puts the Linux kernel compilers' sources (scripts/linux.lock) in
# WORK/linux: the GCC and binutils tarballs, each checked against its SHA-256.
# With MIRROR (a folder holding the tarballs, such as WORK/aros of an m68k-aros
# fetch), a tarball found there with the right SHA-256 is copied instead.
# GPL-3.0-or-later, like the patches it goes with. Copyright (c) 2026 AmiCradle Team.
set -euo pipefail
WORK=$1; MIRROR=${2:-}
HERE=$(cd "$(dirname "$0")" && pwd)
A=$WORK/linux; mkdir -p "$A"
sha() { sha256sum "$1" | cut -d' ' -f1; }
grep -v '^#' "$HERE/linux.lock" | while read -r name url pin dest; do
  [ -n "$name" ] || continue
  f=$A/$dest
  if [ -f "$f" ] && [ "$(sha "$f")" = "$pin" ]; then echo "$name: already in $f"; continue; fi
  rm -f "$f"
  if [ -n "$MIRROR" ] && [ -f "$MIRROR/$dest" ] && [ "$(sha "$MIRROR/$dest")" = "$pin" ]; then
    cp "$MIRROR/$dest" "$f"
  else
    curl -fsSL --retry 3 -o "$f.part" "$url" && mv "$f.part" "$f"
  fi
  [ "$(sha "$f")" = "$pin" ] || { echo "$name: $f is not the pinned $pin"; rm -f "$f"; exit 1; }
  echo "$name: $dest ($pin)"
done
