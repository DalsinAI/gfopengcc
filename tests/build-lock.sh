#!/bin/bash
# A second build must stop before changing a shared work folder.
set -euo pipefail

HERE=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/gfopenamigagcc-lock.XXXXXX")
LOCK=$WORK/.gfopenamigagcc-build.lock

( flock 8; sleep 3 ) 8>"$LOCK" &
holder=$!
sleep 1

set +e
output=$("$HERE/scripts/build.sh" "$WORK" "$WORK/prefix" /dev/null 1 2>&1)
rc=$?
set -e
wait "$holder"

[ "$rc" -ne 0 ] || { echo "a second build entered the locked work folder"; exit 1; }
case $output in
  *"another GFOpenAmigaGCC build is using $WORK"*) ;;
  *) echo "unexpected lock diagnostic: $output"; exit 1 ;;
esac
[ ! -e "$WORK/prefix" ] || { echo "the rejected build changed its prefix"; exit 1; }
echo "build lock: a concurrent invocation stopped before changing output"
