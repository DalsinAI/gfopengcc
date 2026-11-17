#!/bin/sh
# Host test for scripts/libstdcxx-c99-stdlib.sh: a stand-in PREFIX with two
# c++config.h files and a stand-in g++. With a g++ that compiles, both
# macros are turned on in both files and nothing else changes; with one that
# fails, both files are byte for byte as before. Also runs stoll.cpp with the
# host's g++, so the test's own values are right.
#   sh tests/cxx/c99-stdlib-check.sh
# MIT. Copyright (c) 2026 AmiCradle Team.
set -u
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
S=$HERE/../../scripts/libstdcxx-c99-stdlib.sh
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0 checks=0
ok() { checks=$((checks + 1)); if ! eval "$1"; then echo "FAIL: $2"; fails=$((fails + 1)); fi; }
mk() {
  rm -rf "$T/p"
  for m in . m68040; do
    d=$T/p/lib/gcc/m68k-amigaos/16.2.0/include/c++/m68k-amigaos/$m/bits
    mkdir -p "$d"
    printf '/* #undef _GLIBCXX11_USE_C99_STDLIB */\n/* #undef _GLIBCXX98_USE_C99_STDLIB */\n/* #undef _GLIBCXX_USE_C99_FENV */\n#define _GLIBCXX_HAVE_STRTOLD 1\n' > "$d/c++config.h"
  done
  find "$T/p" -name c++config.h | sort | xargs cat > "$T/before"
}
mkdir -p "$T/bin"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/good"; printf '#!/bin/sh\necho "cstdlib: no _Exit" >&2; exit 1\n' > "$T/bin/badcc"
chmod +x "$T/bin/good" "$T/bin/badcc"

mk; out=$(CXX=$T/bin/good sh "$S" "$T/p")
ok '[ $? -eq 0 ]' "script failed with a good g++"
ok 'echo "$out" | grep -q "C99 stdlib on"' "did not say it is on: $out"
for f in $(find "$T/p" -name c++config.h); do
  ok 'grep -q "^#define _GLIBCXX11_USE_C99_STDLIB 1" "$f"' "$f: C++11 macro not on"
  ok 'grep -q "^#define _GLIBCXX98_USE_C99_STDLIB 1" "$f"' "$f: C++98 macro not on"
  ok 'grep -q "^/\* #undef _GLIBCXX_USE_C99_FENV \*/" "$f"' "$f: another macro changed"
  ok '[ ! -e "$f.c99-orig" ]' "$f: backup left behind"
done
on=$(find "$T/p" -name c++config.h | sort | xargs cat)
CXX=$T/bin/good sh "$S" "$T/p" > /dev/null
ok '[ "$(find "$T/p" -name c++config.h | sort | xargs cat)" = "$on" ]' "second run changed the files"

mk; out=$(CXX=$T/bin/badcc LOG=$T/log sh "$S" "$T/p")
ok 'echo "$out" | grep -q "left off"' "did not say it is left off: $out"
ok '[ "$(find "$T/p" -name c++config.h | sort | xargs cat)" = "$(cat "$T/before")" ]' "files not put back"
ok '[ -z "$(find "$T/p" -name "*.c99-orig")" ]' "backup left behind after a failure"
ok 'grep -q "no _Exit" "$T/log"' "the compiler's error is not in the log"
ok '! sh "$S" "$T/nowhere" > /dev/null 2>&1' "took a PREFIX with no c++config.h"

if command -v g++ > /dev/null; then
  g++ -std=gnu++11 -O2 -o "$T/stoll" "$HERE/stoll.cpp" && "$T/stoll"
  ok '[ $? -eq 0 ]' "stoll.cpp fails on the host"
fi
[ $fails -eq 0 ] && echo "libstdcxx-c99-stdlib.sh: all $checks checks passed"
exit $((fails != 0))
