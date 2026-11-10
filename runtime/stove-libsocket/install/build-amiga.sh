#!/bin/sh
# Copyright (c) 2026 AmiCradle Team. MIT licence (see LICENSE at the repository root).
# Cradle's way to run install-stove.sh on the machine its builds run on: a
# stove build of this folder puts libnix patch 0010 into that machine's
# os32-gcc16-open6 stove (checked before and after, put back on any failure).
# Dale's decision, 10 November 2026: "refresh the open6 stove now".
set -eu
exec nice -n 19 sh "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/../install-stove.sh"
