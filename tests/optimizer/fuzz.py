#!/usr/bin/env python3
"""Defined-behaviour differential optimiser test for m68k-amigaos GCC."""
import hashlib
import json
import os
from pathlib import Path
import random
import re
import resource
import shutil
import subprocess
import sys
import tempfile


def run(args):
    return subprocess.run([str(arg) for arg in args], text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          timeout=30)


def u32(value):
    return f"UINT32_C(0x{value & 0xffffffff:08x})"


def generate(seed):
    rng = random.Random(seed)
    lines = [
        "#include <stdint.h>",
        "extern void puts_ (const char *);",
        "extern void putu (unsigned long);",
        "static volatile uint32_t fuzz_sink;",
        "int main (void)",
        "{",
    ]
    for index in range(8):
        lines.append(f"  uint32_t v{index} = {u32(rng.getrandbits(32))};")
    lines += [
        "  uint32_t table[16];",
        "  uint32_t checksum = UINT32_C(0x811c9dc5);",
        "  unsigned int i;",
        "  for (i = 0; i < 16; ++i)",
        "    table[i] = (v0 ^ (uint32_t) i) + UINT32_C(0x9e3779b9);",
        "  for (i = 0; i < 64; ++i)",
        "    {",
    ]
    indent = "      "
    for _ in range(28):
        a, b = rng.randrange(8), rng.randrange(8)
        operation = rng.randrange(7)
        constant = rng.getrandbits(32)
        shift = rng.randrange(1, 32)
        if operation == 0:
            statement = f"v{a} += v{b} ^ {u32(constant)};"
        elif operation == 1:
            statement = (f"v{a} = (v{a} << {shift}) "
                         f"| (v{a} >> {32 - shift});")
        elif operation == 2:
            statement = f"v{a} ^= v{b} * {u32(constant | 1)};"
        elif operation == 3:
            statement = (f"v{a} += table[(v{b} >> {shift}) "
                         "& UINT32_C(15)];")
        elif operation == 4:
            statement = (f"table[(v{a} >> {shift}) & UINT32_C(15)] "
                         f"^= v{b} + {u32(constant)};")
        elif operation == 5:
            mask = u32(constant)
            statement = f"v{a} = (v{a} & {mask}) | (v{b} & ~{mask});"
        else:
            mask = 1 << rng.randrange(32)
            statement = (f"if ((v{a} & {u32(mask)}) != 0) "
                         f"v{a} += v{b}; else v{a} ^= {u32(constant)};")
        lines.append(indent + statement)
    lines += [
        "      v0 += (uint32_t) i * UINT32_C(0x45d9f3b);",
        "    }",
        "  for (i = 0; i < 8; ++i)",
        "    {",
        "      uint32_t value;",
        "      switch (i)",
        "        {",
    ]
    for index in range(8):
        lines.append(f"        case {index}: value = v{index}; break;")
    lines += [
        "        default: value = 0; break;",
        "        }",
        "      checksum = (checksum ^ value) * UINT32_C(0x01000193);",
        "    }",
        "  for (i = 0; i < 16; ++i)",
        "    checksum = (checksum ^ table[i]) * UINT32_C(0x01000193);",
        "  fuzz_sink = checksum;",
        "  puts_ (\"checksum=\");",
        "  putu ((unsigned long) fuzz_sink);",
        "  puts_ (\"\\n\");",
        "  return 0;",
        "}",
    ]
    return "\n".join(lines) + "\n"


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit(f"usage: {sys.argv[0]} BINDIR [SEEDS]")
    bindir = Path(sys.argv[1]).resolve()
    seeds = int(sys.argv[2]) if len(sys.argv) == 3 else 12
    if not 1 <= seeds <= 100:
        sys.exit("SEEDS must be between 1 and 100")
    cc = bindir / "m68k-amigaos-gcc"
    if not cc.is_file():
        sys.exit(f"compiler is missing: {cc}")
    if shutil.which("qemu-m68k") is None:
        sys.exit("qemu-m68k is required")
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    here = Path(__file__).resolve().parent
    repro = here.parent / "repro"
    out = Path(os.environ.get("OUT", tempfile.mkdtemp(prefix="open7-fuzz-")))
    out.mkdir(parents=True, exist_ok=True)
    receipt = {"compiler": str(cc), "seed_count": seeds, "cases": []}
    version = run([cc, "-v"])
    receipt["version"] = version.stdout + version.stderr
    frontend = run([cc, "-print-prog-name=cc1"])
    frontend_path = Path(frontend.stdout.strip())
    if frontend_path.is_file():
        receipt["cc1_sha256"] = hashlib.file_digest(
            frontend_path.open("rb"), "sha256").hexdigest()
    cpu_profiles = [("68000", "m68000"), ("68020", "m68020"),
                    ("68040", "m68040"), ("68060", "m68060")]
    opt_profiles = ["-O0", "-O2", "-O3", "-Os"]
    expected = {}
    failures = 0

    try:
        for number in range(seeds):
            seed = 0x0A090000 + number
            source = out / f"seed-{seed:08x}.c"
            source.write_text(generate(seed))
            for cpu, qcpu in cpu_profiles:
                common = out / f"{seed:08x}-{cpu}"
                crt = common.with_suffix(".crt.o")
                runtime = common.with_suffix(".rt.o")
                helper = common.with_suffix(".helper.o")
                setup = [
                    [cc, f"-m{cpu}", "-c", repro / "crt.s", "-o", crt],
                    [cc, f"-m{cpu}", "-O1", "-fno-builtin", "-c",
                     repro / "rt.c", "-o", runtime],
                    [cc, f"-m{cpu}", "-O1", "-fno-builtin", "-c",
                     here / "helpers.c", "-o", helper],
                ]
                for command in setup:
                    completed = run(command)
                    if completed.returncode:
                        raise RuntimeError(completed.stderr)
                for opt in opt_profiles:
                    stem = out / f"{seed:08x}-{cpu}-{opt[1:]}"
                    obj = stem.with_suffix(".o")
                    hunk = stem.with_suffix(".hunk")
                    elf = stem.with_suffix(".elf")
                    commands = [
                        [cc, f"-m{cpu}", opt, "-fno-builtin", "-c", source,
                         "-o", obj],
                        [cc, f"-m{cpu}", opt, "-nostartfiles", "-nostdlib",
                         crt, obj, runtime, helper, "-o", hunk],
                        [sys.executable, repro / "mkelf.py", hunk, elf],
                    ]
                    result = {"seed": seed, "cpu": cpu, "opt": opt,
                              "passed": False}
                    receipt["cases"].append(result)
                    for command in commands:
                        completed = run(command)
                        if completed.returncode:
                            result["failure"] = completed.stderr
                            break
                    else:
                        elf.chmod(0o755)
                        completed = run(["qemu-m68k", "-cpu", qcpu, elf])
                        match = re.fullmatch(r"checksum=([0-9]+)\n?",
                                             completed.stdout)
                        if completed.returncode or not match:
                            result["failure"] = (completed.stdout
                                                 + completed.stderr)
                        else:
                            checksum = int(match.group(1))
                            result["checksum"] = checksum
                            baseline = expected.setdefault(seed, checksum)
                            result["passed"] = checksum == baseline
                            if not result["passed"]:
                                result["failure"] = f"expected {baseline}"
                    if not result["passed"]:
                        failures += 1
                        print("WRONG:", result, flush=True)
            print(f"optimizer-fuzz: seed 0x{seed:08x} checked", flush=True)
    except (OSError, subprocess.SubprocessError, RuntimeError) as error:
        receipt["error"] = str(error)
        failures += 1
    receipt["failures"] = failures
    receipt["status"] = "failed" if failures else "passed"
    (out / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(f"optimizer-fuzz: {len(receipt['cases'])} cases, "
          f"{failures} failures; {out}")
    return bool(failures)


if __name__ == "__main__":
    sys.exit(main())
