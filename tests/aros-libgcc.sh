#!/bin/bash
# aros-libgcc.sh PREFIX
#
# Check that every m68k-aros multilib selects its own libgcc and that the
# integer helpers needed by C++ and generated code are present.  Open6's
# release notes recorded an unresolved __divsi3 at -m68040; the installed
# Open6 and archived predecessor do not reproduce it, so keep the exact
# condition as a build gate instead of relying on that historical report.
set -euo pipefail

PREFIX=$(cd "${1:?usage: $0 PREFIX}" && pwd)
CC=$PREFIX/m68k-aros-gcc
NM=$PREFIX/m68k-aros-nm
[ -x "$CC" ] || { echo "AROS libgcc: no compiler: $CC"; exit 2; }
[ -x "$NM" ] || { echo "AROS libgcc: no nm: $NM"; exit 2; }

helpers=(__divsi3 __modsi3 __mulsi3 __udivsi3 __umodsi3)
seen=0
while IFS=';' read -r dir options; do
  flags=${options//@/ -}
  # Intentional word splitting: -print-multi-lib encodes a list of switches.
  # shellcheck disable=SC2086
  libgcc=$($CC $flags -print-libgcc-file-name)
  [ -f "$libgcc" ] || { echo "AROS libgcc: '$dir' selects missing $libgcc"; exit 1; }
  case $dir in
    .) ;;
    *) case $libgcc in */"$dir"/libgcc.a) ;; *)
         echo "AROS libgcc: '$dir' selects another multilib: $libgcc"; exit 1 ;;
       esac ;;
  esac
  symbols=$($NM -g --defined-only "$libgcc")
  for helper in "${helpers[@]}"; do
    grep -Eq "[[:space:]]T[[:space:]]+$helper$" <<< "$symbols" || {
      echo "AROS libgcc: '$dir' has no $helper in $libgcc"; exit 1;
    }
  done
  echo "AROS libgcc: '$dir' right (${helpers[*]})"
  seen=$((seen + 1))
done < <("$CC" -print-multi-lib)

[ "$seen" -gt 0 ] || { echo "AROS libgcc: compiler reported no multilibs"; exit 1; }
echo "AROS libgcc: $seen multilibs checked"
