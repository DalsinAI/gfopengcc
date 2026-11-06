# Open7 fpuauto data-dispatch validation — 2026-11-06

The fpuauto version merged into `amicradle-guest` main at `d506dccd` patches
each wrapper's first `JMP` instruction and calls `CacheClearU`. That is unsafe
as the long-term dispatcher for multicore AmigaChrome and incompatible with
write-protected executable code.

Open7 uses local `amicradle-guest` commit `e62e5c24` on branch
`team1/fpuauto-data-dispatch`:

- `04942e58` replaces instruction rewriting with one aligned four-byte data
  target per wrapper. Calls load the target and jump indirectly. Concurrent
  first calls can only store the same aligned pointer.
- `e62e5c24` adds an idempotent release-prefix installer and makes the build
  tests work even when a stove already has fpuauto installed.

The Open6 compiler built all 29 revised wrappers. Object inspection confirmed
the data target, found no `CacheClear` reference and showed the wrapper as a
data load followed by an indirect jump. Link validation passed for automatic
wrapping, `-DNO_FPUAUTO`, hard float and programs with no floating-point
maths. The benchmark binaries built successfully; AmigaChrome runtime timing
and checksum qualification remain required because the published 5 November
measurements cover the former self-patching dispatcher.

The release-prefix installer also passed against a complete disposable copy
of the Open6 prefix. The installed library exported all 29 wrappers; an
ordinary 68040 soft-float link contained wrapped references and the explicit
opt-out contained none. The live Open6 stove's specs hash remained
`795fccc84bbee65bd60fe1a21cda3e6ee774259cf130665a0ff01ac83e38bc61`
before and after the disposable test.

GFOpenAmigaGCC now pins this guest commit, invokes its prefix installer and
records the resolved source head in the installed provenance bundle.

Remote publication was not possible in this session: both Git and the
connected GitHub/Desktop tools were rejected by the account's approval policy.
The commits are preserved locally and must be pushed before a remote Open7
build can resolve the new source lock.
