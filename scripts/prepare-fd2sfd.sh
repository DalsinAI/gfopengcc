#!/bin/bash
# Do not let Git checkout timestamp ordering select an Autoconf version.
set -euo pipefail
SOURCE=${1:?usage: $0 FD2SFD_SOURCE}
( cd "$SOURCE" && autoconf --force )
