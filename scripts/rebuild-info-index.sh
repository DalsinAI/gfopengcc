#!/bin/bash
# Parallel upstream install-info calls can overwrite each other's entries.
# Rebuild once, serially, from every installed manual after installation.
set -euo pipefail
export LC_ALL=C
INFO=${1:?usage: $0 PREFIX/share/info}
[ -d "$INFO" ] || { echo "missing Info directory: $INFO"; exit 1; }
INDEX=$(mktemp "$INFO/.dir.XXXXXX")
trap 'rm -f "$INDEX"' EXIT
rm -f "$INDEX"
count=0
for manual in "$INFO"/*.info; do
  [ -f "$manual" ] || continue
  install-info --info-file="$manual" --dir-file="$INDEX"
  count=$((count + 1))
done
[ "$count" -gt 0 ] && [ -s "$INDEX" ] || { echo "no Info manuals indexed"; exit 1; }
chmod 644 "$INDEX"
mv "$INDEX" "$INFO/dir"
echo "Info index: $count manuals installed serially"
