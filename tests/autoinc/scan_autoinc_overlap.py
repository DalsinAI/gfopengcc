#!/usr/bin/env python3
"""scan_autoinc_overlap.py: find m68k moves whose source steps an address
register ((An)+ or -(An)) that the destination's address also uses.

In GCC's RTL another address in the same insn sees the register's value
from BEFORE the increment or decrement (gcc/doc/rtl.texi, "Incdec"), but a
680x0 works the source out first, side effect included, and only then the
destination's address.  So

    move.b (a1)+,(0,a1,d0.l)        ; GCC meant: to old a1 + d0

stores each byte one place on.  GCC 15 and later make such moves after
register allocation (late-combine; GCC PR rtl-optimization/123853 and PR
target/123076) and the m68k back end does not refuse them.  GFOpenAmigaGCC
carries the fix (DalsinAI/gfopengcc patches/gcc/0013, from open4); stock
GCC 15/16 builds such as the aros68k-gcc16 stove (the ROM's exec) do not.

What is reported, per instruction:
  WRONG      the source steps the register and the destination's address
             uses it: the hardware uses the stepped value, GCC meant the old
             one.  This is the bug.
  BOTH       the same register is stepped in both operands.  GCC never makes
             this, so in compiled code it is data; listed, and fails only
             with --strict.
  REGDIRECT  the stepped register is the other operand itself, as in
             "move.l sp,-(sp)" (hand-written assembly).  Listed with
             --regdirect, never failing.
  BENIGN     the destination steps the register and the source's address
             uses it: the source is read first, with the old value, which is
             what was meant.  Listed with --all only.

Tables, strings and jump tables inside .text (common in AmigaOS hunk files
and libraries) disassemble into anything, so a hit in a switch's jump table
(the offsets after "jmp pc@(T,Xn)"), in a C++ variable (by c++filt), after
words in its symbol that do not decode, in a symbol that never returns or
branches away, or after its symbol's last return or branch, or
with words that do not decode, ASCII text, zero words or a run of small
numbers next to it, is
marked "looks like data" and does not fail unless --strict.
Only WRONG hits in code fail by default.  Give it objects or unstripped
binaries: without symbols most of these tests cannot be made, and a big
stripped program's tables come out as many false hits.
Hand-written code that means the 68k's order (exec's "move.l (sp)+,(sp)")
can be let through with --allow.

Inputs: object files, archives, ELF and Amiga hunk executables (through an
m68k objdump; several can be given, each file goes to the first that reads
it), raw code with --raw, or text (gcc -S output or objdump -d output) with
--text.  Directories are walked.

Exit status: 0 no failing hit, 1 failing hits, 2 usage or tool error.

Examples:
  scan_autoinc_overlap.py --objdump m68k-aros-objdump --objdump m68k-amigaos-objdump rom-out/b
  m68k-aros-gcc -m68040 -O2 -S x.c -o x.s && scan_autoinc_overlap.py --text x.s
  scan_autoinc_overlap.py --selftest
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys

OBJDUMPS = ("m68k-aros-objdump", "m68k-amigaos-objdump",
            "m68k-linux-gnu-objdump", "m68k-elf-objdump")
SKIP_SUFFIXES = (".c", ".cc", ".cpp", ".h", ".txt", ".md", ".json", ".log", ".py", ".sh",
                 ".d", ".mk", ".html", ".png", ".jpg", ".info", ".lha", ".map", ".sym.txt",
                 ".adf", ".hdf", ".iso", ".zip", ".gz", ".xz", ".bz2")

REGNAME = {"sp": "a7", "fp": "a6", "ssp": "a7", "usp": None}
AREG = r"%?(?:a[0-7]|sp|fp)\b"                 # an address register, MIT or Motorola
AUTO_RES = [
    (re.compile(r"^%?(a[0-7]|sp|fp)@\+$"), "postinc"),        # %a1@+  (MIT)
    (re.compile(r"^%?(a[0-7]|sp|fp)@-$"), "predec"),          # %a1@-
    (re.compile(r"^\(%?(a[0-7]|sp|fp)\)\+$"), "postinc"),     # (a1)+  (Motorola)
    (re.compile(r"^-\(%?(a[0-7]|sp|fp)\)$"), "predec"),       # -(a1)
]
INSN_RE = re.compile(r"^\s*([0-9a-f]+):\s+((?:[0-9a-f]{4} ?)+)\s+(\S+)\s*(.*)$")
FUNC_RE = re.compile(r"^([0-9a-f]+) <([^>]+)>:\s*$")
FILE_RE = re.compile(r"^(\S.*):\s+file format\s+(\S+)")
ARCHIVE_RE = re.compile(r"^In archive (.*):\s*$")
ASM_RE = re.compile(r"^\s+([a-z][a-z0-9.]*)\s+(.*)$")         # gcc -S: mnemonic, operands
ASM_LABEL_RE = re.compile(r"^([A-Za-z_.$][\w.$]*):")
UNDECODABLE = (".short", ".long", ".byte", ".word")
FLOW_END = ("rts", "rte", "rtd", "rtr", "jmp", "jra", "bra", "illegal", "trap")


def canon(reg):
    reg = reg.lstrip("%")
    return REGNAME.get(reg, reg)


def split_operands(ops):
    """Split at the commas outside parentheses and brackets."""
    out, depth, cur = [], 0, ""
    for ch in ops:
        if ch in "([":
            depth += 1
        elif ch in ")]":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur.strip())
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


def auto_mod(op):
    for rx, kind in AUTO_RES:
        m = rx.match(op)
        if m:
            return canon(m.group(1)), kind
    return None


def addr_regs(op):
    """The address registers a memory operand's address is made from."""
    if "@" not in op and "(" not in op:
        return set()
    return {canon(r) for r in re.findall(AREG, op)} - {None}


def bare_reg(op):
    m = re.fullmatch(AREG, op.strip())
    return canon(m.group(0)) if m else None


def classify(mnem, operands):
    """(class, register, detail) for each finding in one instruction."""
    if mnem.lower().startswith(("movem", "lea", "pea", "link", "unlk")) or len(operands) < 2:
        return []
    src, dst = operands[0], operands[-1]
    a_src, a_dst = auto_mod(src), auto_mod(dst)
    if a_src and a_dst and a_src[0] == a_dst[0]:
        return [("BOTH", a_src[0], "%s and %s" % (a_src[1], a_dst[1]))]
    hits = []
    if a_src:
        r = a_src[0]
        if r in addr_regs(dst):
            hits.append(("WRONG", r, "%s source, register in the destination's address" % a_src[1]))
        elif bare_reg(dst) == r:
            hits.append(("REGDIRECT", r, "%s source, register is the destination" % a_src[1]))
    if a_dst:
        r = a_dst[0]
        if r in addr_regs(src):
            hits.append(("BENIGN", r, "%s destination, register in the source's address" % a_dst[1]))
        elif bare_reg(src) == r:
            hits.append(("REGDIRECT", r, "%s destination, register is the source" % a_dst[1]))
    return hits


def ends_flow(mnem):
    return mnem.startswith(FLOW_END)


def symbol_regions(rows):
    """For each row, the index of the first and last row of its symbol."""
    first, last, lo = [0] * len(rows), [0] * len(rows), 0
    for i in range(1, len(rows) + 1):
        if i == len(rows) or rows[i][5] != rows[lo][5] or rows[i][4] != rows[lo][4]:
            for j in range(lo, i):
                first[j], last[j] = lo, i - 1
            lo = i
    return first, last


JMP_TABLE_RE = re.compile(r"%?pc@\(([0-9a-f]+)[^,)]*,")      # jmp %pc@(T <sym>,%a1:w)


def jump_tables(rows):
    """Indexes of rows inside a GCC switch table: after "jmp %pc@(T,Xn)",
    16-bit offsets from T up to the first case they point at."""
    where = {int(r[0], 16): k for k, r in enumerate(rows)}
    table = set()
    for r in rows:
        if not r[2].startswith("jmp"):
            continue
        m = JMP_TABLE_RE.search(r[3])
        if not m or int(m.group(1), 16) not in where:
            continue
        t = int(m.group(1), 16)
        k, end, words = where[t], None, 0
        while k < len(rows) and words < 4096:
            a = int(rows[k][0], 16)
            if end is not None and a >= end:
                break
            raw = bytes.fromhex(rows[k][1].replace(" ", ""))
            for j in range(0, len(raw) - 1, 2):
                off = int.from_bytes(raw[j:j + 2], "big", signed=True)
                if off > 0 and (end is None or t + off < end):
                    end = t + off
                words += 1
            table.add(k)
            k += 1
    return table


def cxx_variables(names):
    """The C++ symbols among names that are variables, not functions (by
    c++filt: a function's name ends in its parameter list)."""
    names = sorted({n for n in names if n.lstrip("_").startswith("Z")})
    tool = shutil.which("c++filt")
    if not names or not tool:
        return set()
    try:
        out = subprocess.run([tool], input="\n".join("_" + n.lstrip("_") for n in names) + "\n",
                             stdout=subprocess.PIPE, universal_newlines=True).stdout.splitlines()
    except OSError:
        return set()
    found = set()
    for n, d in zip(names, out):
        d = re.sub(r"( \[clone [^]]*\])+$", "", d.strip())
        d = re.sub(r"( (const|volatile|&|&&|noexcept))+$", "", d)
        if d != "_" + n.lstrip("_") and not d.endswith(")"):
            found.add(n)
    return found


def last_flow_end(rows, lo, hi):
    """Index of the last return or branch away in rows[lo..hi], or -1."""
    for k in range(hi, lo - 1, -1):
        if ends_flow(rows[k][2]):
            return k
    return -1


def looks_like_data(rows, i, regions, facts, tables, variables):
    """Why rows[i] looks like data a linear disassembly decoded, or None.
    rows: (addr, hexbytes, mnemonic, operands, file, symbol)."""
    if i in tables:
        return "a switch's jump table"
    fn = rows[i][5]
    if fn in variables:
        return "%s is a C++ variable" % fn
    if fn not in ("?", ".text"):
        lo, hi = regions[0][i], regions[1][i]
        for k in range(lo, i):
            if k not in tables and rows[k][2].startswith(UNDECODABLE):
                return "words before it in %s that do not decode" % fn
        if lo not in facts:
            facts[lo] = last_flow_end(rows, lo, hi)
        last_end = facts[lo]
        if last_end < 0:
            return "nothing in %s returns or branches away" % fn
        if last_end < i:
            return "after %s's last return or branch" % fn
    for k in range(max(0, i - 6), min(len(rows), i + 7)):
        if k not in tables and (rows[k][2].startswith(UNDECODABLE) or rows[k][2] in ("illegal", "unknown")):
            return "words nearby that do not decode"
    raw = b"".join(bytes.fromhex(r[1].replace(" ", "")) for r in rows[max(0, i - 4):i + 5])
    run = best = 0
    for b in raw:
        run = run + 1 if 0x20 <= b < 0x7f else 0
        best = max(best, run)
    if best >= 8:
        return "ASCII text nearby"
    if raw.count(b"\0\0\0\0") >= 3:
        return "zero words nearby"
    # tables of small numbers (offsets, lengths, relocations) decode as runs
    # of "ori.b #n,dN" and friends: first words $0000 to $00FF
    small = sum(1 for r in rows[max(0, i - 4):i + 5] if r[1][:2] == "00")
    if small >= 3:
        return "small numbers nearby (a table)"
    return None


def scan_objdump_text(text, label):
    hits, rows = [], []
    member, func, archive = label, "?", None

    def flush():
        regions, facts, tables = symbol_regions(rows), {}, jump_tables(rows)
        variables = None
        for i, (addr, _hx, mnem, ops, mem, fn) in enumerate(rows):
            if "@" not in ops and "(" not in ops:
                continue
            for cls, reg, detail in classify(mnem, split_operands(ops)):
                data = None
                if cls in ("WRONG", "BOTH"):
                    if variables is None:
                        variables = cxx_variables(r[5] for r in rows)
                    data = looks_like_data(rows, i, regions, facts, tables, variables)
                hits.append(dict(cls=cls, file=mem, func=fn, addr="0x" + addr,
                                 insn=("%s %s" % (mnem, ops)).strip(), reg=reg, detail=detail, data=data))
        del rows[:]

    for line in text.splitlines():
        am = ARCHIVE_RE.match(line)
        if am:
            archive = am.group(1)
            continue
        fm = FILE_RE.match(line)
        if fm:
            flush()
            member = "%s(%s)" % (archive, fm.group(1)) if archive else fm.group(1)
            func = "?"
            continue
        f = FUNC_RE.match(line)
        if f:
            func = f.group(2)
            continue
        m = INSN_RE.match(line)
        if m:
            ops = m.group(4).split("|")[0].split(";")[0].strip()
            ops = re.sub(r"\s+<[^>]*>$", "", ops)
            rows.append((m.group(1), m.group(2).strip(), m.group(3), ops, member, func))
    flush()
    return hits


def scan_asm_text(text, label):
    hits, func = [], "?"
    for n, line in enumerate(text.splitlines(), 1):
        lm = ASM_LABEL_RE.match(line)
        if lm and not lm.group(1).startswith((".L", "L")):
            func = lm.group(1)
        m = ASM_RE.match(line)
        if not m or m.group(1).startswith("."):
            continue
        mnem, ops = m.group(1), m.group(2).split("|")[0].strip()
        for cls, reg, detail in classify(mnem, split_operands(ops)):
            hits.append(dict(cls=cls, file=label, func=func, addr="line %d" % n,
                             insn=("%s %s" % (mnem, ops)).strip(), reg=reg, detail=detail, data=None))
    return hits


def scan_text(text, label):
    if "file format" in text or any(INSN_RE.match(l) for l in text.splitlines()):
        return scan_objdump_text(text, label)
    return scan_asm_text(text, label)


def disassemble(path, objdump, raw, cpu):
    # -m: an Amiga hunk file says 68000, and its 68020+ instructions would
    # then come out as ".short" words, which would look like data
    cmd = [objdump, "-D", "-b", "binary"] if raw else [objdump, "-d"]
    cmd += ["-w", "-m", "m68k:" + cpu]
    try:
        p = subprocess.run(cmd + [path], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           universal_newlines=True, errors="replace")
    except OSError as e:
        return None, str(e)
    if p.returncode != 0:
        err = p.stderr.strip().splitlines()
        return None, err[-1] if err else "objdump failed"
    return p.stdout, None


def walk(paths):
    for p in paths:
        if os.path.isdir(p):
            for root, dirs, files in os.walk(p):
                dirs.sort()
                for f in sorted(files):
                    fp = os.path.join(root, f)
                    if not os.path.islink(fp) and not f.endswith(SKIP_SUFFIXES):
                        yield fp
        else:
            yield p


SELFTEST = """
x.o:     file format elf32-m68k

00000000 <f>:
   0:\t1399 0800      \tmoveb %a1@+,%a1@(0,%d0:l)
   4:\t1090           \tmoveb a0@+,a0@
   6:\t2562 0004      \tmovel a2@-,a2@(4)
   a:\t27a2 a804      \tmovel a2@-,a3@(4,a2:l)
   e:\t14d9           \tmoveb a1@+,a2@+
  10:\t252a 0004      \tmovel a2@(4),a2@-
  14:\tb108           \tcmpmb a0@+,a0@+
  16:\t2058           \tmoveal a0@+,a0
  18:\t4cdf 7cfc      \tmoveml sp@+,d2-d7/a2-a6
  1c:\t2d5f fffc      \tmovel sp@+,fp@(-4)
  20:\t2e9f           \tmovel %sp@+,%sp@
  22:\t51c8 ffdc      \tdbf %d0,0 <f>
  26:\t4efb 1002      \tjmp %pc@(2a <f+0x2a>,%d1:w)
  2a:\t0004           \t.short 0x0004
  2c:\t2498           \tmovel a0@+,a2@
  2e:\t2098           \tmovel a0@+,a0@
  30:\t4e75           \trts

00000032 <table>:
  32:\t1f1f           \tmoveb sp@+,sp@-
  34:\t1f1e           \tmoveb a6@+,sp@-
"""
SELFTEST_ASM = """
f:
\tmove.b (%a1)+,(%a1,%d0.l)
\tmove.l -(%a2),4(%a2)
\tmove.b (%a0)+,(%a1)+
\trts
"""


def selftest():
    got = [(h["cls"], h["addr"], bool(h["data"])) for h in scan_text(SELFTEST, "x.o")]
    want = [("WRONG", "0x0", False), ("WRONG", "0x4", False), ("WRONG", "0x6", False),
            ("WRONG", "0xa", False), ("BENIGN", "0x10", False), ("BOTH", "0x14", False),
            ("REGDIRECT", "0x16", False), ("WRONG", "0x20", False), ("WRONG", "0x2e", False),
            ("BOTH", "0x32", True)]
    asm = [(h["cls"], h["func"]) for h in scan_text(SELFTEST_ASM, "x.s")]
    ok = got == want and asm == [("WRONG", "f"), ("WRONG", "f")]
    if not ok:
        print("selftest: WRONG\n got  %s\n want %s\n asm  %s" % (got, want, asm), file=sys.stderr)
        return 1
    print("selftest: right (%d objdump findings, %d -S findings)" % (len(got), len(asm)))
    return 0


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="*")
    ap.add_argument("--objdump", action="append",
                    help="m68k objdump; repeat to try several in turn (ELF and Amiga hunk files need "
                         "different ones). Default: each of %s found on PATH" % ", ".join(OBJDUMPS))
    ap.add_argument("--raw", action="store_true", help="inputs are raw m68k code (objdump -b binary)")
    ap.add_argument("--cpu", default="68040",
                    help="CPU to disassemble for (objdump -m m68k:CPU; default 68040, which decodes "
                         "68000 to 68040 code)")
    ap.add_argument("--text", action="store_true", help="inputs are gcc -S or objdump -d text")
    ap.add_argument("--allow", action="append", default=[], metavar="REGEX",
                    help="let a hit through if REGEX matches 'FILE: SYMBOL: INSTRUCTION' (re.search)")
    ap.add_argument("--allow-file", action="append", default=[], metavar="FILE",
                    help="--allow patterns, one per line (# comments)")
    ap.add_argument("--all", action="store_true", help="list every finding, BENIGN and REGDIRECT too")
    ap.add_argument("--data", action="store_true", help="also list WRONG/BOTH hits that look like data")
    ap.add_argument("--regdirect", action="store_true", help="also list REGDIRECT findings")
    ap.add_argument("--strict", action="store_true", help="BOTH hits and hits that look like data fail too")
    ap.add_argument("--json", action="store_true", help="JSON output")
    ap.add_argument("-q", "--quiet", action="store_true", help="do not list files no objdump could read")
    ap.add_argument("--selftest", action="store_true", help="check the classifier on built-in samples")
    a = ap.parse_args(argv)
    if a.selftest:
        return selftest()
    if not a.paths:
        ap.error("no input")

    allow = list(a.allow)
    for f in a.allow_file:
        with open(f) as fh:
            allow += [l.strip() for l in fh if l.strip() and not l.lstrip().startswith("#")]
    allow_re = [re.compile(p) for p in allow]

    objdumps = [] if a.text else (a.objdump or [p for p in (shutil.which(n) for n in OBJDUMPS) if p])
    if not a.text and not objdumps:
        print("no m68k objdump found; give --objdump", file=sys.stderr)
        return 2
    hits, scanned, skipped = [], 0, []
    for path in walk(a.paths):
        if a.text:
            with open(path, errors="replace") as fh:
                hits += scan_text(fh.read(), path)
            scanned += 1
            continue
        out = err = None
        for od in objdumps:
            out, err = disassemble(path, od, a.raw, a.cpu)
            if out is not None:
                break
        if out is None:
            skipped.append((path, err))
            continue
        scanned += 1
        hits += scan_objdump_text(out, path)

    for h in hits:
        key = "%s: %s: %s" % (h["file"], h["func"], h["insn"])
        h["allowed"] = any(r.search(key) for r in allow_re)

    def failing(h):
        if h["allowed"]:
            return False
        if a.strict:
            return h["cls"] in ("WRONG", "BOTH")
        return h["cls"] == "WRONG" and not h["data"]
    shown = [h for h in hits if a.all
             or (h["cls"] in ("WRONG", "BOTH") and (a.data or not h["data"]))
             or (h["cls"] == "REGDIRECT" and a.regdirect)]
    bad = [h for h in hits if failing(h)]
    if a.json:
        json.dump(dict(scanned=scanned, skipped=[p for p, _ in skipped], failing=len(bad), hits=shown),
                  sys.stdout, indent=1)
        print()
    else:
        for h in shown:
            notes = []
            if h["data"]:
                notes.append("looks like data: %s" % h["data"])
            if h["allowed"]:
                notes.append("allowed")
            print("%-9s %s: %s @ %s: %s  [%s: %s]%s" % (
                h["cls"], h["file"], h["func"], h["addr"], h["insn"], h["reg"], h["detail"],
                " (%s)" % "; ".join(notes) if notes else ""))
        if not a.quiet:
            for p, e in skipped:
                print("skipped   %s: %s" % (p, e), file=sys.stderr)
        count = lambda c, d: sum(1 for h in hits if h["cls"] == c and bool(h["data"]) == d)
        print("# %d file(s) scanned, %d not read; WRONG %d, BOTH %d (and %d, %d that look like data); "
              "REGDIRECT %d, BENIGN %d; %d allowed; %d failing"
              % (scanned, len(skipped), count("WRONG", False), count("BOTH", False),
                 count("WRONG", True), count("BOTH", True),
                 sum(1 for h in hits if h["cls"] == "REGDIRECT"),
                 sum(1 for h in hits if h["cls"] == "BENIGN"),
                 sum(1 for h in hits if h["allowed"]), len(bad)), file=sys.stderr)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
