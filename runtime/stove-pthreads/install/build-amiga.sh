#!/bin/sh
# Copyright (c) 2026 AmiCradle Team. MIT licence (see LICENSE at the repository root).
# Cradle's way to run install-stove.sh on the machine its builds run on: a
# stove build of this folder puts aros-stuff patch 0010 (pthreads' exit) into
# that machine's os32-gcc16-open6 stove (checked before and after, put back
# on any failure). Task 44, 10 November 2026: "a stove refresh by the #45/#46
# method".
set -eu
exec nice -n 19 sh "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/../install-stove.sh"
