#!/bin/bash
# fetch-userland.sh WORK [MIRROR]
# Puts the Linux userland compilers' sources (scripts/userland.lock) in
# WORK/userland: GCC, binutils, glibc and the Linux headers, each checked against its SHA-256.
# With MIRROR (a folder holding the tarballs, such as WORK/aros of an m68k-aros
# fetch), a tarball found there with the right SHA-256 is copied instead.
# Each tarball is tried at the lock's URL and then at its mirrors (urls_for):
# ftp.gnu.org at mirrors.kernel.org/gnu and ftpmirror.gnu.org, archive.ubuntu.com
# at mirrors.edge.kernel.org/ubuntu; curl retries cut transfers too. The SHA-256
# decides, whichever mirror answered. URLS_ONLY=1 prints each name's URLs, fetches nothing.
# GPL-3.0-or-later, like the patches it goes with. Copyright (c) 2026 AmiCradle Team.
set -euo pipefail
WORK=${1:-}; MIRROR=${2:-}
HERE=$(cd "$(dirname "$0")" && pwd)
sha() { sha256sum "$1" | cut -d' ' -f1; }
urls_for() {
  echo "$1"
  case $1 in
    https://ftp.gnu.org/gnu/*) echo "https://mirrors.kernel.org/gnu/${1#https://ftp.gnu.org/gnu/}"
                               echo "https://ftpmirror.gnu.org/gnu/${1#https://ftp.gnu.org/gnu/}" ;;
    http://archive.ubuntu.com/ubuntu/*) echo "https://mirrors.edge.kernel.org/ubuntu/${1#http://archive.ubuntu.com/ubuntu/}" ;;
  esac
}
if [ "${URLS_ONLY:-}" = 1 ]; then
  grep -v '^#' "${LOCK:-$HERE/userland.lock}" | while read -r name url pin dest; do
    [ -n "$name" ] || continue
    for u in $(urls_for "$url"); do echo "$name $u"; done
  done
  exit 0
fi
[ -n "$WORK" ] || { echo "usage: fetch-userland.sh WORK [MIRROR]"; exit 1; }
A=$WORK/userland; mkdir -p "$A"
grep -v '^#' "${LOCK:-$HERE/userland.lock}" | while read -r name url pin dest; do
  [ -n "$name" ] || continue
  f=$A/$dest
  if [ -f "$f" ] && [ "$(sha "$f")" = "$pin" ]; then echo "$name: already in $f"; continue; fi
  rm -f "$f"
  if [ -n "$MIRROR" ] && [ -f "$MIRROR/$dest" ] && [ "$(sha "$MIRROR/$dest")" = "$pin" ]; then
    cp "$MIRROR/$dest" "$f"
  else
    for u in $(urls_for "$url"); do
      rm -f "$f.part"
      if curl -fsSL --connect-timeout 30 --retry 3 --retry-all-errors -o "$f.part" "$u" && [ "$(sha "$f.part")" = "$pin" ]; then
        mv "$f.part" "$f"; break
      fi
      echo "$name: not from $u, trying the next"
    done
    rm -f "$f.part"
  fi
  [ -f "$f" ] || { echo "$name: no URL gave the pinned $pin"; exit 1; }
  [ "$(sha "$f")" = "$pin" ] || { echo "$name: $f is not the pinned $pin"; rm -f "$f"; exit 1; }
  echo "$name: $dest ($pin)"
done
