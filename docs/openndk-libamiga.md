# libamiga.a is GFOpenNDK's

GCC's link spec for `m68k-amigaos` always adds `-lamiga`, so every program
links `libamiga.a`: NewList, CreatePort, BeginIO, DoMethod, the varargs stubs
such as OpenWindowTags, SetRexxVar and the rest.

## Before open3

bebbo's amiga-gcc framework keeps a prebuilt `libamiga.a` in its `lib/` and
`lib/libb/` folders, made from Commodore's `amiga.lib`, and its `libamiga`
step copies them into the toolchain. open1 and open2 shipped those two files
in both release tarballs (the toolchain and the source). They are not free
software, and programs built with the toolchain carried their objects.

## From open3

- `build.sh` step 2b removes the two prebuilt files from the work folder
  before amiga-gcc's build runs, so they are never installed.
- Step 5b builds GFOpenNDK's `libamiga.a` (DalsinAI/gfopensdk, pinned in
  `scripts/sources.lock`) with the new compiler once for every multilib
  folder that `-print-multi-lib` lists, each with that multilib's own
  flags: `.` for the 68000, `libm020` with `-mcpu=68020`, `libm060` with
  `-mcpu=68060`, `libm020/libm881` with `-mcpu=68020 -m68881`, `libb` with
  `-fbaserel`, `libb32/libm020` with `-fbaserel32 -mcpu=68020`, and so on.
  GFOpenNDK's `lib/build.sh` starts from `-m68040`, so a multilib that names
  no CPU gets `-m68000` after it (the last CPU flag wins).
- Each old file is removed before the new one is copied, so a stove whose
  `libamiga.a` is a link gets a new file and the link's target is untouched.
- Step 7 checks that every `libamiga.a` in the toolchain has GFOpenNDK's
  `rexxvar.o` (Commodore's has no such member), that each multilib's
  `-print-file-name=libamiga.a` is the file in its own folder, that the
  68000 ones (`.`, `libb`) have no 68020+ instruction or addressing mode,
  and that a NewList program links.

16.2.0-open3 and open4 built GFOpenNDK for the 68040 only and put that build
in every 68000-family folder, so a `-m68000` program calling RangeRand, ArgArrayInit or the
other helpers got 68020 instructions (`mulu.l`, `tst.l An`, scaled
indexes) and crashed on a 68000. From the next release each multilib has
its own.

## Not changed

libnix and the target libraries are still compiled against the NDK 3.2
headers you supply (`NDK3.2.lha`). No NDK file is installed in the release
tarball, and none is linked into a program by default.
