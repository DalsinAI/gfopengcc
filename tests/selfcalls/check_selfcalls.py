#!/usr/bin/env python3
"""Fail when a function in an AmigaOS program (hunk format, with its symbols)
calls itself in its first few instructions: a wrapper that calls itself
until the stack runs out. The stove libm's floorf, ceilf and sqrtf were
such wrappers (GCC had folded each into a call to itself), and WarMUX's
Play hung in sqrtf (25 Nov 2026). A deeper call to itself is a recursion
with a way out and is left alone. A self-caller that only unused code calls
or points to (a library copy left in after ld --wrap, and the copies beside
it) is reported as a note only.
Prints what it finds; exit 1 if any self-caller is used.

  check_selfcalls.py PROGRAM [--within BYTES]"""
# MIT, Copyright (c) 2026 AmiCradle Team.
import argparse, struct, sys

HUNK_HEADER, HUNK_CODE, HUNK_DATA, HUNK_BSS = 0x3F3, 0x3E9, 0x3EA, 0x3EB
HUNK_RELOC32, HUNK_SYMBOL, HUNK_DEBUG, HUNK_END = 0x3EC, 0x3F0, 0x3F1, 0x3F2
HUNK_DREL32, HUNK_RELOC32SHORT = 0x3F7, 0x3FC


def read_hunks(data):
    """[(kind, bytes, {offset: name}, [(offset, target hunk)])] for each
    hunk of a load file; the last list is its HUNK_RELOC32 entries."""
    pos = 0

    def word():
        nonlocal pos
        v = struct.unpack_from(">I", data, pos)[0]
        pos += 4
        return v

    if word() != HUNK_HEADER:
        raise ValueError("not an AmigaOS program (no HUNK_HEADER)")
    while word():          # resident library names: none in a program
        pass
    count, first, last = word(), word(), word()
    for _ in range(last - first + 1):
        word()
    hunks, cur = [], None
    while pos < len(data) and len(hunks) <= count:
        kind = word() & 0x3FFFFFFF
        if kind in (HUNK_CODE, HUNK_DATA):
            n = word()
            cur = [kind, data[pos:pos + n * 4], {}, []]
            pos += n * 4
        elif kind == HUNK_BSS:
            word()
            cur = [kind, b"", {}, []]
        elif kind == HUNK_RELOC32:
            while True:
                n = word()
                if not n:
                    break
                target = word()
                for _ in range(n):
                    cur[3].append((word(), target))
        elif kind in (HUNK_DREL32, HUNK_RELOC32SHORT):
            while True:
                n = struct.unpack_from(">H", data, pos)[0]
                pos += 2
                if not n:
                    break
                target = struct.unpack_from(">H", data, pos)[0]
                pos += 2
                for _ in range(n):
                    cur[3].append((struct.unpack_from(">H", data, pos)[0], target))
                    pos += 2
            pos += pos % 4
        elif kind == HUNK_SYMBOL:
            while True:
                n = word()
                if not n:
                    break
                name = data[pos:pos + n * 4].rstrip(b"\0").decode("latin-1")
                pos += n * 4
                cur[2][word()] = name
        elif kind == HUNK_DEBUG:
            pos += word() * 4
        elif kind == HUNK_END:
            hunks.append(cur)
            cur = None
        else:
            raise ValueError(f"hunk type {kind:#x} at {pos - 4}: not one this reads")
    return hunks


def call_target(code, at):
    """Where the call at offset at goes (in the same hunk), or None."""
    if at + 2 > len(code):
        return None
    op = struct.unpack_from(">H", code, at)[0]
    if op == 0x4EBA and at + 4 <= len(code):                  # jsr (d16,pc)
        return at + 2 + struct.unpack_from(">h", code, at + 2)[0]
    if op == 0x6100 and at + 4 <= len(code):                  # bsr.w
        return at + 2 + struct.unpack_from(">h", code, at + 2)[0]
    if op == 0x61FF and at + 6 <= len(code):                  # bsr.l
        return at + 2 + struct.unpack_from(">i", code, at + 2)[0]
    if op == 0x4EFA and at + 4 <= len(code):                  # jmp (d16,pc)
        return at + 2 + struct.unpack_from(">h", code, at + 2)[0]
    if op == 0x6000 and at + 4 <= len(code):                  # bra.w
        return at + 2 + struct.unpack_from(">h", code, at + 2)[0]
    if op == 0x60FF and at + 6 <= len(code):                  # bra.l
        return at + 2 + struct.unpack_from(">i", code, at + 2)[0]
    if op >> 8 == 0x61 and op & 0xFF not in (0, 0xFF):       # bsr.b
        return at + 2 + struct.unpack(">b", bytes([op & 0xFF]))[0]
    return None


def references(hunks, targets):
    """{(hunk, start): [(hunk, offset)]} for each (hunk, start) in targets:
    where code calls or jumps to it, and where a RELOC32 points to it."""
    refs = {t: [] for t in targets}
    for h, (kind, code, _, relocs) in enumerate(hunks):
        if kind == HUNK_CODE:
            for at in range(0, len(code) - 1, 2):
                t = call_target(code, at)
                if (h, t) in refs:
                    refs[(h, t)].append((h, at))
        for off, target in relocs:
            if off + 4 <= len(code):
                v = struct.unpack_from(">I", code, off)[0]
                if (target, v) in refs:
                    refs[(target, v)].append((h, off))
    return refs


def self_calls(data, within=8):
    """[(name, start, offset of the call, callers)]: callers names the
    functions that call, jump to or point to it and that are used themselves
    (the program's entry, or something outside each refers to it); empty when nothing that is used
    refers to it, as for a library copy left in after ld --wrap."""
    hunks = read_hunks(data)
    found, spans = [], {}
    for h, (kind, code, syms, _) in enumerate(hunks):
        starts = sorted(syms)
        for i, start in enumerate(starts):
            end = starts[i + 1] if i + 1 < len(starts) else len(code)
            spans[(h, start)] = (end, syms[start])
            if kind != HUNK_CODE:
                continue
            for at in range(start, min(end, start + within + 2), 2):
                if call_target(code, at) == start:
                    found.append((h, syms[start], start, at - start))
                    break
    if not found:
        return []

    def owner(h, at):
        """(hunk, start) of the function holding offset at, or None."""
        best = None
        for (hh, st), (end, _) in spans.items():
            if hh == h and st <= at < end and (best is None or st > best[1]):
                best = (hh, st)
        return best

    refs = references(hunks, [(h, start) for h, _, start, _ in found])
    callers = {}
    for t, sites in refs.items():
        callers[t] = sorted({o for o in (owner(h, at) for h, at in sites) if o != t},
                            key=lambda o: o or (0, 0))
    outer = references(hunks, {o for os in callers.values() for o in os if o})
    out = []
    for h, name, start, off in found:
        live = []
        for o in callers[(h, start)]:
            if o is None:
                live.append("(code with no symbol)")
            elif o == (0, 0) or any(owner(hh, at) != o for hh, at in outer[o]):
                live.append(spans[o][1])
        out.append((name, start, off, live))
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("program")
    ap.add_argument("--within", type=int, default=8)
    a = ap.parse_args()
    found = self_calls(open(a.program, "rb").read(), a.within)
    for name, start, off, used in found:
        if used:
            print(f"{a.program}: {name} (at {start:#x}) calls itself {off} bytes in, and is called by {', '.join(used)}")
        else:
            print(f"note: {a.program}: {name} (at {start:#x}) calls itself {off} bytes in; nothing calls it")
    if any(f[3] for f in found):
        sys.exit(1)
    print(f"check_selfcalls: no function in {a.program} that is called calls itself at its start")
