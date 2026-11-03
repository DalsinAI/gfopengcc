#!/bin/bash
# fetch-aros.sh WORK [MIRROR]
# Puts the m68k-aros target's sources (scripts/aros.lock) in WORK/aros: the GCC,
# binutils and isl tarballs, each checked against its SHA-256, and AROS's
# tools/collect-aros and tools/crosstools/gnu at the pinned commit (a partial
# clone: only those two folders are checked out).
# With MIRROR (a folder holding the tarballs, such as an AROS ports folder), a
# tarball found there with the right SHA-256 is copied instead of downloaded.
# AROS_MIRROR (optional) is a local AROS clone to take the commit from.
# GPL-3.0-or-later, like the patches it goes with. Copyright (c) 2026 AmiCradle Team.
set -euo pipefail
WORK=$1; MIRROR=${2:-}
HERE=$(cd "$(dirname "$0")" && pwd)
A=$WORK/aros; mkdir -p "$A"
sha() { sha256sum "$1" | cut -d' ' -f1; }
grep -v '^#' "$HERE/aros.lock" | while read -r name url pin dest; do
  [ -n "$name" ] || continue
  case $url in
    *.git)
      d=$A/$dest
      if [ ! -d "$d/.git" ]; then
        rm -rf "$d"; git init -q "$d"
        git -C "$d" remote add origin "${AROS_MIRROR:-$url}"
        git -C "$d" config remote.origin.promisor true
        git -C "$d" config remote.origin.partialclonefilter blob:none
        git -C "$d" sparse-checkout set --no-cone /tools/collect-aros/ /tools/crosstools/gnu/ /LICENSE /ACKNOWLEDGEMENTS
      fi
      git -C "$d" cat-file -e "$pin^{commit}" 2>/dev/null || git -C "$d" fetch -q --depth 1 --filter=blob:none origin "$pin"
      git -C "$d" -c advice.detachedHead=false checkout -q "$pin"
      echo "$name: $(git -C "$d" rev-parse --short HEAD) (tools/collect-aros, tools/crosstools/gnu)" ;;
    *)
      f=$A/$dest
      if [ -f "$f" ] && [ "$(sha "$f")" = "$pin" ]; then echo "$name: already in $f"; continue; fi
      rm -f "$f"
      if [ -n "$MIRROR" ] && [ -f "$MIRROR/$dest" ] && [ "$(sha "$MIRROR/$dest")" = "$pin" ]; then
        cp "$MIRROR/$dest" "$f"
      else
        curl -fsSL --retry 3 -o "$f.part" "$url" && mv "$f.part" "$f"
      fi
      [ "$(sha "$f")" = "$pin" ] || { echo "$name: $f is not the pinned $pin"; rm -f "$f"; exit 1; }
      echo "$name: $dest ($pin)" ;;
  esac
done
