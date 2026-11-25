#!/bin/sh
# The kitchen's entry for tests/selfcalls: check_selfcalls.py's own test, then
# check.sh on the stove it runs with (STOVE, or PREFIX as the first argument).
# On a stove without gcc patch 0020 (open9 and before) check.sh fails: that is
# the bug it is there to find. MIT. Copyright (c) 2026 AmiCradle Team.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PREFIX=${1:-${STOVE:-}}
[ -x "$PREFIX/prefix/bin/m68k-amigaos-g++" ] && PREFIX=$PREFIX/prefix
if [ ! -x "$PREFIX/bin/m68k-amigaos-g++" ]; then
  python3 "$HERE/test_check_selfcalls.py"
  echo "selfcalls: no stove (STOVE or PREFIX), so only check_selfcalls.py's own test ran"
  exit 0
fi
sh "$HERE/check.sh" "$PREFIX"
