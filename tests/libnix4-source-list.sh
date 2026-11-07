#!/bin/bash
# Keep libnix4's normal and FULL_SPECIFIERS printf helpers disjoint.
set -euo pipefail

HERE=$(cd "$(dirname "$0")/.." && pwd)
PATCH=$HERE/patches/libnix/0009-libnix4-exclude-the-non-FULL-vfwprintf-helper.patch

grep -Fq -- '-not -name __vfwprintf_total_size.o' "$PATCH" || {
  echo 'libnix4 source list: ordinary __vfwprintf_total_size.o is not excluded'; exit 1;
}
if grep -Fq -- '+  -not -name __vwfprintf_total_size.o' "$PATCH"; then
  echo 'libnix4 source list: misspelled wide helper exclusion remains'; exit 1;
fi
grep -Fq -- 'FULL_SPECIFIERS implementation' "$PATCH" || {
  echo 'libnix4 source list: patch does not document the retained FULL_SPECIFIERS helper'; exit 1;
}

echo 'libnix4 source list: normal helper excluded; FULL_SPECIFIERS helper retained'
