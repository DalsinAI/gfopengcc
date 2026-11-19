#!/bin/bash
# tests/fetch-userland-test.sh
# scripts/fetch-userland.sh falls back to a mirror when the lock's host fails, and
# keeps only a tarball with the pinned SHA-256. No network: curl is a stand-in
# that fails for some hosts and serves a file for others.
# GPL-3.0-or-later. Copyright (c) 2026 AmiCradle Team.
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
F=$HERE/scripts/fetch-userland.sh
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail() { echo "fetch-userland: $*"; exit 1; }

# 1. Every name in the real lock has its own URL first, then its mirrors.
U=$(URLS_ONLY=1 "$F")
echo "$U" | grep -qx 'gcc https://ftp.gnu.org/gnu/gcc/gcc-16.2.0/gcc-16.2.0.tar.xz' || fail "gcc's own URL is not first"
echo "$U" | grep -qx 'gcc https://mirrors.kernel.org/gnu/gcc/gcc-16.2.0/gcc-16.2.0.tar.xz' || fail "no kernel.org mirror for gcc"
echo "$U" | grep -qx 'glibc https://ftpmirror.gnu.org/gnu/glibc/glibc-2.35.tar.xz' || fail "no ftpmirror for glibc"
echo "$U" | grep -qx 'linux https://mirrors.edge.kernel.org/ubuntu/pool/main/l/linux/linux_5.15.0.orig.tar.gz' || fail "no Ubuntu mirror for linux"
[ "$(echo "$U" | grep -c '^zlib ')" -eq 1 ] || fail "zlib (GitHub) should have no mirror"
[ "$(echo "$U" | awk '$1=="gcc"' | head -1 | cut -d' ' -f2)" = https://ftp.gnu.org/gnu/gcc/gcc-16.2.0/gcc-16.2.0.tar.xz ] || fail "lock URL not tried first"

# A stand-in curl: fails for hosts in $T/down, writes "bad" for hosts in $T/bad, else "good".
mkdir -p "$T/bin"
cat > "$T/bin/curl" <<'C'
#!/bin/bash
out=""; url=""
while [ $# -gt 0 ]; do case $1 in -o) out=$2; shift 2 ;; -*) [ "$1" = --connect-timeout ] || [ "$1" = --retry ] && shift; shift ;; *) url=$1; shift ;; esac; done
echo "$url" >> "$STUB_LOG"
host=${url#*://}; host=${host%%/*}
grep -qx "$host" "$STUB_DOWN" 2>/dev/null && exit 28
if grep -qx "$host" "$STUB_BAD" 2>/dev/null; then echo bad > "$out"; else echo good > "$out"; fi
C
chmod +x "$T/bin/curl"
GOOD=$(echo good | sha256sum | cut -d' ' -f1)
printf 'gcc https://ftp.gnu.org/gnu/gcc/x.tar.xz %s x.tar.xz\nlinux http://archive.ubuntu.com/ubuntu/pool/l/y.tar.gz %s y.tar.gz\n' "$GOOD" "$GOOD" > "$T/lock"
run() { rm -rf "$T/w"; : > "$T/log"; PATH="$T/bin:$PATH" LOCK="$T/lock" STUB_LOG="$T/log" STUB_DOWN="$T/down" STUB_BAD="$T/bad" "$F" "$T/w" > "$T/out" 2>&1; }

# 2. Lock hosts down: the mirrors give the files.
printf 'ftp.gnu.org\narchive.ubuntu.com\n' > "$T/down"; : > "$T/bad"
run || { cat "$T/out"; fail "did not fall back to a mirror"; }
[ -f "$T/w/userland/x.tar.xz" ] && [ -f "$T/w/userland/y.tar.gz" ] || fail "files missing after fallback"
grep -qx 'https://mirrors.kernel.org/gnu/gcc/x.tar.xz' "$T/log" || fail "kernel.org GNU mirror not tried"
grep -qx 'https://mirrors.edge.kernel.org/ubuntu/pool/l/y.tar.gz' "$T/log" || fail "Ubuntu mirror not tried"

# 3. Lock host up: no mirror is asked.
: > "$T/down"; run || fail "plain fetch failed"
[ "$(wc -l < "$T/log")" -eq 2 ] || fail "asked a mirror when the lock's host answered"

# 4. A mirror with the wrong file is passed over for the next.
echo ftp.gnu.org > "$T/down"; echo mirrors.kernel.org > "$T/bad"
run || { cat "$T/out"; fail "did not pass over a wrong file"; }
grep -qx 'https://ftpmirror.gnu.org/gnu/gcc/x.tar.xz' "$T/log" || fail "ftpmirror not tried after a wrong file"
[ "$(sha256sum < "$T/w/userland/x.tar.xz" | cut -d' ' -f1)" = "$GOOD" ] || fail "kept the wrong file"

# 5. Every host down or wrong: refused, nothing kept.
printf 'ftp.gnu.org\nftpmirror.gnu.org\n' > "$T/down"
if run; then fail "accepted when no URL had the pinned file"; fi
[ ! -e "$T/w/userland/x.tar.xz" ] && [ ! -e "$T/w/userland/x.tar.xz.part" ] || fail "left a file behind"
grep -q 'no URL gave the pinned' "$T/out" || fail "no clear message"

echo "fetch-userland: 5 cases (mirror URLs, fallback, no needless mirror, wrong file passed over, refusal)"
