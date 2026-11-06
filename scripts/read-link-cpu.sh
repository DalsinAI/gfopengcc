#!/bin/bash
# Read one GCC link_cpu spec without closing a producer's pipe early.
set -euo pipefail
CC=${1:?usage: read-link-cpu.sh COMPILER}
"$CC" -dumpspecs | awk '
  $0 == "*link_cpu:" { if (getline <= 0) exit 1; print; found++ }
  END { if (found != 1) exit 1 }
'
