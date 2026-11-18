#!/bin/bash
# tests/release-names-test.sh: tests/release-names.sh passes the names it should
# and refuses the ones it should, the release candidate (rc) input among them.
# No build, no network: it reads this checkout only.
# GPL-3.0-or-later. Copyright (c) 2026 AmiCradle Team.
set -uo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
T=$HERE/tests/release-names.sh
v=$(sed -n 's/^+.*--with-pkgversion="GFOpenAmigaGCC \([^"]*\)".*/\1/p' "$HERE"/patches/amiga-gcc/0002-*-pkgversion.patch)
fails=0
pass() { if out=$("$T" "$@" 2>&1); then echo "ok   passes: ${*:-(no arguments)}"; else echo "FAIL should pass: $* ($out)"; fails=$((fails+1)); fi; }
refuse() { if out=$("$T" "$@" 2>&1); then echo "FAIL should refuse: $* ($out)"; fails=$((fails+1)); else echo "ok   refuses: $* ($out)"; fi; }
pass
pass "" ""
pass "$v"
pass "$v" ""
pass "$v" 1
pass "$v" 12
refuse "$v" 0
refuse "$v" 01
refuse "$v" rc1
refuse "$v" -1
refuse "" 1
refuse 16.2.0-open1
refuse "$v-rc1"
# the rc line says which pre-release it is
"$T" "$v" 3 | grep -qF "pre-release v$v-rc3" || { echo "FAIL rc 3 is not named v$v-rc3"; fails=$((fails+1)); }
[ $fails -eq 0 ] && echo "release-names-test: all passed" || { echo "release-names-test: $fails failed"; exit 1; }
