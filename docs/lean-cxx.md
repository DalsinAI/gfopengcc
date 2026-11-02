# Lean C++ for the GFOpen family

The GFOpen family's libraries and apps can be written in C++ with this compiler. On a 68040 at 25 MHz every kilobyte and every start-up step shows, so our C++ is a lean subset: what C++ gives at compile time (classes, templates, `constexpr`, RAII, `enum class`, namespaces, overloading, lambdas, virtual functions) and none of the runtime machinery that needs setting up before code can run.

Two kinds of code stay in C:
- **Each library's entry points.** AmigaOS calls a library with its arguments in registers and its base in A6. The jump table, the `LVO` stubs and the functions it points at stay C (or `extern "C"`), as they are generated from the SFD today. They call into C++.
- **ROM-resident code** (exec and the low parts of dos), where every byte counts and nothing can run before the library is set up.

Existing C moves to C++ only when it is next reworked.

## The two profiles

| | Libraries, devices, handlers, datatypes | Apps and commands |
| --- | --- | --- |
| Flags | `-std=gnu++23 -fno-exceptions -fno-rtti -fno-threadsafe-statics -fno-asynchronous-unwind-tables -fno-unwind-tables -nostdlib++` | `-std=gnu++23 -fno-exceptions -fno-rtti` |
| libstdc++ | not linked | linked; header-only parts preferred |
| Global objects with constructors or destructors | none: `constinit`/`constexpr` data only | allowed (libnix runs them), but avoid in hot start-up paths |
| `new`/`delete` | our own, in the library's glue (see below) | libstdc++'s, or a class's own pool |
| Threads | exec tasks and signals, through the library's own code | `std::thread` and friends work (amicradle-stoves' t1-t19) |

An app that needs exceptions or `dynamic_cast` (a port that uses them, such as a parser library) leaves those two flags out; the stove's tests t1, t2 and t11 show both work. WebKit already builds with `-fno-exceptions -fno-rtti`.

## Rules for library code

1. **No static constructors or destructors.** A library has no start code that runs `__INIT_LIST__`, so a global object with a constructor is never constructed. Make globals `constinit` or `constexpr`, or plain structs filled in by `LibInit`. Check with `nm`: no `_GLOBAL__sub_I_` symbol may appear (`tests/cxx/lean-check.sh` does this).
2. **No function-local statics that need a constructor.** With `-fno-threadsafe-statics` there is no guard; two tasks calling the function at once would both construct it. Put the object in the library base or construct it in `LibInit`.
3. **Memory comes from exec.** Define `operator new`, `operator new[]`, `operator delete` (all sized and unsized forms) in the library's glue, on `AllocVec`/`FreeVec` or the library's memory pool, and `__cxa_pure_virtual` (an `Alert` and a `Wait(0)`). With `-fno-exceptions`, `new` returns `nullptr` on failure and callers check it.
4. **Only header-only, allocation-free standard headers.** `<array>`, `<span>`, `<string_view>`, `<algorithm>`, `<utility>`, `<optional>`, `<variant>`, `<bit>`, `<type_traits>`, `<limits>`, `<cstdint>`, `<cstring>`, `<concepts>`. Not `<string>`, `<vector>`, `<map>`, `<iostream>`, `<thread>`, `<mutex>`, `<functional>` (they need libstdc++ or allocate behind your back); write a small container on the library's allocator when one is needed.
5. **The library base and anything shared with C stay standard-layout.** Structs that cross the jump table, or that C code or 68k assembler reads, have no virtual functions or base classes; `static_assert(std::is_standard_layout_v<T>)` next to them.
6. **The entry points stay `extern "C"`.** A C++ function called from the jump table is declared `extern "C"` and takes its library base as an argument; it never lets anything escape as an exception (there are none with these flags).
7. **The 68k inline rules still hold.** Never nest one inline library call in another's arguments (wrong A6); see gfopensdk `Docs/PORTING.md`.

## Not yet working

- **Catching an exception by type in base-relative C++.** With libnix 0007 and aros-stuff 0005, `-fbaserel` and `-fbaserel32` C++ programs link, start and run threads (`tests/baserel`), but their exception tables still point at typeinfo PC-relative across hunks (the linker's "out of range" lines), so a `catch` by type may not match. Base-relative libraries keep `-fno-exceptions` (they do anyway) until the GCC fix lands.
- **64-bit atomics on the 68020-68040** call libatomic. In a library, use 32-bit atomics or exec's `Forbid`/`Permit` or a semaphore.

## Checking a build

`tests/cxx/lean-check.sh` compiles `tests/cxx/lean.cpp` (a small class hierarchy, a template, a lambda, `constinit` data and its own `operator new`) with the library profile and fails if the object refers to anything the profile forbids: exception or RTTI support (`__cxa_throw`, `__gxx_personality`, `_ZTI`, `_ZTS`), static constructors (`_GLOBAL__sub_I_`), function-local statics that need constructing (`_ZGV` guard variables) or libstdc++'s `operator new`.

```bash
CXX=/opt/amiga/bin/m68k-amigaos-g++ NM=/opt/amiga/bin/m68k-amigaos-nm tests/cxx/lean-check.sh
```
