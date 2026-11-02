#!/bin/bash
# tests/release-names.sh [VERSION]
# The release's names agree, before hours of building: the identity
# patches/amiga-gcc/0002-*-pkgversion.patch builds into GCC (--version's
# "(GFOpenAmigaGCC 16.2.0-openN)") is the one scripts/build.sh checks for, its
# file name names the same openN, and scripts/package.sh and the build workflow
# name the tarballs gfopenamigagcc-VERSION-*. With VERSION (the workflow's
# release input), that is the identity's version and docs/releases/VERSION.md
# exists. Open1 to open4 were "OpenAmigaGCC" and openamigagcc-*.tar.xz; those
# releases stay as they were published.
# GPL-3.0-or-later. Copyright (c) 2026 AmiCradle Team.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
fail() { echo "release names: $*"; exit 1; }
shopt -s nullglob
patches=("$HERE"/patches/amiga-gcc/0002-*-pkgversion.patch)
[ ${#patches[@]} -eq 1 ] || fail "want one patches/amiga-gcc/0002-*-pkgversion.patch, found ${#patches[@]}"
p=${patches[0]}
pkg=$(sed -n 's/^+.*--with-pkgversion="\([^"]*\)".*/\1/p' "$p")
[ -n "$pkg" ] || fail "$(basename "$p") sets no --with-pkgversion"
[[ $pkg =~ ^GFOpenAmigaGCC\ ([0-9]+\.[0-9]+\.[0-9]+-open([0-9]+))$ ]] || fail "pkgversion \"$pkg\" is not \"GFOpenAmigaGCC <gcc version>-open<N>\""
v=${BASH_REMATCH[1]}; n=${BASH_REMATCH[2]}
[ "$(basename "$p")" = "0002-open$n-pkgversion.patch" ] || fail "$(basename "$p") names another release than $v"
grep -qxF "ID=\"$pkg\"" "$HERE/scripts/build.sh" || fail "scripts/build.sh does not check for ($pkg)"
grep -qF 'BIN=gfopenamigagcc-$V-x86_64-linux; SRC=gfopenamigagcc-$V-src' "$HERE/scripts/package.sh" || fail "scripts/package.sh does not name the tarballs gfopenamigagcc-*"
for f in 'gfopenamigagcc-$V-x86_64-linux.tar.xz' 'gfopenamigagcc-$V-src.tar.xz'; do
  grep -qF "\$RUNNER_TEMP/out/$f" "$HERE/.github/workflows/build.yml" || fail "the build workflow does not publish $f"
done
if [ $# -gt 0 ] && [ -n "$1" ]; then
  [ "$1" = "$v" ] || fail "the release asked for is $1, but the compiler identifies itself as $pkg"
  [ -f "$HERE/docs/releases/$1.md" ] || fail "docs/releases/$1.md is missing"
fi
echo "release names: $pkg, gfopenamigagcc-$v-x86_64-linux.tar.xz and gfopenamigagcc-$v-src.tar.xz"
