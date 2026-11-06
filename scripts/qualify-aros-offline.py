#!/usr/bin/env python3
"""Clean full-SDK AROS build, using only verified local cached inputs.

Usage: qualify-aros-offline.py NEW_ROOT AROS_MIRROR SDK_INPUT [JOBS]
The mirror is the folder containing AROS/ and the three pinned tarballs.
The SDK is copied and fingerprinted; libatomic never changes the input SDK.
GPL-3.0-or-later. Copyright (c) 2026 AmiCradle Team.
"""
import importlib.util
import json
import os
from pathlib import Path
import resource
import subprocess
import sys
import time


def main():
    if len(sys.argv) not in (4, 5):
        sys.exit(__doc__)
    root, mirror, sdk_input = (Path(arg).resolve() for arg in sys.argv[1:4])
    jobs = int(sys.argv[4]) if len(sys.argv) == 5 else 4
    repository = Path(__file__).resolve().parent.parent
    if root.exists() or jobs < 1:
        sys.exit("use a new output directory and a positive job count")
    spec = importlib.util.spec_from_file_location("offline_support",
                                                repository / "scripts/reproduce-offline.py")
    support = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(support)
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repository,
                                     text=True).strip()
    epoch = subprocess.check_output(["git", "show", "-s", "--format=%ct", "HEAD"],
                                    cwd=repository, text=True).strip()
    root.mkdir()
    os.umask(0o022)
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    orchestration, work, prefix, sdk = (root / name for name in
                                       ("orchestration", "work", "prefix", "sdk"))
    state = {"status": "preparing", "orchestration_commit": commit,
             "source_date_epoch": epoch, "jobs": jobs, "started": time.time(),
             "mirror": str(mirror), "sdk_input": str(sdk_input),
             "network": "inherited seccomp: socket/connect return ENETDOWN"}

    def save():
        temporary = root / "status.json.new"
        temporary.write_text(json.dumps(state, indent=2) + "\n")
        temporary.replace(root / "status.json")

    environment = os.environ.copy()
    for key in tuple(environment):
        if "proxy" in key.lower() or key in ("AROS_FROM", "GCC_EXEC_PREFIX",
                                             "LIBRARY_PATH", "CPATH", "OUT"):
            environment.pop(key, None)
    environment.update(SOURCE_DATE_EPOCH=epoch, TZ="UTC", LC_ALL="C", LANG="C",
                       PYTHONHASHSEED="0", CCACHE_DISABLE="1", GIT_TERMINAL_PROMPT="0",
                       GIT_ALLOW_PROTOCOL="file", TMPDIR=str(work / ".tmp"))
    (work / ".tmp").mkdir(parents=True)

    def run(label, arguments, logfile):
        state["stage"], state["stage_started"] = label, time.time()
        save()
        print(f"[{time.strftime('%H:%M:%S')}] AROS {label}: {logfile}", flush=True)
        with logfile.open("w") as output:
            output.write("command: " + json.dumps(list(map(str, arguments))) + "\n")
            output.flush()
            completed = subprocess.run(list(map(str, arguments)), cwd=root, env=environment,
                                       stdout=output, stderr=subprocess.STDOUT)
        if completed.returncode:
            raise RuntimeError(f"{label} failed ({completed.returncode}); see {logfile}")

    save()
    try:
        support.offline()
        state["offline_probe_passed"] = True
        run("freeze orchestration", ["git", "clone", "--local", "--no-checkout",
                                     repository, orchestration], root / "freeze.log")
        run("select commit", ["git", "-C", orchestration, "checkout", "--detach", commit],
            root / "checkout.log")
        cache = work / "aros"
        cache.mkdir()
        sources = []
        for line in (orchestration / "scripts/aros.lock").read_text().splitlines():
            if not line or line.startswith("#"):
                continue
            name, url, expected, relative = line.split()
            if name == "aros":
                run("fresh AROS checkout", ["git", "clone", "--local", "--no-checkout",
                                            mirror / relative, cache / relative],
                    root / "aros-clone.log")
                run("pinned AROS commit", ["git", "-C", cache / relative, "checkout",
                                           "--detach", expected], root / "aros-checkout.log")
                actual = subprocess.check_output(["git", "-C", cache / relative,
                                                   "rev-parse", "HEAD"], text=True).strip()
            else:
                actual = support.sha(mirror / relative)
                if actual == expected:
                    import shutil
                    shutil.copyfile(mirror / relative, cache / relative)
            if actual != expected:
                raise RuntimeError(f"{name}: pinned input mismatch")
            sources.append({"name": name, "source": url, "pin": expected})
        (root / "sources.json").write_text(json.dumps(sources, indent=2) + "\n")
        run("isolated SDK copy", ["rsync", "-aL", str(sdk_input) + "/", str(sdk) + "/"],
            root / "sdk-copy.log")
        entries = support.manifest(sdk)
        (root / "sdk-input-manifest.json").write_text(json.dumps(entries, sort_keys=True,
                                                                 indent=2) + "\n")
        state["sdk_input_manifest_sha256"] = support.sha(root / "sdk-input-manifest.json")
        state["empty_build_tree"] = not (cache / "build").exists()
        state["empty_prefix"] = not prefix.exists()
        state["status"] = "running"
        run("full offline build", ["bash", orchestration / "scripts/build-aros.sh",
                                    work, prefix, sdk, jobs], root / "build.log")
        run("AROS patch accounting", ["bash", orchestration / "tests/aros-series.sh"],
            root / "patch-accounting.log")
        run("autoincrement matrix", ["bash", orchestration / "tests/autoinc/check.sh",
                                      "--aros", prefix], root / "autoinc.log")
        state["tool_hashes"] = {}
        for name in ("libexec/gcc/m68k-aros/16.2.0/cc1",
                     "libexec/gcc/m68k-aros/16.2.0/cc1plus",
                     "m68k-aros-collect-aros", "m68k-aros-gcc"):
            state["tool_hashes"][name] = support.sha(prefix / name)
        state["status"], state["finished"] = "passed", time.time()
        save()
        print(f"AROS clean offline qualification passed: {root}", flush=True)
    except BaseException as error:
        state["status"], state["error"] = "failed", str(error)
        save()
        raise


if __name__ == "__main__":
    main()
