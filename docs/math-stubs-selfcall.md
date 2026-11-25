# libstdc++'s floorf, ceilf and sqrtf called themselves

**Patch:** `patches/gcc/0020-libstdc-build-the-float-math-stubs-with-fno-builtin.patch`
**Check:** `tests/selfcalls/check.sh PREFIX` (build.sh step 7)

libnix's libm has no `floorf`, `ceilf` or `sqrtf` (nor most other float
functions), so libstdc++'s configure leaves `_GLIBCXX_HAVE_FLOORF` and the rest
off and builds `src/c++98/math_stubs_float.cc`, which defines each one as the
double function:

    float floorf(float x) { return (float) floor(x); }

With builtins on, GCC knows that `(float) floor((double) x)` is `floorf(x)` and
narrows it, so up to open9 the stub was a call to itself:

    _floorf: move.l 4(sp),-(sp); jsr _floorf(pc); addq.l #4,sp; rts

The same for `ceilf` and `sqrtf` (the other stubs, `cosf`, `expf`, `powf`...,
are not narrowed and were right). A program linked with g++ takes them from
`libstdc++.a(math_stubs_float.o)` before libm, and the first call ran until the
stack was gone. WarMUX's Play hung in `sqrtf` (25 Nov 2026; the port works
round it with `ld --wrap`).

The patch builds `math_stubs_float.cc` with `-fno-builtin`, so the stubs call
`floor`, `ceil` and `sqrt`. Host GCC shows the same: `g++ -O2 -mno-sse4 -S`
of the stub makes `sqrtf` jump to `sqrtf`, and with `-fno-builtin` it calls
`sqrt`.

`tests/selfcalls/check.sh` links `floatmath.cpp`, which calls every function
the stubs can define, with g++ for `-m68040`, `-m68040 -m68881` and `-m68020`,
and runs `check_selfcalls.py` on each program: it fails when a function that
is called (from the entry, or from code that something else refers to) calls itself in its first 8 bytes. `check_selfcalls.py` is a copy of
amigawarmux's `tools/check_selfcalls.py` (MIT), with its test.
