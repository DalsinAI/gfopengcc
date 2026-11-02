# Base-relative C++: findings (daletop, 12 October 2026)

Stove: gfopengcc main f9efa3d full build (~/stoves-work/stove-gcc16-pth), compat from the installed os32-gcc16 stove. Labs: a lab copy of Instance-32 (AmigaOS 3.2.3, AC090 68040), clean start for each run.

## A. Multilibs

```
$ m68k-amigaos-g++ -m68020 -m68881  -print-multi-directory
libm020/libm881
  libstdc++.a: 4344124 bytes  lib/gcc/m68k-amigaos/16.2.0b/libm020/libm881/libstdc++.a
  libsupc++.a: 183952 bytes  lib/gcc/m68k-amigaos/16.2.0b/libm020/libm881/libsupc++.a
  libpthread.a: 18652 bytes  lib/gcc/m68k-amigaos/16.2.0b/../../../../m68k-amigaos/lib/libpthread.a
  libatomic.a: 13684 bytes  lib/gcc/m68k-amigaos/16.2.0b/libm020/libm881/libatomic.a
  libgcc.a: 539828 bytes  lib/gcc/m68k-amigaos/16.2.0b/libm020/libm881/libgcc.a
  libnix.a: 76392 bytes  m68k-amigaos/libnix/lib/libnix.a

$ m68k-amigaos-g++ -m68020 -m68881 -fbaserel32 -print-multi-directory
libb32/libm020/libm881
  libstdc++.a: 4406080 bytes  lib/gcc/m68k-amigaos/16.2.0b/libb32/libm020/libm881/libstdc++.a
  libsupc++.a: 184360 bytes  lib/gcc/m68k-amigaos/16.2.0b/libb32/libm020/libm881/libsupc++.a
  libpthread.a: 18652 bytes  lib/gcc/m68k-amigaos/16.2.0b/../../../../m68k-amigaos/lib/libpthread.a
  libatomic.a: 13688 bytes  lib/gcc/m68k-amigaos/16.2.0b/libb32/libm020/libm881/libatomic.a
  libgcc.a: 537924 bytes  lib/gcc/m68k-amigaos/16.2.0b/libb32/libm020/libm881/libgcc.a
  libnix.a: 76392 bytes  m68k-amigaos/libnix/lib/libnix.a

$ m68k-amigaos-g++ -m68020 -m68881 -fbaserel -print-multi-directory
libb/libm020/libm881
  libstdc++.a: 4396696 bytes  lib/gcc/m68k-amigaos/16.2.0b/libb/libm020/libm881/libstdc++.a
  libsupc++.a: 184032 bytes  lib/gcc/m68k-amigaos/16.2.0b/libb/libm020/libm881/libsupc++.a
  libpthread.a: 18652 bytes  lib/gcc/m68k-amigaos/16.2.0b/../../../../m68k-amigaos/lib/libpthread.a
  libatomic.a: 13680 bytes  lib/gcc/m68k-amigaos/16.2.0b/libb/libm020/libm881/libatomic.a
  libgcc.a: 537028 bytes  lib/gcc/m68k-amigaos/16.2.0b/libb/libm020/libm881/libgcc.a
  libnix.a: 76392 bytes  m68k-amigaos/libnix/lib/libnix.a

```
Which copies the links open (`-Wl,--verbose`, the libraries named above plus os32compat):

$ g++ -fbaserel32 ... -Wl,--verbose | grep 'attempt to open|succeeded' (libstdc++, libsupc++, libpthread, libatomic, libgcc, libnix, os32compat)
```
attempt to open ~/stoves-work/stove-pth-root/compat/libos32compat.a succeeded
attempt to open lib/gcc/m68k-amigaos/16.2.0b/libb32/libm020/libm881/libatomic.a succeeded
attempt to open lib/gcc/m68k-amigaos/16.2.0b/libb32/libm020/libm881/libgcc.a succeeded
attempt to open lib/gcc/m68k-amigaos/16.2.0b/libb32/libm020/libm881/libstdc++.a succeeded
attempt to open lib/gcc/m68k-amigaos/16.2.0b/../../../../m68k-amigaos/lib/libb32/libm020/libpthread.a succeeded
attempt to open m68k-amigaos/libnix/lib/libb32/libm020/libnix.a succeeded
```

$ g++ -fbaserel ... -Wl,--verbose | grep 'attempt to open|succeeded' (libstdc++, libsupc++, libpthread, libatomic, libgcc, libnix, os32compat)
```
attempt to open ~/stoves-work/stove-pth-root/compat/libos32compat.a succeeded
attempt to open lib/gcc/m68k-amigaos/16.2.0b/libb/libm020/libm881/libatomic.a succeeded
attempt to open lib/gcc/m68k-amigaos/16.2.0b/libb/libm020/libm881/libgcc.a succeeded
attempt to open lib/gcc/m68k-amigaos/16.2.0b/libb/libm020/libm881/libstdc++.a succeeded
attempt to open lib/gcc/m68k-amigaos/16.2.0b/../../../../m68k-amigaos/lib/libb/libm020/libpthread.a succeeded
attempt to open m68k-amigaos/libnix/lib/libb/libm020/libnix.a succeeded
```

So libstdc++, libatomic, libgcc, libpthread and libnix all come from the matching baserel multilib. **libos32compat.a has only an absolute-model build** (stove compat/) and is linked into both baserel programs.

## B. LDFCM

No LDFCM in our own objects (`t3_threads.cpp` built -fbaserel32 has none). They come from the libb32 libstdc++.a: 118 sections in 99 members:

```
assert_fail.o atexit_thread.o atomic.o basic_file.o bitmap_allocator.o chrono.o codecvt_members.o co
decvt.o compatibility-chrono.o compatibility.o complex_io.o condition_variable.o cow-fs_dir.o cow-fs
_ops.o cow-fs_path.o cow-fstream-inst.o cow-istream-string.o cow-locale_init.o cow-shim_facets.o cow
-sstream-inst.o cow-stdexcept.o cow-string-inst.o cow-system_error.o cow-wstring-inst.o cow-wstring-
io-inst.o ctype_members.o ctype.o cxx11-ios_failure.o cxx11-locale-inst.o cxx11-shim_facets.o cxx11-
stdexcept.o cxx11-wlocale-inst.o debug.o eh_alloc.o eh_globals.o eh_personality.o eh_ptr.o eh_termin
ate.o eh_tm.o ext11-inst.o floating_from_chars.o floating_to_chars.o format-inst.o format.o fs_dir.o
 fs_ops.o fs_path.o fstream-inst.o functexcept.o future.o guard.o ios_errcat.o ios_failure.o ios_ini
t.o ios-inst.o ios.o iostream-inst.o istream-inst.o istream.o istream-string.o locale_facets.o local
e_init.o locale-inst.o localename.o locale.o memory_resource.o misc-inst.o monetary_members_cow.o mo
netary_members.o mt_allocator.o mutex.o new_handler.o new_opant.o new_opnt.o new_opvant.o new_opvnt.
o numeric_members_cow.o numeric_members.o ostream-inst.o pool_allocator.o random.o regex.o shared_pt
r.o sso_string.o sstream-inst.o stdexcept.o streambuf-inst.o string-inst.o strstream.o system_error.
o thread.o time_members.o tzdb.o valarray.o vec.o vterminate.o wlocale-inst.o wstring-inst.o wstring
-io-inst.o 
```

Example, compatibility.o (libb32/libm020/libm881/libstdc++.a):
```
  7 .data.rel.local.LDFCM0 00000004  00000000  00000000  00000ae0  2**2
                  CONTENTS, ALLOC, LOAD, RELOC, DATA
  8 .data.rel.local.LDFCM1 00000004  00000000  00000000  00000b48  2**2
                  CONTENTS, ALLOC, LOAD, RELOC, DATA
RELOCATION RECORDS FOR [.data.rel.local.LDFCM0]:
OFFSET   TYPE              VALUE
00000000 RELOC32           __ZTIN10__cxxabiv115__forced_unwindE


RELOCATION RECORDS FOR [.gcc_except_table]:
00000030 RELRELOC32        .data.rel.local.LDFCM0
00000064 RELRELOC32        .data.rel.local.LDFCM0
```
Each LDFCM section is 4 bytes holding a pointer to a typeinfo (here `__ZTIN10__cxxabiv115__forced_unwindE`, RELOC32), and `.gcc_except_table` points at it with **RELRELOC32** (32-bit PC-relative). The link's "reloc for .data.rel.local.LDFCM0 is out of range: 00000000" lines are those, between the except table and a data section.

The 3-line test, `-m68020 -m68881 -fbaserel32 -O2 -c`:
```
Sections:
Idx Name          Size      VMA       LMA       File off  Algn
  0 .text         00000030  00000000  00000000  00000024  2**2
                  CONTENTS, ALLOC, LOAD, CODE

00000000 <__Z1fe-0x18>:
   0:	3fff           	.short 0x3fff
   2:	0000 c000      	orib #0,d0
   6:	0000 0000      	orib #0,d0
   a:	0000 3ffd      	orib #-3,d0
   e:	0000 8000      	orib #0,d0
  12:	0000 0000      	orib #0,d0
	...

00000018 <__Z1fe>:
  18:	2f0c           	movel a4,sp@-
  1a:	f22f 4800 0008 	fmovex sp@(8),%fp0
  20:	f23a 4823 ffdc 	fmulx %pc@(0 <__Z1fe-0x18>),%fp0
  26:	f23a 4822 ffe2 	faddx %pc@(c <__Z1fe-0xc>),%fp0
  2c:	285f           	moveal sp@+,a4
  2e:	4e75           	rts
```
The stove puts these long double constants in **.text, addressed PC-relative** (`fmulx %pc@(...)`); no LDFCM, no a4. So LDFCM is not long double constants: it is the indirect typeinfo references in exception tables.

## C. cxxglue (libb/libm020/libnix.a) and EH_FRAME_BEGIN

```
00000000 <___init_eh>:
   0:	2f0b           	movel a3,sp@-
   2:	2f0a           	movel a2,sp@-
   4:	202c 0004      	movel a4@(4),d0
			6: DREL16	.list___EH_FRAME_BEGIN
   8:	6720           	beqs 2a <___init_eh+0x2a>
   a:	264c           	moveal a4,a3
   c:	d7fc 0000 0008 	addal #8,a3
			e: DREL32	.list___EH_FRAME_BEGIN
  12:	244c           	moveal a4,a2
  14:	d5fc 0000 0004 	addal #4,a2
			16: DREL32	.dlist___EH_FRAME_OBJECT
  1a:	2f1a           	movel a2@+,sp@-
  1c:	2f00           	movel d0,sp@-
  1e:	61ff           	bsrs 1f <___init_eh+0x1f>
  20:	0000 0000      	orib #0,d0
			20: RELRELOC32	___register_frame_info
  24:	201b           	movel a3@+,d0
  26:	508f           	addql #8,sp
  28:	66f0           	bnes 1a <___init_eh+0x1a>
  2a:	245f           	moveal sp@+,a2
  2c:	265f           	moveal sp@+,a3
  2e:	4e75           	rts
```
From the failing t3-b16 link with `-Wl,-Map`:
```
355:.text           0x00000000    0x36be8
4387:.data           0x00036be8      0x848
4668:.bss            0x00037430      0x398
 .list___EH_FRAME_BEGIN
                0x00036a84        0x4 ~/stoves-work/stove-gcc16-pth/m68k-amigaos/libnix/lib/libb/libm020/libnix.a(cxxglue.o)
                0x00036a84                _EH_FRAME_BEGINS__
                0x0003ebe6                        ___a4_init = 0x7ffe
```
`.list___EH_FRAME_BEGIN` is at 0x36a84, **inside .text** (0–0x36be8), 0x164 bytes before .data starts. a4 = .data + 0x7ffe = 0x3ebe6, so the DREL16 offset is 0x36a84 − 0x3ebe6 = −0x8162 (−33,122), past −32,768. The section that `__init_eh` reaches a4-relative is placed in the code hunk by the linker script (`*(SORT_BY_NAME(.list___EH_FRAME*))` inside .text), so it only fits while .data is within 32 KB of it.

## D. No-threads control

`nothreads.cpp`: a std::vector and a printf, no std::thread. It still needs `-lpthread` (libstdc++'s eh_globals.o and libgcc's unwind-dw2.o call pthread_key_create, pthread_once and others).

| Build | Link | Lab |
| --- | --- | --- |
| plain | OK | `nothreads OK 328350`, rc 0 |
| -fbaserel32 | OK, 18 out-of-range lines | **hangs**, nothing printed |

So the -fbaserel32 hang is not about threads: a C++ program with no threads hangs the same way.

## Fix 1: libnix 0007 (cxxglue, __initcpp)

`patches/libnix/0007`: `__init_eh` takes `_EH_FRAME_BEGINS__`'s address with `lea` (RELOC32), and so do `__initcpp`/`__exitcpp` for `__CTOR_LIST__`/`__DTOR_LIST__`. `__initcpp` had the same fault: its loop's end was computed a4-relative (`DREL32 ___CTOR_LIST__`) even with `__far`. After the patch, `objdump -r` shows no DREL against `.list___EH_FRAME_BEGIN`, `___CTOR_LIST__` or `___DTOR_LIST__` in libb, libb/libm020 and libb32/libm020. Built into a copy of the stove (`ar r` of those two members only, flags `-O2 -fomit-frame-pointer -fno-tree-loop-distribute-patterns` plus the multilib's, which reproduce the old members exactly).

Lab (copy of Instance-32, clean start each run, 60 s):

| Program | libnix | libos32compat | Result |
| --- | --- | --- | --- |
| nothreads -fbaserel32, no compat | old | none | hangs |
| nothreads -fbaserel32, no compat | 0007 | none | `nothreads OK 328350`, rc 0 |
| nothreads -fbaserel32 | 0007 | absolute (installed), no `--wrap` | `nothreads OK 328350`, rc 0 |
| nothreads -fbaserel32 / -fbaserel | 0007 | absolute, with `--wrap=malloc…` | hangs |
| nothreads -fbaserel32 | 0007 | **built -fbaserel32**, with `--wrap` | `nothreads OK 328350`, rc 0 |
| t3_threads -fbaserel32 | 0007 | built -fbaserel32, with `--wrap` | **hangs** (no output; stdout is buffered) |

`-fbaserel` C++ now links. Plain C (`printf`) with -fbaserel32 ran before and after.

## Item 3: libos32compat is not safe in base-relative programs

`objdump -dr libos32compat.a | grep -c a4@` gives 7, all in `os32compat_malloc.o`: absolute-model code uses **a4 as a scratch register** (`movel a4@(-12),d2`, `clrl a4@(-4)` …: a4 holds the block header there) and calls `__real_malloc`/`__real_free`, which in a base-relative program need a4 to be the data base. With `--wrap=malloc,…` every allocation goes through it, so the program hangs. It needs base-relative builds (libb, libb32 multilibs) like the other libraries; built `-fbaserel32`, the no-threads program runs.

## Open at this point (both since fixed)

- **Threads under -fbaserel32** hung even with 0007 and a base-relative libos32compat: the new tasks libpthread started never loaded a4. Fixed by aros-stuff 0005 (Fix 4, below).
- **Fix 2 (GCC 0011, absptr EH data format)** was not done yet: the "out of range" lines were still there (18 for nothreads, 25 for t3) with 0007. Fixed by GCC 0011 (Fix 5, below).

## Fix 4: aros-stuff 0005 (libpthread's thread entry), reworked

`StarterFunc`, every thread's `NP_Entry`, ran with no a4. The first version called crt0's `_geta4`, which is wrong for `-resident`/`-resident32` (data per invocation; nrcrt0 has no usable `_geta4`). Now, under `__baserel__`, `pthread_create` saves its own a4 and the thread's id in the ThreadInfo (which never moves) and passes the ThreadInfo in `NP_Input`; `StarterFunc` reads it through `*(struct ExecBase **)4` → `ThisTask` → `pr_CIS`, reads no global, loads a4 (`moveal a2,a4`), puts the id back in `pr_CIS` and tail-calls the body. objdump (libb32/libm020): `moveal 4,a0; moveal a0@(276),a0; moveal a0@(156),a1; moveal a1@(20),a2; moveal a2,a4; movel a1@(24),a0@(156)`, and `pthread_create` does `movel a4,a3@(20)`. The plain build is unchanged. (`__saveds` does nothing on this stove: an empty `__saveds` function is a bare `rts` under `-fbaserel`.) `USE_ASYNC_CANCEL` is off, so there is no other entry exec calls.

Lab, with libnix 0007, libpthread 0005 and libos32compat built base-relative:

| Program | Result |
| --- | --- |
| t3_threads -fbaserel32 | `t3 OK`, rc 0 |
| t3_threads -fbaserel | `t3 OK`, rc 0 |
| t3_threads -resident32 | `t3 OK`, rc 0 |
| t3_threads -resident | `t3 OK`, rc 0 |
| t3_threads -resident32, `Resident … PURE`, two `Run`s at once | both `t3 OK`, rc 0 |

## Fix 5: GCC 0011 (EH data always absolute)

`patches/gcc/0011` overrides `ASM_PREFERRED_EH_DATA_FORMAT` to `DW_EH_PE_absptr` in `m68kamigaos.h` (the target's tm_file after `m68k.h`), so `.gcc_except_table` points at typeinfo with RELOC32 in every code model and there are no LDFCM pools. The target libraries must be rebuilt with the new compiler (an incremental build reuses the old objects).

Full build of main fd08383 plus 0011, on daletop:

- `objdump -r -j .gcc_except_table` on `libstdc++.a`, `libsupc++.a` and `libgcc.a` (libb32, libb and plain multilibs): 0 RELRELOC32, 0 LDFCM sections (before: 122 RELRELOC32 and 119 LDFCM in each base-relative libstdc++).
- `catch.cpp` and `t3_threads.cpp` linked `-fbaserel32`, `-resident32`, `-fbaserel`: 0 "out of range" lines.

Lab copy of Instance-32:

| Program | Result |
| --- | --- |
| catch.cpp plain, -fbaserel32, -resident32, -fbaserel | five PASS lines and `catch OK`, rc 0 |
| t3_threads -fbaserel32 | `t3 OK`, rc 0 |
| catch.cpp -fbaserel32, stove without 0011 | "Program aborted", hangs |

CI runs `eh-check.sh`, the link and LDFCM part of this.
