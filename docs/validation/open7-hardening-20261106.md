# Open7 hardening validation — 2026-11-06

This records the Open7 hardening candidate and its current evidence. It is not
an Open7 release qualification.

## Defects reproduced on Open6

- `-fstack-protector-strong` and `-fstack-protector-all` generated guard and
  failure references, but links failed because libnix supplied neither
  `__stack_chk_guard` nor `__stack_chk_fail`.
- `-fhardened` warned that the option was unsupported but continued with PIE
  and GOT code generation. The Amiga hunk assembler then rejected the emitted
  `@GOT(a4)` syntax, obscuring the real target limitation.

## Open7 candidate

- `runtime/ssp.c` provides a process guard, constructor-time entropy mixing,
  `__stack_chk_fail` and its local forwarding entry point without recursively
  protecting the runtime itself. A forwarding function is used because the
  Amiga hunk target rejects C symbol aliases.
- `scripts/install-ssp.sh` builds and installs `libssp.a` beside the exact
  `libgcc.a` selected for every advertised multilib and verifies all three
  public symbols. It deliberately does not use libnix's path because libnix
  collapses several CPU variants onto a shared directory.
- GCC links that runtime when any stack-protector mode is selected.
- The driver stops immediately on `-fhardened` and recommends the supported
  `-fstack-protector-strong` option.

## Gate

The gate passes only when the patched driver rebuilds, every multilib runtime
installs, protected programs link in every advertised multilib, and
`-fhardened` produces the target diagnostic without reaching the assembler.
Runtime canary-corruption testing on AmigaOS/AmigaChrome remains part of final
Open7 qualification.

## Host-side results

- Patch 0016 applied to the disposable GCC source after patches 0001–0015.
- `make -j8 all-gcc` rebuilt and linked `xgcc`, `cc1` and LTO successfully.
- The first diagnostic text contained a semicolon, which GCC's spec parser
  interpreted as an alternative separator. The compiler smoke step exposed
  it; the final diagnostic uses spec-safe punctuation and was rebuilt.
- The Amiga hunk target rejected a symbol alias for
  `__stack_chk_fail_local`; the final runtime uses a forwarding function.
- Installing beside libnix was rejected during testing because several CPU
  variants select a shared libnix directory. The final installer uses each
  multilib's selected `libgcc.a` directory, producing 11 distinct archives.
- All four GCC stack-protector modes linked their protected probes. All 11
  advertised multilibs linked the strong-protector probe and contained the
  resolved guard and failure definitions.
- `-fhardened` returned the Open7 target diagnostic and created no object; it
  did not reach the assembler.

The link matrix used a disposable complete Open6 prefix with the rebuilt
Open7 driver and an explicit Open7 candidate specs file. Linker-plugin use was
disabled only for this composite-prefix test because the minimal development
driver and the complete prefix were configured separately. A clean full
Open7 build remains the production integration gate.
