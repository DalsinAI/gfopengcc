#!/bin/bash
# install-provenance.sh WORK PREFIX
#
# Verify that every patch used by the AmigaOS build has an exact entry in the
# build stamp, then install the source locks, resolved commits, patches and
# compiler identity beside the toolchain.  This makes a stove or binary
# release independently auditable instead of relying on an old workspace.
set -euo pipefail

WORK=$(cd "$1" && pwd)
PREFIX=$(cd "$2" && pwd)
HERE=$(cd "$(dirname "$0")/.." && pwd)
STAMP=$WORK/.gfopenamigagcc-applied
DEST=$PREFIX/share/gfopenamigagcc/provenance

[ -f "$STAMP" ] || { echo "provenance: missing $STAMP"; exit 1; }

patches=()
for dir in gcc amiga-gcc libnix aros-stuff gfopensdk; do
  while IFS= read -r patch; do patches+=("$patch"); done \
    < <(find "$HERE/patches/$dir" -maxdepth 1 -type f -name '*.patch' | sort)
done
[ ${#patches[@]} -gt 0 ] || { echo "provenance: no build patches found"; exit 1; }

for patch in "${patches[@]}"; do
  id="$(basename "$patch") $(sha256sum < "$patch" | cut -c1-16)"
  grep -qxF "$id" "$STAMP" || {
    echo "provenance: current patch is not recorded as applied: ${patch#"$HERE/"} ($id)"
    exit 1
  }
done

mkdir -p "$DEST/locks" "$DEST/patches"
rsync -a --delete "$HERE/patches/" "$DEST/patches/"
cp "$HERE/scripts/sources.lock" "$HERE/scripts/aros.lock" \
   "$HERE/scripts/ndk.lock" "$DEST/locks/"
cp "$STAMP" "$DEST/applied-patches.txt"

(
  cd "$HERE"
  find patches -type f -name '*.patch' -print0 | sort -z | xargs -0 sha256sum
) > "$DEST/all-patches.sha256"

(
  grep -v '^#' "$HERE/scripts/sources.lock" | while read -r name url commit dir; do
    [ -n "$name" ] || continue
    resolved=$(git -C "$WORK/$dir" rev-parse HEAD)
    printf '%-18s locked=%s resolved=%s source=%s\n' "$name" "$commit" "$resolved" "$url"
  done
) > "$DEST/source-heads.txt"

{
  "$PREFIX/bin/m68k-amigaos-gcc" --version | sed -n '1p'
  "$PREFIX/bin/m68k-amigaos-ld" --version | sed -n '1p'
} > "$DEST/toolchain.txt"

echo "provenance: ${#patches[@]} applied build patches and all source heads preserved in $DEST"
