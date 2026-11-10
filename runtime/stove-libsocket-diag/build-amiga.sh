#!/bin/sh
# diagnostic only (never merge): where a plain -lsocket link finds libsocket.a
set -u
P="$STOVE/prefix"; CC="$P/bin/m68k-amigaos-gcc"
for cf in "-noixemul -m68040" "-noixemul" "-noixemul -m68020"; do
  echo "== $cf: multidir $($CC $cf -print-multi-directory) libsocket $($CC $cf -print-file-name=libsocket.a)"
done
find "$P" -name 'libsocket.a*' | sort | while read f; do echo "$(sha256sum < "$f" | cut -c1-16) $(wc -c < "$f") $f"; done
echo 'int main(void){return 0;}' > /tmp/d$$.c
$CC -noixemul -m68040 -O2 -Wl,--verbose -o /tmp/d$$ /tmp/d$$.c -lsocket 2>&1 | grep -i "libsocket\|SEARCH_DIR" | head -20
$CC -noixemul -m68040 -v -o /tmp/d$$ /tmp/d$$.c -lsocket 2>&1 | grep -E "collect2|ld " | head -3
rm -f /tmp/d$$ /tmp/d$$.c
mkdir -p "${OUT:-.}"; echo ok > "${OUT:-.}/diag.txt"
