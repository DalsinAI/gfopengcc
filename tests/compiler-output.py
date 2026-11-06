#!/usr/bin/env python3
"""Exercise complete stream consumption and upstream-error propagation."""
from pathlib import Path
import os
import subprocess
import tempfile


root = Path(__file__).resolve().parent.parent
helper = root / "scripts/read-link-cpu.sh"
with tempfile.TemporaryDirectory(prefix="gcc-output-") as directory:
    compiler = Path(directory) / "compiler"
    compiler.write_text('''#!/usr/bin/env python3
import os, signal, sys
signal.signal(signal.SIGPIPE, signal.SIG_DFL)
assert sys.argv[1:] == ["-dumpspecs"]
kind = os.environ.get("FIXTURE_KIND", "normal")
sys.stdout.write("*other:\\n" + "padding\\n" * 131072)
if kind != "missing":
    sys.stdout.write("*link_cpu:\\n%{m68040:-fl libm040}\\n")
if kind == "duplicate":
    sys.stdout.write("*link_cpu:\\nsecond definition\\n")
sys.stdout.write("*trailer:\\n" + "padding\\n" * 131072)
sys.stdout.flush()
sys.exit(73 if kind == "failure" else 0)
''')
    compiler.chmod(0o755)
    for kind in ("normal", "missing", "duplicate", "failure"):
        result = subprocess.run(["bash", helper, compiler],
                                env=os.environ | {"FIXTURE_KIND": kind},
                                text=True, capture_output=True, timeout=15)
        if kind == "normal":
            assert result.returncode == 0, result.stderr
            assert result.stdout == "%{m68040:-fl libm040}\n", result.stdout
        elif kind == "failure":
            assert result.returncode == 73, (result.returncode, result.stderr)
        else:
            assert result.returncode != 0, kind
    # Prove that the fixture exposes the historical failure, rather than
    # merely checking a small stream which fits in a pipe buffer.
    old = subprocess.run(["bash", "-o", "pipefail", "-c",
                          '"$1" -dumpspecs | sed -n \'/^\\*link_cpu:/{n;p;q;}\'',
                          "control", compiler], text=True, capture_output=True, timeout=15)
    assert old.returncode != 0, "fixture did not expose the short-reader SIGPIPE"
print("compiler output: large stream, missing/duplicate spec and real failure controls pass")
