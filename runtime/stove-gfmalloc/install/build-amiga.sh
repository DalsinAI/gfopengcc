#!/bin/sh
# Copyright (c) 2026 AmiCradle Team. MIT licence (see LICENSE at the repository root).
# Cradle's way to run install-stove.sh on the machine its builds run on: a
# stove build of this folder puts gfmalloc's size-wrap fix into that machine's
# os32 stoves (checked before and after, put back on any failure).
# Dale's "merge, build and deploy", 10 November 2026.
set -eu
exec nice -n 19 sh "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/../install-stove.sh"
