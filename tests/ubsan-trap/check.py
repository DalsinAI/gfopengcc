#!/usr/bin/env python3
"""Check opt-in UBSan trap instrumentation without a target UBSan runtime.

Usage: check.py BINDIR [compiler flags...]
Uses the existing hunk-to-ELF harness and QEMU; this is compiler validation,
not AmigaOS/AC090 runtime qualification. OUT retains all generated evidence.
"""
import json
import hashlib
import os
from pathlib import Path
import resource
import shlex
import signal
import subprocess
import sys
import tempfile


def run(args, **kwargs):
    return subprocess.run([str(arg) for arg in args], text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          timeout=30, **kwargs)


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: check.py BINDIR [compiler flags...]")
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    bindir = Path(sys.argv[1]).resolve()
    cc = bindir / "m68k-amigaos-gcc"
    nm = bindir / "m68k-amigaos-nm"
    extra = sys.argv[2:]
    here = Path(__file__).resolve().parent
    repro = here.parent / "repro"
    out = Path(os.environ.get("OUT", tempfile.mkdtemp(prefix="open7-ubsan-")))
    out.mkdir(parents=True, exist_ok=True)
    receipt = {"compiler": str(cc), "flags": extra, "cases": []}
    version = run([cc, *extra, "-v"])
    receipt["version"] = version.stdout + version.stderr
    (out / "compiler.txt").write_text(receipt["version"])
    frontend = run([cc, *extra, "-print-prog-name=cc1"])
    frontend_path = Path(frontend.stdout.strip())
    if frontend_path.is_file():
        receipt["cc1"] = str(frontend_path)
        receipt["cc1_sha256"] = hashlib.file_digest(
            frontend_path.open("rb"), "sha256").hexdigest()
    preflight = run([cc, *extra, "-m68040", "-fsanitize=undefined",
                     "-fsanitize-undefined-trap-on-error", "-c",
                     here / "probe.c", "-o", out / "preflight.o"])
    (out / "preflight.log").write_text(preflight.stdout + preflight.stderr)
    if preflight.returncode:
        receipt["status"] = "unsupported" if "not supported on this target" in preflight.stderr else "build failure"
        (out / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
        print(f"ubsan-trap: {receipt['status']}; see {out / 'preflight.log'}")
        return 77 if receipt["status"] == "unsupported" else 1
    profiles = [("68000", "m68000", ["-m68000"]),
                ("68020", "m68020", ["-m68020"]),
                ("68040-soft", "m68040", ["-m68040", "-msoft-float"]),
                ("68040-fpu", "m68040", ["-m68040", "-m68881"]),
                ("68060", "m68060", ["-m68060"])]
    bad = 0
    try:
        receipt["rejected_modes"] = []
        for options in (["-fsanitize=undefined"],
                        ["-fsanitize=address", "-fsanitize-trap=all"],
                        ["-fsanitize=thread"],
                        ["-fsanitize=shift,signed-integer-overflow", "-fsanitize-trap=shift"]):
            completed = run([cc, *extra, "-m68040", *options, "-c",
                             here / "probe.c", "-o", out / "unsupported.o"])
            passed = completed.returncode != 0 and "not supported on this target" in completed.stderr
            receipt["rejected_modes"].append({"flags": options, "passed": passed,
                                               "diagnostic": completed.stderr})
            bad += not passed
        for name, qcpu, cpu in profiles:
            helper = out / f"{name}-helpers.o"
            completed = run([cc, *extra, *cpu, "-O2", "-fno-builtin",
                             "-c", here / "helpers.c", "-o", helper])
            if completed.returncode:
                receipt["helper_failure"] = completed.stdout + completed.stderr
                bad += 1
                break
            for opt in ("-O0", "-O2", "-O3", "-Os"):
                for case in range(6):
                    stem = out / f"{name}-{opt[1:]}-{case}"
                    obj = stem.with_suffix(".o")
                    hunk = stem.with_suffix(".hunk")
                    elf = stem.with_suffix(".elf")
                    commands = [
                        [cc, *extra, *cpu, opt, "-fsanitize=undefined",
                         "-fsanitize-undefined-trap-on-error",
                         f"-DTEST_CASE={case}", "-c", here / "probe.c", "-o", obj],
                        [cc, *extra, *cpu, "-nostartfiles", "-nostdlib",
                         repro / "crt.s", obj, helper, "-o", hunk],
                        [sys.executable, repro / "mkelf.py", hunk, elf],
                    ]
                    result = {"profile": name, "opt": opt, "case": case,
                              "passed": False}
                    receipt["cases"].append(result)
                    log = []
                    for command in commands:
                        completed = run(command)
                        log.append("$ " + shlex.join(map(str, command)) + "\n"
                                   + completed.stdout + completed.stderr)
                        if completed.returncode:
                            result["failure"] = "build"
                            break
                    else:
                        symbols = run([nm, "-u", obj])
                        if symbols.returncode or "ubsan" in symbols.stdout:
                            result["failure"] = "target sanitizer runtime reference"
                        else:
                            elf.chmod(0o755)
                            completed = run(["qemu-m68k", "-cpu", qcpu, elf])
                            result["returncode"] = completed.returncode
                            log.append(completed.stdout + completed.stderr)
                            # GCC lowers __builtin_trap to trap #7. QEMU maps
                            # it to SIGILL. Other crashes must not count as
                            # successful sanitizer traps (e.g. SIGSEGV/FPE).
                            expected = (0,) if case == 0 else (-signal.SIGILL,
                                                               128 + signal.SIGILL)
                            result["passed"] = completed.returncode in expected
                            if not result["passed"]:
                                result["failure"] = "unexpected execution result"
                    stem.with_suffix(".log").write_text("\n".join(log))
                    if not result["passed"]:
                        bad += 1
                        print(f"WRONG: {name} {opt} case {case}: {result}", flush=True)
                print(f"ubsan-trap: {name} {opt} checked", flush=True)
    except (subprocess.SubprocessError, OSError) as error:
        bad += 1
        receipt["error"] = str(error)
    finally:
        receipt["failures"] = bad
        receipt["status"] = "failed" if bad else "passed"
        (out / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(f"ubsan-trap: {len(receipt['cases'])} cases, {bad} failures; {out}")
    return bool(bad)


if __name__ == "__main__":
    sys.exit(main())
