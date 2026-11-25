#!/usr/bin/env python3
"""check_selfcalls.py on made-up programs: libm's self-calling sqrtf
(as the os32-gcc16-open9 stove built it) fails when something calls it and is
only a note when nothing used does (the library copy left after ld --wrap,
and a copy beside it that calls it); a sound
function is not found, and one that calls itself further in (a real
recursion) is left alone."""
# MIT, Copyright (c) 2026 AmiCradle Team.
import struct, subprocess, sys, tempfile
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))
import check_selfcalls

def program(funcs):
    """A one-hunk program of (name, code bytes) with a symbol for each."""
    code, syms = b"", []
    for name, body in funcs:
        syms.append((name, len(code)))
        code += body
    code += b"\0" * (-len(code) % 4)
    out = struct.pack(">IIIII", 0x3F3, 0, 1, 0, 0) + struct.pack(">I", len(code) // 4)
    out += struct.pack(">II", 0x3E9, len(code) // 4) + code + struct.pack(">I", 0x3F0)
    for name, off in syms:
        n = (name.encode() + b"\0" * 4)[: (len(name) + 4) // 4 * 4]
        out += struct.pack(">I", len(n) // 4) + n + struct.pack(">I", off)
    return out + struct.pack(">II", 0, 0x3F2)

# move.l 4(sp),-(sp); jsr (pc) to itself; addq.l #4,sp; rts  (libm's sqrtf)
LOOPING = bytes.fromhex("2f2f00044ebafffa588f4e75")
# move.l 4(sp),d0; rts
SOUND = bytes.fromhex("202f00044e75")
# twelve bytes of work, then bsr.l to itself (recursion with a way out)
DEEPER = bytes.fromhex("4a6f0004670a4e714e714e7161ff") + struct.pack(">i", -14) + bytes.fromhex("4e75")

def caller(to):
    """jsr (pc) to the code `to` bytes from this jsr; rts"""
    return struct.pack(">Hh", 0x4EBA, to - 2) + bytes.fromhex("4e75")

found = check_selfcalls.self_calls(program([("_fabsf", SOUND), ("_sqrtf", LOOPING), ("_walk", DEEPER)]))
assert [(f[0], f[3]) for f in found] == [("_sqrtf", [])], found
assert check_selfcalls.self_calls(program([("_fabsf", SOUND), ("_walk", DEEPER)])) == []
# the entry (offset 0) calls _main, which calls _sqrtf: used
USED = program([("_start", caller(6)), ("_main", caller(6)), ("_sqrtf", LOOPING)])
assert [(f[0], f[3]) for f in check_selfcalls.self_calls(USED)] == [("_sqrtf", ["_main"])]
# only _hypotf calls _sqrtf, and nothing calls _hypotf: not used
UNUSED = program([("_start", SOUND), ("_hypotf", caller(6)), ("_sqrtf", LOOPING)])
assert [(f[0], f[3]) for f in check_selfcalls.self_calls(UNUSED)] == [("_sqrtf", [])]

with tempfile.TemporaryDirectory() as t:
    bad = Path(t) / "bad"
    bad.write_bytes(USED)
    r = subprocess.run([sys.executable, str(TOOLS / "check_selfcalls.py"), str(bad)], capture_output=True, text=True)
    assert r.returncode == 1 and "_sqrtf" in r.stdout, r.stdout + r.stderr
    good = Path(t) / "good"
    good.write_bytes(program([("_fabsf", SOUND)]))
    r = subprocess.run([sys.executable, str(TOOLS / "check_selfcalls.py"), str(good)], capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr
    left = Path(t) / "left"
    left.write_bytes(UNUSED)
    r = subprocess.run([sys.executable, str(TOOLS / "check_selfcalls.py"), str(left)], capture_output=True, text=True)
    assert r.returncode == 0 and "note:" in r.stdout and "_sqrtf" in r.stdout, r.stdout + r.stderr
print("PASS check_selfcalls: a called looping wrapper fails, an uncalled one is a note, sound code and real recursion are not found")
