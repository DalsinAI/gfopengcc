#!/bin/sh
# For the kitchen's stove_build (target tests/selfcalls): check.sh on the
# stove the build runs with (STOVE). On open9 and before it fails, which is
# the bug gcc patch 0020 fixes. MIT. Copyright (c) 2026 AmiCradle Team.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec sh "$HERE/test_selfcalls.sh" "${STOVE:?STOVE names the stove}"
